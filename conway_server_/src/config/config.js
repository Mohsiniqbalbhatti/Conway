require("dotenv").config();

module.exports = {
  // Server Configuration
  PORT: process.env.PORT || 5000,
  NODE_ENV: process.env.NODE_ENV || "development",

  // MongoDB Configuration
  MONGODB_URI: process.env.MONGODB_URI || "mongodb://localhost:27017/conway",

  // JWT Configuration
  JWT_SECRET: process.env.JWT_SECRET || "your-secret-key",
  JWT_EXPIRES_IN: process.env.JWT_EXPIRES_IN || "7d",

  // Cloudinary Configuration
  CLOUDINARY_CLOUD_NAME: process.env.CLOUDINARY_CLOUD_NAME,
  CLOUDINARY_API_KEY: process.env.CLOUDINARY_API_KEY,
  CLOUDINARY_API_SECRET: process.env.CLOUDINARY_API_SECRET,

  // Socket.IO Configuration
  SOCKET_CORS: {
    origin: "*",
    methods: ["GET", "POST"],
  },

  // Message Configuration
  MESSAGE_CHECK_INTERVAL: process.env.MESSAGE_CHECK_INTERVAL || 60000, // 1 minute in milliseconds
};
