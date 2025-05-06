const express = require("express");
const router = express.Router();
const multer = require("multer");
const cloudinary = require("cloudinary").v2;
const Group = require("../models/Group");
const User = require("../models/User");
const Message = require("../models/Message");

// --- Multer Setup for Memory Storage (Copied from user.js) ---
const storage = multer.memoryStorage();
const upload = multer({
  storage: storage,
  limits: { fileSize: 5 * 1024 * 1024 }, // Limit file size (e.g., 5MB)
  fileFilter: (req, file, cb) => {
    // Accept common image types
    if (
      file.mimetype === "image/jpeg" ||
      file.mimetype === "image/png" ||
      file.mimetype === "image/gif" ||
      file.mimetype === "image/jpg"
    ) {
      cb(null, true); // Accept the file
    } else {
      cb(
        new Error("Invalid file type. Only JPEG, PNG, or GIF images allowed."),
        false
      );
    }
  },
});
// --- End Multer Setup ---

// Create Group
router.post("/groups", async (req, res) => {
  try {
    const { groupName, creator, deleted_at } = req.body;
    const group = new Group({
      groupName,
      creator,
      deleted_at,
      users: [creator],
      admins: [creator],
    });
    await group.save();
    res.send({ message: "Group created", group });
  } catch (err) {
    res
      .status(500)
      .json({ error: "Failed to create group", details: err.message });
  }
});

// Add User to Group
router.post("/addInGroup", async (req, res) => {
  try {
    const { userEmail, groupId } = req.body;
    const user = await User.findOne({ email: userEmail });

    if (!user) {
      return res.status(404).json({ error: "User not found" });
    }

    const group = await Group.findById(groupId);
    if (!group) {
      return res.status(404).json({ error: "Group not found" });
    }

    const userId = user._id;
    if (!group.users.includes(userId)) {
      group.users.push(userId);
      await group.save();
    }

    res.send({ message: "User added to group" });
  } catch (err) {
    res
      .status(500)
      .json({ error: "Failed to add user to group", details: err.message });
  }
});

// Get group members
router.get("/group-members/:groupId", async (req, res) => {
  try {
    const { groupId } = req.params;

    const group = await Group.findById(groupId);
    if (!group) {
      return res.status(404).json({ error: "Group not found" });
    }

    // Get user details for all group members
    const members = await User.find(
      { _id: { $in: group.users } },
      "fullname email profileUrl"
    );

    res.json({
      members: members.map((member) => ({
        id: member._id,
        name: member.fullname,
        email: member.email,
        profileUrl: member.profileUrl,
      })),
    });
  } catch (err) {
    res
      .status(500)
      .json({ error: "Failed to get group members", details: err.message });
  }
});

// Get group messages
router.get("/group-messages/:groupId", async (req, res) => {
  try {
    const { groupId } = req.params;
    const { userId: requestingUserId } = req.query; // Get requesting user ID from query
    const now = new Date();

    const group = await Group.findById(groupId);
    if (!group) {
      return res.status(404).json({ error: "Group not found" });
    }

    // Authorization: Only members can fetch messages
    if (
      !requestingUserId ||
      !group.users.some((id) => id.toString() === requestingUserId.toString())
    ) {
      return res.status(403).json({ error: "Forbidden: Not a group member" });
    }

    // Base query: group match, not deleted
    const query = { group: groupId, deleted_at: null };

    // Add filter to exclude future scheduled messages NOT sent by the requesting user
    if (requestingUserId) {
      // If we know the user, only hide others' future scheduled messages
      query["$nor"] = [
        {
          sender: { $ne: requestingUserId }, // Sender is not the requester
          isScheduled: true, // Message is scheduled
          scheduledAt: { $gt: now }, // Scheduled time is in the future
        },
      ];
    } else {
      // If user ID is not provided, hide ALL future scheduled messages
      query["$nor"] = [{ isScheduled: true, scheduledAt: { $gt: now } }];
    }

    const messages = await Message.find(query)
      .sort({ time: 1 })
      .populate("sender", "fullname email");

    // Format messages for the client
    const formattedMessages = messages.map((msg) => {
      // Determine if already expired for the sender
      const isMe = requestingUserId === msg.sender?._id.toString();
      const isBurnout = msg.isBurnout ?? false;
      const expireAt = msg.expireAt ? new Date(msg.expireAt) : null;
      const actuallyExpiredForSender =
        isMe && isBurnout && expireAt && expireAt <= now;

      // Determine if pending schedule (only relevant if sender is known and is the requester)
      const isScheduled = msg.isScheduled ?? false;
      const scheduledAt = msg.scheduledAt ? new Date(msg.scheduledAt) : null;
      const isPendingSchedule =
        isMe && isScheduled && scheduledAt && scheduledAt > now;

      return {
        id: msg._id,
        senderId: msg.sender._id,
        senderName: msg.sender.fullname,
        senderEmail: msg.sender.email,
        text: msg.message,
        time: msg.time,
        isBurnout: isBurnout,
        expireAt: msg.expireAt?.toISOString(), // Send as ISO string
        isScheduled: isScheduled,
        scheduledAt: msg.scheduledAt?.toISOString(), // Send as ISO string
        // Add flags needed for UI rendering
        actuallyExpired: actuallyExpiredForSender,
        // visuallyExpired is determined client-side based on expiry event
        // isPendingSchedule: isPendingSchedule, // Can derive this client-side too if needed
      };
    });

    res.json({ messages: formattedMessages });
  } catch (err) {
    console.error(
      `[GET Group Messages Error] Group ID ${req.params.groupId}, User ${requestingUserId}:`,
      err
    );
    res
      .status(500)
      .json({ error: "Failed to get group messages", details: err.message });
  }
});

