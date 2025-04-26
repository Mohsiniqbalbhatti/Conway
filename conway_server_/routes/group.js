const express = require('express');
const router = express.Router();
const Group = require('../models/Group');
const User = require('../models/User');
const Message = require('../models/Message');

// Create Group
router.post('/groups', async (req, res) => {
  try {
    const { groupName, creator, deleted_at } = req.body;
    const group = new Group({ groupName, creator, deleted_at, users: [creator] });
    await group.save();
    res.send({ message: 'Group created', group });
  } catch (err) {
    res.status(500).json({ error: 'Failed to create group', details: err.message });
  }
});

// Add User to Group
router.post('/addInGroup', async (req, res) => {
  try {
    const { userEmail, groupId } = req.body;
    const user = await User.findOne({ email: userEmail });

    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    const group = await Group.findById(groupId);
    if (!group) {
      return res.status(404).json({ error: 'Group not found' });
    }

    const userId = user._id;
    if (!group.users.includes(userId)) {
      group.users.push(userId);
      await group.save();
    }

    res.send({ message: 'User added to group' });
  } catch (err) {
    res.status(500).json({ error: 'Failed to add user to group', details: err.message });
  }
});

// Get group members
router.get('/group-members/:groupId', async (req, res) => {
  try {
    const { groupId } = req.params;
    
    const group = await Group.findById(groupId);
    if (!group) {
      return res.status(404).json({ error: 'Group not found' });
    }
    
    // Get user details for all group members
    const members = await User.find(
      { _id: { $in: group.users } },
      'fullname email profileUrl'
    );
    
    res.json({
      members: members.map(member => ({
        id: member._id,
        name: member.fullname,
        email: member.email,
        profileUrl: member.profileUrl,
      }))
    });
  } catch (err) {
    res.status(500).json({ error: 'Failed to get group members', details: err.message });
  }
});

// Get group messages
router.get('/group-messages/:groupId', async (req, res) => {
  try {
    const { groupId } = req.params;
    
    const group = await Group.findById(groupId);
    if (!group) {
      return res.status(404).json({ error: 'Group not found' });
    }
    
    // Get all messages for this group that aren't deleted
    const messages = await Message.find({
      group: groupId,
      deleted_at: null
    })
    .sort({ time: 1 })
    .populate('sender', 'fullname email');
    
    // Format messages for the client
    const formattedMessages = messages.map(msg => ({
      id: msg._id,
      senderId: msg.sender._id,
      senderName: msg.sender.fullname,
      senderEmail: msg.sender.email,
      text: msg.message,
      time: msg.time,
    }));
    
    res.json({ messages: formattedMessages });
  } catch (err) {
    res.status(500).json({ error: 'Failed to get group messages', details: err.message });
  }
});

// Get suggested groups for a user based on their chat contacts
router.get('/suggested-groups', async (req, res) => {
  try {
    const { email } = req.query;
    if (!email) {
      return res.status(400).json({ error: 'Email is required' });
    }

    // Find the user
    const user = await User.findOne({ email });
    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    // Find all messages to/from this user to identify their contacts
    const messages = await Message.find({
      $or: [
        { 'sender': user._id },
        { 'receiver': user._id }
      ]
    });

    // Extract unique user IDs the user has chatted with
    const contactIds = new Set();
    messages.forEach(msg => {
      if (msg.sender.toString() !== user._id.toString()) {
        contactIds.add(msg.sender.toString());
      }
      if (msg.receiver && msg.receiver.toString() !== user._id.toString()) {
        contactIds.add(msg.receiver.toString());
      }
    });

    // Find groups where the user's contacts are members, but the user is not
    const groups = await Group.find({
      users: { $nin: [user._id] } // User is not in these groups
    }).populate('users creator', 'fullname email');

    // Filter and sort groups by the number of the user's contacts in each group
    const suggestedGroups = groups.map(group => {
      const commonContacts = group.users.filter(groupUser => 
        contactIds.has(groupUser._id.toString())
      );
      
      return {
        _id: group._id,
        groupName: group.groupName,
        creator: {
          fullname: group.creator.fullname,
          email: group.creator.email
        },
        memberCount: group.users.length,
        commonContactsCount: commonContacts.length
      };
    })
    .filter(group => group.commonContactsCount > 0) // Only suggest groups with common contacts
    .sort((a, b) => b.commonContactsCount - a.commonContactsCount); // Sort by most common contacts first

    res.json({ 
      groups: suggestedGroups.slice(0, 5) // Limit to top 5 suggestions
    });
  } catch (err) {
    res.status(500).json({ error: 'Failed to get suggested groups', details: err.message });
  }
});

module.exports = router;
