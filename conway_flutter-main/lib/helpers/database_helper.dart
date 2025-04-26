// database_helper.dart
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
      version: 1,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $_userTable(
        user_id TEXT PRIMARY KEY, 
        email TEXT UNIQUE,
        profileUrl TEXT
      )
      ''');
  }

  // Insert or update user
  Future<void> insertUser(conway_user.User user) async {
    final db = await database;
    await db.insert(
      _userTable,
      user.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace, // Replace if user_id exists
    );
    print("User inserted/updated in local DB: ${user.id}");
  }

  // Get the current user (should only be one)
  Future<conway_user.User?> getUser() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(_userTable, limit: 1);

    if (maps.isNotEmpty) {
      print("User retrieved from local DB: ${maps.first['user_id']}");
      return conway_user.User.fromMap(maps.first);
    } else {
      print("No user found in local DB.");
      return null;
    }
  }

  // Clear user data (for logout)
  Future<void> deleteUser() async {
    final db = await database;
    await db.delete(_userTable);
    print("User data deleted from local DB.");
  }
}