// Get suggested groups for a user based on their chat contacts
router.get("/suggested-groups", async (req, res) => {
  try {
    const { email } = req.query;
    if (!email) {
      return res.status(400).json({ error: "Email is required" });
    }

    // Find the user
    const user = await User.findOne({ email });
    if (!user) {
      return res.status(404).json({ error: "User not found" });
    }

    // Find all messages to/from this user to identify their contacts
    const messages = await Message.find({
      $or: [{ sender: user._id }, { receiver: user._id }],
    });

    // Extract unique user IDs the user has chatted with
    const contactIds = new Set();
    messages.forEach((msg) => {
      if (msg.sender.toString() !== user._id.toString()) {
        contactIds.add(msg.sender.toString());
      }
      if (msg.receiver && msg.receiver.toString() !== user._id.toString()) {
        contactIds.add(msg.receiver.toString());
      }
    });

    // Find groups where the user's contacts are members, but the user is not
    const groups = await Group.find({
      users: { $nin: [user._id] }, // User is not in these groups
    }).populate("users creator", "fullname email");

    // Filter and sort groups by the number of the user's contacts in each group
    const suggestedGroups = groups
      .map((group) => {
        const commonContacts = group.users.filter((groupUser) =>
          contactIds.has(groupUser._id.toString())
        );

        return {
          _id: group._id,
          groupName: group.groupName,
          creator: {
            fullname: group.creator.fullname,
            email: group.creator.email,
          },
          memberCount: group.users.length,
          commonContactsCount: commonContacts.length,
        };
      })
      .filter((group) => group.commonContactsCount > 0) // Only suggest groups with common contacts
      .sort((a, b) => b.commonContactsCount - a.commonContactsCount); // Sort by most common contacts first

    res.json({
      groups: suggestedGroups.slice(0, 5), // Limit to top 5 suggestions
    });
  } catch (err) {
    res
      .status(500)
      .json({ error: "Failed to get suggested groups", details: err.message });
  }
});

// --- Routes for Group Settings ---

// GET Group Details (for settings screen)
// Includes both members and pending invites
router.get("/groups/:groupId/details", async (req, res) => {
  try {
    const { groupId } = req.params;
    const group = await Group.findById(groupId)
      .populate("creator", "fullname email _id") // Populate creator info
      .populate("users", "fullname email profileUrl _id") // Populate member info
      .populate("invitedMembers.user", "fullname email profileUrl _id") // Populate invited users
      .populate("joinRequests.user", "fullname email profileUrl _id"); // Populate join request users

    if (!group) {
      return res.status(404).json({ error: "Group not found" });
    }

    // Only return pending invitations
    const pendingInvites = group.invitedMembers
      .filter((inv) => inv.status === "pending")
      .map((inv) => ({
        _id: inv._id,
        user: {
          _id: inv.user._id,
          fullname: inv.user.fullname,
          email: inv.user.email,
          profileUrl: inv.user.profileUrl,
        },
        status: inv.status,
        invitedAt: inv.invitedAt,
        respondedAt: inv.respondedAt,
      }));

    // Only return pending join requests
    const pendingRequests = group.joinRequests.map((jr) => ({
      _id: jr._id,
      user: {
        _id: jr.user._id,
        fullname: jr.user.fullname,
        email: jr.user.email,
        profileUrl: jr.user.profileUrl,
      },
      requestedAt: jr.requestedAt,
    }));

    res.json({
      _id: group._id,
      groupName: group.groupName,
      profileUrl: group.profileUrl,
      creatorId: group.creator._id,
      creatorName: group.creator.fullname,
      members: group.users.map((user) => ({
        _id: user._id,
        fullname: user.fullname,
        email: user.email,
        profileUrl: user.profileUrl,
      })),
      invitedMembers: pendingInvites,
      joinRequests: pendingRequests,
      createdAt: group.createdAt,
      updatedAt: group.updatedAt,
    });
  } catch (err) {
    console.error(
      `[GET Group Details Error] Group ID ${req.params.groupId}:`,
      err
    );
    res
      .status(500)
      .json({ error: "Failed to get group details", details: err.message });
  }
});

