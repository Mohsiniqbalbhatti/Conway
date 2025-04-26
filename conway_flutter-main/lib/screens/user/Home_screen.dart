import 'package:flutter/material.dart';
import 'package:conway/helpers/auth_guard.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import './settings_screen.dart';
import './chat_screen.dart';
import './group_chat_screen.dart';
import './Search_user_screen.dart';
import './Create_group_screen.dart';
import '../../models/user.dart';
import '../../helpers/database_helper.dart';
import '../../constants/api_config.dart';
import '../../services/socket_service.dart';
import 'dart:async';

class HomeScreen extends StatefulWidget {
  final VoidCallback? onLogout;

  const HomeScreen({Key? key, this.onLogout}) : super(key: key);

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _currentIndex = 0;
  final PageController _pageController = PageController();

  // Color scheme
  final Color _primaryColor = const Color(0xFF19BFB7);
  final Color _secondaryColor = const Color(0xFF59A52C);
  final Color _backgroundColor = Colors.white;

  // Data
  List<Map<String, dynamic>> _chats = [];
  List<Map<String, dynamic>> _groups = [];
  bool _isLoading = true;
  User? _currentUser;
  String _searchQuery = '';

  final SocketService _socketService = SocketService();
  StreamSubscription? _messageSubscription;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _checkAuth();
    _loadUserData().then((_) {
      if (mounted && _currentUser != null) {
         print("[HomeScreen] User loaded: ${_currentUser!.email} (ID: ${_currentUser!.id})");
         // Ensure socket is connected *before* subscribing
         _socketService.connect(_currentUser!.id.toString());
         print("[HomeScreen] Socket connect initiated.");
         // Now fetch initial data and subscribe
         _fetchData();
         _subscribeToMessages();
      } else if (mounted) {
         print("[HomeScreen] User not loaded after trying.");
         // Handle error? Maybe show a message?
         setState(() => _isLoading = false); // Stop loading indicator
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _pageController.dispose();
    _messageSubscription?.cancel();
    super.dispose();
  }

  Future<void> _checkAuth() async {
    await AuthGuard.isAuthenticated(context);
  }

  Future<void> _loadUserData() async {
    final user = await DBHelper().getUser();
    if (mounted) {
      _currentUser = user;
    }
  }

  Future<void> _fetchData() async {
    if (_currentUser == null) {
       print("[HomeScreen FETCH] User not loaded yet, skipping fetch.");
       return;
    }
    print("[HomeScreen FETCH] Starting data fetch for user: ${_currentUser?.email}");
    setState(() => _isLoading = true);

    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/getupdate'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'myemail': _currentUser!.email}),
      ).timeout(const Duration(seconds: 15));

      print("[HomeScreen FETCH] API response status: ${response.statusCode}");

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> messages = data['message'] ?? [];

        setState(() {
            final Map<String, Map<String, dynamic>> userChats = {};
            for (var msgData in messages) {
              if (msgData is Map<String, dynamic>) {
                final String? email = msgData['email'];
                final String? rawTimeString = msgData['time']?.toString();
                if (email != null && email != _currentUser!.email) {
                  userChats[email] = {
                    'name': msgData['name'] ?? 'Unknown',
                    'email': email,
                    'message': msgData['message'] ?? '',
                    'time': _formatTime(rawTimeString),
                    'rawTime': rawTimeString,
                  };
                }
              }
            }
            _chats = userChats.values.toList();

            // Process Groups
             _groups = (data['groups'] as List<dynamic>? ?? []).map((group) {
               return {
                 'name': group['name'],
                 'id': group['groupId'],
                 'members': '${group['memberCount'] ?? 'Unknown'} members',
                 'lastActive': group['lastActive'] ?? 'Unknown',
               };
             }).toList();

            _sortChats();
            _isLoading = false;
            print("[HomeScreen FETCH] Processed chats/groups for UI");
        });
      } else {
        print('[HomeScreen FETCH] Error fetching data: Status code ${response.statusCode}');
         setState(() => _isLoading = false);
      }
    } catch (e) {
       print('[HomeScreen FETCH] Error fetching data: $e');
       if (!mounted) return;
       setState(() => _isLoading = false);
    }
  }

  void _subscribeToMessages() {
     _messageSubscription?.cancel();
     print("[HomeScreen] Subscribing to messages...");
     _messageSubscription = _socketService.onMessageReceived.listen((messageData) {
         print("[HomeScreen LISTENER] Received message via stream: $messageData");
         if (!mounted || _currentUser == null) {
             print("[HomeScreen LISTENER] Not mounted or user null, ignoring message.");
             return;
         }

         final senderEmail = messageData['senderEmail'] as String?;
         final receiverEmail = messageData['receiverEmail'] as String?;
         final messageText = messageData['text'] as String? ?? '';
         final messageTime = messageData['time'] as String?;
         final senderName = messageData['senderName'] as String?;

         String? chatPartnerEmail;
         String? chatPartnerName;

         if (senderEmail == _currentUser!.email) {
             chatPartnerEmail = receiverEmail;
             chatPartnerName = null;
              print("[HomeScreen LISTENER] Ignored message I sent to $chatPartnerEmail");
             return;
         } else if (receiverEmail == _currentUser!.email) {
             chatPartnerEmail = senderEmail;
             chatPartnerName = senderName;
             print("[HomeScreen LISTENER] Message received from $chatPartnerEmail ($chatPartnerName)");
         } else {
              print("[HomeScreen LISTENER] Message not relevant (Sender: $senderEmail, Receiver: $receiverEmail, Me: ${_currentUser!.email})");
              return;
         }


         if (chatPartnerEmail != null) {
             print("[HomeScreen LISTENER] Updating chat list for partner: $chatPartnerEmail");
             final List<Map<String, dynamic>> chatsBeforeUpdate = List.from(_chats);
             print("[HomeScreen LISTENER] _chats list BEFORE update (${chatsBeforeUpdate.length} items): $chatsBeforeUpdate");

             setState(() {
               print("[HomeScreen LISTENER] Inside setState...");
               final chatIndex = _chats.indexWhere((chat) => chat['email'] == chatPartnerEmail);
               print("[HomeScreen LISTENER] Found chat index: $chatIndex");

               Map<String, dynamic> updatedChatData = {
                   'email': chatPartnerEmail,
                   'name': 'Unknown',
                   'message': messageText,
                   'time': _formatTime(messageTime),
                   'rawTime': messageTime,
               };

               if (chatIndex != -1) {
                   updatedChatData['name'] = _chats[chatIndex]['name'];
                   _chats[chatIndex] = updatedChatData;
                   print("[HomeScreen LISTENER] Updated _chats[$chatIndex] with: $updatedChatData");
               } else {
                   updatedChatData['name'] = chatPartnerName ?? 'New Chat';
                   _chats.add(updatedChatData);
                   print("[HomeScreen LISTENER] Added new entry to _chats: $updatedChatData");
               }

               print("[HomeScreen LISTENER] _chats list BEFORE sort (${_chats.length} items): $_chats");
               _sortChats();
               print("[HomeScreen LISTENER] _chats list AFTER sort (${_chats.length} items): $_chats");
               print("[HomeScreen LISTENER] ...exiting setState.");
             });
         }
     });
      print("[HomeScreen] Message subscription setup complete.");
  }

  String _formatTime(String? timeString) {
    if (timeString == null) return '';

    try {
      // Parse the ISO 8601 string (likely UTC from server)
      final DateTime utcTime = DateTime.parse(timeString);
      // Convert to local time zone
      final DateTime localTime = utcTime.toLocal();

      final DateTime now = DateTime.now();
      final Duration difference = now.difference(localTime);

      // Format based on how recent it is
      if (difference.inDays == 0 && localTime.day == now.day) {
        // Today: Format as 12-hour time (e.g., 5:53 PM)
        int hour = localTime.hour;
        final String minute = localTime.minute.toString().padLeft(2, '0');
        final String period = hour < 12 ? 'AM' : 'PM';
        if (hour == 0) { // Handle midnight
          hour = 12;
        } else if (hour > 12) {
          hour -= 12;
        }
        return '$hour:$minute $period';
      } else if (difference.inDays == 1 || (difference.inDays == 0 && localTime.day == now.day - 1)) {
        // Yesterday
        return 'Yesterday';
      } else {
        // Older: Format as date (e.g., 25/04/2025)
        final String day = localTime.day.toString().padLeft(2, '0');
        final String month = localTime.month.toString().padLeft(2, '0');
        final String year = localTime.year.toString();
        return '$day/$month/$year';
      }
    } catch (e) {
      print("Error formatting time '$timeString': $e");
      return ''; // Return empty or original string on error
    }
  }

  void _sortChats() {
       _chats.sort((a, b) {
            final String? rawTimeA = a['rawTime'];
            final String? rawTimeB = b['rawTime'];
            try {
              DateTime? timeA = rawTimeA != null ? DateTime.parse(rawTimeA) : null;
              DateTime? timeB = rawTimeB != null ? DateTime.parse(rawTimeB) : null;
              if (timeA == null && timeB == null) return 0;
              if (timeA == null) return 1; 
              if (timeB == null) return -1;
              return timeB.compareTo(timeA); // Sort descending
            } catch (e) {
                 print("Error parsing time during sort: $e");
                 return 0; // Keep original order on error
            }
       });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              readOnly: true,
              onTap: () {
                if (_currentIndex == 0) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SearchUserScreen()),
                  ).then((refreshNeeded) {
                    if (refreshNeeded == true) {
                      _fetchData();
                    }
                  });
                } else {
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
              decoration: InputDecoration(
                hintText: 'Search...',
                prefixIcon: Icon(Icons.search, color: _primaryColor),
                filled: true,
                fillColor: Colors.grey[100],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 20),
              ),
            ),
          ),
          // Main Content
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator(color: _primaryColor))
                : PageView(
                    controller: _pageController,
                    onPageChanged: (index) {
                      setState(() => _currentIndex = index);
                      _tabController.animateTo(index);
                    },
                    children: [
                      _buildChatList(),
                      _buildGroupList(),
                    ],
                  ),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomNavBar(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
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
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: const Icon(Icons.person, color: Colors.white),
            ),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => SettingScreen(onLogout: widget.onLogout)),
            ),
          ),
        ],
      ),
      centerTitle: false,
      elevation: 4,
    );
  }

  Widget _buildChatList() {
    // Filter chats based on search query
    final filteredChats = _searchQuery.isEmpty
        ? _chats
        : _chats.where((chat) =>
            chat['name'].toString().toLowerCase().contains(_searchQuery) ||
            chat['message'].toString().toLowerCase().contains(_searchQuery)).toList();
    
    return Stack(
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
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.only(top: 8, bottom: 80), // Add padding at bottom for FAB
                itemCount: filteredChats.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final chat = filteredChats[index];
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
                      chat['name'] ?? 'Unknown',
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    subtitle: Text(
                      chat['message'] ?? '',
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Text(
                      chat['time'] ?? '',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChatScreen(
                            userName: chat['name'] ?? 'Unknown',
                            userIndex: index,
                            userEmail: chat['email'],
                          ),
                        ),
                      ).then((_) => _fetchData());
                    },
                  );
                },
              ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton(
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
    final filteredGroups = _searchQuery.isEmpty
        ? _groups
        : _groups.where((group) =>
            group['name'].toString().toLowerCase().contains(_searchQuery)).toList();
    
    return Stack(
      children: [
        filteredGroups.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.group_outlined,
                      size: 70,
                      color: Colors.grey[300],
                    ),
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
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                      ),
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
                  return ListTile(
                    leading: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: _getUserColor(index),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.group,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    title: Text(
                      group['name'] ?? 'Unknown',
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    subtitle: Text(group['members'] ?? ''),
                    trailing: Text(
                      group['lastActive'] ?? '',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => GroupChatScreen(
                            groupName: group['name'] ?? 'Unknown',
                            members: group['members'] ?? '',
                            groupIndex: index,
                            groupId: group['id'],
                          ),
                        ),
                      ).then((_) => _fetchData());
                    },
                  );
                },
              ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CreateGroupScreen()),
              ).then((refreshNeeded) {
                if (refreshNeeded == true) {
                  _fetchData();
                }
              });
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
            color: Colors.grey.withOpacity(0.2),
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
            _pageController.animateToPage(
              index,
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeInOut,
            );
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
                  color: _currentIndex == 0
                      ? _primaryColor.withOpacity(0.2)
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
                  color: _currentIndex == 1
                      ? _primaryColor.withOpacity(0.2)
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
}