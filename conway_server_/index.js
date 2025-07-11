require("dotenv").config();
const express = require("express");
const mongoose = require("mongoose");
const bodyParser = require("body-parser");
const cors = require("cors");
const http = require("http");
const { Server } = require("socket.io");
const schedule = require("node-schedule"); // Use node-schedule for better cron-like jobs
const cloudinary = require("cloudinary").v2; // Import Cloudinary V2
const User = require("./models/User");
const Message = require("./models/Message");
const Group = require("./models/Group"); // Import Group model
const Chat = require("./models/Chat"); // Add this line
const bcrypt = require("bcryptjs");
const moment = require("moment-timezone");
const pakistaniFestivals = require("./utils/pakistani_festivals");
const { sendFestivalWish } = require("./utils/festivalService");
const config = require("./src/config/config");
const { initializeSocket } = require("./src/socket/socketHandler");
const {
  checkScheduledAndExpiredMessages,
} = require("./src/services/messageService");
const reportRoutes = require("./routes/report");
const fs = require("fs");
const path = require("path");

const app = express();
const server = http.createServer(app);
const io = new Server(server, {
  cors: {
    origin: "*",
    methods: ["GET", "POST"],
  },
});

const userSockets = new Map();

// Now require routes after io and userSockets are initialized
const authRoutes = require("./routes/auth");
const groupRoutes = require("./routes/group");
const messageRoutes = require("./routes/message")(io, userSockets);
const searchRoutes = require("./routes/search");
const userRoutes = require("./routes/user");

// Import birthday service
const birthdayService = require("./utils/birthdayService");

app.use(cors());
app.use(bodyParser.json());

// Add a simple root route to check server status
app.get("/", (req, res) => {
  res.status(200).json({ status: "ok", message: "Conway server is running" });
});

