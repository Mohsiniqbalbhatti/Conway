class User {
  // Change id type to String to store MongoDB ObjectId
  final String id;
  final String email;
  final String? fullname;
  final String? profileUrl;
  final DateTime? dateOfBirth;
  final String? timezone;

  User({
    required this.id,
    required this.email,
    this.fullname,
    this.profileUrl,
    this.dateOfBirth,
    this.timezone,
  });

  // Constructor for Firebase users (with String UID)
  factory User.fromFirebase(String uid, String email, String profileUrl) {
    // Convert Firebase UID to an integer hash code
    return User(
      id:
          uid.hashCode
              .abs()
              .toString(), // Convert string UID to int and then to string
      email: email,
      profileUrl: profileUrl,
      timezone: null,
    );
  }

  // Convert a User into a Map. Keys must correspond to column names in db.
  Map<String, dynamic> toMap() {
    return {
      // Use a consistent key like 'user_id' for the map key
      'user_id': id,
      'email': email,
      'fullname': fullname,
      'profileUrl': profileUrl,
      'dateOfBirth': dateOfBirth?.toIso8601String(),
      'timezone': timezone,
    };
  }

  // Implement toString to make it easier to see information about each user when debugging.
  @override
  String toString() {
    return 'User{id: $id, email: $email, profileUrl: $profileUrl, dateOfBirth: $dateOfBirth, timezone: $timezone}';
  }

  // Factory constructor to create a User from a Map
  factory User.fromMap(Map<String, dynamic> map) {
    return User(
      id: map['user_id'] ?? '', // Provide default or handle error
      email: map['email'] ?? '',
      fullname: map['fullname'], // Get from map
      profileUrl: map['profileUrl'],
      dateOfBirth:
          map['dateOfBirth'] != null
              ? DateTime.tryParse(map['dateOfBirth'])
              : null,
      timezone: map['timezone'],
    );
  }
}
