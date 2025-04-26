const express = require('express');
const router = express.Router();
const Group = require('../models/Group');
const User = require('../models/User');

// 🔍 Search User
router.post('/search-user', async (req, res) => {
  const { useremail, content } = req.body;

  try {
    const regex = new RegExp(content, 'i'); // case-insensitive partial match
    const users = await User.find({
      email: { $ne: useremail }, // exclude the user by email
      $or: [
        { username: regex },
        { email: regex },
        { fullname: regex }
      ]
    });

    res.send({ message: 'Users found', users });
  } catch (err) {
    res.status(500).send({ message: 'Error searching users', error: err });
  }
});

// ➕ Create Group (fixed)
router.post('/search-group', async (req, res) => {
  const { groupName } = req.body;

  try {
    const regex = new RegExp(groupName, 'i');
    const groups = await Group.find({ groupName: regex }).populate('creator', 'fullname email');

    res.send({ message: 'Groups found', groups });
  } catch (err) {
    res.status(500).send({ message: 'Error searching groups', error: err });
  }
});

module.exports = router;
