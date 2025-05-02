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
const Group = require("./models/Group"); // Import Group model
const Chat = require("./models/Chat"); // Add this line

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
      groupId,
      messageText,
      burnoutDateTime, // Now used for both direct and group
      scheduleDateTime, // Now used for both direct and group
      senderEmail,
      tempId,
    } = data;

    // --- Basic Validation ---
    if (!senderId || !messageText || !(receiverEmail || groupId)) {
      console.error(
        "[Socket SEND] Invalid message data (missing senderId, messageText, or receiverEmail/groupId):",
        data
      );
      socket.emit("messageError", { message: "Invalid message data" });
      return;
    }
    // If it's a direct message, senderEmail is also needed for the receive payload
    if (receiverEmail && !senderEmail) {
      console.error(
        "[Socket SEND] Invalid direct message data (missing senderEmail):",
        data
      );
      socket.emit("messageError", {
        message: "Sender email required for direct message",
      });
      return;
    }

    try {
      // --- Get Sender ---
      const sender = await User.findById(senderId).select("fullname email _id");
      if (!sender) {
        console.error(`[Socket SEND] Sender not found for ID: ${senderId}`);
        socket.emit("messageError", { message: "Sender not found" });
        return;
      }
      const senderName = sender.fullname;
      console.log(`[Socket SEND] Sender found: ${senderName} (${senderId})`);

      const plainMessageText = messageText;
      const now = new Date();
      let newMessageData = {
        sender: senderId,
        message: plainMessageText,
        time: now,
        // Add burnout/schedule fields - default to false/null
        isScheduled: false,
        scheduledAt: null,
        isBurnout: false,
        expireAt: null,
        sent: false, // Always false initially
      };

      // Common logic for validating/processing dates
      const isScheduledInput = !!scheduleDateTime;
      const isBurnoutInput = !!burnoutDateTime;
      let scheduleTime = isScheduledInput ? new Date(scheduleDateTime) : null;
      let expireTime = isBurnoutInput ? new Date(burnoutDateTime) : null;

      // Validate times are in the future if provided
      if (scheduleTime && scheduleTime <= now) {
        console.warn(
          `[Socket SEND] Schedule time ${scheduleTime.toISOString()} is in the past. Sending now.`
        );
        scheduleTime = null;
      }
      if (expireTime && expireTime <= now) {
        console.warn(
          `[Socket SEND] Burnout time ${expireTime.toISOString()} is in the past. Ignoring burnout.`
        );
        expireTime = null;
      }

      // Apply validated schedule/burnout times to message data
      newMessageData.isScheduled = !!scheduleTime;
      newMessageData.scheduledAt = scheduleTime;
      newMessageData.isBurnout = !!expireTime;
      newMessageData.expireAt = expireTime;

      // --- Handle Group Message ---
      if (groupId) {
        newMessageData.group = groupId;
        newMessageData.receiver = null;

        console.log(
          `[Socket SEND] Processing group message for group: ${groupId}`
        );
        const group = await Group.findById(groupId).select("users");
        if (!group) {
          console.error(`[Socket SEND] Group not found for ID: ${groupId}`);
          socket.emit("messageError", { message: "Group not found" });
          return;
        }

        // Find or create a group chat
        let chat = await Chat.findOne({
          group: groupId,
          isGroup: true,
        });

        if (!chat) {
          console.log(
            "[Socket SEND] No existing group chat found. Creating new chat."
          );
          chat = await Chat.create({
            participants: group.users, // Set participants only on insert
            group: groupId,
            isGroup: true,
          });
          console.log(`[Socket SEND] New group chat created: ${chat._id}`);
        } else {
          console.log(`[Socket SEND] Found existing group chat: ${chat._id}`);
          // Ensure participants are up-to-date in existing chat (optional, but good practice)
          if (
            !chat.participants ||
            chat.participants.length !== group.users.length
          ) {
            // Simple check; more robust check might compare elements
            console.log(
              `[Socket SEND] Updating participants in existing group chat ${chat._id}`
            );
            chat.participants = group.users;
            await chat.save(); // Save the update
          }
        }

        console.log(`[Socket SEND] Using group chat: ${chat._id}`);

        // Add chat reference to message
        newMessageData.chat = chat._id;

        // Save message to DB
        const newMessage = new Message(newMessageData);
        await newMessage.save();
        console.log(
          `[Socket SEND] Group message saved (ID: ${newMessage._id}, Scheduled: ${newMessage.isScheduled}, Burnout: ${newMessage.isBurnout})`
        );

        // Update the last message reference in the chat
        await Chat.findByIdAndUpdate(chat._id, { lastMessage: newMessage._id });

        // Emit to online group members if NOT scheduled
        if (!newMessage.isScheduled) {
          const messageToSend = {
            id: newMessage._id.toString(),
            groupId: groupId,
            senderId: senderId,
            senderName: senderName,
            text: plainMessageText,
            time: newMessage.time.toISOString(),
            // Include burnout/schedule info for clients
            isBurnout: newMessage.isBurnout,
            expireAt: newMessage.expireAt?.toISOString(),
            isScheduled: newMessage.isScheduled, // Although false here, include for consistency?
            scheduledAt: newMessage.scheduledAt?.toISOString(),
          };

          group.users.forEach((userId) => {
            const memberIdStr = userId.toString();
            if (memberIdStr !== senderId) {
              const memberSocketId = userSockets.get(memberIdStr);
              if (memberSocketId) {
                console.log(
                  `[Socket SEND] Emitting receiveGroupMessage to member ${memberIdStr} (Socket: ${memberSocketId})`
                );
                io.to(memberSocketId).emit(
                  "receiveGroupMessage",
                  messageToSend
                );
              }
            }
          });
        } else {
          console.log(
            `[Socket SEND] Group message ${newMessage._id} is SCHEDULED. Not sending now.`
          );
        }

        // Confirm processing back to sender
        socket.emit("groupMessageSent", {
          tempId: tempId,
          dbId: newMessage._id.toString(),
          time: newMessage.time.toISOString(),
          groupId: groupId,
          // Include schedule/burnout info in confirmation
          isScheduled: newMessage.isScheduled,
          scheduledAt: newMessage.scheduledAt?.toISOString(),
          isBurnout: newMessage.isBurnout,
          expireAt: newMessage.expireAt?.toISOString(),
        });
      }
      // --- Handle Direct Message ---
      else if (receiverEmail) {
        console.log(
          `[Socket SEND] Processing direct message for receiver: ${receiverEmail}`
        );
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

        // Find or create a chat between these users
        let chat = await Chat.findOne({
          participants: { $all: [senderId, receiverId] },
          isGroup: false,
        });

        if (!chat) {
          console.log(
            "[Socket SEND] No existing chat found. Creating new chat."
          );
          chat = await Chat.create({
            participants: [senderId, receiverId],
            isGroup: false,
          });
          console.log(`[Socket SEND] New chat created: ${chat._id}`);
        } else {
          console.log(`[Socket SEND] Found existing chat: ${chat._id}`);
        }

        console.log(`[Socket SEND] Using chat: ${chat._id}`);

        newMessageData.receiver = receiver._id;
        newMessageData.group = null;
        newMessageData.chat = chat._id;
        // Burnout/schedule already added above

        // Save message to DB
        const newMessage = new Message(newMessageData);
        await newMessage.save();
        console.log(
          `[Socket SEND] Direct message saved (ID: ${newMessage._id}, Scheduled: ${newMessage.isScheduled}, Burnout: ${newMessage.isBurnout})`
        );

        // Update the last message reference in the chat
        await Chat.findByIdAndUpdate(chat._id, { lastMessage: newMessage._id });

        // Send immediately if NOT scheduled
        if (!newMessage.isScheduled) {
          const recipientSocketId = userSockets.get(receiverId);
          const messageToSend = {
            id: newMessage._id.toString(),
            senderId: senderId,
            senderEmail: sender.email,
            senderName: senderName,
            receiverEmail: receiverEmail,
            text: plainMessageText,
            time: newMessage.time.toISOString(),
            isBurnout: newMessage.isBurnout,
            expireAt: newMessage.expireAt?.toISOString(),
            isScheduled: newMessage.isScheduled, // Although false here
            scheduledAt: newMessage.scheduledAt?.toISOString(),
          };

          if (recipientSocketId) {
            console.log(
              `[Socket SEND] Recipient ${receiverEmail} ONLINE. Emitting receiveMessage to socket ${recipientSocketId}.`
            );
            io.to(recipientSocketId).emit("receiveMessage", messageToSend);
            newMessage.sent = true;
            await newMessage.save();
          } else {
            console.log(
              `[Socket SEND] Recipient ${receiverEmail} (ID: ${receiverId}) OFFLINE. Message ${newMessage._id} saved.`
            );
            // Message remains sent: false
          }
        } else {
          console.log(
            `[Socket SEND] Direct message ${newMessage._id} is SCHEDULED.`
          );
        }

        // Confirm processing back to sender
        socket.emit("messageSent", {
          tempId: tempId,
          dbId: newMessage._id.toString(),
          time: newMessage.time.toISOString(),
          // Include schedule/burnout info in confirmation
          isScheduled: newMessage.isScheduled,
          scheduledAt: newMessage.scheduledAt?.toISOString(),
          isBurnout: newMessage.isBurnout,
          expireAt: newMessage.expireAt?.toISOString(),
        });
      }
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
  console.log(`[Scheduler] Checking jobs @ ${now.toISOString()}...`);
  try {
    // --- Handle Scheduled Messages (Direct & Group) ---
    const scheduledMessagesToSend = await Message.find({
      isScheduled: true,
      scheduledAt: { $lte: now },
      deleted_at: null, // Ensure not deleted
    }).populate(
      "sender receiver group chat",
      "fullname email _id users participants"
    ); // Add chat to populate

    console.log(
      `[Scheduler] Found ${scheduledMessagesToSend.length} potential scheduled messages to send.`
    );

    if (scheduledMessagesToSend.length > 0) {
      for (const msg of scheduledMessagesToSend) {
        console.log(
          `[Scheduler] Processing msg ${
            msg._id
          }. Scheduled at: ${msg.scheduledAt?.toISOString()}, Current time: ${now.toISOString()}`
        );

        // Update the message status
        msg.isScheduled = false;
        await msg.save();

        // --- Scheduled Group Message ---
        if (msg.group) {
          const groupId = msg.group._id.toString();
          const senderId = msg.sender?._id.toString();
          const senderName = msg.sender?.fullname || "Unknown";

          if (!senderId || !msg.chat || !msg.chat.participants) {
            console.error(
              `[Scheduler] Skipping scheduled group msg ${msg._id} (missing sender/chat).`
            );
            continue;
          }

          console.log(
            `[Scheduler] Processing scheduled GROUP message ${msg._id} for group ${groupId}`
          );
          const messagePayload = {
            id: msg._id.toString(),
            groupId: groupId,
            senderId: senderId,
            senderName: senderName,
            text: msg.message,
            time: msg.scheduledAt.toISOString(), // Use scheduled time
            isBurnout: msg.isBurnout,
            expireAt: msg.expireAt?.toISOString(),
            isScheduled: false, // It's being sent now
            scheduledAt: msg.scheduledAt?.toISOString(), // Keep original schedule time
          };

          msg.chat.participants.forEach((userId) => {
            const memberIdStr = userId.toString();
            if (memberIdStr !== senderId) {
              // Don't send to sender
              const memberSocketId = userSockets.get(memberIdStr);
              if (memberSocketId) {
                console.log(
                  `[Scheduler] Emitting receiveGroupMessage to member ${memberIdStr} (Socket: ${memberSocketId}) for msg ${msg._id}`
                );
                io.to(memberSocketId).emit(
                  "receiveGroupMessage",
                  messagePayload
                );
              } else {
                console.log(
                  `[Scheduler] Member ${memberIdStr} for group msg ${msg._id} is OFFLINE.`
                );
              }
            }
          });
        }
        // --- Scheduled Direct Message ---
        else if (msg.receiver) {
          const receiverId = msg.receiver._id.toString();
          const senderId = msg.sender._id.toString();
          const senderName = msg.sender.fullname;
          const senderEmail = msg.sender.email;
          const receiverEmail = msg.receiver.email;

          if (!receiverId || !senderId || !senderEmail || !receiverEmail) {
            console.error(
              `[Scheduler] Skipping scheduled direct msg ${msg._id} (missing info).`
            );
            msg.isScheduled = false;
            await msg.save(); // Mark as processed even if skipped
            continue;
          }

          console.log(
            `[Scheduler] Processing scheduled DIRECT message ${msg._id} to ${receiverEmail}`
          );
          const recipientSocketId = userSockets.get(receiverId);
          const messagePayload = {
            id: msg._id.toString(),
            senderId: senderId,
            senderEmail: senderEmail,
            senderName: senderName,
            receiverEmail: receiverEmail,
            text: msg.message,
            time: msg.scheduledAt.toISOString(),
            isBurnout: msg.isBurnout,
            expireAt: msg.expireAt?.toISOString(),
            isScheduled: false,
            scheduledAt: msg.scheduledAt?.toISOString(),
          };

          if (recipientSocketId) {
            console.log(
              `[Scheduler] Sending scheduled msg ${msg._id} to online user ${receiverEmail} (Socket: ${recipientSocketId})`
            );
            io.to(recipientSocketId).emit("receiveMessage", messagePayload);
            msg.sent = true;
          } else {
            console.log(
              `[Scheduler] Scheduled msg ${msg._id} for offline user ${receiverEmail}. Marked for later fetch.`
            );
            msg.sent = false;
          }
        }
      }
    }

    // --- Handle Expired Burnout Messages ---
    // Update to delete expired burnout messages
    const expiredBurnoutMessages = await Message.find({
      isBurnout: true,
      expireAt: { $lte: now },
      deleted_at: null,
    });

    console.log(
      `[Scheduler] Found ${expiredBurnoutMessages.length} expired burnout messages to clean up.`
    );

    for (const msg of expiredBurnoutMessages) {
      msg.deleted_at = now;
      await msg.save();
      console.log(
        `[Scheduler] Marked burnout message ${
          msg._id
        } as deleted (expired at ${msg.expireAt?.toISOString()}).`
      );
    }

    console.log(`[Scheduler] Job run completed.`);
  } catch (err) {
    console.error("[Scheduler] Error in scheduled job:", err);
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
