const express = require("express");
const router = express.Router();
const User = require("../models/User");
const Group = require("../models/Group");
const Message = require("../models/Message");
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

    // Fetch latest message for each 1-to-1 conversation, filtering out expired/scheduled
    let recentMessages = [];
    try {
      recentMessages = await Message.aggregate([
        {
          $match: {
            group: null, // Only 1-to-1 chats
            $or: [{ sender: me._id }, { receiver: me._id }], // Involving the user
            isScheduled: { $ne: true }, // Exclude pending scheduled messages
            $or: [
              // Include non-burnout OR burnout that haven't expired
              { isBurnout: false },
              { expireAt: { $gt: now } },
            ],
          },
        },
        { $sort: { time: -1 } },
        {
          $group: {
            _id: {
              // Group by the other participant
              $cond: [{ $eq: ["$sender", me._id] }, "$receiver", "$sender"],
            },
            lastMessage: { $first: "$$ROOT" }, // Get the latest message for that participant
          },
        },
        { $replaceRoot: { newRoot: "$lastMessage" } }, // Reshape to message document
        { $sort: { time: -1 } }, // Sort the final list by time
        { $limit: 50 }, // Limit results
      ]);
      console.log(
        `[GETUPDATE] Aggregation found ${recentMessages.length} recent valid conversations.`
      );

      if (recentMessages.length > 0) {
        // Only populate if there are messages
        await Message.populate(recentMessages, {
          path: "sender receiver",
          select: "fullname email _id profileUrl",
        });
        console.log(
          `[GETUPDATE] Populated sender/receiver for recent messages.`
        );
      }
    } catch (aggError) {
      console.error("[GETUPDATE] Error during message aggregation:", aggError);
      // Continue with potentially empty recentMessages
    }

    // Prepare the response messages
    const responseMessages = recentMessages
      .map((m) => {
        const isSenderMe = m.sender?._id.equals(me._id);
        const otherUser = isSenderMe ? m.receiver : m.sender;

        if (!otherUser) {
          console.warn(
            `[GETUPDATE] Warning: Missing other user details for message ID ${m._id}. Sender: ${m.sender?._id}, Receiver: ${m.receiver?._id}`
          );
          return null;
        }

        return {
          name: otherUser.fullname,
          email: otherUser.email,
          profileUrl: otherUser.profileUrl ?? "", // Add profileUrl to response
          message: m.message ?? "", // Plain text
          time: m.time.toISOString(), // Send as ISO string
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

    // Fetch messages involving both users
    const messages = await Message.find({
      group: null,
      $or: [
        { sender: sender._id, receiver: receiver._id },
        { sender: receiver._id, receiver: sender._id },
      ],
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
