const express = require("express");
const router = express.Router();
const multer = require("multer");
const cloudinary = require("cloudinary").v2;
const User = require("../models/User");
const bcrypt = require("bcrypt"); // Needed for password check

// --- Assume helper functions exist ---
// const { generateOtp } = require('../utils/otpHelper'); // Or your OTP logic location
// const { sendEmail } = require('../utils/emailHelper'); // Or your email logic location
// Mock functions if helpers don't exist yet:
const generateOtp = () =>
  Math.floor(100000 + Math.random() * 900000).toString();
const sendEmail = async (to, subject, text) => {
  console.log(
    `---- MOCK EMAIL ----\nTo: ${to}\nSubject: ${subject}\nBody: ${text}\n--------------------`
  );
  // In real app, integrate with SendGrid, Nodemailer, etc.
  return Promise.resolve();
};
// --- End Assume helper functions ---

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

    const { userId } = req.body; // <<< CHANGE: Expect userId instead of userEmail

    if (!userId) {
      // <<< CHANGE: Check for userId
      console.log("[POST /user/profile-picture] User ID missing from body."); // <<< CHANGE: Log message
      return res.status(400).json({ message: "User ID is required." }); // <<< CHANGE: Error message
    }

    console.log(
      `[POST /user/profile-picture] Attempting update for userId: ${userId}` // <<< CHANGE: Log message
    );

    try {
      const user = await User.findById(userId); // <<< CHANGE: Find by ID
      if (!user) {
        console.log(
          `[POST /user/profile-picture] User not found for ID: ${userId}` // <<< CHANGE: Log message
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
          timeout: 60000, // Add timeout: 60 seconds (60000 ms)
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
            `[POST /user/profile-picture] User profile URL updated in DB for ${userId}.` // <<< CHANGE: Log message
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

// --- Route to Initiate Profile Update (Name and/or Email) ---
router.put("/profile", async (req, res) => {
  const { userId, currentPassword, fullname, newEmail } = req.body;

  console.log(`[PUT /user/profile] Update request for userId: ${userId}`);

  if (!userId || !currentPassword) {
    return res
      .status(400)
      .json({ error: "User ID and current password are required." });
  }
  if (!fullname && !newEmail) {
    return res
      .status(400)
      .json({ error: "No changes provided (fullname or newEmail required)." });
  }

  try {
    const user = await User.findById(userId);
    if (!user) {
      return res.status(404).json({ error: "User not found." });
    }

    // 1. Verify Current Password
    const isMatch = await bcrypt.compare(currentPassword, user.password);
    if (!isMatch) {
      console.warn(
        `[PUT /user/profile] Invalid password attempt for userId: ${userId}`
      );
      return res.status(401).json({ error: "Invalid current password." });
    }

    let nameChanged = false;
    let emailChangeInitiated = false;

    // 2. Update Fullname if provided and different
    if (fullname && fullname.trim() !== user.fullname) {
      user.fullname = fullname.trim();
      nameChanged = true;
      console.log(
        `[PUT /user/profile] Updating fullname for userId: ${userId}`
      );
    }

    // 3. Handle Email Change Request if provided and different
    if (newEmail && newEmail.trim().toLowerCase() !== user.email) {
      const cleanNewEmail = newEmail.trim().toLowerCase();

      // Check if the new email is already taken by another verified user
      const existingUser = await User.findOne({
        email: cleanNewEmail,
        _id: { $ne: user._id },
        isVerified: true,
      });
      if (existingUser) {
        console.warn(
          `[PUT /user/profile] New email ${cleanNewEmail} already in use by userId: ${existingUser._id}`
        );
        return res
          .status(409)
          .json({ error: "New email address is already registered." });
      }

      // Generate and store OTP for email change
      const otp = generateOtp();
      const otpExpiry = new Date(Date.now() + 10 * 60 * 1000); // OTP valid for 10 minutes

      user.pendingEmail = cleanNewEmail;
      user.emailChangeOtp = otp;
      user.emailChangeOtpExpires = otpExpiry;
      emailChangeInitiated = true;

      console.log(
        `[PUT /user/profile] Initiating email change for userId: ${userId} to ${cleanNewEmail}. OTP: ${otp}`
      );

      // Send OTP to the *new* email address
      await sendEmail(
        cleanNewEmail,
        "Verify Your New Email Address",
        `Your OTP to verify your new email address is: ${otp}\nThis code will expire in 10 minutes.`
      ).catch((err) => {
        console.error(
          `[PUT /user/profile] Failed to send OTP email to ${cleanNewEmail}:`,
          err
        );
        // Don't block the process, but log the error. User might still check console if mock.
      });
    }

    // 4. Save Changes (including potential OTP info and name change)
    if (nameChanged || emailChangeInitiated) {
      user.updatedAt = Date.now();
      await user.save();
    }

    // 5. Send Response
    res.status(200).json({
      success: true,
      message: emailChangeInitiated
        ? "Profile updated. OTP sent to new email for verification."
        : "Profile updated successfully.",
      otpRequired: emailChangeInitiated, // Signal to frontend if OTP step is next
      // Optionally return updated user data (excluding sensitive fields)
      user: {
        fullname: user.fullname,
        email: user.email, // Return current email, not pending one yet
        profileUrl: user.profileUrl,
      },
    });
  } catch (err) {
    console.error(
      `[PUT /user/profile] Error updating profile for userId ${userId}:`,
      err
    );
    res
      .status(500)
      .json({ error: "Server error updating profile.", details: err.message });
  }
});

// --- Route to Verify Email Change OTP and Finalize ---
router.post("/verify-email-change", async (req, res) => {
  const { userId, otp } = req.body;

  console.log(
    `[POST /user/verify-email-change] Verification attempt for userId: ${userId}`
  );

  if (!userId || !otp) {
    return res.status(400).json({ error: "User ID and OTP are required." });
  }

  try {
    const user = await User.findById(userId);

    // Basic checks
    if (!user) {
      return res.status(404).json({ error: "User not found." });
    }
    if (
      !user.pendingEmail ||
      !user.emailChangeOtp ||
      !user.emailChangeOtpExpires
    ) {
      return res
        .status(400)
        .json({ error: "No pending email change found for this user." });
    }

    // Check OTP expiry
    if (new Date() > user.emailChangeOtpExpires) {
      console.warn(
        `[POST /user/verify-email-change] Expired OTP attempt for userId: ${userId}`
      );
      // Clear expired OTP details
      user.pendingEmail = undefined;
      user.emailChangeOtp = undefined;
      user.emailChangeOtpExpires = undefined;
      await user.save();
      return res
        .status(410)
        .json({ error: "OTP has expired. Please try again." }); // 410 Gone
    }

    // Check OTP value
    if (otp !== user.emailChangeOtp) {
      console.warn(
        `[POST /user/verify-email-change] Invalid OTP attempt for userId: ${userId}`
      );
      return res.status(400).json({ error: "Invalid OTP." });
    }

    // --- Success ---
    console.log(
      `[POST /user/verify-email-change] OTP verified for userId: ${userId}. Updating email to ${user.pendingEmail}`
    );
    user.email = user.pendingEmail;
    user.pendingEmail = undefined;
    user.emailChangeOtp = undefined;
    user.emailChangeOtpExpires = undefined;
    user.updatedAt = Date.now();
    await user.save();

    res
      .status(200)
      .json({ success: true, message: "Email address updated successfully." });
  } catch (error) {
    console.error(
      "[POST /user/verify-email-change] Server error:",
      error.message
    );
    res.status(500).json({
      error: "Server error verifying email change.",
      details: error.message,
    });
  }
});

// --- Route to Change Password ---
router.put("/change-password", async (req, res) => {
  const { userId, currentPassword, newPassword } = req.body;

  console.log(`[PUT /user/change-password] Request for userId: ${userId}`);

  // Basic validation
  if (!userId || !currentPassword || !newPassword) {
    return res.status(400).json({
      success: false,
      error: "User ID, current password, and new password are required.",
    });
  }
  if (newPassword.length < 8) {
    return res.status(400).json({
      success: false,
      error: "New password must be at least 8 characters long.",
    });
  }

  try {
    const user = await User.findById(userId);
    if (!user) {
      console.warn(`[PUT /user/change-password] User not found: ${userId}`);
      return res.status(404).json({ success: false, error: "User not found." });
    }

    // Verify current password
    const isMatch = await bcrypt.compare(currentPassword, user.password);
    if (!isMatch) {
      console.warn(
        `[PUT /user/change-password] Invalid current password for userId: ${userId}`
      );
      return res
        .status(401)
        .json({ success: false, error: "Incorrect current password." });
    }

    // Hash the new password
    const salt = await bcrypt.genSalt(10);
    const hashedPassword = await bcrypt.hash(newPassword, salt);

    // Update password in database
    user.password = hashedPassword;
    user.updatedAt = Date.now();
    await user.save();

    console.log(
      `[PUT /user/change-password] Password updated for userId: ${userId}`
    );
    res
      .status(200)
      .json({ success: true, message: "Password updated successfully." });
  } catch (error) {
    console.error("[PUT /user/change-password] Server error:", error.message);
    res.status(500).json({
      success: false,
      error: "Server error changing password.",
      details: error.message,
    });
  }
});

module.exports = router;
