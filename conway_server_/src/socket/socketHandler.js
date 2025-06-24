const { Server } = require("socket.io");
const User = require("../../models/User");
const Message = require("../../models/Message");
const Group = require("../../models/Group");
const Chat = require("../../models/Chat");
const { handleScheduledMessage } = require("../services/messageService");

const userSockets = new Map();

function initializeSocket(server) {
  const io = new Server(server, {
    cors: {
      origin: "*",
      methods: ["GET", "POST"],
    },
  });

  io.on("connection", (socket) => {
    console.log("a user connected:", socket.id);

    socket.on("join", (userId) => {
      console.log(
        `[Socket JOIN] Received userId: ${userId} (Type: ${typeof userId})`
      );
      if (userId) {
        const userIdStr = userId.toString();
        socket.userId = userIdStr;
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
        burnoutDateTime,
        scheduleDateTime,
        senderEmail,
        tempId,
      } = data;

      // Basic Validation
      if (!senderId || !messageText || !(receiverEmail || groupId)) {
        console.error(
          "[Socket SEND] Invalid message data (missing senderId, messageText, or receiverEmail/groupId):",
          data
        );
        socket.emit("messageError", { message: "Invalid message data" });
        return;
      }

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
        const sender = await User.findById(senderId).select(
          "fullname email _id"
        );
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
          isScheduled: false,
          scheduledAt: null,
          isBurnout: false,
          expireAt: null,
          sent: false,
        };

        // Process schedule and burnout times
        const isScheduledInput = !!scheduleDateTime;
        const isBurnoutInput = !!burnoutDateTime;
        let scheduleTime = isScheduledInput ? new Date(scheduleDateTime) : null;
        let expireTime = isBurnoutInput ? new Date(burnoutDateTime) : null;

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

        newMessageData.isScheduled = !!scheduleTime;
        newMessageData.scheduledAt = scheduleTime;
        newMessageData.isBurnout = !!expireTime;
        newMessageData.expireAt = expireTime;

        // Handle Group Message
        if (groupId) {
          await handleGroupMessage(
            groupId,
            newMessageData,
            senderName,
            socket,
            io
          );
        } else {
          await handleDirectMessage(
            receiverEmail,
            newMessageData,
            senderName,
            socket,
            io
          );
        }
      } catch (error) {
        console.error("[Socket SEND] Error processing message:", error);
        socket.emit("messageError", { message: "Error processing message" });
      }
    });

    socket.on("disconnect", () => {
      console.log("user disconnected:", socket.id);
      if (socket.userId) {
        userSockets.delete(socket.userId);
      }
    });
  });

  return { io, userSockets };
}

async function handleGroupMessage(
  groupId,
  newMessageData,
  senderName,
  socket,
  io
) {
  newMessageData.group = groupId;
  newMessageData.receiver = null;

  console.log(`[Socket SEND] Processing group message for group: ${groupId}`);
  const group = await Group.findById(groupId).select("users");
  if (!group) {
    console.error(`[Socket SEND] Group not found for ID: ${groupId}`);
    socket.emit("messageError", { message: "Group not found" });
    return;
  }

  let chat = await Chat.findOne({
    group: groupId,
    isGroup: true,
  });

  if (!chat) {
    console.log(
      "[Socket SEND] No existing group chat found. Creating new chat."
    );
    chat = await Chat.create({
      participants: group.users,
      group: groupId,
      isGroup: true,
    });
    console.log(`[Socket SEND] New group chat created: ${chat._id}`);
  } else {
    console.log(`[Socket SEND] Found existing group chat: ${chat._id}`);
    if (!chat.participants || chat.participants.length !== group.users.length) {
      console.log(
        `[Socket SEND] Updating participants in existing group chat ${chat._id}`
      );
      chat.participants = group.users;
      await chat.save();
    }
  }

  newMessageData.chat = chat._id;
  const newMessage = new Message(newMessageData);
  await newMessage.save();

  if (!newMessage.isScheduled && !newMessage.isBurnout) {
    await Chat.findByIdAndUpdate(chat._id, {
      lastMessage: newMessage._id,
    });
  }

  if (!newMessage.isScheduled) {
    const messageToSend = {
      id: newMessage._id.toString(),
      groupId: groupId,
      senderId: newMessageData.sender,
      senderName: senderName,
      text: newMessageData.message,
      time: newMessage.time.toISOString(),
      isBurnout: newMessage.isBurnout,
      expireAt: newMessage.expireAt?.toISOString(),
      isScheduled: newMessage.isScheduled,
      scheduledAt: newMessage.scheduledAt?.toISOString(),
    };

    group.users.forEach((userId) => {
      const memberIdStr = userId.toString();
      if (memberIdStr !== newMessageData.sender) {
        const memberSocketId = userSockets.get(memberIdStr);
        if (memberSocketId) {
          io.to(memberSocketId).emit("receiveMessage", messageToSend);
        }
      }
    });
  }

  if (newMessage.isScheduled) {
    handleScheduledMessage(newMessage, io, userSockets);
  }
}

async function handleDirectMessage(
  receiverEmail,
  newMessageData,
  senderName,
  socket,
  io
) {
  const receiver = await User.findOne({ email: receiverEmail });
  if (!receiver) {
    console.error(
      `[Socket SEND] Receiver not found for email: ${receiverEmail}`
    );
    socket.emit("messageError", { message: "Receiver not found" });
    return;
  }

  newMessageData.receiver = receiver._id;
  newMessageData.group = null;

  let chat = await Chat.findOne({
    participants: { $all: [newMessageData.sender, receiver._id] },
    isGroup: false,
  });

  if (!chat) {
    chat = await Chat.create({
      participants: [newMessageData.sender, receiver._id],
      isGroup: false,
    });
  }

  newMessageData.chat = chat._id;
  const newMessage = new Message(newMessageData);
  await newMessage.save();

  if (!newMessage.isScheduled && !newMessage.isBurnout) {
    await Chat.findByIdAndUpdate(chat._id, {
      lastMessage: newMessage._id,
    });
  }

  if (!newMessage.isScheduled) {
    const messageToSend = {
      id: newMessage._id.toString(),
      senderId: newMessageData.sender,
      senderName: senderName,
      text: newMessageData.message,
      time: newMessage.time.toISOString(),
      isBurnout: newMessage.isBurnout,
      expireAt: newMessage.expireAt?.toISOString(),
      isScheduled: newMessage.isScheduled,
      scheduledAt: newMessage.scheduledAt?.toISOString(),
    };

    const receiverSocketId = userSockets.get(receiver._id.toString());
    if (receiverSocketId) {
      io.to(receiverSocketId).emit("receiveMessage", messageToSend);
    }
  }

  if (newMessage.isScheduled) {
    handleScheduledMessage(newMessage, io, userSockets);
  }
}

module.exports = { initializeSocket, userSockets };
