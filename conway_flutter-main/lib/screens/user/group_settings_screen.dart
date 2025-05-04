import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart'; // For group image
import 'package:image_picker/image_picker.dart'; // For picking image
import 'package:intl/intl.dart'; // For formatting date
import '../../constants/api_config.dart';
// To potentially display user info
// To get current user if needed again
import './add_members_screen.dart'; // Import the new screen

class GroupSettingsScreen extends StatefulWidget {
  final String groupId;
  final String groupName;
  final String currentUserId; // To check admin status

  const GroupSettingsScreen({
    super.key,
    required this.groupId,
    required this.groupName,
    required this.currentUserId,
  });

  @override
  GroupSettingsScreenState createState() => GroupSettingsScreenState();
}

class GroupSettingsScreenState extends State<GroupSettingsScreen> {
  bool _isAdmin = false;
  bool _isLoading = true;
  String? _creatorId;
  String _groupNameState = ''; // Use state variable for name
  String? _profileUrlState; // Use state variable for profile URL
  List<Map<String, dynamic>> _membersState =
      []; // Use state variable for members
  List<Map<String, dynamic>> _invitedState = [];
  DateTime? _createdAtState; // Add state variable for creation date
  int _selectedTab = 0; // 0: members, 1: invited, 2: requests
  List<Map<String, dynamic>> _requestsState = [];

  final TextEditingController _nameEditController = TextEditingController();
  final ImagePicker _picker = ImagePicker(); // Image picker instance

  @override
  void initState() {
    super.initState();
    _groupNameState = widget.groupName; // Initialize with passed name
    _fetchGroupDetailsAndCheckAdmin();
  }

  @override
  void dispose() {
    _nameEditController.dispose();
    super.dispose();
  }

