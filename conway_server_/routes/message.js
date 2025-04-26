const express = require('express');
const router = express.Router();
const User = require('../models/User');
const Group = require('../models/Group');
const Message = require('../models/Message');
// const { encrypt, decrypt } = require('../utils/crypto'); // Import crypto utils

// Get update - Note: This needs review. It sends unsent messages, but might need adjustment with socket handling
router.post('/getupdate', async (req, res) => {
  console.log(`[GETUPDATE] Received request for email: ${req.body.myemail}`);
  const now = new Date();
  const { myemail } = req.body;

  if (!myemail) {
    console.error('[GETUPDATE] Error: Email missing in request body.');
    return res.status(400).json({ error: 'Email is required in the request body' });
  }

  const me = await User.findOne({ email: myemail });

  if (!me) {
    console.error(`[GETUPDATE] Error: User not found for email: ${myemail}`);
    return res.status(404).json({ error: 'User not found' });
  }
  console.log(`[GETUPDATE] Found current user: ${me.fullname} (ID: ${me._id})`);

  // Fetch groups the user is in (remains the same)
  const groups = await Group.find({
    users: me._id, 
    $or: [
      { deleted_at: null },
      { deleted_at: { $gt: now } }
    ]
  }).populate('creator', 'fullname email');
  console.log(`[GETUPDATE] Found ${groups.length} groups for user.`);

  // Fetch latest message for each 1-to-1 conversation
  let recentMessages = [];
  try {
    recentMessages = await Message.aggregate([
      { $match: { 
          group: null,
          $or: [{ sender: me._id }, { receiver: me._id }] 
        }
      },
      { $sort: { time: -1 } },
      { $group: {
          _id: {
            $cond: [
              { $eq: ["$sender", me._id] },
              "$receiver",
              "$sender"
            ]
          },
          lastMessage: { $first: "$$ROOT" }
        }
      },
      { $replaceRoot: { newRoot: "$lastMessage" } },
      { $limit: 50 } 
    ]);
    console.log(`[GETUPDATE] Aggregation found ${recentMessages.length} recent conversations.`);

    if (recentMessages.length > 0) { // Only populate if there are messages
        await Message.populate(recentMessages, { path: 'sender receiver', select: 'fullname email _id' });
        console.log(`[GETUPDATE] Populated sender/receiver for recent messages.`);
    }

  } catch (aggError) {
      console.error("[GETUPDATE] Error during message aggregation:", aggError);
      // Decide if you want to return partial data or an error
      // For now, continue with potentially empty recentMessages
  }

  // Prepare the response
  const responseMessages = recentMessages.map(m => {
      const isSenderMe = m.sender?._id.equals(me._id);
      const otherUser = isSenderMe ? m.receiver : m.sender;
      
      if (!otherUser) {
          console.warn(`[GETUPDATE] Warning: Missing other user details for message ID ${m._id}. Sender: ${m.sender?._id}, Receiver: ${m.receiver?._id}`);
          return null;
      }
      
      return {
        name: otherUser.fullname,
        email: otherUser.email,
        message: m.message ?? '', // Plain text
        time: m.time
      };

    }).filter(m => m !== null); 
  
  console.log(`[GETUPDATE] Sending ${responseMessages.length} formatted messages in response.`);

  res.send({
    groups: groups.map(g => ({
      name: g.groupName,
      groupId: g._id,
      creator: g.creator.fullname,
      memberCount: g.users.length
    })),
    message: responseMessages,
  });
});


// Get messages between two users (fetch history)
router.post('/get-messages', async (req, res) => {
  try {
    const { senderEmail, receiverEmail } = req.body;
    
    if (!senderEmail || !receiverEmail) {
      return res.status(400).json({ error: 'Sender and receiver emails are required' });
    }
    
    const sender = await User.findOne({ email: senderEmail });
    const receiver = await User.findOne({ email: receiverEmail });
    
    if (!sender || !receiver) {
      return res.status(404).json({ error: 'One or both users not found' });
    }
    
    const messages = await Message.find({
      group: null,
      $or: [
        { sender: sender._id, receiver: receiver._id },
        { sender: receiver._id, receiver: sender._id }
      ],
      deleted_at: null
    }).sort({ time: 1 })
      .populate('sender receiver', 'fullname email'); // Populate needed info
    
    // Format messages, send plain text directly
    const formattedMessages = messages.map(msg => ({
      id: msg._id, 
      senderId: msg.sender._id, 
      senderEmail: msg.sender.email,
      receiverEmail: msg.receiver.email,
      text: msg.message, // Send plain text as stored
      time: msg.time.toISOString(), 
      sent: msg.sent
    }));
    
    // Mark messages TO ME in this specific chat as read/sent? 
    // Better to handle read status separately.
    // await Message.updateMany(
    //   { sender: receiver._id, receiver: sender._id, sent: false },
    //   { $set: { sent: true } }
    // );
    
    res.json({ messages: formattedMessages });
  } catch (err) {
    res.status(500).json({ error: 'Failed to get messages', details: err.message });
  }
});

// Store a new message (DEPRECATED by socket handler, keep for reference or specific cases?)
router.post('/sendMessage', async (req, res) => {
  // This endpoint is now largely handled by the Socket.IO 'sendMessage' event.
  // If needed for specific scenarios (e.g., offline queuing), 
  // ensure it encrypts messages similarly to the socket handler.
  res.status(405).json({ message: 'Use Socket.IO `sendMessage` event instead.'});
});

module.exports = router;
