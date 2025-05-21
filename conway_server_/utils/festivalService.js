const User = require("../models/User");
const Chat = require("../models/Chat");
const Message = require("../models/Message");

async function sendFestivalWish(messageText) {
  const users = await User.find({});
  let systemUser = await User.findOne({ userName: "Conway" });
  if (!systemUser) {
    const bcrypt = require("bcryptjs");
    const salt = await bcrypt.genSalt(10);
    const hashedPassword = await bcrypt.hash("Conway@2025", salt);
    systemUser = await User.create({
      fullname: "Conway",
      userName: "Conway",
      email: "conway@system",
      password: hashedPassword,
      isVerified: true,
    });
  }
  for (const user of users) {
    let chat = await Chat.findOne({
      participants: { $all: [systemUser._id, user._id] },
      isGroup: false,
    });
    if (!chat) {
      chat = await Chat.create({
        participants: [systemUser._id, user._id],
        isGroup: false,
      });
    }
    const newMessage = new Message({
      sender: systemUser._id,
      receiver: user._id,
      chat: chat._id,
      message: messageText,
      time: new Date(),
      sent: true,
    });
    await newMessage.save();
    await Chat.findByIdAndUpdate(chat._id, { lastMessage: newMessage._id });
    // Optionally emit socket event if user is online (add if needed)
  }
}

module.exports = { sendFestivalWish };
