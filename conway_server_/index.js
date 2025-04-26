require("dotenv").config();
const express = require("express");
const mongoose = require("mongoose");
const bodyParser = require("body-parser");
const cors = require("cors");
const http = require('http');
const { Server } = require("socket.io");
const authRoutes = require("./routes/auth");
const groupRoutes = require("./routes/group");
const messageRoutes = require("./routes/message");
const searchRoutes = require("./routes/search");
const User = require('./models/User');
const Message = require('./models/Message');

const app = express();
const server = http.createServer(app);
const io = new Server(server, {
  cors: {
    origin: "*",
    methods: ["GET", "POST"]
  }
});

app.use(cors());
app.use(bodyParser.json());

const userSockets = new Map();

io.on('connection', (socket) => {
  console.log('a user connected:', socket.id);

  socket.on('join', (userId) => {
    console.log(`[Socket JOIN] Received userId: ${userId} (Type: ${typeof userId})`);
    if (userId) {
      const userIdStr = userId.toString();
      userSockets.set(userIdStr, socket.id);
      socket.join(userIdStr);
      console.log(`[Socket JOIN] Mapped userId '${userIdStr}' to socket ${socket.id}`);
      console.log('[Socket JOIN] Current userSockets map:', Object.fromEntries(userSockets));
    } else {
      console.warn('[Socket JOIN] Received null or undefined userId.');
    }
  });

  socket.on('sendMessage', async (data) => {
    console.log('[Socket SEND] sendMessage event received:', data);
    const { senderId, receiverEmail, messageText } = data;

    if (!senderId || !receiverEmail || !messageText) {
      console.error('[Socket SEND] Invalid sendMessage data:', data);
      socket.emit('messageError', { message: 'Invalid message data' });
      return;
    }

    try {
      const sender = await User.findById(senderId);
      const senderName = sender ? sender.fullname : 'Unknown Sender';

      const receiver = await User.findOne({ email: receiverEmail });
      if (!receiver) {
        console.error(`[Socket SEND] Receiver not found for email: ${receiverEmail}`);
        socket.emit('messageError', { message: 'Receiver not found' });
        return;
      }
      const receiverId = receiver._id.toString();
      console.log(`[Socket SEND] Found receiver: ${receiver.fullname} (ID: ${receiverId})`);

      const plainMessageText = messageText;

      const newMessage = new Message({
        sender: senderId,
        receiver: receiver._id,
        message: plainMessageText,
        time: new Date(),
        sent: false
      });
      await newMessage.save();
      console.log('[Socket SEND] Plain text message saved to DB');

      const messageToSend = {
        senderId: senderId,
        senderEmail: data.senderEmail,
        senderName: senderName,
        receiverEmail: receiverEmail,
        text: plainMessageText,
        time: newMessage.time.toISOString()
      };

      console.log('[Socket SEND] Looking up recipient in userSockets map:', Object.fromEntries(userSockets));
      console.log(`[Socket SEND] Attempting to get socket for receiverId: '${receiverId}' (Type: ${typeof receiverId})`);

      const recipientSocketId = userSockets.get(receiverId);

      if (recipientSocketId) {
        console.log(`[Socket SEND] Found recipient socket: ${recipientSocketId}. Emitting receiveMessage...`);
        io.to(recipientSocketId).emit('receiveMessage', messageToSend);
        console.log(`Emitted receiveMessage to ${receiverEmail} (socket ${recipientSocketId})`);
        newMessage.sent = true;
        await newMessage.save();
      } else {
        console.log(`[Socket SEND] Recipient ${receiverEmail} (ID: ${receiverId}) is OFFLINE (socket not found in map).`);
      }

      socket.emit('messageSent', { tempId: data.tempId, dbId: newMessage._id, time: newMessage.time });

    } catch (error) {
      console.error('[Socket SEND] Error handling sendMessage:', error);
      socket.emit('messageError', { message: 'Server error sending message' });
    }
  });

  socket.on('disconnect', () => {
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
      console.log(`[Socket DISCONNECT] Removed mapping for user ${deletedUserId}`);
    } else {
      console.log(`[Socket DISCONNECT] No user mapping found for disconnected socket ${socket.id}`);
    }
    console.log('[Socket DISCONNECT] Current userSockets map:', Object.fromEntries(userSockets));
  });
});

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
