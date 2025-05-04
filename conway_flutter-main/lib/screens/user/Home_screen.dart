import 'package:flutter/material.dart';
import 'package:conway/helpers/auth_guard.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import './settings_screen.dart';
import './chat_screen.dart';
import './group_chat_screen.dart';
import './Search_user_screen.dart';
import './Create_group_screen.dart';
import '../../models/user.dart' as conway_user;
import '../../helpers/database_helper.dart';
import '../../constants/api_config.dart';
import '../../services/socket_service.dart';
import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';

class HomeScreen extends StatefulWidget {
  final VoidCallback? onLogout;

  const HomeScreen({super.key, this.onLogout});

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _currentIndex = 0;

  // Color scheme
  final Color _primaryColor = const Color(0xFF19BFB7);
  final Color _secondaryColor = const Color(0xFF59A52C);
  final Color _backgroundColor = Colors.white;

  // Data
  List<Map<String, dynamic>> _chats = [];
  List<Map<String, dynamic>> _groups = [];
  bool _isLoading = true;
  conway_user.User? _currentUser;
  String _searchQuery = '';

  final SocketService _socketService = SocketService();
  StreamSubscription? _messageSubscription;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        // Optional: Fetch data only when tab actually changes if needed
        // print("Tab changed to: ${_tabController.index}");
      } else {
        // Update _currentIndex when animation finishes
        if (mounted && _currentIndex != _tabController.index) {
          setState(() {
            _currentIndex = _tabController.index;
          });
        }
      }
    });
    _loadUserData().then((_) {
      if (mounted && _currentUser != null) {
        debugPrint(
          "[HomeScreen] User loaded: ${_currentUser!.email} (ID: ${_currentUser!.id})",
        );
        _socketService.connect(_currentUser!.id.toString());
        debugPrint("[HomeScreen] Socket connect initiated.");
        _fetchData();
        _subscribeToMessages();
      } else if (mounted) {
        debugPrint("[HomeScreen] User not loaded after trying.");
        setState(() => _isLoading = false);
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _messageSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    if (!mounted) return;
    // Check mounted immediately before using context after potential async gap
    if (mounted) {
      await AuthGuard.isAuthenticated(context);
    } else {
      return;
    }
    // Keep check after DB call, before setState
    final user = await DBHelper().getUser();
    if (mounted) {
      setState(() {
        _currentUser = user;
      });
    } else {
      debugPrint("[HomeScreen _loadUserData] Not mounted after loading user.");
    }
  }

  Future<void> _fetchData() async {
    if (_currentUser == null) {
      debugPrint("[HomeScreen FETCH] User not loaded yet, skipping fetch.");
      return;
    }
    debugPrint(
      "[HomeScreen FETCH] Starting data fetch for user: ${_currentUser?.email}",
    );
    if (mounted) setState(() => _isLoading = true);

    try {
      final response = await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/api/getupdate'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'myemail': _currentUser!.email}),
          )
          .timeout(const Duration(seconds: 15));

      debugPrint(
        "[HomeScreen FETCH] API response status: ${response.statusCode}",
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> messages = data['message'] ?? [];

        // Process chats (fetching profile URL from user data)
        final Map<String, Map<String, dynamic>> userChats = {};

        for (var msgData in messages) {
          if (msgData is Map<String, dynamic>) {
            final String? email = msgData['email'];
            final String? rawTimeString = msgData['time']?.toString();
            if (email != null && email != _currentUser!.email) {
              // Look up user details (implement a user service or fetch directly)
              // For now, assume msgData contains necessary details if backend provides them
              userChats[email] = {
                'name': msgData['name'] ?? 'Unknown',
                'email': email,
                'profileUrl':
                    msgData['profileUrl'], // **Use profileUrl from response**
                'message': msgData['message'] ?? '',
                'time': _formatTime(rawTimeString),
                'rawTime': rawTimeString,
              };
            }
          }
        }

        // TODO: If backend doesn't send profileUrl in /getupdate message list,
        // you would need to fetch user details separately based on email here.

        // Process Groups
        final List<Map<String, dynamic>> groupsData =
            (data['groups'] as List<dynamic>? ?? []).map((group) {
              return {
                'name': group['name'],
                'id': group['groupId'],
                'members': '${group['memberCount'] ?? 'Unknown'} members',
                'lastActive': group['lastActive'] ?? 'Unknown',
                'groupProfileUrl': group['groupProfileUrl'],
                // invitationStatus: 'member' | 'pending' | 'rejected'
                'invitationStatus': group['invitationStatus'] ?? 'member',
              };
            }).toList();

        if (mounted) {
          setState(() {
            _chats = userChats.values.toList();
            _groups = groupsData;
            _sortChats();
            _isLoading = false;
            debugPrint("[HomeScreen FETCH] Processed chats/groups for UI");
          });
        }
      } else {
        debugPrint(
          '[HomeScreen FETCH] Error fetching data: Status code ${response.statusCode}',
        );
        if (mounted) setState(() => _isLoading = false);
        // Show error message?
      }
    } catch (e) {
      debugPrint('[HomeScreen FETCH] Error fetching data: $e');
      if (!mounted) return;
      setState(() => _isLoading = false);
      // Show error message?
    }
  }

  void _subscribeToMessages() {
    _messageSubscription?.cancel();
    debugPrint("[HomeScreen] Subscribing to messages...");
    _messageSubscription = _socketService.onMessageReceived.listen((
      messageData,
    ) {
      debugPrint(
        "[HomeScreen LISTENER] Received message via stream: $messageData",
      );
      if (!mounted || _currentUser == null) {
        debugPrint(
          "[HomeScreen LISTENER] Not mounted or user null, ignoring message.",
        );
        return;
      }

      final senderEmail = messageData['senderEmail'] as String?;
      final receiverEmail = messageData['receiverEmail'] as String?;
      final messageText = messageData['text'] as String? ?? '';
      final messageTime = messageData['time'] as String?;
      final senderName = messageData['senderName'] as String?;
      final senderProfileUrl =
          messageData['senderProfileUrl']
              as String?; // **Assume backend sends this**

      String? chatPartnerEmail;
      String? chatPartnerName;
      String? chatPartnerProfileUrl;

      if (senderEmail == _currentUser!.email) {
        // Message I sent - update the chat corresponding to the receiver
        chatPartnerEmail = receiverEmail;
        // We might not get receiver details in this payload, so fetch if needed or use existing
        final existingChat = _chats.firstWhere(
          (c) => c['email'] == chatPartnerEmail,
          orElse: () => {},
        );
        chatPartnerName = existingChat['name'];
        chatPartnerProfileUrl = existingChat['profileUrl'];
        debugPrint(
          "[HomeScreen LISTENER] Updated message I sent to $chatPartnerEmail",
        );
      } else if (receiverEmail == _currentUser!.email) {
        // Message I received - update the chat corresponding to the sender
        chatPartnerEmail = senderEmail;
        chatPartnerName = senderName;
        chatPartnerProfileUrl = senderProfileUrl;
        debugPrint(
          "[HomeScreen LISTENER] Message received from $chatPartnerEmail ($chatPartnerName)",
        );
      } else {
        debugPrint(
          "[HomeScreen LISTENER] Message not relevant (Sender: $senderEmail, Receiver: $receiverEmail, Me: ${_currentUser!.email})",
        );
        return;
      }

      if (chatPartnerEmail != null) {
        debugPrint(
          "[HomeScreen LISTENER] Updating chat list for partner: $chatPartnerEmail",
        );
        if (mounted) {
          setState(() {
            final chatIndex = _chats.indexWhere(
              (chat) => chat['email'] == chatPartnerEmail,
            );

            Map<String, dynamic> updatedChatData = {
              'email': chatPartnerEmail,
              'name': chatPartnerName ?? 'Unknown',
              'profileUrl':
                  chatPartnerProfileUrl, // Use the profile URL from stream/existing
              'message': messageText,
              'time': _formatTime(messageTime),
              'rawTime': messageTime,
            };

            if (chatIndex != -1) {
              _chats[chatIndex] = updatedChatData;
            } else {
              // Only add if it was a message received, not one I sent
              if (receiverEmail == _currentUser!.email) {
                _chats.add(updatedChatData);
              }
            }
            _sortChats();
          });
        }
      }
    });
    debugPrint("[HomeScreen] Message subscription setup complete.");
  }

  String _formatTime(String? timeString) {
    if (timeString == null) {
      return '';
    }
    try {
      final DateTime utcTime = DateTime.parse(timeString);
      final DateTime localTime = utcTime.toLocal();
      final DateTime now = DateTime.now();
      final Duration difference = now.difference(localTime);
      if (difference.inDays == 0 && localTime.day == now.day) {
        int hour = localTime.hour;
        final String minute = localTime.minute.toString().padLeft(2, '0');
        final String period = hour < 12 ? 'AM' : 'PM';
        if (hour == 0) {
          hour = 12;
        } else if (hour > 12) {
          hour -= 12;
        }
        return '$hour:$minute $period';
      } else if (difference.inDays == 1 ||
          (difference.inDays == 0 && localTime.day == now.day - 1)) {
        return 'Yesterday';
      } else {
        final String day = localTime.day.toString().padLeft(2, '0');
        final String month = localTime.month.toString().padLeft(2, '0');
        final String year = localTime.year.toString();
        return '$day/$month/$year';
      }
    } catch (e) {
      debugPrint("Error formatting time '$timeString': $e");
      return '';
    }
  }

  void _sortChats() {
    _chats.sort((a, b) {
      final String? rawTimeA = a['rawTime'];
      final String? rawTimeB = b['rawTime'];
      try {
        DateTime? timeA = rawTimeA != null ? DateTime.parse(rawTimeA) : null;
        DateTime? timeB = rawTimeB != null ? DateTime.parse(rawTimeB) : null;
        if (timeA == null && timeB == null) {
          return 0;
        }
        if (timeA == null) {
          return 1; // Treat nulls as older
        }
        if (timeB == null) {
          return -1; // Treat nulls as older
        }
        return timeB.compareTo(timeA); // Sort descending (newest first)
      } catch (e) {
        debugPrint("Error parsing time during sort: $e");
        return 0;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Get current user's profile URL for the AppBar
    final currentUserProfileUrl = _currentUser?.profileUrl;
    final hasCurrentUserProfileUrl =
        currentUserProfileUrl != null && currentUserProfileUrl.isNotEmpty;

    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: _buildAppBar(hasCurrentUserProfileUrl, currentUserProfileUrl),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              onChanged:
                  (value) => setState(() => _searchQuery = value.toLowerCase()),
              decoration: InputDecoration(
                hintText: 'Search chats or groups...',
                prefixIcon: Icon(Icons.search, color: _primaryColor),
                filled: true,
                fillColor: Colors.grey[100],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 0,
                  horizontal: 20,
                ),
              ),
            ),
          ),
          // Main Content
          Expanded(
            child:
                _isLoading
                    ? Center(
                      child: CircularProgressIndicator(color: _primaryColor),
                    )
                    : IndexedStack(
                      index: _currentIndex,
                      children: [_buildChatList(), _buildGroupList()],
                    ),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomNavBar(),
    );
  }

  PreferredSizeWidget _buildAppBar(
    bool hasCurrentUserProfileUrl,
    String? currentUserProfileUrl,
  ) {
    return AppBar(
      flexibleSpace: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [_primaryColor, _secondaryColor],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
        ),
      ),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Image.asset(
            'assets/logo.png',
            height: 100,
            width: 150,
            color: Colors.white,
          ),
          IconButton(
            icon: CircleAvatar(
              radius: 18,
              backgroundColor: Colors.white.withAlpha(50),
              backgroundImage:
                  hasCurrentUserProfileUrl
                      ? CachedNetworkImageProvider(currentUserProfileUrl!)
                      : null,
              child:
                  !hasCurrentUserProfileUrl
                      ? const Icon(Icons.person, size: 22, color: Colors.white)
                      : null,
            ),
            onPressed: () async {
              // Fetch user fresh before navigating
              final user = await DBHelper().getUser();
              // Check mounted AFTER await and before using context
              if (user != null && mounted) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder:
                        (_) => SettingScreen(
                          currentUser: user,
                          onLogout: widget.onLogout,
                        ),
                  ),
                ).then((_) {
                  _loadUserData();
                });
              } else if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Could not load user data.")),
                );
              }
            },
          ),
        ],
      ),
      centerTitle: false,
      elevation: 4,
    );
  }

  Widget _buildChatList() {
    // Filter chats based on search query
    final filteredChats =
        _searchQuery.isEmpty
            ? _chats
            : _chats.where((chat) {
              final name = chat['name']?.toString().toLowerCase() ?? '';
              final message = chat['message']?.toString().toLowerCase() ?? '';
              return name.contains(_searchQuery) ||
                  message.contains(_searchQuery);
            }).toList();

    return Stack(
      key: const ValueKey('chat_list_stack'),
      children: [
        filteredChats.isEmpty
            ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.chat_bubble_outline,
                    size: 70,
                    color: Colors.grey[300],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No chats yet',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Start chatting with people',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                ],
              ),
            )
            : ListView.separated(
              padding: const EdgeInsets.only(top: 8, bottom: 80),
              itemCount: filteredChats.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final chat = filteredChats[index];
                final profileUrl = chat['profileUrl'] as String?;
                final hasProfileUrl =
                    profileUrl != null && profileUrl.isNotEmpty;

                return ListTile(
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
                    chat['name'] ?? 'Unknown',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  subtitle: Text(
                    chat['message'] ?? '',
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Text(
                    chat['time'] ?? '',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                  onTap: () {
                    // Check mounted before using context
                    if (mounted) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder:
                              (_) => ChatScreen(
                                userName: chat['name'] ?? 'Unknown',
                                userIndex: index,
                                userEmail: chat['email'],
                                profileUrl: profileUrl,
                              ),
                        ),
                      ).then((_) => _fetchData());
                    }
                  },
                );
              },
            ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton(
            heroTag: 'fab_chat',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SearchUserScreen()),
              ).then((refreshNeeded) {
                if (refreshNeeded == true) {
                  _fetchData();
                }
              });
            },
            backgroundColor: _primaryColor,
            child: const Icon(Icons.chat, color: Colors.white),
          ),
        ),
      ],
    );
  }

  Widget _buildGroupList() {
    // Filter groups based on search query
    final filteredGroups =
        _searchQuery.isEmpty
            ? _groups
            : _groups.where((group) {
              final name = group['name']?.toString().toLowerCase() ?? '';
              return name.contains(_searchQuery);
            }).toList();

    // ---- DEBUG PRINT ----
    debugPrint("[HomeScreen BUILD GroupList] _groups count: ${_groups.length}");
    debugPrint(
      "[HomeScreen BUILD GroupList] filteredGroups count: ${filteredGroups.length}",
    );
    if (filteredGroups.isNotEmpty) {
      debugPrint(
        "[HomeScreen BUILD GroupList] First filtered group: ${filteredGroups.first}",
      );
    }
    // ---- END DEBUG ----

    return Stack(
      key: const ValueKey('group_list_stack'),
      children: [
        filteredGroups.isEmpty
            ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.group_outlined, size: 70, color: Colors.grey[300]),
                  const SizedBox(height: 16),
                  const Text(
                    'No groups yet',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Create or join a group to chat',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                ],
              ),
            )
            : ListView.separated(
              padding: const EdgeInsets.only(top: 8, bottom: 80),
              itemCount: filteredGroups.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final group = filteredGroups[index];
                final status = group['invitationStatus'] as String? ?? 'member';
                final groupProfileUrl = group['groupProfileUrl'] as String?;
                final hasGroupProfileUrl =
                    groupProfileUrl != null && groupProfileUrl.isNotEmpty;
                // Decide subtitle, trailing, and tap behavior
                Widget subtitleWidget;
                Widget trailingWidget;
                GestureTapCallback? onTapAction;
                if (status == 'pending') {
                  // Pending invitation: show label + members, and tick/cross icons
                  subtitleWidget = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Group Invitation',
                        style: TextStyle(
                          color: Colors.orange[700],
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        group['members'] ?? '',
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                    ],
                  );
                  trailingWidget = Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(
                          Icons.check_circle,
                          color: Colors.green[700],
                        ),
                        tooltip: 'Accept Invitation',
                        onPressed:
                            () => _respondInvitation(group['id'], 'accept'),
                      ),
                      IconButton(
                        icon: Icon(Icons.cancel, color: Colors.red[700]),
                        tooltip: 'Reject Invitation',
                        onPressed:
                            () => _respondInvitation(group['id'], 'reject'),
                      ),
                    ],
                  );
                  onTapAction = null;
                } else if (status == 'rejected') {
                  // Rejected invitation: label + members
                  subtitleWidget = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Invitation Rejected',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                      Text(
                        group['members'] ?? '',
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                    ],
                  );
                  trailingWidget = SizedBox.shrink();
                  onTapAction = null;
                } else {
                  // Regular joined group
                  subtitleWidget = Text(
                    group['members'] ?? '',
                    style: TextStyle(color: Colors.grey[600]),
                  );
                  trailingWidget = Text(
                    group['lastActive'] ?? '',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  );
                  onTapAction = () {
                    if (mounted) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder:
                              (_) => GroupChatScreen(
                                groupName: group['name'] ?? 'Unknown',
                                members: group['members'] ?? '',
                                groupIndex: index,
                                groupId: group['id'],
                              ),
                        ),
                      ).then((_) => _fetchData());
                    }
                  };
                }
                return ListTile(
                  leading: CircleAvatar(
                    radius: 24,
                    backgroundColor: _getUserColor(index + _chats.length),
                    backgroundImage:
                        hasGroupProfileUrl
                            ? CachedNetworkImageProvider(groupProfileUrl!)
                            : null,
                    child:
                        !hasGroupProfileUrl
                            ? const Icon(
                              Icons.group,
                              color: Colors.white,
                              size: 24,
                            )
                            : null,
                  ),
                  title: Text(
                    group['name'] ?? 'Unknown',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  subtitle: subtitleWidget,
                  trailing: trailingWidget,
                  onTap: onTapAction,
                );
              },
            ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton(
            heroTag: 'fab_group',
            onPressed: () {
              // Check mounted before using context
              if (mounted) {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CreateGroupScreen()),
                ).then((refreshNeeded) {
                  if (refreshNeeded == true) {
                    _fetchData();
                  }
                });
              }
            },
            backgroundColor: _primaryColor,
            child: const Icon(Icons.add, color: Colors.white),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomNavBar() {
    return Container(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withAlpha(51),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) {
            setState(() => _currentIndex = index);
            _tabController.animateTo(index);
          },
          backgroundColor: Colors.white,
          selectedItemColor: _primaryColor,
          unselectedItemColor: Colors.grey,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
          type: BottomNavigationBarType.fixed,
          items: [
            BottomNavigationBarItem(
              icon: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color:
                      _currentIndex == 0
                          ? _primaryColor.withAlpha(51)
                          : Colors.transparent,
                ),
                child: const Icon(Icons.chat_bubble_outline),
              ),
              label: 'Chats',
            ),
            BottomNavigationBarItem(
              icon: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color:
                      _currentIndex == 1
                          ? _primaryColor.withAlpha(51)
                          : Colors.transparent,
                ),
                child: const Icon(Icons.group_outlined),
              ),
              label: 'Groups',
            ),
          ],
        ),
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

  Future<void> _respondInvitation(String groupId, String action) async {
    if (_currentUser == null) return;
    setState(() => _isLoading = true);
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/groups/$groupId/respond'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'userId': _currentUser!.id.toString(),
          'action': action,
        }),
      );
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Invitation ${action}ed successfully')),
        );
      } else {
        final err = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to ${action} invitation: ${err['error'] ?? response.statusCode}',
            ),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      await _fetchData();
      if (mounted) setState(() => _isLoading = false);
    }
  }
}
