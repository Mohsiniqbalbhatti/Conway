const mongoose = require("mongoose");

const messageSchema = new mongoose.Schema({
  sender: { type: mongoose.Schema.Types.ObjectId, ref: "User", required: true },
  receiver: {
    type: mongoose.Schema.Types.ObjectId,
    ref: "User",
    default: null,
  },
  group: { type: mongoose.Schema.Types.ObjectId, ref: "Group", default: null },
  chat: {
    type: mongoose.Schema.Types.ObjectId,
    ref: "Chat",
    required: true,
  },
  message: { type: String, required: true },
  time: { type: Date, default: Date.now },
  sent: { type: Boolean, default: false },
  isBurnout: { type: Boolean, default: false },
  expireAt: { type: Date, default: null },
  isScheduled: { type: Boolean, default: false },
  scheduledAt: { type: Date, default: null },
  deleted_at: { type: Date, default: null },
});

messageSchema.index({ sender: 1, receiver: 1, time: -1 });
messageSchema.index({ receiver: 1, sender: 1, time: -1 });
messageSchema.index({ group: 1, time: -1 });
messageSchema.index({ isScheduled: 1, scheduledAt: 1 });
messageSchema.index({ chat: 1, time: -1 });

module.exports = mongoose.model("Message", messageSchema);
