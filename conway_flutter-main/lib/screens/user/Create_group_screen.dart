import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../models/user.dart';
import '../../helpers/database_helper.dart';
import '../../constants/api_config.dart';
import 'package:cached_network_image/cached_network_image.dart';

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  CreateGroupScreenState createState() => CreateGroupScreenState();
}

class CreateGroupScreenState extends State<CreateGroupScreen> {
  final TextEditingController _createGroupController = TextEditingController();
  final TextEditingController _searchGroupController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final Color _primaryColor = const Color(0xFF19BFB7);
  final Color _secondaryColor = const Color(0xFF59A52C);

  List<Map<String, dynamic>> _searchedGroups = [];
  List<Map<String, dynamic>> _suggestedGroups = [];
  List<Map<String, dynamic>> _allGroups = [];
  bool _isLoading = false;
  User? _currentUser;
  final Set<String> _requestedGroupIds = {};

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadSuggestedGroups();
    _fetchAllGroups();

    // Set focus to search field after widget is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _createGroupController.dispose();
    _searchGroupController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    final user = await DBHelper().getUser();
    setState(() {
      _currentUser = user;
    });
  }

  Future<void> _loadSuggestedGroups() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final user = await DBHelper().getUser();
      if (user == null) return;

      final response = await http.get(
        Uri.parse(
          '${ApiConfig.baseUrl}/api/suggested-groups?email=${user.email}',
        ),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _suggestedGroups = List<Map<String, dynamic>>.from(data['groups']);
        });
      }
    } catch (e) {
      // Handle error
      debugPrint('Error loading suggested groups: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _createGroup() async {
    if (_createGroupController.text.trim().isEmpty || _currentUser == null) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/groups'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'groupName': _createGroupController.text.trim(),
          'creator': _currentUser!.id,
        }),
      );

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Group created successfully!')),
          );
          _createGroupController.clear();
          Navigator.pop(
            context,
            true,
          ); // Return true to refresh the groups list
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Failed to create group')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _fetchAllGroups() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/search-group'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'groupName': '', 'userId': _currentUser?.id}),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _allGroups = List<Map<String, dynamic>>.from(data['groups']);
        });
      }
    } catch (e) {
      debugPrint('Error fetching all groups: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _filterGroups(String query) {
    final trimmed = query.trim().toLowerCase();
    if (trimmed.isEmpty) {
      setState(() {
        _searchedGroups = [];
      });
    } else {
      setState(() {
        _searchedGroups =
            _allGroups.where((group) {
              final name = group['groupName']?.toString().toLowerCase() ?? '';
              return name.contains(trimmed);
            }).toList();
      });
    }
  }

  Future<void> _joinGroup(String groupId) async {
    if (_currentUser == null) return;

    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/addInGroup'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'userEmail': _currentUser!.email,
          'groupId': groupId,
        }),
      );

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Joined group successfully!')));
          Navigator.pop(
            context,
            true,
          ); // Return true to refresh the groups list
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Failed to join group')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _requestJoinGroup(String groupId) async {
    if (_currentUser == null) return;
    setState(() => _requestedGroupIds.add(groupId));
    try {
      final resp = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/groups/$groupId/join-requests'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'userId': _currentUser!.id}),
      );
      if (resp.statusCode == 200) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Join request sent')));
      } else {
        setState(() => _requestedGroupIds.remove(groupId));
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to send request')));
      }
    } catch (e) {
      setState(() => _requestedGroupIds.remove(groupId));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
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
        title: const Text('Groups', style: TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body:
          _isLoading
              ? Center(child: CircularProgressIndicator(color: _primaryColor))
              : SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Create Group Section
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Create New Group',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: _createGroupController,
                              decoration: InputDecoration(
                                hintText: 'Enter group name',
                                filled: true,
                                fillColor: Colors.white,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(30),
                                  borderSide: BorderSide.none,
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 15,
                                ),
                              ),
                            ),
                            const SizedBox(height: 15),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _createGroup,
                                style: ElevatedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  backgroundColor: _primaryColor,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(30),
                                  ),
                                ),
                                child: const Text('Create Group'),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Search Group Section
                      const Text(
                        'Search Groups',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _searchGroupController,
                        focusNode: _searchFocusNode,
                        decoration: InputDecoration(
                          hintText: 'Search by group name',
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
                              _searchGroupController.clear();
                              setState(() {
                                _searchedGroups = [];
                              });
                            },
                          ),
                        ),
                        onChanged: (value) => _filterGroups(value),
                      ),

                      // Search Results
                      if (_searchedGroups.isNotEmpty) ...[
                        const SizedBox(height: 15),
                        const Text(
                          'Search Results',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 5),
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _searchedGroups.length,
                          itemBuilder: (context, index) {
                            final group = _searchedGroups[index];
                            return ListTile(
                              leading: CircleAvatar(
                                radius: 20,
                                backgroundColor: _primaryColor,
                                backgroundImage:
                                    (group['profileUrl'] as String?)
                                                ?.isNotEmpty ==
                                            true
                                        ? CachedNetworkImageProvider(
                                          group['profileUrl'],
                                        )
                                        : null,
                                child:
                                    (group['profileUrl'] as String?)
                                                ?.isNotEmpty ==
                                            true
                                        ? null
                                        : const Icon(
                                          Icons.group,
                                          color: Colors.white,
                                          size: 24,
                                        ),
                              ),
                              title: Text(group['groupName'] ?? ''),
                              subtitle: Text(
                                'Created by: ${group['creator']['fullname']}',
                              ),
                              trailing:
                                  _requestedGroupIds.contains(group['_id'])
                                      ? const Text(
                                        'Requested',
                                        style: TextStyle(color: Colors.grey),
                                      )
                                      : ElevatedButton(
                                        onPressed:
                                            () =>
                                                _requestJoinGroup(group['_id']),
                                        style: ElevatedButton.styleFrom(
                                          foregroundColor: Colors.white,
                                          backgroundColor: _secondaryColor,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
                                          ),
                                        ),
                                        child: const Text('Join'),
                                      ),
                            );
                          },
                        ),
                      ],

                      // Suggested Groups
                      if (_suggestedGroups.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        const Text(
                          'Suggested Groups',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 10),
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _suggestedGroups.length,
                          itemBuilder: (context, index) {
                            final group = _suggestedGroups[index];
                            return ListTile(
                              leading: CircleAvatar(
                                radius: 20,
                                backgroundColor: _secondaryColor,
                                backgroundImage:
                                    (group['profileUrl'] as String?)
                                                ?.isNotEmpty ==
                                            true
                                        ? CachedNetworkImageProvider(
                                          group['profileUrl'],
                                        )
                                        : null,
                                child:
                                    (group['profileUrl'] as String?)
                                                ?.isNotEmpty ==
                                            true
                                        ? null
                                        : const Icon(
                                          Icons.group,
                                          color: Colors.white,
                                          size: 24,
                                        ),
                              ),
                              title: Text(group['groupName'] ?? ''),
                              subtitle: Text('${group['memberCount']} members'),
                              trailing:
                                  _requestedGroupIds.contains(group['_id'])
                                      ? const Text(
                                        'Requested',
                                        style: TextStyle(color: Colors.grey),
                                      )
                                      : ElevatedButton(
                                        onPressed:
                                            () =>
                                                _requestJoinGroup(group['_id']),
                                        style: ElevatedButton.styleFrom(
                                          foregroundColor: Colors.white,
                                          backgroundColor: _primaryColor,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
                                          ),
                                        ),
                                        child: const Text('Join'),
                                      ),
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
    );
  }
}
