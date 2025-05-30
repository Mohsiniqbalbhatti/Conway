// database_helper.dart
import 'package:flutter/foundation.dart'; // Import for debugPrint
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/user.dart' as conway_user;

class DBHelper {
  static final DBHelper _instance = DBHelper._internal();
  factory DBHelper() => _instance;
  DBHelper._internal();

  static Database? _database;
  static const String _dbName = 'conway.db';
  static const String _userTable = 'user';

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  Future<Database> _initDB() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbName);
    return await openDatabase(
      path,
      version: 3, // Increment version number for migration
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $_userTable(
        user_id TEXT PRIMARY KEY, 
        email TEXT UNIQUE,
        fullname TEXT,
        profileUrl TEXT,
        dateOfBirth TEXT,
        timezone TEXT
      )
      ''');
  }

  // Handle database migrations when version changes
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    debugPrint("Upgrading database from version $oldVersion to $newVersion");

    if (oldVersion < 2) {
      // Add dateOfBirth column if upgrading from version 1
      debugPrint("Adding dateOfBirth column to $_userTable table");
      try {
        await db.execute('ALTER TABLE $_userTable ADD COLUMN dateOfBirth TEXT');
      } catch (e) {
        debugPrint("Error adding dateOfBirth column: $e");
        // Handle the case where column might already exist
      }
    }
    if (oldVersion < 3) {
      // Add timezone column if upgrading from version < 3
      debugPrint("Adding timezone column to $_userTable table");
      try {
        await db.execute('ALTER TABLE $_userTable ADD COLUMN timezone TEXT');
      } catch (e) {
        debugPrint("Error adding timezone column: $e");
      }
    }
  }

  // Insert or update user
  Future<void> insertUser(conway_user.User user) async {
    final db = await database;
    await db.insert(
      _userTable,
      user.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace, // Replace if user_id exists
    );
    debugPrint(
      "[DBHelper insertUser] User inserted/replaced: ${user.email}, Fullname: ${user.fullname}, Timezone: ${user.timezone}",
    );
  }

  // Get the current user (should only be one)
  Future<conway_user.User?> getUser() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      _userTable,
      limit: 1,
    );

    if (maps.isNotEmpty) {
      debugPrint(
        "User retrieved from local DB: ${maps.first['user_id']}, Timezone: ${maps.first['timezone']}",
      );
      return conway_user.User.fromMap(maps.first);
    } else {
      debugPrint("No user found in local DB.");
      return null;
    }
  }

  // Update specific user details (like email, name, profileUrl, dateOfBirth, timezone)
  Future<int> updateUserDetails(
    String userId, {
    String? email,
    String? fullname,
    String? profileUrl,
    DateTime? dateOfBirth,
    String? timezone,
  }) async {
    final db = await database;
    Map<String, dynamic> dataToUpdate = {};
    if (email != null) dataToUpdate['email'] = email;
    if (fullname != null) dataToUpdate['fullname'] = fullname;
    if (profileUrl != null) dataToUpdate['profileUrl'] = profileUrl;
    if (dateOfBirth != null) {
      dataToUpdate['dateOfBirth'] = dateOfBirth.toIso8601String();
      debugPrint(
        "[DBHelper] Updating dateOfBirth to ${dateOfBirth.toIso8601String()} for user $userId",
      );
    }
    if (timezone != null) {
      dataToUpdate['timezone'] = timezone;
      debugPrint("[DBHelper] Updating timezone to $timezone for user $userId");
    }

    if (dataToUpdate.isEmpty) {
      debugPrint(
        "[DBHelper updateUserDetails] No details provided to update for userId: $userId",
      );
      return 0; // No changes made
    }

    debugPrint(
      "[DBHelper updateUserDetails] Updating userId: $userId with data: $dataToUpdate",
    );

    int result = await db.update(
      _userTable,
      dataToUpdate,
      where: 'user_id = ?',
      whereArgs: [userId],
    );

    // Verify the update by retrieving the user again
    if (result > 0) {
      final List<Map<String, dynamic>> updatedData = await db.query(
        _userTable,
        where: 'user_id = ?',
        whereArgs: [userId],
      );

      if (updatedData.isNotEmpty) {
        final storedDateOfBirth = updatedData.first['dateOfBirth'];
        final storedTimezone = updatedData.first['timezone'];
        debugPrint(
          "[DBHelper] After update, stored dateOfBirth is: $storedDateOfBirth, stored timezone is: $storedTimezone",
        );
      }
    }

    return result;
  }

  // Clear user data (for logout)
  Future<void> deleteUser() async {
    final db = await database;
    await db.delete(_userTable);
    debugPrint("User data deleted from local DB.");
  }
}
