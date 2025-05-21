const moment = require("moment-timezone");
const User = require("../models/User");
const BirthdayWish = require("../models/BirthdayWish");
const Chat = require("../models/Chat");
const Message = require("../models/Message");

/**
 * Check if a user's birthday is today in their local timezone
 * @param {Object} user - User document with dateOfBirth and timezone fields
 * @returns {boolean} True if today is the user's birthday
 */
const isBirthdayToday = (user) => {
  if (!user.dateOfBirth) return false;

  // Get user's timezone, default to "Asia/Karachi" if not set or is "UTC"
  const userTimezone =
    user.timezone && user.timezone !== "UTC" && user.timezone !== ""
      ? user.timezone
      : "Asia/Karachi";

  // Convert current time to user's effective timezone (Asia/Karachi or specific)
  const nowInUserTimezone = moment().tz(userTimezone);

  // Get just the month and date from the date of birth (ignoring year and time)
  const birthDate = moment.utc(user.dateOfBirth);

  // Format dates for debugging in user-friendly format (1-indexed months)
  const birthDayOfMonth = birthDate.date();
  const birthMonth = birthDate.month() + 1; // Add 1 because months are 0-indexed

  const currentDayOfMonth = nowInUserTimezone.date();
  const currentMonth = nowInUserTimezone.month() + 1; // Add 1 for consistency

  // Log detailed comparison information
  console.log(
    `[Birthday Service] Checking birthday for user ${user._id} (${
      user.fullname || "Unknown"
    })`
  );
  console.log(
    `[Birthday Service] Date of birth (UTC): ${user.dateOfBirth.toISOString()}`
  );
  console.log(
    `[Birthday Service] Effective User timezone for check: ${userTimezone}`
  ); // Log the timezone being used
  console.log(
    `[Birthday Service] Current date in effective user timezone (${userTimezone}): ${nowInUserTimezone.format(
      "YYYY-MM-DD HH:mm:ss"
    )}`
  );
  console.log(
    `[Birthday Service] Birth month/day (from UTC DOB): ${birthMonth}/${birthDayOfMonth}`
  );
  console.log(
    `[Birthday Service] Current month/day in effective user timezone: ${currentMonth}/${currentDayOfMonth}`
  );

  // Compare month and day only (ignore year)
  const isToday =
    birthMonth === currentMonth && birthDayOfMonth === currentDayOfMonth;

  console.log(
    `[Birthday Service] Is birthday today in user's effective timezone? ${isToday}`
  );
  return isToday;
};

/**
 * Add a user to the birthday wishes collection if today is their birthday
 * @param {Object} user - User document
 * @returns {Promise<boolean>} True if user was added to birthday wishes
 */
const checkAndAddToBirthdayWishes = async (user) => {
  const isBirthday = isBirthdayToday(user);
  console.log(
    `[Birthday Service] Birthday check result for ${user._id}: ${isBirthday}`
  );

  if (!isBirthday) return false;

  // Get today's date in user's timezone as YYYY-MM-DD
  const effectiveTimezone =
    user.timezone && user.timezone !== "UTC" && user.timezone !== ""
      ? user.timezone
      : "Asia/Karachi";
  const localDateForTarget = moment()
    .tz(effectiveTimezone)
    .format("YYYY-MM-DD");

  console.log(
    `[Birthday Service] Using localDate for targetDate (${effectiveTimezone}): ${localDateForTarget}`
  );

  try {
    // Use the LOCAL date (in user's effective timezone) for targetDate
    const result = await BirthdayWish.findOneAndUpdate(
      { userId: user._id, targetDate: localDateForTarget },
      { sent: false },
      { upsert: true, new: true }
    );

    console.log(
      `[Birthday Service] User ${user._id} (${
        user.fullname || "Unknown"
      }) added/updated in birthday wishes for targetDate: ${localDateForTarget}. Document: ${JSON.stringify(
        result.toJSON ? result.toJSON() : result
      )}`
    );
    return true;
  } catch (err) {
    console.error(
      `[Birthday Service] Error adding user ${user._id} to birthday wishes:`,
      err
    );
    return false;
  }
};

/**
 * Process real-time birthday check for user registration or profile update
 * @param {Object} user - User document
 * @returns {Promise<void>}
 */
const processBirthdayRealTime = async (user) => {
  console.log(
    `[Birthday Service] Processing real-time birthday check for user: ${user._id}`
  );
  const result = await checkAndAddToBirthdayWishes(user);
  console.log(
    `[Birthday Service] Real-time check result: ${
      result ? "Birthday wish created" : "No birthday today"
    }`
  );
  return result;
};

