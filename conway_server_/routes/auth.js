const express = require("express");
const router = express.Router();
const User = require("../models/User");
const bcrypt = require("bcryptjs");
const nodemailer = require("nodemailer");

// Store OTPs temporarily (in production, use Redis or a database)
const otpStore = new Map();

// Function to generate OTP
function generateOTP() {
  return Math.floor(100000 + Math.random() * 900000).toString();
}

// Configure email transporter
const transporter = nodemailer.createTransport({
  service: "gmail",
  auth: {
    user: process.env.EMAIL_USER || "mohsiniqbalbhatti0024@gmail.com", // Set in .env file
    pass: process.env.EMAIL_PASS || "vtjg llbf qigc gypa", // Set in .env file for app password
  },
});

// Send OTP via email
async function sendOTPEmail(email, otp) {
  const mailOptions = {
    from: "Conway-Connecting Beyond Boundaries",
    to: email,
    subject: "Your Conway App Verification Code",
    html: `
      <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px; border: 1px solid #e0e0e0; border-radius: 5px;">
        <h2 style="color: #19BFB7; text-align: center;">Conway App Email Verification</h2>
        <p>Hello,</p>
        <p>Your verification code for Conway App is:</p>
        <div style="background-color: #f5f5f5; padding: 12px; border-radius: 4px; text-align: center; margin: 20px 0;">
          <h1 style="margin: 0; color: #333; letter-spacing: 8px;">${otp}</h1>
        </div>
        <p>This code will expire in 10 minutes.</p>
        <p>If you didn't request this verification, please ignore this email.</p>
        <p>Best Regards,<br>Conway App Team</p>
      </div>
    `
  };

  return transporter.sendMail(mailOptions);
}

// Request OTP for signup
router.post("/request-otp", async (req, res) => {
  try {
    const { fullname, username, email, password } = req.body;

    // Basic validation
    if (!fullname || !username || !email || !password) {
      return res.status(400).json({ message: "All fields are required" });
    }

    // Check if username already exists
    const existingUsername = await User.findOne({ userName: username });
    if (existingUsername) {
      return res.status(409).json({ message: "Username already exists" });
    }

    // Check if email already exists
    const existingUser = await User.findOne({ email });
    if (existingUser) {
      return res.status(409).json({ message: "Email is already registered" });
    }

    // Generate OTP
    const otp = generateOTP();
    
    // Store OTP and user data temporarily (expires in 10 minutes)
    otpStore.set(email, {
      otp,
      userData: { fullname, username, email, password },
      expiresAt: Date.now() + 10 * 60 * 1000 // 10 minutes
    });

    // Send OTP via email
    await sendOTPEmail(email, otp);

    res.status(200).json({ 
      message: "OTP sent to your email. Please verify to complete registration." 
    });
  } catch (error) {
    console.error("OTP request error:", error);
    res.status(500).json({ message: "Server error" });
  }
});

// Verify OTP and create user
router.post("/verify-otp", async (req, res) => {
  try {
    const { email, otp } = req.body;

    if (!email || !otp) {
      return res.status(400).json({ message: "Email and OTP are required" });
    }

    // Check if OTP exists and is valid
    const otpData = otpStore.get(email);
    
    if (!otpData) {
      return res.status(404).json({ message: "OTP not found or expired. Please request a new one." });
    }

    // Check if OTP has expired
    if (Date.now() > otpData.expiresAt) {
      otpStore.delete(email);
      return res.status(400).json({ message: "OTP has expired. Please request a new one." });
    }

    // Check if OTP matches
    if (otpData.otp !== otp) {
      return res.status(400).json({ message: "Invalid OTP. Please try again." });
    }

    // OTP is valid, proceed with user registration
    const { fullname, username, email: userEmail, password } = otpData.userData;

    // Hash password
    const salt = await bcrypt.genSalt(10);
    const hashedPassword = await bcrypt.hash(password, salt);

    // Create new user
    const newUser = new User({
      fullname,
      userName: username,
      email: userEmail,
      password: hashedPassword
    });

    await newUser.save();

    // Remove OTP data
    otpStore.delete(email);

    res.status(201).json({ 
      message: "Account created successfully", 
      user: newUser 
    });
  } catch (error) {
    console.error("OTP verification error:", error);
    res.status(500).json({ message: "Server error" });
  }
});