// PUT Update Group Info (Name, Profile Picture) - Admin Only
router.put("/groups/:groupId", async (req, res) => {
  console.log("PUT Update Group Info", req.body);
  try {
    const { groupId } = req.params;
    const { groupName, profileUrl, userId } = req.body; // userId is the ID of the user making the request

    if (!userId) {
      return res
        .status(400)
        .json({ error: "User ID is required for authorization" });
    }

    const group = await Group.findById(groupId);
    if (!group) {
      return res.status(404).json({ error: "Group not found" });
    }

    // Authorization: Only the creator can update
    if (group.creator.toString() !== userId) {
      return res.status(403).json({
        error: "Forbidden: Only the group creator can update group info",
      });
    }

    // Update fields if provided
    let updated = false;
    if (groupName && groupName !== group.groupName) {
      group.groupName = groupName;
      updated = true;
    }
    if (profileUrl && profileUrl !== group.profileUrl) {
      group.profileUrl = profileUrl;
      updated = true;
    }

    if (updated) {
      group.updatedAt = Date.now();
      await group.save();
      res.json({ message: "Group updated successfully", group }); // Return updated group
    } else {
      res.json({ message: "No changes provided", group }); // Return current group if no changes
    }
  } catch (err) {
    console.error(
      `[PUT Group Update Error] Group ID ${req.params.groupId}:`,
      err
    );
    res
      .status(500)
      .json({ error: "Failed to update group", details: err.message });
  }
});

// POST Add Members to Group - Admin Only
router.post("/groups/:groupId/members", async (req, res) => {
  try {
    const { groupId } = req.params;
    const { emailsToAdd, userId } = req.body; // userId of requester, emailsToAdd is an array of emails

    if (!userId) {
      return res
        .status(400)
        .json({ error: "User ID is required for authorization" });
    }
    if (
      !emailsToAdd ||
      !Array.isArray(emailsToAdd) ||
      emailsToAdd.length === 0
    ) {
      return res
        .status(400)
        .json({ error: "Array of emails to add is required" });
    }

    const group = await Group.findById(groupId);
    if (!group) {
      return res.status(404).json({ error: "Group not found" });
    }

    // Authorization: Only creator can add members
    if (group.creator.toString() !== userId) {
      return res
        .status(403)
        .json({ error: "Forbidden: Only the group creator can add members" });
    }

    // Find users by email
    const usersToAdd = await User.find({ email: { $in: emailsToAdd } });
    const userIdsToAdd = usersToAdd.map((user) => user._id);

    let addedCount = 0;
    userIdsToAdd.forEach((id) => {
      if (!group.users.includes(id)) {
        group.users.push(id);
        addedCount++;
      }
    });

    if (addedCount > 0) {
      group.updatedAt = Date.now();
      await group.save();
      res.json({
        message: `${addedCount} member(s) added successfully`,
        addedUserIds: userIdsToAdd,
      });
    } else {
      res.json({
        message:
          "No new members added (users might already be in the group or emails not found)",
      });
    }
  } catch (err) {
    console.error(
      `[POST Add Group Members Error] Group ID ${req.params.groupId}:`,
      err
    );
    res
      .status(500)
      .json({ error: "Failed to add members to group", details: err.message });
  }
});

