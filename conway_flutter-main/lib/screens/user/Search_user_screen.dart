import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../models/user.dart';
import '../../helpers/database_helper.dart';
import './chat_screen.dart';
import '../../constants/api_config.dart';

class SearchUserScreen extends StatefulWidget {
  const SearchUserScreen({Key? key}) : super(key: key);

  @override
  _SearchUserScreenState createState() => _SearchUserScreenState();
}

class _SearchUserScreenState extends State<SearchUserScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final Color _primaryColor = const Color(0xFF19BFB7);
  final Color _secondaryColor = const Color(0xFF59A52C);
  
  List<Map<String, dynamic>> _searchedUsers = [];
  bool _isLoading = false;
  User? _currentUser;
  
  @override
  void initState() {
    super.initState();
    _loadUserData();
    
    // Set focus to search field after widget is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocusNode.requestFocus();
    });
  }
  
  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }
  
  Future<void> _loadUserData() async {
    final user = await DBHelper().getUser();
    setState(() {
      _currentUser = user;
    });
  }
  
  Future<void> _searchUsers() async {
    if (_searchController.text.trim().isEmpty || _currentUser == null) return;
    
    setState(() {
      _isLoading = true;
    });
    
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/search-user'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'useremail': _currentUser!.email,
          'content': _searchController.text.trim(),
        }),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _searchedUsers = List<Map<String, dynamic>>.from(data['users']);
        });
      }
    } catch (e) {
      print('Error searching users: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  void _startChat(Map<String, dynamic> user) {
    final index = _searchedUsers.indexOf(user);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          userName: user['fullname'],
          userIndex: index,
          userEmail: user['email'],
        ),
      ),
    ).then((_) => Navigator.pop(context, true)); // Return true to refresh the chat list
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
                    setState(() {
                      _searchedUsers = [];
                    });
                  },
                ),
              ),
              onChanged: (_) => _searchUsers(),
            ),
          ),
          
          if (_isLoading)
            Center(child: CircularProgressIndicator(color: _primaryColor))
          else if (_searchedUsers.isEmpty && _searchController.text.isNotEmpty)
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
                  return ListTile(
                    leading: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: _getUserColor(index),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.person,
                        color: Colors.white,
                        size: 24,
                      ),
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