const express = require("express");
const router = express.Router();
const multer = require("multer");
const cloudinary = require("cloudinary").v2;
const Report = require("../models/Report");
const fs = require("fs");
const path = require("path");

// Multer setup for file upload
const storage = multer.memoryStorage();
const upload = multer({ storage });

// POST /api/report
router.post("/report", upload.single("screenshot"), async (req, res) => {
  try {
    const { reporterEmail, reportedUserEmail, reportedMessage, description } =
      req.body;
    if (!reporterEmail || !reportedUserEmail || !description) {
      return res.status(400).json({
        success: false,
        message:
          "reporterEmail, reportedUserEmail, and description are required.",
      });
    }

    let screenshotUrl = undefined;
    if (req.file) {
      // Upload screenshot to Cloudinary
      const streamUpload = () => {
        return new Promise((resolve, reject) => {
          const stream = cloudinary.uploader.upload_stream(
            { folder: "conway_reports", resource_type: "image" },
            (error, result) => {
              if (result) {
                resolve(result.secure_url);
              } else {
                reject(error);
              }
            }
          );
          stream.end(req.file.buffer);
        });
      };
      try {
        screenshotUrl = await streamUpload();
      } catch (error) {
        return res
          .status(500)
          .json({ success: false, message: "Screenshot upload failed." });
      }
    }

    // Save report to DB
    const report = new Report({
      reporterEmail,
      reportedUserEmail,
      reportedMessage,
      description,
      screenshotUrl,
    });
    await report.save();
    return res
      .status(201)
      .json({ success: true, message: "Report submitted successfully." });
  } catch (err) {
    console.error("Error submitting report:", err);
    return res.status(500).json({ success: false, message: "Server error." });
  }
});

// GET /api/reports - List all reports (for admin)
router.get("/reports", async (req, res) => {
  try {
    const reports = await Report.find().sort({ createdAt: -1 });
    res.json({ success: true, reports });
  } catch (err) {
    console.error("Error fetching reports:", err);
    res.status(500).json({ success: false, message: "Server error." });
  }
});

// POST /api/profanity/add - Add words to custom profanity list (admin only)
router.post("/profanity/add", async (req, res) => {
  try {
    // For now, check admin by email in body (in production, use auth)
    const adminEmail = req.body.adminEmail || "";
    if (adminEmail !== "mohsiniqbalbhatti0024@gmail.com") {
      return res
        .status(403)
        .json({ success: false, message: "Access denied." });
    }
    const wordsRaw = req.body.words;
    if (!wordsRaw || typeof wordsRaw !== "string") {
      return res
        .status(400)
        .json({ success: false, message: "No words provided." });
    }
    const words = wordsRaw
      .split(",")
      .map((w) => w.trim().toLowerCase())
      .filter((w) => w.length > 0);
    if (words.length === 0) {
      return res
        .status(400)
        .json({ success: false, message: "No valid words provided." });
    }
    const filePath = path.join(__dirname, "../utils/custom_profanity.json");
    let currentList = [];
    if (fs.existsSync(filePath)) {
      try {
        currentList = JSON.parse(fs.readFileSync(filePath, "utf8"));
      } catch (e) {
        currentList = [];
      }
    }
    // Add new words, avoiding duplicates, and ensure all are lowercased
    const newList = Array.from(new Set([...currentList, ...words])).map((w) =>
      w.toLowerCase()
    );
    fs.writeFileSync(filePath, JSON.stringify(newList, null, 2));
    res.json({
      success: true,
      message: "Words added to custom profanity list.",
      list: newList,
    });
  } catch (err) {
    console.error("Error adding to profanity list:", err);
    res.status(500).json({ success: false, message: "Server error." });
  }
});

module.exports = router;
