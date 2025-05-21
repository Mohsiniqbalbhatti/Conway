# Conway App Birthday Wishes System

This document explains the architecture and implementation of the birthday wishes system in Conway app.

## Architecture Overview

The birthday wishes system is designed to ensure users receive birthday wishes even if they update their birthdate after the initial midnight check.

### Database Collections

1. **users Collection**:

   - Stores user details including birthdate (stored as Date) and timezone.

2. **birthday_wishes Collection**:
   - Tracks users to be wished, with fields:
     - `userId` (reference to users)
     - `targetDate` (local date of the birthday, stored as YYYY-MM-DD)
     - `sent` (boolean)
     - `createdAt` (timestamp for cleanup)

### System Components

#### 1. Real-Time Population on Updates/Registrations

**Trigger**: Whenever a user registers or updates their birthdate/timezone.

**Action**:

- Convert current UTC time to the user's local time zone.
- If local date matches birthdate, upsert into birthday_wishes with targetDate as today's local date and sent: false.

#### 2. Daily Prepopulation Cron Job

**Schedule**: Runs at midnight UTC.

**Action**:

- For each user, convert current UTC time to their local time zone.
- If local date matches birthdate, upsert into birthday_wishes with targetDate as today's local date and sent: false.

#### 3. Frequent Sending Cron Job

**Schedule**: Runs every 3 hours at 12, 3, 6, 9 AM/PM (0:00, 3:00, 6:00, 9:00, 12:00, 15:00, 18:00, 21:00 UTC).

**Action**:

- Query birthday_wishes where sent is false and targetDate is today in the user's local time.
- Send birthday wishes and set sent to true.

#### 4. Cleanup Cron Job

**Schedule**: Runs daily at 11:59 PM UTC (right before midnight).

**Action**:

- Remove ALL entries from the birthday_wishes collection, providing a fresh start for the next day.

## Implementation Details

### BirthdayWish Model

The `BirthdayWish` model defines the schema for the birthday_wishes collection with necessary fields and indexing.

### Birthday Service

Located in `utils/birthdayService.js`, this utility provides functions for:

1. Checking if today is a user's birthday based on their timezone
2. Adding users to the birthday_wishes collection
3. Processing real-time birthday checks during profile updates
4. Pre-populating birthday wishes at midnight
5. Sending birthday wishes to pending users
6. Cleaning up old entries

### Cron Jobs

Three scheduled jobs in `index.js`:

1. Midnight - Prepopulate birthday wishes
2. Every 3 hours (at 12, 3, 6, 9 AM/PM) - Send pending wishes
3. 11:59 PM - Clean up ALL birthday wishes

### Integration Points

1. **User Profile Updates**: When a user updates their birthdate or timezone, we trigger a real-time birthday check.
2. **Cron Jobs**: Scheduled tasks handle the regular processing of birthday wishes.

## Benefits

This architecture ensures:

1. **Timeliness**: Users get birthday wishes on their birthday, even if they update their birthdate during the day.
2. **Timezone Awareness**: Respects user's local time for accurate birthday detection.
3. **Efficiency**: Multiple sending jobs throughout the day catch newly updated birthdates.
4. **Cleanup**: Outdated entries are automatically removed.

## Future Enhancements

1. Add personalized birthday messages
2. Implement birthday reminders for friends
3. Add custom notification preferences for birthdays
