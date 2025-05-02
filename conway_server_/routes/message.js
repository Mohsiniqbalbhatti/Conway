const express = require("express");
const router = express.Router();
const User = require("../models/User");
const Group = require("../models/Group");
const Message = require("../models/Message");
const Chat = require("../models/Chat");
// const { encrypt, decrypt } = require('../utils/crypto'); // Import crypto utils

// Wrap the router definition in a function that accepts the io instance
module.exports = (io, userSockets) => {
  // Get update - Fetches latest message per conversation and groups
  router.post("/getupdate", async (req, res) => {
    console.log(`[GETUPDATE] Received request for email: ${req.body.myemail}`);
    const { myemail } = req.body;

    if (!myemail) {
      return res.status(400).json({ error: "Email is required" });
    }

    try {
      const me = await User.findOne({ email: myemail });
      if (!me) {
        return res.status(404).json({ error: "User not found" });
      }
      console.log(`[GETUPDATE] Found user: ${me.fullname} (ID: ${me._id})`);

      // 1. Fetch groups (no change needed here for now)
      const groups = await Group.find({
        users: me._id,
        deleted_at: null,
      }).populate("creator", "fullname email");
      console.log(`[GETUPDATE] Found ${groups.length} groups.`);

      // 2. Fetch direct chats the user is part of (don't populate lastMessage yet)
      const chats = await Chat.find({
        participants: me._id,
        isGroup: false,
      })
        .populate({
          // Still need participants to get the other user's info
          path: "participants",
          match: { _id: { $ne: me._id } },
          select: "fullname email _id profileUrl",
        })
        .sort({ updatedAt: -1 }); // Sort chats by most recently updated

      console.log(`[GETUPDATE] Found ${chats.length} direct chats for user.`);

      // Helper function to find the latest suitable preview message for a chat
      const getSuitablePreviewMessage = async (chatId) => {
        const now = new Date();
        const message = await Message.findOne({
          chat: chatId,
          deleted_at: null, // Must not be deleted
          $or: [
            // Must NOT be scheduled in the future
            { isScheduled: false },
            { scheduledAt: { $lte: now } },
          ],
          $nor: [
            // Must NOT be an expired burnout message
            { isBurnout: true, expireAt: { $lte: now } },
          ],
        }).sort({ time: -1 }); // Get the latest one matching criteria

        // console.log(`[GETUPDATE Helper] Chat ${chatId}, Suitable Message: ${message?._id}`);
        return message;
      };

      // 3. Process chats to find suitable preview messages
      let responseMessages = [];
      for (const chat of chats) {
        const previewMessage = await getSuitablePreviewMessage(chat._id);

        if (
          previewMessage &&
          chat.participants &&
          chat.participants.length > 0
        ) {
          const otherUser = chat.participants[0]; // Should be populated correctly
          if (otherUser) {
            responseMessages.push({
              name: otherUser.fullname,
              email: otherUser.email,
              profileUrl: otherUser.profileUrl ?? "",
              message: previewMessage.message ?? "",
              time: previewMessage.time.toISOString(),
            });
          } else {
            console.warn(
              `[GETUPDATE] Chat ${chat._id} missing other participant after populate.`
            );
          }
        } else if (!previewMessage) {
          console.log(
            `[GETUPDATE] No suitable preview message found for chat ${chat._id}. Skipping.`
          );
        }
      }

      console.log(
        `[GETUPDATE] Sending ${responseMessages.length} formatted chat previews.`
      );

      res.send({
        groups: groups.map((g) => ({
          name: g.groupName,
          groupId: g._id,
          creator: g.creator.fullname,
          memberCount: g.users.length,
        })),
        message: responseMessages, // Send the processed list
      });
    } catch (err) {
      console.error(`[GETUPDATE] Error for ${myemail}:`, err);
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
          {
            sender: receiver._id,
            isScheduled: true,
            scheduledAt: { $gt: now },
          }, // Scheduled by receiver, not due
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

  // DELETE a specific message (Admin only for group messages)
  router.delete("/messages/:messageId", async (req, res) => {
    const { messageId } = req.params;
    const { userId: adminUserId } = req.body; // ID of admin making the request
    const now = new Date();

    console.log(
      `[DELETE /messages] Request received for message ${messageId} by admin ${adminUserId}`
    );

    if (!adminUserId) {
      return res
        .status(400)
        .json({ error: "Admin User ID is required for authorization." });
    }
    if (!messageId) {
      return res.status(400).json({ error: "Message ID is required." });
    }

    try {
      const message = await Message.findById(messageId).populate("group");
      if (!message) {
        return res.status(404).json({ error: "Message not found." });
      }

      // --- Authorization Check ---
      if (!message.group) {
        return res.status(403).json({
          error: "Forbidden: Cannot delete non-group messages via this route.",
        });
      }

      const group = message.group; // Already populated
      if (!group) {
        return res.status(404).json({ error: "Associated group not found." });
      }

      if (group.creator.toString() !== adminUserId) {
        console.warn(
          `[DELETE /messages] Unauthorized attempt by user ${adminUserId} to delete message ${messageId} in group ${group._id} (Creator: ${group.creator})`
        );
        return res.status(403).json({
          error: "Forbidden: Only the group admin can delete messages.",
        });
      }

      // --- Perform Soft Deletion ---
      if (message.deleted_at) {
        console.log(
          `[DELETE /messages] Message ${messageId} already marked as deleted.`
        );
        return res.status(200).json({ message: "Message already deleted." });
      }

      message.deleted_at = now;
      await message.save();

      console.log(
        `[DELETE /messages] Message ${messageId} marked as deleted by admin ${adminUserId}.`
      );

      // --- Emit Socket Event to INDIVIDUAL Online Group Members ---
      const deletedEventData = {
        messageId: messageId,
        groupId: group._id.toString(),
        deletedBy: adminUserId,
      };

      group.users.forEach((memberId) => {
        const memberIdStr = memberId.toString();
        // Don't send the event back to the admin who initiated the delete
        if (memberIdStr !== adminUserId) {
          const memberSocketId = userSockets.get(memberIdStr);
          if (memberSocketId) {
            // User is online, emit directly to their socket
            io.to(memberSocketId).emit("groupMessageDeleted", deletedEventData);
            console.log(
              `[DELETE /messages] Emitted 'groupMessageDeleted' to user ${memberIdStr} (Socket: ${memberSocketId})`
            );
          } else {
            // User is offline, no need to emit
            console.log(
              `[DELETE /messages] User ${memberIdStr} is offline, skipping socket emit.`
            );
          }
        }
      });
      // --- End Emit Logic ---

      res.status(200).json({ message: "Message deleted successfully." });
    } catch (err) {
      console.error(
        `[DELETE /messages] Error deleting message ${messageId}:`,
        err
      );
      res
        .status(500)
        .json({ error: "Failed to delete message", details: err.message });
    }
  });

  return router; // Return the configured router
};
