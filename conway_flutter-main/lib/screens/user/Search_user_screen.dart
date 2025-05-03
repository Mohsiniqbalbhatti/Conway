import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../models/user.dart' as conway_user; // Alias User model
import '../../helpers/database_helper.dart';
import './chat_screen.dart';
import '../../constants/api_config.dart';
import 'package:cached_network_image/cached_network_image.dart'; // Import
import 'dart:async'; // Import for Timer

class SearchUserScreen extends StatefulWidget {
  const SearchUserScreen({super.key}); // Use super parameters

  @override
  State<SearchUserScreen> createState() => _SearchUserScreenState(); // Make state public
}

class _SearchUserScreenState extends State<SearchUserScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final Color _primaryColor = const Color(0xFF19BFB7);
  final Color _secondaryColor = const Color(0xFF59A52C);

  List<Map<String, dynamic>> _searchedUsers = [];
  bool _isLoading = false;
  conway_user.User? _currentUser;
  Timer? _debounce; // Timer for debouncing search requests

  @override
  void initState() {
    super.initState();
    _loadUserData();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _debounce?.cancel(); // Cancel timer on dispose
    super.dispose();
  }

  Future<void> _loadUserData() async {
    final user = await DBHelper().getUser();
    if (mounted) {
      // Add mounted check
      setState(() {
        _currentUser = user;
      });
    }
  }

  void _onSearchChanged(String query) {
    // Cancel previous timer if active
    _debounce?.cancel();
    if (query.trim().isEmpty) {
      // Clear results immediately if query is empty
      setState(() {
        _searchedUsers = [];
        _isLoading = false;
      });
      return;
    }
    // Start a new timer
    _debounce = Timer(const Duration(milliseconds: 500), () {
      // Only search if the query hasn't changed during the debounce period
      if (_searchController.text == query) {
        _searchUsers(query.trim());
      }
    });
  }

  Future<void> _searchUsers(String query) async {
    if (query.isEmpty || _currentUser == null) return;

    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      // Use the correct search endpoint (assuming it's /api/search-user)
      // **Verify this endpoint exists and returns profileUrl**
      final response = await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/search-user'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'useremail': _currentUser!.email,
              'content': query,
            }),
          )
          .timeout(const Duration(seconds: 10)); // Add timeout

      debugPrint('Search Response Status: ${response.statusCode}');
      debugPrint('Search Response Body: ${response.body}');

      if (response.statusCode == 200 && mounted) {
        final data = jsonDecode(response.body);
        setState(() {
          _searchedUsers = List<Map<String, dynamic>>.from(data['users']);
        });
      } else if (mounted) {
        // Handle errors (e.g., show a snackbar)
        // Added mounted check
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Search failed: ${response.statusCode}')),
        );
      }
    } catch (e) {
      debugPrint('Error searching users: $e');
      if (mounted) {
        // Added mounted check
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Network error during search: ${e.toString()}'),
          ),
        );
      }
    } finally {
      if (mounted) {
        // Check mounted before final setState
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _startChat(Map<String, dynamic> user) async {
    // Check if required fields exist before navigating
    final String? userName = user['fullname'];
    final String? userEmail = user['email'];
    final String? profileUrl = user['profileUrl']; // Get profile URL

    if (userName == null || userEmail == null) {
      debugPrint("Error: Missing user details for chat.");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not start chat. User details missing.'),
        ),
      );
      return;
    }

    final index = _searchedUsers.indexOf(user);
    // Use await here to ensure the context check happens after pop
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => ChatScreen(
              userName: userName,
              userIndex:
                  index, // Pass index for color consistency in chat screen
              userEmail: userEmail,
              profileUrl: profileUrl, // Pass profile URL to ChatScreen
            ),
      ),
    ); // Wait for ChatScreen to pop

    // Check if mounted *after* the ChatScreen is popped
    if (mounted) {
      Navigator.pop(
        context,
        true,
      ); // Return true to refresh the chat list in HomeScreen
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [_primaryColor, _secondaryColor],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
          ),
        ),
        title: const Text('Find People', style: TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              decoration: InputDecoration(
                hintText: 'Search by name or email',
                prefixIcon: Icon(Icons.search, color: _primaryColor),
                filled: true,
                fillColor: Colors.grey[100],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 15,
                ),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    _onSearchChanged(
                      '',
                    ); // Trigger clearing results via debouncer logic
                  },
                ),
              ),
              onChanged: _onSearchChanged, // Use debounced search
            ),
          ),

          if (_isLoading)
            Padding(
              padding: EdgeInsets.all(16.0),
              child: Center(
                child: CircularProgressIndicator(color: _primaryColor),
              ),
            )
          else if (_searchedUsers.isEmpty &&
              _searchController.text.trim().isNotEmpty)
            const Expanded(
              child: Center(
                child: Text(
                  'No users found',
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                itemCount: _searchedUsers.length,
                itemBuilder: (context, index) {
                  final user = _searchedUsers[index];
                  final profileUrl = user['profileUrl'] as String?;
                  final hasProfileUrl =
                      profileUrl != null && profileUrl.isNotEmpty;

                  return ListTile(
                    // Display Profile Picture
                    leading: CircleAvatar(
                      radius: 24,
                      backgroundColor: _getUserColor(index),
                      backgroundImage:
                          hasProfileUrl
                              ? CachedNetworkImageProvider(profileUrl)
                              : null,
                      child:
                          !hasProfileUrl
                              ? const Icon(
                                Icons.person,
                                color: Colors.white,
                                size: 24,
                              )
                              : null,
                    ),
                    title: Text(
                      user['fullname'] ?? 'Unknown',
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    subtitle: Text(user['email'] ?? ''),
                    trailing: ElevatedButton(
                      onPressed: () => _startChat(user),
                      style: ElevatedButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: _primaryColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      child: const Text('Chat'),
                    ),
                    onTap: () => _startChat(user),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Color _getUserColor(int index) {
    final colors = [
      _primaryColor,
      _secondaryColor,
      Colors.deepPurple,
      Colors.orange,
    ];
    return colors[index % colors.length];
  }
}
