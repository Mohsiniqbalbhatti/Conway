const mongoose = require("mongoose");

const birthdayWishSchema = new mongoose.Schema({
  userId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: "User",
    required: true,
  },
  targetDate: {
    type: String, // YYYY-MM-DD format
    required: true,
  },
  sent: {
    type: Boolean,
    default: false,
  },
  createdAt: {
    type: Date,
    default: Date.now,
  },
});

// Compound index to ensure each user only has one entry per target date
birthdayWishSchema.index({ userId: 1, targetDate: 1 }, { unique: true });

module.exports = mongoose.model("BirthdayWish", birthdayWishSchema);
