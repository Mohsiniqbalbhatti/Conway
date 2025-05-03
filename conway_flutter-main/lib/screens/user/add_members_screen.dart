import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import '../../constants/api_config.dart';
// Assuming this model has id, fullname, email, profileUrl

class AddMembersScreen extends StatefulWidget {
  final String groupId;
  final String adminId; // ID of the user performing the action (admin)

  const AddMembersScreen({
    super.key,
    required this.groupId,
    required this.adminId,
  });

  @override
  AddMembersScreenState createState() => AddMembersScreenState();
}

class AddMembersScreenState extends State<AddMembersScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  final Set<Map<String, dynamic>> _selectedUsers =
      {}; // Use a Set to avoid duplicates
  bool _isLoadingSearch = false;
  bool _isLoadingAdd = false;
  Timer? _debounce;

  // Colors
  final Color _primaryColor = const Color(0xFF19BFB7);
  final Color _secondaryColor = const Color(0xFF59A52C);

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (query.trim().isNotEmpty) {
        _searchUsers(query.trim());
      } else {
        setState(() {
          _searchResults = [];
        });
      }
    });
  }

  Future<void> _searchUsers(String query) async {
    setState(() {
      _isLoadingSearch = true;
    });

    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/search-user'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'query': query,
          // 'useremail' is optional in backend now, no need to send if not excluding admin
          // 'useremail': widget.adminEmail, // If you had admin email and wanted to exclude
        }),
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          // Assuming the API returns a list of users with 'id', 'fullname', 'email', 'profileUrl'
          _searchResults = List<Map<String, dynamic>>.from(data['users'] ?? []);
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error searching users: ${response.statusCode}'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Network error searching users: ${e.toString()}'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingSearch = false;
        });
      }
    }
  }

  void _toggleSelection(Map<String, dynamic> user) {
    setState(() {
      if (_selectedUsers.any((selected) => selected['_id'] == user['_id'])) {
        _selectedUsers.removeWhere(
          (selected) => selected['_id'] == user['_id'],
        );
      } else {
        _selectedUsers.add(user);
      }
    });
  }

  Future<void> _addSelectedMembers() async {
    if (_selectedUsers.isEmpty || _isLoadingAdd) return;

    setState(() => _isLoadingAdd = true);

    final emailsToAdd =
        _selectedUsers.map((user) => user['email'] as String).toList();

    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/groups/${widget.groupId}/members'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'emailsToAdd': emailsToAdd,
          'userId': widget.adminId, // Pass admin ID for authorization
        }),
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              responseData['message'] ?? 'Members added successfully!',
            ),
          ),
        );
        // Optionally clear selection and search, or pop the screen
        setState(() {
          _selectedUsers.clear();
          _searchController.clear();
          _searchResults = [];
        });
        // Consider popping back to settings screen after success
        Navigator.pop(context, true); // Pass true to indicate changes were made
      } else {
        final errorBody = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to add members: ${response.statusCode} - ${errorBody?['error'] ?? 'Unknown error'}',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Network error adding members: ${e.toString()}'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingAdd = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Members'),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [_primaryColor, _secondaryColor],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: const TextStyle(color: Colors.white, fontSize: 20),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by name or email...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon:
                    _searchController.text.isNotEmpty
                        ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchResults = []);
                          },
                        )
                        : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.grey[100],
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 0,
                  horizontal: 20,
                ),
              ),
              onChanged: _onSearchChanged,
            ),
          ),
          if (_isLoadingSearch)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Center(child: CircularProgressIndicator()),
            ),
          Expanded(
            child: ListView.builder(
              itemCount: _searchResults.length,
              itemBuilder: (context, index) {
                final user = _searchResults[index];
                final isSelected = _selectedUsers.any(
                  (selected) => selected['_id'] == user['_id'],
                );
                final profileUrl = user['profileUrl'] as String?;
                final hasProfileUrl =
                    profileUrl != null && profileUrl.isNotEmpty;

                // TODO: Consider filtering out users already in the group here if needed

                return ListTile(
                  leading: CircleAvatar(
                    backgroundImage:
                        hasProfileUrl
                            ? CachedNetworkImageProvider(profileUrl)
                            : null,
                    child: !hasProfileUrl ? const Icon(Icons.person) : null,
                  ),
                  title: Text(user['fullname'] ?? 'Unknown Name'),
                  subtitle: Text(user['email'] ?? 'No email'),
                  trailing: Checkbox(
                    value: isSelected,
                    onChanged: (bool? value) {
                      _toggleSelection(user);
                    },
                    activeColor: _primaryColor,
                  ),
                  onTap: () => _toggleSelection(user),
                );
              },
            ),
          ),
          if (_selectedUsers.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: ElevatedButton(
                onPressed: _addSelectedMembers,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryColor,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(
                    double.infinity,
                    50,
                  ), // Make button wide
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                child:
                    _isLoadingAdd
                        ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                            strokeWidth: 3,
                          ),
                        )
                        : Text(
                          'Add ${_selectedUsers.length} Member${_selectedUsers.length > 1 ? 's' : ''}',
                        ),
              ),
            ),
        ],
      ),
    );
  }
}