// Register (keeping for backward compatibility, but will be replaced by the OTP flow)
router.post("/register", async (req, res) => {
  try {
    const { fullname, username, email, password } = req.body;

    // Validate input
    if (!fullname || !username || !email || !password) {
      return res.status(400).json({ message: "All fields are required" });
    }

    // Check if username already exists
    const existingUsername = await User.findOne({ userName: username });
    if (existingUsername) {
      return res.status(409).json({ message: "Username already exists" });
    }

    // Check if user already exists
    const existingUser = await User.findOne({ email });
    if (existingUser) {
      return res.status(409).json({ message: "Email is already registered" });
    }

    // Hash password
    const salt = await bcrypt.genSalt(10);
    const hashedPassword = await bcrypt.hash(password, salt);

    // Create and save new user
    const user = new User({
      fullname,
      userName: username,
      email,
      password: hashedPassword,
    });
    await user.save();
    res.status(201).json({ message: "User registered successfully", user });
  } catch (err) {
    console.error("Registration error:", err);
    res.status(500).json({ message: "Server error during registration" });
  }
});

// Login
router.post("/login", async (req, res) => {
  try {
    const { identifier, password } = req.body;

    // Validate input
    if (!identifier || !password) {
      return res.status(400).json({ message: "Email/username and password are required" });
    }

    // Find user by email or username
    const user = await User.findOne({
      $or: [
        { email: identifier },
        { userName: identifier }
      ]
    });

    if (!user) {
      return res.status(401).json({ message: "user not found" });
    }

    // Compare passwords
    const isMatch = await bcrypt.compare(password, user.password);
    if (!isMatch) {
      return res.status(401).json({ message: "Invalid credentials" });
    }

    res.status(200).json({ message: "Login successful", user });
  } catch (error) {
    console.error("Login error:", error);
    res.status(500).json({ message: "Server error" });
  }
});

// Google Auth - Handle login and account linking
router.post("/google-auth", async (req, res) => {
  try {
    const { email, fullname, photoURL, firebaseUID } = req.body;

    if (!email || !firebaseUID) {
      return res.status(400).json({ message: "Email and Firebase UID are required" });
    }

    // Check if a user with this email already exists
    let user = await User.findOne({ email });

    if (user) {
      // User exists - update their profile with Google info
      user.profileUrl = photoURL || user.profileUrl;
      user.firebaseUID = firebaseUID;
      
      // If the user doesn't have a fullname (rare case), set it from Google data
      if (!user.fullname && fullname) {
        user.fullname = fullname;
      }
      
      await user.save();
      return res.status(200).json({ 
        message: "Google account linked to existing account", 
        user,
        isExistingAccount: true
      });
    } else {
      // No existing user - create a new one with Google data
      // Generate a random username from the email (before the @ symbol)
      const baseUsername = email.split('@')[0];
      let username = baseUsername;
      let usernameExists = true;
      let counter = 1;
      
      // Keep trying until we find an available username
      while (usernameExists) {
        const existingUser = await User.findOne({ userName: username });
        if (!existingUser) {
          usernameExists = false;
        } else {
          username = `${baseUsername}${counter}`;
          counter++;
        }
      }
      
      // Create the new user
      const newUser = new User({
        fullname: fullname || "Google User",
        userName: username,
        email,
        profileUrl: photoURL || "",
        firebaseUID,
        // Set a secure random password that the user can't use
        // (they'll authenticate with Google)
        password: await bcrypt.hash(Math.random().toString(36).slice(-10), 10)
      });
      
      await newUser.save();
      
      return res.status(201).json({ 
        message: "New account created with Google", 
        user: newUser,
        isExistingAccount: false
      });
    }
  } catch (error) {
    console.error("Google auth error:", error);
    res.status(500).json({ message: "Server error" });
  }
});

// Resend OTP route
router.post("/resend-otp", async (req, res) => {
  try {
    const { email } = req.body;

    // Validate input
    if (!email) {
      return res.status(400).json({ message: "Email is required" });
    }

    // Check if there's an existing OTP request
    const existingRequest = otpStore.get(email);
    
    if (!existingRequest) {
      return res.status(404).json({ 
        message: "No pending registration found for this email" 
      });
    }

    // Generate new OTP
    const otp = generateOTP();
    
    // Update the OTP and expiration
    otpStore.set(email, {
      otp,
      userData: existingRequest.userData,
      expiresAt: Date.now() + 10 * 60 * 1000 // 10 minutes
    });

    // Send new OTP via email
    await sendOTPEmail(email, otp);

    res.status(200).json({ 
      message: "New OTP sent to your email" 
    });
  } catch (error) {
    console.error("Resend OTP error:", error);
    res.status(500).json({ message: "Server error" });
  }
});

module.exports = router;
