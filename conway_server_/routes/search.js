const express = require("express");
const router = express.Router();
const Group = require("../models/Group");
const User = require("../models/User");

// 🔍 Search User (Modified)
router.post("/search-user", async (req, res) => {
  // Accept 'query' from frontend, treat 'content' as fallback if needed
  const query = req.body.query || req.body.content;
  // Make useremail optional for exclusion
  const { useremail } = req.body;

  if (!query) {
    return res.status(400).send({ message: "Search query is required." });
  }

  try {
    const regex = new RegExp(query, "i"); // case-insensitive partial match

    let searchCriteria = {
      $or: [{ username: regex }, { email: regex }, { fullname: regex }],
    }; // Ensure closing brace is here

    // Optionally exclude the requester if their email is provided
    if (useremail) {
      searchCriteria.email = { $ne: useremail };
    }

    // Find users matching criteria, select necessary fields
    const users = await User.find(
      searchCriteria,
      "_id fullname email profileUrl"
    );

    res.send({ message: "Users found", users }); // Ensure key is 'users'
  } catch (err) {
    console.error("Search user error:", err);
    res
      .status(500)
      .send({ message: "Error searching users", error: err.message });
  }
});

// ➕ Create Group (fixed)
router.post("/search-group", async (req, res) => {
  const { groupName } = req.body;

  try {
    const regex = new RegExp(groupName, "i");
    const groups = await Group.find({ groupName: regex }).populate(
      "creator",
      "fullname email"
    );

    res.send({ message: "Groups found", groups });
  } catch (err) {
    res.status(500).send({ message: "Error searching groups", error: err });
  }
});

module.exports = router;
