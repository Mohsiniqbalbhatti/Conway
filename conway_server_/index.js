require("dotenv").config();
const express = require("express");
const mongoose = require("mongoose");
const bodyParser = require("body-parser");
const cors = require("cors");
const http = require("http");
const { Server } = require("socket.io");
const schedule = require("node-schedule"); // Use node-schedule for better cron-like jobs
const cloudinary = require("cloudinary").v2; // Import Cloudinary V2
const authRoutes = require("./routes/auth");
const groupRoutes = require("./routes/group");
const messageRoutes = require("./routes/message");
const searchRoutes = require("./routes/search");
const userRoutes = require("./routes/user"); // Import new user routes
const User = require("./models/User");
const Message = require("./models/Message");

const app = express();
const server = http.createServer(app);
const io = new Server(server, {
  cors: {
    origin: "*",
    methods: ["GET", "POST"],
  },
});

app.use(cors());
app.use(bodyParser.json());

const userSockets = new Map();

io.on("connection", (socket) => {
  console.log("a user connected:", socket.id);

  socket.on("join", (userId) => {
    console.log(
      `[Socket JOIN] Received userId: ${userId} (Type: ${typeof userId})`
    );
    if (userId) {
      const userIdStr = userId.toString();
      userSockets.set(userIdStr, socket.id);
      socket.join(userIdStr);
      console.log(
        `[Socket JOIN] Mapped userId '${userIdStr}' to socket ${socket.id}`
      );
      console.log(
        "[Socket JOIN] Current userSockets map:",
        Object.fromEntries(userSockets)
      );
    } else {
      console.warn("[Socket JOIN] Received null or undefined userId.");
    }
  });

  socket.on("sendMessage", async (data) => {
    console.log("[Socket SEND] sendMessage event received:", data);
    const {
      senderId,
      receiverEmail,
      messageText,
      burnoutDateTime,
      scheduleDateTime,
      senderEmail,
    } = data;

    if (!senderId || !receiverEmail || !messageText || !senderEmail) {
      console.error(
        "[Socket SEND] Invalid sendMessage data (missing sender/receiver/text/senderEmail):",
        data
      );
      socket.emit("messageError", { message: "Invalid message data" });
      return;
    }

    try {
      const sender = await User.findById(senderId);
      if (!sender) {
        console.error(`[Socket SEND] Sender not found for ID: ${senderId}`);
        socket.emit("messageError", { message: "Sender not found" });
        return;
      }
      const senderName = sender.fullname;

      const receiver = await User.findOne({ email: receiverEmail });
      if (!receiver) {
        console.error(
          `[Socket SEND] Receiver not found for email: ${receiverEmail}`
        );
        socket.emit("messageError", { message: "Receiver not found" });
        return;
      }
      const receiverId = receiver._id.toString();
      console.log(
        `[Socket SEND] Found receiver: ${receiver.fullname} (ID: ${receiverId})`
      );

      const plainMessageText = messageText;
      const now = new Date();

      const isScheduled = !!scheduleDateTime;
      const isBurnout = !!burnoutDateTime;
      let scheduleTime = isScheduled ? new Date(scheduleDateTime) : null;
      let expireTime = isBurnout ? new Date(burnoutDateTime) : null;

      // Validate times are in the future if provided
      if (scheduleTime && scheduleTime <= now) {
        console.warn(
          `[Socket SEND] Schedule time ${scheduleTime.toISOString()} is in the past. Sending now.`
        );
        scheduleTime = null; // Treat as immediate send
      }
      if (expireTime && expireTime <= now) {
        console.warn(
          `[Socket SEND] Burnout time ${expireTime.toISOString()} is in the past. Ignoring burnout.`
        );
        expireTime = null; // Ignore burnout
      }

      const messageData = {
        sender: senderId,
        receiver: receiver._id,
        message: plainMessageText,
        time: now, // Record when the request was received
        isScheduled: !!scheduleTime,
        scheduledAt: scheduleTime,
        isBurnout: !!expireTime,
        expireAt: expireTime,
        sent: false, // Mark as not sent initially
      };

      const newMessage = new Message(messageData);
      await newMessage.save();
      console.log(
        `[Socket SEND] Message saved to DB (ID: ${
          newMessage._id
        }, Scheduled: ${!!scheduleTime}, Burnout: ${!!expireTime})`
      );

      // If it's NOT scheduled, send immediately
      if (!scheduleTime) {
        const recipientSocketId = userSockets.get(receiverId);
        const messageToSend = {
          id: newMessage._id,
          senderId: senderId,
          senderEmail: senderEmail,
          senderName: senderName,
          receiverEmail: receiverEmail,
          text: plainMessageText,
          time: newMessage.time.toISOString(), // Time it was saved/sent
          isBurnout: newMessage.isBurnout,
          expireAt: newMessage.expireAt?.toISOString(), // Send expiry time if set
        };

        if (recipientSocketId) {
          console.log(
            `[Socket SEND] Recipient ${receiverEmail} ONLINE. Emitting receiveMessage to socket ${recipientSocketId}.`
          );
          io.to(recipientSocketId).emit("receiveMessage", messageToSend);
          newMessage.sent = true;
          await newMessage.save(); // Update sent status
          console.log(
            `[Socket SEND] Message ${newMessage._id} marked as sent.`
          );
        } else {
          console.log(
            `[Socket SEND] Recipient ${receiverEmail} (ID: ${receiverId}) OFFLINE. Message ${newMessage._id} saved but not sent immediately.`
          );
          // Message remains sent: false, will be picked up by /get-messages or /getupdate later?
          // Maybe /getupdate should check for sent: false messages too?
          // For now, rely on /get-messages
        }
      } else {
        console.log(
          `[Socket SEND] Message ${
            newMessage._id
          } is SCHEDULED for ${scheduleTime.toISOString()}. Not sending now.`
        );
        // Acknowledge schedule? Optional.
        // socket.emit('messageScheduled', { dbId: newMessage._id, scheduledAt: scheduleTime });
      }

      // Confirm original message processing to sender
      socket.emit("messageSent", {
        tempId: data.tempId,
        dbId: newMessage._id,
        time: newMessage.time,
      });
    } catch (error) {
      console.error("[Socket SEND] Error handling sendMessage:", error);
      socket.emit("messageError", { message: "Server error sending message" });
    }
  });

  socket.on("disconnect", () => {
    console.log(`[Socket DISCONNECT] User disconnected: ${socket.id}`);
    let deletedUserId = null;
    for (const [userId, socketId] of userSockets.entries()) {
      if (socketId === socket.id) {
        userSockets.delete(userId);
        deletedUserId = userId;
        break;
      }
    }
    if (deletedUserId) {
      console.log(
        `[Socket DISCONNECT] Removed mapping for user ${deletedUserId}`
      );
    } else {
      console.log(
        `[Socket DISCONNECT] No user mapping found for disconnected socket ${socket.id}`
      );
    }
    console.log(
      "[Socket DISCONNECT] Current userSockets map:",
      Object.fromEntries(userSockets)
    );
  });
});

