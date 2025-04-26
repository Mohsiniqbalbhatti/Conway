// import 'dart:convert'; // Unused
// import 'package:http/http.dart' as http; // Unused
// import '../constants/api_config.dart'; // Unused

// DEPRECATED: Use SocketService for real-time chat
// class ChatService {
  // static const String baseUrl = 'http://192.168.1.17:3000/api'; // Old hardcoded URL
// ... rest of the deprecated class ...
// }

/* // Comment out the entire deprecated class
class ChatService {
  String? _userEmail;

  void setUserEmail(String email) {
    _userEmail = email;
  }

  Future<Map<String, dynamic>> getUpdates() async {
    try {
      if (_userEmail == null) {
        throw Exception('User email not set');
      }

      final response = await http.post(
        Uri.parse('$baseUrl/getupdate'), // Error here
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'myemail': _userEmail}),
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to get updates: ${response.statusCode}');
      }

      return jsonDecode(response.body);
    } catch (e) {
      throw Exception('Error getting updates: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getMessages(String receiverEmail) async {
    try {
      if (_userEmail == null) {
        throw Exception('User email not set');
      }

      final response = await http.post(
        Uri.parse('$baseUrl/get-messages'), // Error here
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'senderEmail': _userEmail,
          'receiverEmail': receiverEmail,
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to get messages: ${response.statusCode}');
      }

      final data = jsonDecode(response.body);
      return List<Map<String, dynamic>>.from(data['messages'] ?? []);
    } catch (e) {
      throw Exception('Error getting messages: $e');
    }
  }

  Future<void> sendMessage(String message, {String? receiverEmail, String? groupId}) async {
    try {
      if (_userEmail == null) {
        throw Exception('User email not set');
      }

      final Map<String, dynamic> body = {
        'messageText': message,
        'senderEmail': _userEmail,
      };

      if (receiverEmail != null) {
        body['receiverEmail'] = receiverEmail;
      }
      if (groupId != null) {
        body['groupId'] = groupId;
      }

      final response = await http.post(
        Uri.parse('$baseUrl/sendMessage'), // Error here
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      if (response.statusCode != 201) {
        throw Exception('Failed to send message: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error sending message: $e');
    }
  }
  
  Future<List<Map<String, dynamic>>> getSuggestedGroups() async {
    try {
      if (_userEmail == null) {
        throw Exception('User email not set');
      }

      final response = await http.get(
        Uri.parse('$baseUrl/suggested-groups?email=$_userEmail'), // Error here
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to get suggested groups: ${response.statusCode}');
      }

      final data = jsonDecode(response.body);
      return List<Map<String, dynamic>>.from(data['groups'] ?? []);
    } catch (e) {
      throw Exception('Error getting suggested groups: $e');
    }
  }
}
*/