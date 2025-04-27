const express = require("express");
const router = express.Router();
const multer = require("multer");
const cloudinary = require("cloudinary").v2;
const User = require("../models/User");

// --- Multer Setup for Memory Storage ---
// We'll store the file in memory buffer temporarily before uploading to Cloudinary
const storage = multer.memoryStorage();
const upload = multer({
  storage: storage,
  limits: { fileSize: 5 * 1024 * 1024 }, // Limit file size (e.g., 5MB)
  fileFilter: (req, file, cb) => {
    console.log("Received file mimetype:", file.mimetype);
    // Accept specific common image types
    if (
      file.mimetype === "image/jpeg" ||
      file.mimetype === "image/png" ||
      file.mimetype === "image/gif" ||
      file.mimetype === "image/jpg" // Explicitly include jpg
    ) {
      cb(null, true); // Accept the file
    } else {
      // Reject the file
      cb(
        new Error(
          "Invalid file type. Only JPEG, PNG, or GIF images are allowed."
        ),
        false
      );
    }
  },
});
// --- End Multer Setup ---

// --- Route to Update Profile Picture ---
router.post(
  "/profile-picture",
  upload.single("profileImage"),
  async (req, res) => {
    // 'profileImage' must match the field name used in the frontend form data
    console.log("[POST /user/profile-picture] Request received.");

    if (!req.file) {
      console.log("[POST /user/profile-picture] No file uploaded.");
      return res.status(400).json({ message: "No image file uploaded." });
    }

    const { userEmail } = req.body; // Get user identifier from request body

    if (!userEmail) {
      console.log("[POST /user/profile-picture] User email missing from body.");
      return res.status(400).json({ message: "User email is required." });
    }

    console.log(
      `[POST /user/profile-picture] Attempting update for email: ${userEmail}`
    );

    try {
      const user = await User.findOne({ email: userEmail });
      if (!user) {
        console.log(
          `[POST /user/profile-picture] User not found for email: ${userEmail}`
        );
        return res.status(404).json({ message: "User not found." });
      }

      console.log(
        `[POST /user/profile-picture] User found: ${user._id}. Uploading to Cloudinary...`
      );

      // Convert buffer to data URI or use stream upload
      // Using stream upload is generally more efficient for larger files
      const uploadStream = cloudinary.uploader.upload_stream(
        {
          folder: "conway_profiles", // Optional: organize uploads in a folder
          public_id: user._id.toString(), // Use user ID as public ID (overwrites previous)
          overwrite: true,
          resource_type: "image",
          // transformation: [ // Optional: Apply transformations (e.g., resize, crop)
          //   { width: 200, height: 200, gravity: "face", crop: "thumb" }
          // ]
        },
        async (error, result) => {
          if (error) {
            console.error(
              "[POST /user/profile-picture] Cloudinary upload error:",
              error
            );
            return res.status(500).json({
              message: "Failed to upload image.",
              details: error.message,
            });
          }

          if (!result || !result.secure_url) {
            console.error(
              "[POST /user/profile-picture] Cloudinary result missing secure_url:",
              result
            );
            return res.status(500).json({
              message: "Image upload failed (invalid Cloudinary response).",
            });
          }

          console.log(
            `[POST /user/profile-picture] Cloudinary upload successful. URL: ${result.secure_url}`
          );

          // Update user profileUrl in database
          user.profileUrl = result.secure_url;
          user.updatedAt = Date.now();
          await user.save();

          console.log(
            `[POST /user/profile-picture] User profile URL updated in DB for ${userEmail}.`
          );

          res.status(200).json({
            message: "Profile picture updated successfully.",
            profileUrl: user.profileUrl,
          });
        }
      );

      // Pipe the file buffer into the Cloudinary upload stream
      uploadStream.end(req.file.buffer);
    } catch (err) {
      console.error("[POST /user/profile-picture] Server error:", err);
      res.status(500).json({
        message: "Server error updating profile picture.",
        details: err.message,
      });
    }
  }
);

module.exports = router;