// --- Scheduler Service ---
async function checkScheduledAndExpiredMessages() {
  const now = new Date();
  console.log(`[Scheduler] Checking for jobs before ${now.toISOString()}...`);
  try {
    // --- Handle Scheduled Messages ---
    const scheduledMessagesToSend = await Message.find({
      isScheduled: true,
      scheduledAt: { $lte: now },
    }).populate("sender receiver", "fullname email _id");

    if (scheduledMessagesToSend.length > 0) {
      console.log(
        `[Scheduler] Found ${scheduledMessagesToSend.length} scheduled messages to send.`
      );
      for (const msg of scheduledMessagesToSend) {
        const receiverId = msg.receiver?._id.toString();
        const senderId = msg.sender?._id.toString();
        const senderName = msg.sender?.fullname || "Unknown Sender";
        const senderEmail = msg.sender?.email;
        const receiverEmail = msg.receiver?.email;

        if (!receiverId || !senderId || !senderEmail || !receiverEmail) {
          console.error(
            `[Scheduler] Skipping scheduled message ${msg._id} due to missing sender/receiver info.`
          );
          msg.isScheduled = false; // Still mark as processed
          await msg.save();
          continue;
        }

        const recipientSocketId = userSockets.get(receiverId);
        const messagePayload = {
          id: msg._id.toString(), // Ensure ID is string
          senderId: senderId,
          senderEmail: senderEmail,
          senderName: senderName,
          receiverEmail: receiverEmail,
          text: msg.message,
          time: msg.scheduledAt.toISOString(), // Time it was intended to be sent
          isBurnout: msg.isBurnout,
          expireAt: msg.expireAt?.toISOString(),
        };

        if (recipientSocketId) {
          console.log(
            `[Scheduler] Sending scheduled message ${msg._id} to online user ${receiverEmail} (Socket: ${recipientSocketId})`
          );
          io.to(recipientSocketId).emit("receiveMessage", messagePayload);
          msg.sent = true;
        } else {
          console.log(
            `[Scheduler] Scheduled message ${msg._id} for offline user ${receiverEmail}. Marked for later fetch.`
          );
          msg.sent = false;
        }
        msg.isScheduled = false;
        msg.time = new Date(); // Update time to when it was actually processed
        await msg.save();
        console.log(
          `[Scheduler] Scheduled message ${msg._id} processed. Sent: ${msg.sent}`
        );
      }
    }

    // --- Handle Expired Burnout Messages ---
    const expiredMessages = await Message.find({
      isBurnout: true,
      expireAt: { $lte: now },
      deleted_at: null, // Add a flag/field to ensure we only process once?
      // For now, we rely on the client ignoring subsequent expiry events.
      // A `burnoutProcessedAt` field could be added to the model.
    }).populate("receiver", "_id"); // Only need receiver ID

    if (expiredMessages.length > 0) {
      console.log(
        `[Scheduler] Found ${expiredMessages.length} expired burnout messages.`
      );
      for (const msg of expiredMessages) {
        const receiverId = msg.receiver?._id.toString();
        if (!receiverId) {
          console.warn(
            `[Scheduler] Expired message ${msg._id} has no receiver ID.`
          );
          // Optionally mark as processed here?
          // msg.deleted_at = now; // Or use a dedicated flag
          // await msg.save();
          continue;
        }

        const recipientSocketId = userSockets.get(receiverId);
        if (recipientSocketId) {
          console.log(
            `[Scheduler] Emitting messageExpired for ${msg._id} to receiver ${receiverId} (Socket: ${recipientSocketId})`
          );
          // Emit only the ID, client will handle removal
          io.to(recipientSocketId).emit("messageExpired", {
            messageId: msg._id.toString(),
          });
        } else {
          console.log(
            `[Scheduler] Receiver ${receiverId} for expired message ${msg._id} is offline. Expiry will be handled on next fetch.`
          );
        }
        // Mark as processed? If we add a flag like deleted_at or burnoutProcessedAt
        // msg.deleted_at = now; // Example
        // await msg.save();
      }
    }
  } catch (error) {
    console.error(
      "[Scheduler] Error checking scheduled/expired messages:",
      error
    );
  }
}

