const express = require("express");
const router = express.Router();
const User = require("../models/User");
const Group = require("../models/Group");
const Message = require("../models/Message");
const Chat = require("../models/Chat");
// const { encrypt, decrypt } = require('../utils/crypto'); // Import crypto utils

// Get update - Fetches latest message per conversation and groups
router.post("/getupdate", async (req, res) => {
  console.log(`[GETUPDATE] Received request for email: ${req.body.myemail}`);
  const now = new Date();
  const { myemail } = req.body;

  if (!myemail) {
    console.error("[GETUPDATE] Error: Email missing in request body.");
    return res
      .status(400)
      .json({ error: "Email is required in the request body" });
  }

  try {
    const me = await User.findOne({ email: myemail });

    if (!me) {
      console.error(`[GETUPDATE] Error: User not found for email: ${myemail}`);
      return res.status(404).json({ error: "User not found" });
    }
    console.log(
      `[GETUPDATE] Found current user: ${me.fullname} (ID: ${me._id})`
    );

    // Fetch groups the user is in
    const groups = await Group.find({
      users: me._id,
      $or: [{ deleted_at: null }, { deleted_at: { $gt: now } }],
    }).populate("creator", "fullname email");
    console.log(`[GETUPDATE] Found ${groups.length} groups for user.`);

    // Fetch chats (conversations) the user is participating in
    const chats = await Chat.find({
      participants: me._id,
      isGroup: false,
    })
      .populate({
        path: "lastMessage",
        match: {
          isScheduled: { $ne: true }, // Exclude pending scheduled messages
          $or: [
            // Include non-burnout OR burnout that haven't expired
            { isBurnout: false },
            { expireAt: { $gt: now } },
          ],
        },
      })
      .populate({
        path: "participants",
        match: { _id: { $ne: me._id } }, // Exclude current user from participants
        select: "fullname email _id profileUrl",
      })
      .sort({ "lastMessage.time": -1 })
      .limit(50);

    console.log(`[GETUPDATE] Found ${chats.length} chats for user.`);

    // Format the response messages
    const responseMessages = chats
      .filter((chat) => chat.lastMessage) // Only include chats with messages
      .map((chat) => {
        const otherUser = chat.participants[0]; // We filtered to only include other users

        if (!otherUser) {
          console.warn(
            `[GETUPDATE] Warning: Missing other user details for chat ID ${chat._id}.`
          );
          return null;
        }

        return {
          name: otherUser.fullname,
          email: otherUser.email,
          profileUrl: otherUser.profileUrl ?? "",
          message: chat.lastMessage.message ?? "",
          time: chat.lastMessage.time.toISOString(),
        };
      })
      .filter((m) => m !== null);

    console.log(
      `[GETUPDATE] Sending ${responseMessages.length} formatted messages in response.`
    );

    res.send({
      groups: groups.map((g) => ({
        name: g.groupName,
        groupId: g._id,
        creator: g.creator.fullname,
        memberCount: g.users.length,
      })),
      message: responseMessages,
    });
  } catch (err) {
    console.error(`[GETUPDATE] Unexpected error for ${myemail}:`, err);
    res
      .status(500)
      .json({ error: "Failed to get updates", details: err.message });
  }
});

// Get messages between two users (fetch history)
router.post("/get-messages", async (req, res) => {
  try {
    const { senderEmail, receiverEmail } = req.body;
    const now = new Date();

    if (!senderEmail || !receiverEmail) {
      return res
        .status(400)
        .json({ error: "Sender and receiver emails are required" });
    }

    const sender = await User.findOne({ email: senderEmail });
    const receiver = await User.findOne({ email: receiverEmail });

    if (!sender || !receiver) {
      return res.status(404).json({ error: "One or both users not found" });
    }

    // Find or create the chat between these users
    const chat = await Chat.findOne({
      participants: { $all: [sender._id, receiver._id] },
      isGroup: false,
    });

    if (!chat) {
      return res.json({ messages: [] }); // No chat exists yet between these users
    }

    // Fetch messages for this chat
    const messages = await Message.find({
      chat: chat._id,
      // Filter out ONLY messages that are:
      // 1. Burnout AND Expired
      // 2. Scheduled BY THE OTHER USER AND not yet due
      $nor: [
        { isBurnout: true, expireAt: { $lte: now } }, // Burnout and expired
        { sender: receiver._id, isScheduled: true, scheduledAt: { $gt: now } }, // Scheduled by receiver, not due
      ],
      deleted_at: null,
    })
      .sort({ time: 1 }) // Sort ascending for chat history
      .populate("sender receiver", "fullname email _id"); // Populate needed info

    // Format messages, send plain text directly
    const formattedMessages = messages.map((msg) => ({
      id: msg._id,
      senderId: msg.sender._id,
      senderEmail: msg.sender.email,
      receiverEmail: msg.receiver.email,
      text: msg.message,
      time: msg.time.toISOString(),
      isBurnout: msg.isBurnout,
      expireAt: msg.expireAt?.toISOString(),
      isScheduled: msg.isScheduled,
      scheduledAt: msg.scheduledAt?.toISOString(),
      sent: msg.sent,
    }));

    res.json({ messages: formattedMessages });
  } catch (err) {
    console.error(
      `[GET-MESSAGES] Error fetching between ${senderEmail} and ${receiverEmail}:`,
      err
    );
    res
      .status(500)
      .json({ error: "Failed to get messages", details: err.message });
  }
});

// Store a new message (DEPRECATED by socket handler)
router.post("/sendMessage", async (req, res) => {
  console.warn("[DEPRECATED ROUTE] /sendMessage called.");
  res
    .status(405)
    .json({ message: "Use Socket.IO `sendMessage` event instead." });
});

module.exports = router;
