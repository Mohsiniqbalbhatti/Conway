const schedule = require("node-schedule");
const Message = require("../../models/Message");
const Chat = require("../../models/Chat");
const User = require("../../models/User");
const Group = require("../../models/Group");

function handleScheduledMessage(message, io, userSockets) {
  if (!message.isScheduled || !message.scheduledAt) {
    return;
  }

  const scheduleTime = new Date(message.scheduledAt);
  if (scheduleTime <= new Date()) {
    console.warn(
      `[Message Service] Schedule time ${scheduleTime.toISOString()} is in the past. Sending now.`
    );
    sendScheduledMessage(message, io, userSockets);
    return;
  }

  console.log(
    `[Message Service] Scheduling message ${
      message._id
    } for ${scheduleTime.toISOString()}`
  );

  schedule.scheduleJob(scheduleTime, async () => {
    await sendScheduledMessage(message, io, userSockets);
  });
}

async function sendScheduledMessage(message, io, userSockets) {
  try {
    const updatedMessage = await Message.findByIdAndUpdate(
      message._id,
      { sent: true },
      { new: true }
    );

    if (!updatedMessage) {
      console.error(`[Message Service] Message ${message._id} not found`);
      return;
    }

    const sender = await User.findById(message.sender).select("fullname");
    if (!sender) {
      console.error(
        `[Message Service] Sender not found for message ${message._id}`
      );
      return;
    }

    const messageToSend = {
      id: updatedMessage._id.toString(),
      senderId: updatedMessage.sender.toString(),
      senderName: sender.fullname,
      text: updatedMessage.message,
      time: updatedMessage.time.toISOString(),
      isBurnout: updatedMessage.isBurnout,
      expireAt: updatedMessage.expireAt?.toISOString(),
      isScheduled: updatedMessage.isScheduled,
      scheduledAt: updatedMessage.scheduledAt?.toISOString(),
    };

    if (updatedMessage.group) {
      // Handle group message
      messageToSend.groupId = updatedMessage.group.toString();
      const group = await Group.findById(updatedMessage.group).select("users");
      if (!group) {
        console.error(
          `[Message Service] Group not found for message ${message._id}`
        );
        return;
      }

      group.users.forEach((userId) => {
        const memberIdStr = userId.toString();
        if (memberIdStr !== updatedMessage.sender.toString()) {
          const memberSocketId = userSockets.get(memberIdStr);
          if (memberSocketId) {
            io.to(memberSocketId).emit("receiveMessage", messageToSend);
          }
        }
      });
    } else {
      // Handle direct message
      const receiverSocketId = userSockets.get(
        updatedMessage.receiver.toString()
      );
      if (receiverSocketId) {
        io.to(receiverSocketId).emit("receiveMessage", messageToSend);
      }
    }

    // Update chat's last message
    await Chat.findByIdAndUpdate(updatedMessage.chat, {
      lastMessage: updatedMessage._id,
    });

    console.log(
      `[Message Service] Scheduled message ${message._id} sent successfully`
    );
  } catch (error) {
    console.error(
      `[Message Service] Error sending scheduled message ${message._id}:`,
      error
    );
  }
}

async function checkScheduledAndExpiredMessages() {
  try {
    const now = new Date();

    // Find and send scheduled messages that are due
    const scheduledMessages = await Message.find({
      isScheduled: true,
      sent: false,
      scheduledAt: { $lte: now },
    });

    for (const message of scheduledMessages) {
      await sendScheduledMessage(message);
    }

    // Find and delete expired messages
    const expiredMessages = await Message.find({
      isBurnout: true,
      expireAt: { $lte: now },
    });

    for (const message of expiredMessages) {
      await Message.findByIdAndDelete(message._id);
      console.log(`[Message Service] Deleted expired message ${message._id}`);
    }
  } catch (error) {
    console.error(
      "[Message Service] Error checking scheduled and expired messages:",
      error
    );
  }
}

module.exports = {
  handleScheduledMessage,
  sendScheduledMessage,
  checkScheduledAndExpiredMessages,
};