  Future<void> _fetchGroupDetailsAndCheckAdmin() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });

    try {
      final response = await http
          .get(
            Uri.parse(
              '${ApiConfig.baseUrl}/api/groups/${widget.groupId}/details',
            ),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 15));

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _creatorId = data['creatorId'] as String?;
          _groupNameState = data['groupName'] as String? ?? widget.groupName;
          _profileUrlState = data['profileUrl'] as String?;
          _membersState = List<Map<String, dynamic>>.from(
            data['members'] ?? [],
          );
          _invitedState =
              (data['invitedMembers'] as List<dynamic>? ?? [])
                  .where((inv) => inv['status'] == 'pending')
                  .map((inv) => Map<String, dynamic>.from(inv as Map))
                  .toList();
          _requestsState = List<Map<String, dynamic>>.from(
            data['joinRequests'] as List<dynamic>? ?? [],
          );
          final createdAtString = data['createdAt'] as String?;
          _createdAtState =
              createdAtString != null
                  ? DateTime.tryParse(createdAtString)
                  : null;
          _isAdmin = widget.currentUserId == _creatorId;
          _isLoading = false;
          _nameEditController.text =
              _groupNameState; // Set initial text for editing
        });
      } else {
        // Handle error fetching details
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error fetching group details: ${response.statusCode}',
            ),
          ),
        );
        setState(() => _isLoading = false);
      }
    } catch (e) {
      // Handle network or other errors
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Network error fetching details: ${e.toString()}'),
          ),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _pickAndUpdateGroupImage() async {
    debugPrint("Pick and update group image - Tapped");
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);

      if (image == null) {
        debugPrint("No image selected.");
        return;
      }

      if (!mounted) return;

      // Show loading indicator (optional)
      // Consider using a state variable like _isUploadingImage
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Uploading image...')));

      // 1. Upload image to backend endpoint
      String? newImageUrl = await _uploadImage(image);

      if (!mounted) return;

      // 2. If upload successful, update the group via API
      if (newImageUrl != null) {
        debugPrint("Image uploaded, URL: $newImageUrl. Updating group...");
        try {
          final response = await http.put(
            Uri.parse('${ApiConfig.baseUrl}/api/groups/${widget.groupId}'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'profileUrl': newImageUrl, // Update profileUrl field
              'userId': widget.currentUserId, // Send user ID for authorization
            }),
          );

          if (!mounted) return;

          if (response.statusCode == 200) {
            setState(() {
              _profileUrlState = newImageUrl; // Update UI
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Group image updated!')),
            );
          } else {
            final errorBody = jsonDecode(response.body);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Failed to update group image: ${response.statusCode} - ${errorBody?['error'] ?? 'Unknown error'}',
                ),
              ),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Error updating group image URL: ${e.toString()}',
                ),
              ),
            );
          }
        }
      } else {
        // Upload failed (handled within _uploadImage)
        debugPrint("Image upload failed, URL not received.");
      }
    } catch (e) {
      debugPrint("Error picking image: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking image: ${e.toString()}')),
        );
      }
    } finally {
      // Hide loading indicator
    }
  }

  // Upload image to backend and return URL
  Future<String?> _uploadImage(XFile image) async {
    try {
      // Create multipart request
      final request = http.MultipartRequest(
        'POST',
        // Use the correct endpoint from group.js (assuming it's mounted at /api)
        Uri.parse('${ApiConfig.baseUrl}/api/group-picture'),
      );

      // Add fields
      request.fields['groupId'] = widget.groupId;

      // Add file
      request.files.add(
        await http.MultipartFile.fromPath(
          'groupImage', // Field name MUST match upload.single() in backend
          image.path,
          // Optionally set content type
          // contentType: MediaType('image', 'jpeg'), // Example
        ),
      );

      // Send request
      final streamedResponse = await request.send();

      // Read response
      final response = await http.Response.fromStream(streamedResponse);

      if (!mounted) return null;

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        return responseData['groupProfileUrl'] as String?;
      } else {
        // Handle upload error
        final errorBody = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Image upload failed: ${response.statusCode} - ${errorBody?['message'] ?? 'Unknown upload error'}',
            ),
          ),
        );
        return null;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error uploading image: ${e.toString()}')),
        );
      }
      return null;
    }
  }

  void _navigateToAddMembersScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) => AddMembersScreen(
              groupId: widget.groupId,
              adminId: widget.currentUserId, // Pass the admin ID
            ),
      ),
    ).then((changesMade) {
      // If the AddMembersScreen returns true, refresh the details
      if (changesMade == true) {
        _fetchGroupDetailsAndCheckAdmin();
      }
    });
  }

  // TODO: Implement functions for:
  // _editGroupName()
  // _changeGroupPicture()
  // _addMembers()
  // _leaveGroup()
  // _deleteGroup() (if admin)

  // Add helper to show either invited or members list
  Widget _buildMembersOrInvited() {
    if (_selectedTab == 0) {
      // Members
      if (_membersState.isEmpty) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 20.0),
          child: Text(
            'No members found.',
            style: TextStyle(color: Colors.grey),
          ),
        );
      }
      return ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _membersState.length,
        itemBuilder: (context, index) {
          final member = _membersState[index];
          final memberId = member['_id'] as String?;
          final profileUrl = member['profileUrl'] as String?;
          final isMemberAdmin = memberId == _creatorId;
          return ListTile(
            leading: CircleAvatar(
              radius: 20,
              backgroundColor: Colors.grey[200],
              backgroundImage:
                  profileUrl != null && profileUrl.isNotEmpty
                      ? CachedNetworkImageProvider(profileUrl)
                      : null,
              child:
                  profileUrl == null || profileUrl.isEmpty
                      ? const Icon(Icons.person)
                      : null,
            ),
            title: Text(member['fullname'] ?? 'Unknown User'),
            subtitle: Text(member['email'] ?? ''),
            trailing:
                isMemberAdmin
                    ? const Chip(
                      label: Text('Admin'),
                      backgroundColor: Colors.blueGrey,
                      labelStyle: TextStyle(color: Colors.white, fontSize: 10),
                      padding: EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                    )
                    : (_isAdmin && memberId != null
                        ? IconButton(
                          icon: Icon(
                            Icons.remove_circle_outline,
                            color: Colors.red[700],
                          ),
                          onPressed:
                              () => _showRemoveMemberConfirmation(
                                memberId,
                                member['fullname'] ?? 'Member',
                              ),
                        )
                        : null),
          );
        },
      );
    } else if (_selectedTab == 1) {
      // Invited
      if (_invitedState.isEmpty) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 20.0),
          child: Text('No invitations.', style: TextStyle(color: Colors.grey)),
        );
      }
      return ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _invitedState.length,
        itemBuilder: (context, index) {
          final inv = _invitedState[index];
          final user = inv['user'] as Map<String, dynamic>;
          final status = inv['status'] as String? ?? 'pending';
          final profileUrl = user['profileUrl'] as String?;
          final hasProfile = profileUrl != null && profileUrl.isNotEmpty;
          Color statusColor;
          String statusLabel;
          switch (status) {
            case 'accepted':
              statusColor = Colors.green;
              statusLabel = 'Accepted';
              break;
            case 'rejected':
              statusColor = Colors.red;
              statusLabel = 'Rejected';
              break;
            default:
              statusColor = Colors.orange;
              statusLabel = 'Pending';
          }
          return ListTile(
            leading: CircleAvatar(
              backgroundImage:
                  hasProfile ? CachedNetworkImageProvider(profileUrl!) : null,
              child: !hasProfile ? const Icon(Icons.person_add) : null,
            ),
            title: Text(user['fullname'] ?? ''),
            subtitle: Text(user['email'] ?? ''),
            trailing: Chip(
              label: Text(statusLabel),
              backgroundColor: statusColor.withOpacity(0.2),
              labelStyle: TextStyle(color: statusColor),
            ),
          );
        },
      );
    } else if (_selectedTab == 2) {
      // Join Requests
      if (_requestsState.isEmpty) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 20.0),
          child: Text(
            'No join requests.',
            style: TextStyle(color: Colors.grey),
          ),
        );
      }
      return ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _requestsState.length,
        itemBuilder: (context, index) {
          final req = _requestsState[index];
          final user = req['user'] as Map<String, dynamic>;
          return ListTile(
            leading: CircleAvatar(
              backgroundImage:
                  (user['profileUrl'] as String?)?.isNotEmpty == true
                      ? CachedNetworkImageProvider(user['profileUrl'])
                      : null,
              child:
                  (user['profileUrl'] as String?)?.isNotEmpty == true
                      ? null
                      : const Icon(Icons.person_add),
            ),
            title: Text(user['fullname'] ?? ''),
            subtitle: Text(user['email'] ?? ''),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(Icons.check_circle, color: Colors.green[700]),
                  tooltip: 'Accept request',
                  onPressed:
                      () =>
                          _respondJoinRequest(user['_id'].toString(), 'accept'),
                ),
                IconButton(
                  icon: Icon(Icons.cancel, color: Colors.red[700]),
                  tooltip: 'Reject request',
                  onPressed:
                      () =>
                          _respondJoinRequest(user['_id'].toString(), 'reject'),
                ),
              ],
            ),
          );
        },
      );
    } else {
      return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.groupName,
        ), // Use initial name, update later if editable
        // TODO: Add gradient like other screens?
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16.0),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 40.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Group Avatar (editable for admin)
                        InkWell(
                          onTap:
                              _isAdmin
                                  ? _pickAndUpdateGroupImage
                                  : null, // Only allow tap if admin
                          child: CircleAvatar(
                            radius: 60,
                            backgroundColor:
                                Colors.grey[300], // Placeholder background
                            backgroundImage:
                                _profileUrlState != null &&
                                        _profileUrlState!.isNotEmpty
                                    ? CachedNetworkImageProvider(
                                      _profileUrlState!,
                                    )
                                    : null,
                            child:
                                _profileUrlState == null ||
                                        _profileUrlState!.isEmpty
                                    ? Icon(
                                      Icons
                                          .group_add, // Icon for adding image or default
                                      size: 60,
                                      color: Colors.grey[600],
                                    )
                                    : null,
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Group Name (editable for admin)
                        Row(
                          // Wrap name and edit icon in a Row
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Flexible(
                              // Allow name to wrap if long
                              child: Text(
                                _groupNameState, // Display current name from state
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            if (_isAdmin)
                              IconButton(
                                icon: const Icon(Icons.edit, size: 18),
                                onPressed: () {
                                  _showEditNameDialog();
                                },
                              ),
                          ],
                        ),
                        Text(
                          // Use _createdAtState, provide fallback text if null
                          _createdAtState != null
                              ? 'Created on ${DateFormat.yMMMd().format(_createdAtState!)}'
                              : 'Creation date unavailable',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),

                        const SizedBox(height: 20),
                        const Divider(),
                        const SizedBox(height: 10),

                        // Tab Toggle
                        if (_isAdmin)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              TextButton(
                                onPressed:
                                    () => setState(() => _selectedTab = 0),
                                style: TextButton.styleFrom(
                                  backgroundColor:
                                      _selectedTab == 0
                                          ? Theme.of(
                                            context,
                                          ).primaryColor.withOpacity(0.1)
                                          : Colors.transparent,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                ),
                                child: Text(
                                  'Members (${_membersState.length})',
                                  style: TextStyle(
                                    color:
                                        _selectedTab == 0
                                            ? Theme.of(context).primaryColor
                                            : Colors.grey,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              TextButton(
                                onPressed:
                                    () => setState(() => _selectedTab = 1),
                                style: TextButton.styleFrom(
                                  backgroundColor:
                                      _selectedTab == 1
                                          ? Theme.of(
                                            context,
                                          ).primaryColor.withOpacity(0.1)
                                          : Colors.transparent,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                ),
                                child: Text(
                                  'Invited (${_invitedState.length})',
                                  style: TextStyle(
                                    color:
                                        _selectedTab == 1
                                            ? Theme.of(context).primaryColor
                                            : Colors.grey,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              TextButton(
                                onPressed:
                                    () => setState(() => _selectedTab = 2),
                                style: TextButton.styleFrom(
                                  backgroundColor:
                                      _selectedTab == 2
                                          ? Theme.of(
                                            context,
                                          ).primaryColor.withOpacity(0.1)
                                          : Colors.transparent,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                ),
                                child: Text(
                                  'Requests (${_requestsState.length})',
                                  style: TextStyle(
                                    color:
                                        _selectedTab == 2
                                            ? Theme.of(context).primaryColor
                                            : Colors.grey,
                                  ),
                                ),
                              ),
                            ],
                          ),

                        const SizedBox(height: 10),
                        // Display either invited or members list
                        _buildMembersOrInvited(),

                        // Add Members Button (Admin only)
                        if (_isAdmin)
                          TextButton.icon(
                            icon: const Icon(Icons.add),
                            label: const Text('Add Members'),
                            onPressed: () {
                              _navigateToAddMembersScreen();
                            },
                          ),

                        const SizedBox(height: 20),
                        const Divider(),
                        const SizedBox(height: 20),

                        // Action Buttons
                        TextButton.icon(
                          icon: Icon(Icons.exit_to_app, color: Colors.red[700]),
                          label: Text(
                            'Leave Group',
                            style: TextStyle(color: Colors.red[700]),
                          ),
                          onPressed: () => _showLeaveGroupConfirmation(),
                        ),

                        if (_isAdmin)
                          TextButton.icon(
                            icon: Icon(
                              Icons.delete_forever,
                              color: Colors.red[700],
                            ),
                            label: Text(
                              'Delete Group',
                              style: TextStyle(color: Colors.red[700]),
                            ),
                            onPressed: () {
                              /* TODO: Implement delete group confirmation */
                            },
                          ),
                      ],
                    ),
                  ),
                ),
              ),
    );
  }

  void _showEditNameDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Edit Group Name'),
          content: TextField(
            controller: _nameEditController,
            decoration: InputDecoration(labelText: 'New Group Name'),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                // Implement the logic to update the group name
                Navigator.of(context).pop();
              },
              child: Text('Save'),
            ),
          ],
        );
      },
    );
  }

  // Confirmation dialog for removing a member
  void _showRemoveMemberConfirmation(String memberId, String memberName) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Remove Member'),
          content: Text(
            'Are you sure you want to remove $memberName from the group?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red[700]),
              onPressed: () {
                Navigator.of(context).pop();
                _removeMember(memberId);
              },
              child: const Text('Remove'),
            ),
          ],
        );
      },
    );
  }

  // Remove a member via API and update UI
  Future<void> _removeMember(String memberId) async {
    setState(() => _isLoading = true);
    try {
      final response = await http.post(
        Uri.parse(
          '${ApiConfig.baseUrl}/api/groups/${widget.groupId}/remove-member',
        ),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'userId': widget.currentUserId,
          'memberId': memberId,
        }),
      );
      if (response.statusCode == 200) {
        setState(() {
          _membersState.removeWhere((m) => m['_id'] == memberId);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Member removed successfully')),
        );
      } else {
        final error = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to remove member: ${error['error'] ?? error['message'] ?? response.statusCode}',
            ),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error removing member: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // Show confirmation dialog for leaving the group
  void _showLeaveGroupConfirmation() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text('Leave Group'),
            content: Text('Are you sure you want to leave this group?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('Cancel'),
              ),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: Colors.red[700]),
                onPressed: () {
                  Navigator.of(context).pop();
                  _leaveGroup();
                },
                child: Text('Leave'),
              ),
            ],
          ),
    );
  }

  // Call the API to leave the group and handle UI
  Future<void> _leaveGroup() async {
    setState(() => _isLoading = true);
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/groups/${widget.groupId}/leave'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'userId': widget.currentUserId}),
      );
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Left group successfully')));
        Navigator.of(context).pop(true); // Indicate change upstream
      } else {
        final error = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to leave group: ${error['error'] ?? error['message'] ?? response.statusCode}',
            ),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error leaving group: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // Handle accept/reject join requests
  Future<void> _respondJoinRequest(String requestUserId, String action) async {
    setState(() => _isLoading = true);
    try {
      final resp = await http.post(
        Uri.parse(
          '${ApiConfig.baseUrl}/api/groups/${widget.groupId}/join-requests/respond',
        ),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'userId': widget.currentUserId,
          'requestUserId': requestUserId,
          'action': action,
        }),
      );
      if (resp.statusCode == 200) {
        // Remove from requests list
        final removed = _requestsState.firstWhere(
          (r) => r['user']['_id'].toString() == requestUserId,
        );
        setState(() {
          _requestsState.removeWhere(
            (r) => r['user']['_id'].toString() == requestUserId,
          );
          if (action == 'accept') {
            // Add to members
            _membersState.add({
              '_id': removed['user']['_id'],
              'fullname': removed['user']['fullname'],
              'email': removed['user']['email'],
              'profileUrl': removed['user']['profileUrl'] ?? '',
            });
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Request ${action}ed successfully')),
        );
      } else {
        final err = jsonDecode(resp.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to ${action} request: ${err['error'] ?? err['message'] ?? resp.statusCode}',
            ),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }
}