// POST Invite Members to Group - Admin Only
router.post("/groups/:groupId/invite", async (req, res) => {
  try {
    const { groupId } = req.params;
    const { userId, memberIds } = req.body; // memberIds: [String]
    if (!userId || !Array.isArray(memberIds) || memberIds.length === 0) {
      return res
        .status(400)
        .json({ error: "userId and memberIds array required" });
    }
    const group = await Group.findById(groupId);
    if (!group) return res.status(404).json({ error: "Group not found" });
    if (group.creator.toString() !== userId) {
      return res
        .status(403)
        .json({ error: "Forbidden: only group creator can invite" });
    }
    memberIds.forEach((mid) => {
      // skip if already a member or already invited
      if (
        !group.users.some((id) => id.toString() === mid) &&
        !group.invitedMembers.some((im) => im.user.toString() === mid)
      ) {
        group.invitedMembers.push({ user: mid });
      }
    });
    group.updatedAt = Date.now();
    await group.save();
    res.json({ message: "Invitations sent successfully" });
  } catch (err) {
    console.error(`[INVITE MEMBER Error] Group ${req.params.groupId}:`, err);
    res
      .status(500)
      .json({ error: "Failed to invite members", details: err.message });
  }
});

// POST Respond to Group Invitation - User Only
router.post("/groups/:groupId/respond", async (req, res) => {
  try {
    const { groupId } = req.params;
    const { userId, action } = req.body; // action: 'accept' | 'reject'
    if (!userId || !["accept", "reject"].includes(action)) {
      return res
        .status(400)
        .json({ error: "userId and valid action required" });
    }
    const group = await Group.findById(groupId);
    if (!group) {
      return res.status(404).json({ error: "Group not found" });
    }
    // Find the pending invitation for this user
    const idx = group.invitedMembers.findIndex(
      (im) => im.user.toString() === userId
    );
    if (idx === -1) {
      return res.status(404).json({ error: "Invitation not found" });
    }
    // If accepted, add user to group members
    if (action === "accept") {
      group.users.push(userId);
    }
    // Remove the invitation entry
    group.invitedMembers.splice(idx, 1);
    group.updatedAt = Date.now();
    await group.save();
    res.json({ message: `Invitation ${action}ed` });
  } catch (err) {
    console.error(
      `[RESPOND INVITATION Error] Group ${req.params.groupId}:`,
      err
    );
    res.status(500).json({
      error: "Failed to respond to invitation",
      details: err.message,
    });
  }
});

// POST Request to Join Group - User Only
router.post("/groups/:groupId/join-requests", async (req, res) => {
  try {
    const { groupId } = req.params;
    const { userId } = req.body;
    if (!userId) return res.status(400).json({ error: "User ID required" });
    const group = await Group.findById(groupId);
    if (!group) return res.status(404).json({ error: "Group not found" });
    // Prevent duplicate requests or membership
    if (
      group.users.some((id) => id.toString() === userId) ||
      group.joinRequests.some((jr) => jr.user.toString() === userId)
    ) {
      return res
        .status(400)
        .json({ error: "Already a member or pending request" });
    }
    group.joinRequests.push({ user: userId });
    group.updatedAt = Date.now();
    await group.save();
    res.json({ message: "Join request sent" });
  } catch (err) {
    console.error(`[JOIN REQUEST Error] Group ${req.params.groupId}:`, err);
    res
      .status(500)
      .json({ error: "Failed to send join request", details: err.message });
  }
});

// POST Respond to Join Request - Admin Only
router.post("/groups/:groupId/join-requests/respond", async (req, res) => {
  try {
    const { groupId } = req.params;
    const { userId, requestUserId, action } = req.body; // action: 'accept'|'reject'
    if (!userId || !requestUserId || !["accept", "reject"].includes(action)) {
      return res
        .status(400)
        .json({ error: "userId, requestUserId, and valid action required" });
    }
    const group = await Group.findById(groupId);
    if (!group) return res.status(404).json({ error: "Group not found" });
    // Authorization: only creator
    if (group.creator.toString() !== userId) {
      return res
        .status(403)
        .json({ error: "Forbidden: only group admin can respond to requests" });
    }
    const idx = group.joinRequests.findIndex(
      (jr) => jr.user.toString() === requestUserId
    );
    if (idx === -1) {
      return res.status(404).json({ error: "Join request not found" });
    }
    // Accept => add to members
    if (action === "accept") {
      group.users.push(requestUserId);
    }
    // Remove the request
    group.joinRequests.splice(idx, 1);
    group.updatedAt = Date.now();
    await group.save();
    res.json({ message: `Request ${action}ed` });
  } catch (err) {
    console.error(
      `[RESPOND JOIN REQUEST Error] Group ${req.params.groupId}:`,
      err
    );
    res.status(500).json({
      error: "Failed to respond to join request",
      details: err.message,
    });
  }
});

