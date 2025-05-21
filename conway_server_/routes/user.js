const express = require("express");
const router = express.Router();
const multer = require("multer");
const cloudinary = require("cloudinary").v2;
const User = require("../models/User");
const bcrypt = require("bcrypt"); // Needed for password check
const nodemailer = require("nodemailer");
const birthdayService = require("../utils/birthdayService");
const moment = require("moment-timezone");

// --- Assume helper functions exist ---
// const { generateOtp } = require('../utils/otpHelper'); // Or your OTP logic location
// const { sendEmail } = require('../utils/emailHelper'); // Or your email logic location
// Mock functions if helpers don't exist yet:
const generateOtp = () =>
  Math.floor(100000 + Math.random() * 900000).toString();

// Configure email transporter
const transporter = nodemailer.createTransport({
  service: "gmail",
  auth: {
    user: process.env.EMAIL_USER || "mohsiniqbalbhatti0024@gmail.com", // Set in .env file
    pass: process.env.EMAIL_PASS || "vtjg llbf qigc gypa", // Set in .env file for app password
  },
});

// Real email sending function
const sendEmail = async (to, subject, htmlContent) => {
  console.log(`Sending email to: ${to}, Subject: ${subject}`);

  const mailOptions = {
    from: "Conway-Connecting Beyond Boundaries",
    to: to,
    subject: subject,
    html: htmlContent,
  };

  try {
    const info = await transporter.sendMail(mailOptions);
    console.log(`Email sent: ${info.messageId}`);
    return info;
  } catch (error) {
    console.error("Error sending email:", error);
    throw error;
  }
};
// --- End helper functions ---

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
  const { userId, currentPassword, fullname, newEmail, dateOfBirth } = req.body;

  console.log(`[PUT /user/profile] Update request for userId: ${userId}`);
  console.log(`[PUT /user/profile] Date of birth update: ${dateOfBirth}`);

  if (!userId) {
    return res.status(400).json({ error: "User ID is required." });
  }

  // If only dateOfBirth is being updated, we don't require a password
  const isOnlyDateOfBirthUpdate =
    !fullname && !newEmail && dateOfBirth !== undefined;
  console.log(
    `[PUT /user/profile] Is only DOB update: ${isOnlyDateOfBirthUpdate}`
  );

  // Skip password validation if only updating date of birth
  if (!isOnlyDateOfBirthUpdate && !currentPassword) {
    return res.status(400).json({
      error: "Current password is required for updating name or email.",
    });
  }

  // Require at least one field to update
  if (!fullname && !newEmail && dateOfBirth === undefined) {
    return res
      .status(400)
      .json({ error: "At least one field to update is required." });
  }

  try {
    const user = await User.findById(userId);
    if (!user) {
      return res.status(404).json({ error: "User not found." });
    }

    if (!isOnlyDateOfBirthUpdate) {
      // Password check required except for dateOfBirth-only updates
      const isMatch = await bcrypt.compare(currentPassword, user.password);
      if (!isMatch) {
        return res.status(401).json({ error: "Incorrect password." });
      }
    }

    let shouldSendOTP = false;
    let otpEmail = "";

    // Process profile updates
    if (fullname) {
      user.fullname = fullname;
    }

    if (newEmail && newEmail !== user.email) {
      // Email changes require verification
      shouldSendOTP = true;
      otpEmail = newEmail;
      user.pendingEmail = newEmail;
      const otp = generateOtp();
      const otpExpiry = new Date(Date.now() + 30 * 60 * 1000); // 30 min expiry
      user.emailChangeOtp = otp;
      user.emailChangeOtpExpires = otpExpiry;

      // Send OTP email
      await sendEmail(
        newEmail,
        "Conway App Email Change Verification",
        `Your OTP code is: ${otp}`
      );
    }

    if (dateOfBirth !== undefined) {
      console.log(
        `[PUT /user/profile] Setting DOB from ${user.dateOfBirth} to ${dateOfBirth}`
      );
      user.dateOfBirth = dateOfBirth ? new Date(dateOfBirth) : null;
      console.log(
        `[PUT /user/profile] New DOB after setting: ${user.dateOfBirth}`
      );
    }

    // Add timezone update handling
    // HARDCODING TIMEZONE TO ASIA/KARACHI FOR ALL USERS (TEMPORARY FIX)
    if (
      !req.body.timezone ||
      req.body.timezone === "UTC" ||
      req.body.timezone === ""
    ) {
      console.log(
        `[PUT /user/profile] Client sent timezone '${req.body.timezone}', overriding/setting to 'Asia/Karachi'.`
      );
      user.timezone = "Asia/Karachi";
    } else {
      // If client sends a specific, non-UTC, non-empty timezone, respect it for now, but log it.
      // For a true hardcoding, you might want to always set it to Asia/Karachi regardless.
      console.log(
        `[PUT /user/profile] Client sent specific timezone: ${req.body.timezone}. Using it instead of hardcoding.`
      );
      user.timezone = req.body.timezone;
    }
    // To strictly enforce Asia/Karachi for ALL users, uncomment the line below and comment out the if/else block above.
    // user.timezone = "Asia/Karachi";
    // console.log(`[PUT /user/profile] Hardcoding user timezone to 'Asia/Karachi'.`);

    user.updatedAt = Date.now();
    await user.save();
    console.log(
      `[PUT /user/profile] User saved with DOB: ${user.dateOfBirth}, Timezone: ${user.timezone}`
    ); // Log saved timezone

    // Instead of immediately checking for birthday, delay the check slightly
    // to allow the transaction to complete and ensure we're using fresh data
    if (dateOfBirth !== undefined || req.body.timezone) {
      // Retrieve the user again to ensure we have the latest data
      const refreshedUser = await User.findById(userId);

      // DETAILED LOGGING OF REFRESHED USER BEFORE PASSING TO SERVICE
      console.log(
        `[PUT /user/profile] ---- START DETAILED USER DATA FOR BIRTHDAY CHECK ----`
      );
      console.log(
        `[PUT /user/profile] Refreshed User ID: ${refreshedUser._id}`
      );
      console.log(
        `[PUT /user/profile] Refreshed User Fullname: ${refreshedUser.fullname}`
      );
      console.log(
        `[PUT /user/profile] Refreshed User DOB (raw): ${refreshedUser.dateOfBirth}`
      );
      if (refreshedUser.dateOfBirth instanceof Date) {
        console.log(
          `[PUT /user/profile] Refreshed User DOB (ISO): ${refreshedUser.dateOfBirth.toISOString()}`
        );
      }
      console.log(
        `[PUT /user/profile] Refreshed User Timezone: ${refreshedUser.timezone}`
      ); // This should now be Asia/Karachi or respected client TZ
      console.log(
        `[PUT /user/profile] ---- END DETAILED USER DATA FOR BIRTHDAY CHECK ----`
      );

      // Now process birthday with the refreshed user object
      await birthdayService.processBirthdayRealTime(refreshedUser);
    }

    res.json({
      success: true,
      otpRequired: shouldSendOTP,
      message: shouldSendOTP
        ? "OTP sent to the new email for verification."
        : "Profile updated successfully.",
    });
  } catch (err) {
    console.error("[PUT /user/profile] Error:", err.message);
    res.status(500).json({ error: "Server error", details: err.message });
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

// --- Route: Forgot Password (Send OTP) ---
router.post("/forgot-password", async (req, res) => {
  const { email } = req.body;
  if (!email) return res.status(400).json({ error: "Email is required." });
  try {
    const user = await User.findOne({ email });
    if (user) {
      const otp = generateOtp();
      const expiry = new Date(Date.now() + 10 * 60 * 1000);
      user.resetPasswordOtp = otp;
      user.resetPasswordOtpExpires = expiry;
      await user.save();
      await sendEmail(
        email,
        "Conway App Password Reset OTP",
        `<div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px; border: 1px solid #e0e0e0; border-radius: 5px;">
          <h2 style="color: #19BFB7; text-align: center;">Conway App Password Reset OTP</h2>
          <p>Hello,</p>
          <p>Your password reset code is:</p>
          <div style="background-color: #f5f5f5; padding: 12px; border-radius: 4px; text-align: center; margin: 20px 0;">
            <h1 style="margin: 0; color: #333; letter-spacing: 8px;">${otp}</h1>
          </div>
          <p>This code will expire in 10 minutes.</p>
          <p>If you didn't request this, please ignore this email.</p>
          <p>Best Regards,<br/>Conway App Team</p>
        </div>`
      );
    }
    res.json({ success: true });
  } catch (err) {
    console.error("[Forgot Password]", err);
    res.status(500).json({ error: "Server error" });
  }
});

// --- Route: Verify Password Reset OTP ---
router.post("/forgot-password/verify", async (req, res) => {
  const { email, otp } = req.body;
  if (!email || !otp)
    return res.status(400).json({ error: "Email and OTP required." });
  try {
    const user = await User.findOne({ email });
    if (
      !user ||
      user.resetPasswordOtp !== otp ||
      new Date() > user.resetPasswordOtpExpires
    ) {
      return res.status(400).json({ error: "Invalid or expired OTP." });
    }
    res.json({ success: true });
  } catch (err) {
    console.error("[Verify OTP]", err);
    res.status(500).json({ error: "Server error" });
  }
});

// --- Route: Reset Password ---
router.put("/forgot-password/reset", async (req, res) => {
  const { email, otp, newPassword } = req.body;
  if (!email || !otp || !newPassword)
    return res.status(400).json({ error: "Email, OTP, newPassword required." });
  try {
    const user = await User.findOne({ email });
    if (
      !user ||
      user.resetPasswordOtp !== otp ||
      new Date() > user.resetPasswordOtpExpires
    ) {
      return res.status(400).json({ error: "Invalid or expired OTP." });
    }
    const salt = await bcrypt.genSalt(10);
    user.password = await bcrypt.hash(newPassword, salt);
    user.resetPasswordOtp = undefined;
    user.resetPasswordOtpExpires = undefined;
    await user.save();
    res.json({ success: true, message: "Password reset successfully." });
  } catch (err) {
    console.error("[Reset Password]", err);
    res.status(500).json({ error: "Server error" });
  }
});

// --- Route: Get User Details by ID ---
router.get("/:id", async (req, res) => {
  const userId = req.params.id;

  if (!userId) {
    return res.status(400).json({ error: "User ID is required." });
  }

  try {
    const user = await User.findById(userId).select(
      "-password -resetPasswordOtp -resetPasswordOtpExpires -emailChangeOtp -emailChangeOtpExpires"
    );

    if (!user) {
      console.warn(`[GET /user/${userId}] User not found`);
      return res.status(404).json({ error: "User not found." });
    }

    // Format date of birth for consistent handling in frontend
    const userResponse = {
      ...user.toObject(),
      dateOfBirth: user.dateOfBirth ? user.dateOfBirth.toISOString() : null,
    };

    // Remove sensitive fields
    delete userResponse.__v;

    console.log(`[GET /user/${userId}] User details retrieved successfully`);
    res.status(200).json(userResponse);
  } catch (error) {
    console.error(`[GET /user/${userId}] Server error:`, error.message);
    res.status(500).json({
      error: "Server error retrieving user details.",
      details: error.message,
    });
  }
});

// Add a new route that allows users to update their timezone
router.put("/timezone", async (req, res) => {
  try {
    const { userId, timezone } = req.body;

    if (!userId) {
      return res.status(400).json({ error: "User ID is required." });
    }

    if (!timezone) {
      return res.status(400).json({ error: "Timezone is required." });
    }

    // Validate timezone using moment-timezone
    if (!moment.tz.zone(timezone)) {
      return res.status(400).json({ error: "Invalid timezone." });
    }

    const user = await User.findById(userId);
    if (!user) {
      return res.status(404).json({ error: "User not found." });
    }

    // Update timezone
    user.timezone = timezone;
    user.updatedAt = Date.now();
    await user.save();

    // Check for birthday after timezone update
    await birthdayService.processBirthdayRealTime(user);

    res.json({
      success: true,
      message: "Timezone updated successfully.",
      timezone: user.timezone,
    });
  } catch (err) {
    console.error("[PUT /user/timezone] Error:", err.message);
    res.status(500).json({ error: "Server error", details: err.message });
  }
});

module.exports = router;