io.on("connection", (socket) => {
  console.log("a user connected:", socket.id);

  socket.on("join", (userId) => {
    console.log(
      `[Socket JOIN] Received userId: ${userId} (Type: ${typeof userId})`
    );
    if (userId) {
      const userIdStr = userId.toString();
      socket.userId = userIdStr; // Store userId on the socket object
      userSockets.set(userIdStr, socket.id);
      socket.join(userIdStr);
      console.log(
        `[Socket JOIN] Mapped userId '${userIdStr}' to socket ${socket.id} and stored on socket object.`
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
      // --- Profanity Filter (Custom List) ---
      const profanityPath = path.join(__dirname, "utils/custom_profanity.json");
      let customProfanity = [];
      if (fs.existsSync(profanityPath)) {
        try {
          customProfanity = JSON.parse(fs.readFileSync(profanityPath, "utf8"));
        } catch (e) {
          customProfanity = [];
        }
      }
      const plainMessageText = (messageText || "").toLowerCase();
      const messageWords = plainMessageText.split(/\s+/);
      const foundBadWord = customProfanity.find((word) =>
        messageWords.includes(word)
      );
      if (foundBadWord) {
        socket.emit("messageError", {
          message: `Your message contains a prohibited word: '${foundBadWord}'. Please remove it and try again.`,
        });
        return;
      }

      // --- Get Sender ---
      const sender = await User.findById(senderId).select("fullname email _id");
      if (!sender) {
        console.error(`[Socket SEND] Sender not found for ID: ${senderId}`);
        socket.emit("messageError", { message: "Sender not found" });
        return;
      }
      const senderName = sender.fullname;
      console.log(`[Socket SEND] Sender found: ${senderName} (${senderId})`);

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

        // Update the last message reference in the chat ONLY IF NOT SCHEDULED and NOT BURNOUT
        if (!newMessage.isScheduled && !newMessage.isBurnout) {
          await Chat.findByIdAndUpdate(chat._id, {
            lastMessage: newMessage._id,
          });
          console.log(
            `[Socket SEND] Updated chat ${chat._id} lastMessage to ${newMessage._id}`
          );
        } else {
          console.log(
            `[Socket SEND] Chat ${chat._id} lastMessage NOT updated (message is scheduled or burnout).`
          );
        }

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

        // Update the last message reference in the chat ONLY IF NOT SCHEDULED and NOT BURNOUT
        if (!newMessage.isScheduled && !newMessage.isBurnout) {
          await Chat.findByIdAndUpdate(chat._id, {
            lastMessage: newMessage._id,
          });
          console.log(
            `[Socket SEND] Updated chat ${chat._id} lastMessage to ${newMessage._id}`
          );
        } else {
          console.log(
            `[Socket SEND] Chat ${chat._id} lastMessage NOT updated (message is scheduled or burnout).`
          );
        }

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

  // --- Handle Message Deletion ---
  socket.on("deleteMessage", async (data) => {
    console.log("[Socket DELETE] deleteMessage event received:", data);
    const { messageId, groupId } = data;
    const requesterUserId = socket.userId; // Get userId stored during join

    // Basic validation
    if (!messageId || !groupId || !requesterUserId) {
      console.error(
        "[Socket DELETE] Invalid delete data (missing messageId, groupId, or requesterUserId):",
        data
      );
      socket.emit("messageDeleteError", {
        messageId: messageId,
        message: "Invalid request data.",
      });
      return;
    }

    try {
      // Fetch message, populate sender and group (with admins)
      const message = await Message.findById(messageId)
        .populate("sender") // Populate full sender doc
        .populate("group"); // Populate full group doc

      if (!message) {
        console.error(`[Socket DELETE] Message not found for ID: ${messageId}`);
        socket.emit("messageDeleteError", {
          messageId: messageId,
          message: "Message not found.",
        });
        return;
      }

      // Check if the populated group matches the provided groupId
      if (!message.group || message.group._id.toString() !== groupId) {
        console.error(
          `[Socket DELETE] Message ${messageId} does not belong to group ${groupId}.`
        );
        socket.emit("messageDeleteError", {
          messageId: messageId,
          message: "Group mismatch.",
        });
        return;
      }

      // Permission check: Requester must be the sender OR a group admin
      const isSender = message.sender?._id.toString() === requesterUserId;
      // Corrected Admin Check: Compare requester to the group's creator
      const isAdmin = message.group.creator?.toString() === requesterUserId;

      console.log(
        `[Socket DELETE] Checking permissions for user ${requesterUserId} on msg ${messageId}: Sender=${isSender}, Admin=${isAdmin}`
      );

      if (!isSender && !isAdmin) {
        console.warn(
          `[Socket DELETE] Permission denied for user ${requesterUserId} to delete message ${messageId}.`
        );
        socket.emit("messageDeleteError", {
          messageId: messageId,
          message: "Permission denied.",
        });
        return;
      }

      // --- Permission Granted: Update the message ---
      const deletedPlaceholder = "message deleted";
      message.message = deletedPlaceholder;
      message.isEdited = true; // Indicate change
      // Optionally mark with deleted_at if needed for other logic, but changing text is key for UI
      message.deleted_at = new Date();
      await message.save();

      console.log(
        `[Socket DELETE] Message ${messageId} content updated to '${deletedPlaceholder}' by user ${requesterUserId}.`
      );

      // --- Broadcast the deletion to group members ---
      const deletionUpdatePayload = {
        messageId: messageId,
        groupId: groupId,
        deletedByUserId: requesterUserId,
        deletedByAdmin: isAdmin,
        deletedAt: message.deleted_at.toISOString(),
      };

      message.group.users.forEach((userId) => {
        const memberIdStr = userId.toString();
        const memberSocketId = userSockets.get(memberIdStr);
        if (memberSocketId) {
          console.log(
            `[Socket DELETE] Emitting messageDeleted to member ${memberIdStr} (Socket: ${memberSocketId}) for msg ${messageId}`
          );
          io.to(memberSocketId).emit(
            "groupMessageDeleted",
            deletionUpdatePayload
          );
        } else {
          console.log(
            `[Socket DELETE] Member ${memberIdStr} for group ${groupId} is OFFLINE.`
          );
        }
      });

      // Optionally confirm success back to the requester
      socket.emit("messageDeleteSuccess", { messageId: messageId });
    } catch (error) {
      console.error(
        `[Socket DELETE] Error handling deleteMessage for message ${messageId}:`,
        error
      );
      socket.emit("messageDeleteError", {
        messageId: messageId,
        message: "Server error deleting message.",
      });
    }
  });
  // --- End Handle Message Deletion ---

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
// Run scheduler every 30 seconds (adjust interval as needed)
setInterval(checkScheduledAndExpiredMessages, 30 * 1000);
console.log(
  "[Scheduler] Scheduled message & burnout check job started (every 30 seconds)."
);

// Daily Birthday Job at midnight
schedule.scheduleJob("0 0 * * *", async () => {
  const now = new Date();
  const month = now.getMonth() + 1;
  const day = now.getDate();
  console.log(`[Birthday Job] Running daily birthday job for ${month}-${day}`);
  try {
    const birthdayUsers = await User.find({
      dateOfBirth: { $exists: true, $ne: null },
      $expr: {
        $and: [
          { $eq: [{ $dayOfMonth: "$dateOfBirth" }, day] },
          { $eq: [{ $month: "$dateOfBirth" }, month] },
        ],
      },
    });
    console.log(
      `[Birthday Job] Found ${birthdayUsers.length} users with birthdays today.`
    );
    if (birthdayUsers.length === 0) return;
    // Ensure system user exists
    let systemUser = await User.findOne({ userName: "Conway" });
    if (!systemUser) {
      const salt = await bcrypt.genSalt(10);
      const hashedPassword = await bcrypt.hash("Conway@2025", salt);
      systemUser = await User.create({
        fullname: "Conway",
        userName: "Conway",
        email: "conway@system",
        password: hashedPassword,
        isVerified: true,
      });
      console.log(`[Birthday Job] Created system user: ${systemUser._id}`);
    }
    for (const user of birthdayUsers) {
      let chat = await Chat.findOne({
        participants: { $all: [systemUser._id, user._id] },
        isGroup: false,
      });
      if (!chat) {
        chat = await Chat.create({
          participants: [systemUser._id, user._id],
          isGroup: false,
        });
      }
      const messageText = `Happy Birthday, ${user.fullname}! 🎉`;
      const newMessage = new Message({
        sender: systemUser._id,
        receiver: user._id,
        chat: chat._id,
        message: messageText,
        time: now,
        sent: true,
      });
      await newMessage.save();
      await Chat.findByIdAndUpdate(chat._id, { lastMessage: newMessage._id });
      const socketId = userSockets.get(user._id.toString());
      if (socketId) {
        io.to(socketId).emit("receiveMessage", {
          id: newMessage._id.toString(),
          senderId: systemUser._id.toString(),
          senderEmail: systemUser.email,
          senderName: systemUser.fullname,
          receiverEmail: user.email,
          text: messageText,
          time: now.toISOString(),
          isBurnout: false,
          expireAt: null,
          isScheduled: false,
          scheduledAt: null,
        });
      }
    }
    console.log("[Birthday Job] Birthday messages sent successfully.");
  } catch (err) {
    console.error("[Birthday Job] Error sending birthday messages:", err);
  }
});

// --- NEW BIRTHDAY JOBS ---
// 1. Daily Prepopulation at midnight UTC
schedule.scheduleJob("0 0 * * *", async () => {
  console.log("[Birthday Service] Running daily prepopulation job");
  await birthdayService.prepopulateBirthdayWishes();
});

// 2. Frequent Sending Job - Run every 6 hours (4 times a day)
schedule.scheduleJob(
  {
    rule: "0 0,6,12,18 * * *",
    tz: "Asia/Karachi",
  },
  async () => {
    // Cron for every 6 hours (4 times a day)
    console.log(
      "[Birthday Service] Running birthday wish sending job (every 6 hours, Asia/Karachi timezone)"
    );
    await birthdayService.sendBirthdayWishes(io, userSockets);
  }
);

// 3. Daily Cleanup Job - Run at 11:59 PM Asia/Karachi time
schedule.scheduleJob(
  {
    rule: "59 23 * * *",
    tz: "Asia/Karachi",
  },
  async () => {
    console.log("[Birthday Service] Running cleanup job before new day");
    await birthdayService.cleanupBirthdayWishes();
  }
);
// --- END NEW BIRTHDAY JOBS ---

// --- NEW FESTIVAL SCHEDULER ---
schedule.scheduleJob(
  {
    rule: "0 0 * * *", // Every day at midnight
    tz: "Asia/Karachi",
  },
  async () => {
    const today = moment().tz("Asia/Karachi").format("MM-DD");
    const todayFestivals = pakistaniFestivals.filter((f) => f.date === today);
    for (const fest of todayFestivals) {
      await sendFestivalWish(fest.message);
      console.log(`[Festival Scheduler] Sent festival wish: ${fest.name}`);
    }
    // TODO: Add Islamic festival logic here
  }
);
// --- END FESTIVAL SCHEDULER ---

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
    console.log("Connected to MongoDB");

    // Use routes AFTER connection is successful
    app.use("/api", authRoutes);
    app.use("/api", groupRoutes);
    app.use("/api", messageRoutes);
    app.use("/api", searchRoutes);
    app.use("/api/user", userRoutes); // Use the new user routes
    app.use("/api", reportRoutes); // Register report routes

    server.listen(3001, "0.0.0.0", () => {
      console.log(`Server is running on port ${config.PORT}`);
    });

    // Start scheduled tasks
    setInterval(
      checkScheduledAndExpiredMessages,
      config.MESSAGE_CHECK_INTERVAL
    );
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

// Error handling middleware
app.use((err, req, res, next) => {
  console.error(err.stack);
  res.status(500).json({
    status: "error",
    message: "Something went wrong!",
    error: process.env.NODE_ENV === "development" ? err.message : undefined,
  });
});