// POST Remove Member from Group - Admin Only
router.post("/groups/:groupId/remove-member", async (req, res) => {
  try {
    const { groupId } = req.params;
    const { userId, memberId } = req.body;
    if (!userId || !memberId) {
      return res
        .status(400)
        .json({ error: "User ID and Member ID are required" });
    }
    const group = await Group.findById(groupId);
    if (!group) {
      return res.status(404).json({ error: "Group not found" });
    }
    // Authorization: Only the group creator can remove members
    if (group.creator.toString() !== userId) {
      return res
        .status(403)
        .json({ error: "Forbidden: Only group creator can remove members" });
    }
    // Prevent removing the creator
    if (group.creator.toString() === memberId) {
      return res.status(400).json({ error: "Cannot remove group creator" });
    }
    // Remove member from users and admins
    group.users = group.users.filter((id) => id.toString() !== memberId);
    group.admins = group.admins.filter((id) => id.toString() !== memberId);
    group.updatedAt = Date.now();
    await group.save();
    res.json({ message: "Member removed successfully" });
  } catch (err) {
    console.error(`[REMOVE MEMBER Error] Group ID ${req.params.groupId}:`, err);
    res
      .status(500)
      .json({ error: "Failed to remove member", details: err.message });
  }
});

// POST Leave Group - Member Only
router.post("/groups/:groupId/leave", async (req, res) => {
  try {
    const { groupId } = req.params;
    const { userId } = req.body;
    if (!userId) {
      return res.status(400).json({ error: "User ID required" });
    }
    const group = await Group.findById(groupId);
    if (!group) {
      return res.status(404).json({ error: "Group not found" });
    }
    // Prevent creator from leaving
    if (group.creator.toString() === userId) {
      return res.status(400).json({
        error: "Group creator cannot leave the group. Delete group instead.",
      });
    }
    // Remove user from users and admins arrays
    group.users = group.users.filter((id) => id.toString() !== userId);
    group.admins = group.admins.filter((id) => id.toString() !== userId);
    group.updatedAt = Date.now();
    await group.save();
    res.json({ message: "Left group successfully" });
  } catch (err) {
    console.error(`[LEAVE GROUP Error] Group ID ${req.params.groupId}:`, err);
    res
      .status(500)
      .json({ error: "Failed to leave group", details: err.message });
  }
});

// --- NEW Route to Upload Group Picture ---
// This route ONLY handles the upload and returns the URL.
// The actual Group model update happens via PUT /api/groups/:groupId
router.post(
  "/group-picture", // Endpoint path within the group router
  upload.single("groupImage"), // Field name from frontend
  async (req, res) => {
    console.log("[POST /groups/group-picture] Request received.");

    if (!req.file) {
      console.log("[POST /groups/group-picture] No file uploaded.");
      return res.status(400).json({ message: "No image file uploaded." });
    }

    const { groupId } = req.body; // Optional: Get groupId from body

    console.log(
      `[POST /groups/group-picture] Attempting upload for group: ${
        groupId || "unknown"
      }`
    );

    try {
      // Upload to Cloudinary
      const uploadStream = cloudinary.uploader.upload_stream(
        {
          folder: "conway_groups", // Folder for group images
          resource_type: "image",
        },
        (error, result) => {
          if (error) {
            console.error(
              "[POST /groups/group-picture] Cloudinary upload error:",
              error
            );
            return res.status(500).json({
              message: "Failed to upload group image.",
              details: error.message,
            });
          }
          if (!result || !result.secure_url) {
            console.error(
              "[POST /groups/group-picture] Cloudinary result missing secure_url:",
              result
            );
            return res.status(500).json({
              message: "Image upload failed (invalid Cloudinary response).",
            });
          }
          console.log(
            `[POST /groups/group-picture] Cloudinary upload successful. URL: ${result.secure_url}`
          );
          // Return the URL
          res.status(200).json({
            message: "Group image uploaded successfully.",
            groupProfileUrl: result.secure_url,
          });
        }
      );
      // Pipe buffer to Cloudinary
      uploadStream.end(req.file.buffer);
    } catch (err) {
      console.error("[POST /groups/group-picture] Server error:", err);
      res.status(500).json({
        message: "Server error uploading group image.",
        details: err.message,
      });
    }
  }
);

module.exports = router;