// Run scheduler every 30 seconds (adjust interval as needed)
setInterval(checkScheduledAndExpiredMessages, 30 * 1000);
console.log(
  "[Scheduler] Scheduled message & burnout check job started (every 30 seconds)."
);

// --- End Scheduler Service ---

// --- Cloudinary Configuration ---
if (
  !process.env.CLOUDINARY_CLOUD_NAME ||
  !process.env.CLOUDINARY_API_KEY ||
  !process.env.CLOUDINARY_API_SECRET
) {
  console.error(
    "Error: Cloudinary environment variables (CLOUDINARY_CLOUD_NAME, CLOUDINARY_API_KEY, CLOUDINARY_API_SECRET) not set in .env file."
  );
  process.exit(1);
}

cloudinary.config({
  cloud_name: process.env.CLOUDINARY_CLOUD_NAME,
  api_key: process.env.CLOUDINARY_API_KEY,
  api_secret: process.env.CLOUDINARY_API_SECRET,
  secure: true, // Use https
});
console.log("[Cloudinary] Configured successfully.");
// --- End Cloudinary Configuration ---

const mongoUri = process.env.MONGODB_URI || process.env.MONGO_URI;
if (!mongoUri) {
  console.error(
    "Error: MongoDB URI not defined. Set MONGODB_URI or MONGO_URI in .env"
  );
  process.exit(1);
}
mongoose
  .connect(mongoUri)
  .then(() => {
    console.log("MongoDB connected");
    server.listen(3000, "0.0.0.0", () => {
      console.log("Server (with Socket.IO) is running on port 3000");
    });
  })
  .catch((err) => {
    console.error("MongoDB connection error:", err.message);
    if (err.code === "ENOTFOUND") {
      console.error(
        "DNS lookup failed for MongoDB host. Check your connection string in .env"
      );
    }
    process.exit(1);
  });

app.use("/api", authRoutes);
app.use("/api", groupRoutes);
app.use("/api", messageRoutes);
app.use("/api", searchRoutes);
app.use("/api/user", userRoutes); // Use the new user routes