/**
 * Daily prepopulation of birthday wishes collection
 * @returns {Promise<number>} Number of users added to birthday wishes
 */
const prepopulateBirthdayWishes = async () => {
  try {
    const allUsers = await User.find({
      dateOfBirth: { $exists: true, $ne: null },
    });
    console.log(
      `[Birthday Service] Found ${allUsers.length} users with birthdates for prepopulation check`
    );

    let addedCount = 0;
    for (const user of allUsers) {
      const added = await checkAndAddToBirthdayWishes(user);
      if (added) addedCount++;
    }

    console.log(
      `[Birthday Service] Prepopulated ${addedCount} users with birthdays today`
    );
    return addedCount;
  } catch (err) {
    console.error("[Birthday Service] Error in prepopulation job:", err);
    return 0;
  }
};

/**
 * Send birthday wishes to users
 * @param {Object} io - Socket.io instance for real-time notifications
 * @param {Map} userSockets - Map of user IDs to socket IDs
 * @returns {Promise<number>} Number of wishes sent
 */
const sendBirthdayWishes = async (io, userSockets) => {
  try {
    // Get today's date in UTC (this matches how we store targetDate now)
    const today = moment().tz("Asia/Karachi").format("YYYY-MM-DD");

    console.log(
      `[Birthday Service] Checking for birthday wishes with targetDate: ${today}`
    );

    // Find pending birthday wishes for today
    const pendingWishes = await BirthdayWish.find({
      targetDate: today,
      sent: false,
    }).populate("userId", "fullname email _id timezone");

    console.log(
      `[Birthday Service] Found ${pendingWishes.length} pending birthday wishes to send`
    );

    if (pendingWishes.length === 0) return 0;

    // Ensure system user exists
    let systemUser = await User.findOne({ userName: "Conway" });
    if (!systemUser) {
      // Create the system user if needed
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
      console.log(`[Birthday Service] Created system user: ${systemUser._id}`);
    }

    let sentCount = 0;
    for (const wish of pendingWishes) {
      const user = wish.userId; // This is populated with user document

      if (!user) {
        console.warn(`[Birthday Service] User not found for wish ${wish._id}`);
        continue;
      }

      try {
        // Find or create chat between system user and birthday user
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

        // Create birthday message
        const messageText = `Happy Birthday, ${user.fullname}! 🎉`;
        const now = new Date();

        const newMessage = new Message({
          sender: systemUser._id,
          receiver: user._id,
          chat: chat._id,
          message: messageText,
          time: now,
          sent: true,
        });

        await newMessage.save();

        // Update last message in chat
        await Chat.findByIdAndUpdate(chat._id, { lastMessage: newMessage._id });

        // Send real-time notification if user is online
        const socketId = userSockets.get(user._id.toString());
        if (socketId) {
          io.to(socketId).emit("receiveMessage", {
            id: newMessage._id.toString(),
            senderId: systemUser._id.toString(),
            senderEmail: systemUser.email,
            senderName: systemUser.fullname,
            receiverEmail: user.email,
            text: messageText,
            time: now.toISOString(),
            isBurnout: false,
            expireAt: null,
            isScheduled: false,
            scheduledAt: null,
          });
        }

        // Mark wish as sent
        wish.sent = true;
        await wish.save();

        sentCount++;
        console.log(
          `[Birthday Service] Sent birthday wish to ${user.fullname} (${user._id})`
        );
      } catch (err) {
        console.error(
          `[Birthday Service] Error sending wish to user ${user._id}:`,
          err
        );
      }
    }

    console.log(
      `[Birthday Service] Successfully sent ${sentCount} birthday wishes`
    );
    return sentCount;
  } catch (err) {
    console.error("[Birthday Service] Error in send wishes job:", err);
    return 0;
  }
};

/**
 * Clean up old birthday wishes
 * @returns {Promise<number>} Number of wishes cleaned up
 */
const cleanupBirthdayWishes = async () => {
  try {
    console.log(
      `[Birthday Service] Running FULL cleanup of birthday wishes at ${new Date().toISOString()}`
    );

    // Delete ALL wishes instead of just old ones - this ensures a fresh start each day
    const result = await BirthdayWish.deleteMany({});

    console.log(
      `[Birthday Service] Cleaned up ALL birthday wishes (${result.deletedCount} documents)`
    );
    return result.deletedCount;
  } catch (err) {
    console.error("[Birthday Service] Error in cleanup job:", err);
    return 0;
  }
};

module.exports = {
  isBirthdayToday,
  checkAndAddToBirthdayWishes,
  processBirthdayRealTime,
  prepopulateBirthdayWishes,
  sendBirthdayWishes,
  cleanupBirthdayWishes,
};
