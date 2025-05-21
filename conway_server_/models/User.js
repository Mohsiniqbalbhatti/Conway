const mongoose = require("mongoose");

const userSchema = new mongoose.Schema({
  fullname: {
    type: String,
    required: true,
    minlength: 3,
    maxlength: 20,
  },
  userName: {
    type: String,
    required: true,
    unique: true,
    minlength: 3,
    maxlength: 20,
  },
  email: {
    type: String,
    unique: true,
    pattern: /^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/,
  },
  password: {
    type: String,
    required: true,
    minlength: 8,
    maxlength: 1024,
  },
  profileUrl: {
    type: String,
    default: "",
  },
  firebaseUID: {
    type: String,
    default: null,
  },
  createdAt: {
    type: Date,
    default: Date.now,
  },
  updatedAt: {
    type: Date,
    default: Date.now,
  },
  isVerified: {
    type: Boolean,
    default: false,
  },
  pendingEmail: {
    type: String,
    default: null,
  },
  emailChangeOtp: {
    type: String,
    default: null,
  },
  emailChangeOtpExpires: {
    type: Date,
    default: null,
  },
  dateOfBirth: {
    type: Date,
    default: null,
  },
  timezone: {
    type: String,
    default: "UTC", // Default timezone
  },
  resetPasswordOtp: { type: String, default: null },
  resetPasswordOtpExpires: { type: Date, default: null },
});

// Add index for pendingEmail if needed for lookups, maybe unique sparse?
// userSchema.index({ pendingEmail: 1 }, { unique: true, sparse: true });

module.exports = mongoose.model("User", userSchema);
