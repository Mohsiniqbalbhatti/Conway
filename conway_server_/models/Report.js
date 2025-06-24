const mongoose = require("mongoose");

const ReportSchema = new mongoose.Schema({
  reporterEmail: { type: String, required: true },
  reportedUserEmail: { type: String, required: true },
  reportedMessage: { type: String },
  description: { type: String, required: true },
  screenshotUrl: { type: String },
  createdAt: { type: Date, default: Date.now },
});

module.exports = mongoose.model("Report", ReportSchema);
