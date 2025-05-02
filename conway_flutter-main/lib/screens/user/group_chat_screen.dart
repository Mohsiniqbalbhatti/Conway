import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import '../../models/user.dart';
import '../../helpers/database_helper.dart';
import '../../constants/api_config.dart';
import 'group_settings_screen.dart'; // Import the new settings screen
import '../../services/socket_service.dart'; // Import SocketService
import 'dart:async'; // Import async
// Added for member avatars later

class GroupChatScreen extends StatefulWidget {
  final String groupName;
  final String members;
  final int groupIndex;
  final String groupId;

  const GroupChatScreen({
    super.key,
    required this.groupName,
    required this.members,
    required this.groupIndex,
    required this.groupId,
  });

  @override
  _GroupChatScreenState createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final Color _primaryColor = const Color(0xFF19BFB7);
  final Color _secondaryColor = const Color(0xFF59A52C);

  List<Map<String, dynamic>> _messages = []; // Use this for real messages
  bool _isLoading = true; // Start as loading
  bool _isFetchingDetails = true; // Separate loading state for group details
  User? _currentUser;
  String? _creatorId; // To store the group creator's ID
  bool _isAdmin = false; // Flag for admin status

  // Socket Service and Subscriptions
  final SocketService _socketService = SocketService();
  StreamSubscription? _groupMessageSubscription;
  StreamSubscription? _groupMessageSentSubscription;
  StreamSubscription? _groupMessageExpiredSubscription; // NEW: For expiry
  StreamSubscription? _groupMessageDeletedSubscription; // NEW: For deletion

  // NEW: State for Burnout/Schedule
  DateTime? _scheduledTime;
  DateTime? _burnoutTime;

  void _scrollToBottom({bool animate = true}) {
    // Added animate parameter
    if (_scrollController.hasClients) {
      final maxScroll = _scrollController.position.maxScrollExtent;
      if (animate) {
        _scrollController.animateTo(
          maxScroll,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(maxScroll);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _loadInitialData(); // Combine initial loading steps
  }

  Future<void> _loadInitialData() async {
    await _loadUserData();
    if (_currentUser != null) {
      // Connect socket first
      _socketService.connect(_currentUser!.id.toString());
      _setupSocketListeners();

      // Fetch group details and messages concurrently
      await Future.wait([
        _fetchGroupDetails(), // Fetch details to determine admin status
        _fetchGroupMessages(scrollToBottom: true), // Fetch initial messages
      ]);
    } else {
      // Handle error: user data not found
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error: Could not load user data.')),
        );
        setState(() {
          _isLoading = false;
          _isFetchingDetails = false;
        });
      }
    }
  }

  Future<void> _fetchGroupDetails() async {
    if (!mounted) return;
    setState(() => _isFetchingDetails = true);
    try {
      // Add this debug print:
      debugPrint(
        "[GroupChatScreen FetchDetails] Attempting to fetch details for groupId: ${widget.groupId}",
      );

      final response = await http
          .get(
            Uri.parse(
              '${ApiConfig.baseUrl}/api/groups/${widget.groupId}/details',
            ),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 15));

      if (mounted && response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // Add this debug print to see the raw data:
        debugPrint(
          "[GroupChatScreen FetchDetails] Received data from API: $data",
        );

        setState(() {
          _creatorId = data['creatorId'] as String?;
          _isAdmin = (_currentUser != null && _currentUser!.id == _creatorId);
          _isFetchingDetails = false;
          debugPrint(
            "[GroupChatScreen FetchDetails] Parsed Details. Admin: $_isAdmin (Creator: $_creatorId, Current: ${_currentUser?.id})",
          );
        });
      } else if (mounted) {
        debugPrint(
          "[GroupChatScreen] Error fetching group details: ${response.statusCode}",
        );
        setState(() => _isFetchingDetails = false);
        // Optionally show error
      }
    } catch (e) {
      if (mounted) {
        debugPrint(
          "[GroupChatScreen] Network error fetching group details: $e",
        );
        setState(() => _isFetchingDetails = false);
        // Optionally show error
      }
    }
  }

  void _setupSocketListeners() {
    debugPrint("[GroupChatScreen] Setting up socket listeners...");
    _groupMessageSubscription = _socketService.onGroupMessageReceived.listen((
      messageData,
    ) {
      debugPrint(
        "[GroupChatScreen RECEIVE] Raw group message data: $messageData",
      );
      _handleReceivedGroupMessage(messageData);
    });

    _groupMessageSentSubscription = _socketService.onGroupMessageSent.listen((
      sentData,
    ) {
      debugPrint(
        "[GroupChatScreen SENT CONFIRM] Received confirmation: $sentData",
      );
      _handleGroupMessageSentConfirmation(sentData);
    });

    // NEW: Expiry Listener
    _groupMessageExpiredSubscription = _socketService.onGroupMessageExpired
        .listen((expiryData) {
          debugPrint(
            "[GroupChatScreen EXPIRE] Received group expiry data: $expiryData",
          );
          _handleGroupMessageExpiry(expiryData);
        });

    // NEW: Deletion Listener
    _groupMessageDeletedSubscription = _socketService.onGroupMessageDeleted
        .listen((deletedData) {
          debugPrint(
            "[GroupChatScreen DELETE EVENT] Received deletion event: $deletedData",
          );
          _handleGroupMessageDeleted(deletedData);
        });
  }

  void _handleReceivedGroupMessage(Map<String, dynamic> messageData) {
    // Check if the message belongs to the current group
    if (messageData['groupId'] != widget.groupId) {
      debugPrint(
        "[GroupChatScreen RECEIVE] Message for different group (${messageData['groupId']}). Ignoring.",
      );
      return;
    }

    final messageId = messageData['id'];
    // Avoid duplicates
    if (_messages.any((msg) => msg['id'] == messageId)) {
      debugPrint(
        "[GroupChatScreen RECEIVE] Group message ID $messageId already exists. Ignoring.",
      );
      return;
    }

    // Parse burnout/schedule info
    final bool isBurnout = messageData['isBurnout'] as bool? ?? false;
    final String? expireAtStr = messageData['expireAt'] as String?;
    final bool isScheduled = messageData['isScheduled'] as bool? ?? false;
    final String? scheduledAtStr = messageData['scheduledAt'] as String?;
    DateTime? expireAt =
        expireAtStr != null ? DateTime.tryParse(expireAtStr)?.toLocal() : null;

    // Check if message is already deleted or expired on arrival
    final bool isDeleted = messageData['deleted_at'] != null;
    final bool isExpired =
        isBurnout && expireAt != null && expireAt.isBefore(DateTime.now());

    if (isDeleted || isExpired) {
      debugPrint(
        "[GroupChatScreen RECEIVE] Message $messageId arrived deleted or expired. Ignoring display.",
      );
      return; // Don't add if already deleted/expired
    }

    // Construct the message object for UI
    final newMessage = {
      'id': messageId,
      'senderId': messageData['senderId'],
      'senderName': messageData['senderName'] ?? 'Unknown Sender',
      'text': messageData['text'] ?? '',
      'time': messageData['time'],
      'isMe': messageData['senderId'] == _currentUser?.id.toString(),
      // Store burnout/schedule info
      'isBurnout': isBurnout,
      'expireAt': expireAtStr,
      'isScheduled': isScheduled,
      'scheduledAt': scheduledAtStr,
      'deleted_at': null, // Assume not deleted initially
    };

    if (mounted) {
      setState(() {
        _messages.add(newMessage);
        _sortMessages(); // Ensure messages are sorted by time
      });
      // Scroll only if the user is near the bottom
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
  }

  void _handleGroupMessageSentConfirmation(Map<String, dynamic> sentData) {
    final tempId = sentData['tempId'] as String?;
    final dbId = sentData['dbId'] as String?;
    final serverTimeStr = sentData['time'] as String?;
    final groupId = sentData['groupId'] as String?;

    if (tempId == null || dbId == null || groupId != widget.groupId) {
      debugPrint(
        "[GroupChatScreen SENT CONFIRM] Invalid/irrelevant confirmation data.",
      );
      return;
    }

    if (mounted) {
      setState(() {
        final index = _messages.indexWhere((msg) => msg['id'] == tempId);
        if (index != -1) {
          debugPrint(
            "[GroupChatScreen SENT CONFIRM] Found optimistic message $tempId. Updating to ID $dbId.",
          );
          _messages[index]['id'] = dbId;
          _messages[index]['isOptimistic'] = false;
          if (serverTimeStr != null) {
            _messages[index]['time'] = serverTimeStr;
          }
          _messages[index]['failedToSend'] =
              false; // Ensure failed flag is removed
          _messages[index]['isScheduled'] = sentData['isScheduled'] ?? false;
          _messages[index]['scheduledAt'] = sentData['scheduledAt'];
          _messages[index]['isBurnout'] = sentData['isBurnout'] ?? false;
          _messages[index]['expireAt'] = sentData['expireAt'];
          _messages[index]['deleted_at'] =
              null; // Ensure deleted_at is null on confirmation
          _sortMessages();
        } else {
          debugPrint(
            "[GroupChatScreen SENT CONFIRM] Optimistic message $tempId not found.",
          );
        }
      });
    }
  }

  // NEW: Handle message expiry event
  void _handleGroupMessageExpiry(Map<String, dynamic> expiryData) {
    if (expiryData['groupId'] != widget.groupId) {
      return; // Ensure it's for this group
    }
    final messageId = expiryData['messageId'] as String?;
    if (messageId == null) return;

    if (mounted) {
      setState(() {
        final index = _messages.indexWhere((msg) => msg['id'] == messageId);
        if (index != -1) {
          // Don't visually remove for sender, just mark as expired
          // For receiver, mark it to be hidden by the builder
          if (!_messages[index]['isMe']) {
            debugPrint(
              "[GroupChatScreen EXPIRE] Hiding expired message $messageId for receiver.",
            );
            _messages[index]['visuallyExpired'] = true;
          } else {
            debugPrint(
              "[GroupChatScreen EXPIRE] Marking sent message $messageId as actually expired.",
            );
            _messages[index]['actuallyExpired'] =
                true; // Mark for potential visual change
          }
        } else {
          debugPrint(
            "[GroupChatScreen EXPIRE] Expired message $messageId not found in list.",
          );
        }
      });
    }
  }

  // --- NEW: Deletion Handler ---
  void _handleGroupMessageDeleted(Map<String, dynamic> deletedData) {
    final messageId = deletedData['messageId'] as String?;
    final receivedGroupId = deletedData['groupId'] as String?;

    debugPrint(
      "[GroupChatScreen DELETE EVENT] Received deletion event for message: $messageId in group: $receivedGroupId",
    );

    if (messageId == null || receivedGroupId != widget.groupId) {
      debugPrint(
        "[GroupChatScreen DELETE EVENT] Ignoring event (missing data or wrong group).",
      );
      return;
    }

    if (mounted) {
      // Find the index first
      final index = _messages.indexWhere((msg) => msg['id'] == messageId);

      if (index != -1) {
        debugPrint(
          "[GroupChatScreen DELETE EVENT] Marking message $messageId as deleted in UI.",
        );

        // Create a new list with the updated message map
        final updatedMessages = List<Map<String, dynamic>>.from(_messages);
        // Create a new map for the specific message, copying existing and adding deleted_at
        updatedMessages[index] = {
          ...updatedMessages[index], // Spread existing key-value pairs
          'deleted_at':
              DateTime.now().toUtc().toIso8601String(), // Add/update deleted_at
        };

        // Update the state with the new list
        setState(() {
          _messages = updatedMessages;
        });
      } else {
        debugPrint(
          "[GroupChatScreen DELETE EVENT] Message $messageId not found in local list.",
        );
      }
    }
  }

  Future<void> _loadUserData() async {
    final user = await DBHelper().getUser();
    // No setState here, it will be called in _loadInitialData
    _currentUser = user;
  }

  Future<void> _fetchGroupMessages({bool scrollToBottom = true}) async {
    if (!mounted) return;
    // Ensure current user data is available before fetching
    if (_currentUser == null) {
      debugPrint(
        "[Fetch Group] Current user data is null. Cannot fetch messages.",
      );
      setState(() => _isLoading = false);
      // Optionally show a user-facing error message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not load user data. Please restart.'),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final response = await http
          .get(
            // Add userId query parameter to the request URL
            Uri.parse(
              '${ApiConfig.baseUrl}/api/group-messages/${widget.groupId}?userId=${_currentUser!.id}',
            ),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> fetchedMessages = data['messages'] ?? [];
        debugPrint(
          "Fetched ${fetchedMessages.length} group messages from API for group ${widget.groupId}",
        );

        if (mounted) {
          setState(() {
            _messages =
                fetchedMessages
                    .where(
                      (msg) => msg['deleted_at'] == null,
                    ) // Filter out already deleted messages
                    .map((msg) {
                      return {
                        'id': msg['id'],
                        'senderId': msg['senderId'],
                        'senderName': msg['senderName'] ?? 'Unknown Sender',
                        'text': msg['text'] ?? '',
                        'time': msg['time'],
                        'isMe':
                            msg['senderId'] ==
                            _currentUser?.id
                                .toString(), // Recalculate isMe just in case
                        'isBurnout': msg['isBurnout'] ?? false,
                        'expireAt': msg['expireAt'],
                        'isScheduled': msg['isScheduled'] ?? false,
                        'scheduledAt': msg['scheduledAt'],
                        'deleted_at':
                            msg['deleted_at'], // Store deleted_at status
                      };
                    })
                    .cast<Map<String, dynamic>>() // Cast is enough now
                    .toList(); // Filter out nulls
            _isLoading = false;
            _sortMessages();
          });
        }
        if (scrollToBottom) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _scrollToBottom(animate: false), // Jump initially
          );
        }
      } else {
        debugPrint(
          'Error fetching group messages: ${response.statusCode} ${response.body}',
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error fetching messages: ${response.statusCode}'),
            ),
          );
          setState(() => _isLoading = false);
        }
      }
    } catch (e) {
      debugPrint('Error fetching group messages: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Network error fetching messages: ${e.toString()}'),
          ),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    // Cancel subscriptions
    _groupMessageSubscription?.cancel();
    _groupMessageSentSubscription?.cancel();
    _groupMessageExpiredSubscription?.cancel();
    _groupMessageDeletedSubscription?.cancel(); // NEW
    // Consider disconnecting socket if appropriate for app lifecycle
    // _socketService.disconnect();
    super.dispose();
  }

  // Send message using Socket.IO
  void _sendMessage() {
    final messageText = _messageController.text.trim();
    if (messageText.isEmpty || _currentUser == null) return;

    // Get schedule/burnout times from state
    final DateTime? scheduleTime = _scheduledTime;
    final DateTime? burnTime = _burnoutTime;

    // Clear state vars after getting values
    setState(() {
      _scheduledTime = null;
      _burnoutTime = null;
    });

    final tempId = 'optimistic_group_${DateTime.now().millisecondsSinceEpoch}';
    final optimisticMessage = {
      'id': tempId,
      'senderId': _currentUser!.id.toString(),
      'senderName': 'You',
      'text': messageText,
      'time': DateTime.now().toUtc().toIso8601String(),
      'isMe': true,
      'isOptimistic': true,
      // Add optimistic schedule/burnout info
      'isBurnout': burnTime != null,
      'expireAt': burnTime?.toUtc().toIso8601String(),
      'isScheduled': scheduleTime != null,
      'scheduledAt': scheduleTime?.toUtc().toIso8601String(),
      'deleted_at': null, // Optimistic messages are never deleted initially
    };

    setState(() {
      _messages.add(optimisticMessage);
      _messageController.clear();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    // Emit with potential schedule/burnout times
    _socketService.emit('sendMessage', {
      'senderId': _currentUser!.id.toString(),
      'groupId': widget.groupId,
      'messageText': messageText,
      'tempId': tempId,
      if (burnTime != null)
        'burnoutDateTime': burnTime.toUtc().toIso8601String(),
      if (scheduleTime != null)
        'scheduleDateTime': scheduleTime.toUtc().toIso8601String(),
    });
    debugPrint(
      "[GroupChatScreen SEND] Emitted sendMessage event for group ${widget.groupId}",
    );
  }

  void _sortMessages() {
    _messages.sort((a, b) {
      final timeA = DateTime.tryParse(a['time'] ?? '');
      final timeB = DateTime.tryParse(b['time'] ?? '');
      if (timeA != null && timeB != null) return timeA.compareTo(timeB);
      if (timeA == null && timeB == null) return 0;
      return timeA == null ? -1 : 1;
    });
  }

  String _formatTime(String? timeString) {
    if (timeString == null) return '';
    try {
      final DateTime utcTime = DateTime.parse(timeString);
      final DateTime localTime = utcTime.toLocal();
      return DateFormat.jm().format(localTime);
    } catch (e) {
      debugPrint("Error formatting time in GroupChatScreen '$timeString': $e");
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    // Use a loading flag that combines message loading and detail fetching
    final bool isOverallLoading = _isLoading || _isFetchingDetails;

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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (_currentUser != null) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder:
                      (context) => GroupSettingsScreen(
                        groupId: widget.groupId,
                        groupName: widget.groupName,
                        currentUserId: _currentUser!.id, // Pass current user ID
                      ),
                ),
              ).then((_) {
                // Optional: Refresh details if settings were changed
                // _fetchGroupDetails();
              });
            } else {
              // Handle case where user data isn't loaded yet
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('User data not loaded yet.')),
              );
            }
          },
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _getGroupColor(widget.groupIndex),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.group, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.groupName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    widget.members,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onPressed: () {
              // TODO: Maybe move settings access here?
            },
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(color: Colors.grey[100]),
        child: Column(
          children: [
            // REMOVE Group info banner (or make it functional later)
            // Container(...)

            // Chat messages
            Expanded(
              child:
                  isOverallLoading
                      ? Center(
                        child: CircularProgressIndicator(color: _primaryColor),
                      )
                      : _messages.isEmpty
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
                              'No messages in this group yet',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w500,
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Be the first to send a message!',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      )
                      : ListView.builder(
                        // Use _messages here
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 20,
                        ),
                        itemCount: _messages.length, // Use _messages.length
                        itemBuilder: (context, index) {
                          final message = _messages[index];
                          // Check if visually expired
                          if (message['visuallyExpired'] == true) {
                            return const SizedBox.shrink(); // Hide if expired for receiver
                          }
                          final isDeleted =
                              message['deleted_at'] != null; // Check if deleted
                          final isMe =
                              message['isMe'] ?? false; // Get isMe flag

                          // Use the actual sender name from the message data
                          final senderName = message['senderName'] ?? 'Unknown';

                          // Pass necessary data to _buildMessageBubble
                          return isDeleted
                              ? _buildDeletedMessagePlaceholder(message)
                              : _buildMessageBubble(
                                messageData: message,
                                showSender: _shouldShowSender(index),
                              );
                        },
                      ),
            ),

            // Input field and send button
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withAlpha(51),
                    spreadRadius: 1,
                    blurRadius: 5,
                    offset: const Offset(0, -1),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Column(
                // Wrap Row in Column
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Display Schedule/Burnout Info if set
                  if (_scheduledTime != null || _burnoutTime != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 12.0, bottom: 4.0),
                      child: Text(
                        _scheduledTime != null
                            ? 'Scheduled: ${_formatDateTimeUserFriendly(_scheduledTime)}'
                            : 'Expires: ${_formatDateTimeUserFriendly(_burnoutTime)}',
                        style: TextStyle(
                          color:
                              _scheduledTime != null
                                  ? Colors.blue[700]
                                  : Colors.orange[700],
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  // Input Row
                  Row(
                    children: [
                      // Burnout Icon Button (copy from ChatScreen)
                      IconButton(
                        icon: Icon(
                          _burnoutTime != null
                              ? Icons.local_fire_department
                              : Icons.local_fire_department_outlined,
                          color:
                              _burnoutTime != null
                                  ? Colors.orange[700]
                                  : Colors.grey[600],
                        ),
                        tooltip:
                            _burnoutTime == null
                                ? 'Set message expiry'
                                : 'Cancel expiry',
                        onPressed: _handleBurnoutTap,
                      ),
                      // Schedule Icon Button (copy from ChatScreen)
                      IconButton(
                        icon: Icon(
                          _scheduledTime != null
                              ? Icons.alarm_on
                              : Icons.schedule_outlined,
                          color:
                              _scheduledTime != null
                                  ? Colors.blue[700]
                                  : Colors.grey[600],
                        ),
                        tooltip:
                            _scheduledTime == null
                                ? 'Schedule message'
                                : 'Cancel schedule',
                        onPressed: _handleScheduleTap,
                      ),
                      Expanded(
                        child: TextField(
                          controller: _messageController,
                          decoration: InputDecoration(
                            hintText: 'Type a message...',
                            hintStyle: TextStyle(color: Colors.grey[400]),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(25),
                              borderSide: BorderSide.none,
                            ),
                            filled: true,
                            fillColor: Colors.grey[100],
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 10,
                            ),
                          ),
                          textCapitalization: TextCapitalization.sentences,
                          maxLines: null,
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: _sendMessage,
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [_primaryColor, _secondaryColor],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            ),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.send,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Check if we should show the sender name (show it for first message or when sender changes)
  bool _shouldShowSender(int index) {
    if (index == 0) return true;
    if (_messages.isEmpty || index >= _messages.length) {
      return false; // Bounds check
    }

    final currentSenderId = _messages[index]['senderId'];
    // Check previous message exists and has senderId
    if (index > 0 && _messages[index - 1].containsKey('senderId')) {
      final previousSenderId = _messages[index - 1]['senderId'];
      return currentSenderId != previousSenderId;
    }
    return true; // Show if previous message doesn't have senderId (shouldn't happen)
  }

  // Updated _buildMessageBubble to use real data and add optimistic/failed indicators
  Widget _buildMessageBubble({
    required Map<String, dynamic> messageData,
    required bool showSender,
  }) {
    final String sender = messageData['senderName'] ?? 'Unknown';
    final String message = messageData['text'] ?? '';
    final String time = _formatTime(messageData['time']);
    final bool isMe = messageData['isMe'] ?? false;
    final Color? senderColor = isMe ? null : _getUserColor(sender.hashCode);
    final bool isOptimistic = messageData['isOptimistic'] ?? false;
    final bool failedToSend = messageData['failedToSend'] ?? false;
    final bool isBurnout = messageData['isBurnout'] ?? false;
    final String? expireAtStr = messageData['expireAt'];
    final bool isScheduled = messageData['isScheduled'] ?? false;
    final String? scheduledAtStr = messageData['scheduledAt'];
    final bool actuallyExpired = messageData['actuallyExpired'] ?? false;
    final String messageId = messageData['id']; // Get message ID

    // Don't render if visually expired for receiver
    if (!isMe && (messageData['visuallyExpired'] == true)) {
      return const SizedBox.shrink();
    }

    final Color messageColor = isMe ? _primaryColor : Colors.white;
    final Color textColor = isMe ? Colors.white : Colors.black87;

    final bool isPendingSchedule =
        isMe &&
        isScheduled &&
        scheduledAtStr != null &&
        (DateTime.tryParse(scheduledAtStr)?.isAfter(DateTime.now()) ?? false);

    // Main bubble content
    Widget bubbleContent = Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.7,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
      decoration: BoxDecoration(
        color: messageColor,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: isMe ? const Radius.circular(18) : Radius.zero,
          bottomRight: isMe ? Radius.zero : const Radius.circular(18),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withAlpha(26),
            spreadRadius: 1,
            blurRadius: 1,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Text(message, style: TextStyle(color: textColor, fontSize: 16)),
          const SizedBox(height: 2),
          Row(
            // Time and status icons
            mainAxisSize: MainAxisSize.min,
            children: [
              // Schedule/Burnout Icons (existing logic)
              if (isPendingSchedule)
                Icon(
                  Icons.alarm,
                  size: 14,
                  color: isMe ? Colors.white70 : Colors.blue[700],
                ),
              if (isPendingSchedule) const SizedBox(width: 4),
              if (isBurnout)
                Icon(
                  Icons.local_fire_department,
                  size: 14,
                  color:
                      actuallyExpired
                          ? (isMe ? Colors.white54 : Colors.grey[500])
                          : (isMe ? Colors.white70 : Colors.orange[700]),
                ),
              if (isBurnout) const SizedBox(width: 4),
              Text(
                time,
                style: TextStyle(
                  color: isMe ? Colors.white70 : Colors.grey[600],
                  fontSize: 12,
                ),
              ),
              // Sent/Pending/Error Icons (existing logic)
              if (isMe && !isOptimistic && !failedToSend)
                Padding(
                  padding: const EdgeInsets.only(left: 4.0),
                  child: Icon(Icons.done_all, color: Colors.white70, size: 16),
                ),
              if (isMe && isOptimistic)
                Padding(
                  padding: const EdgeInsets.only(left: 4.0),
                  child: Icon(
                    Icons.access_time,
                    color: Colors.white70,
                    size: 16,
                  ),
                ),
              if (isMe && failedToSend)
                Padding(
                  padding: const EdgeInsets.only(left: 4.0),
                  child: Icon(
                    Icons.error_outline,
                    color: Colors.red[200],
                    size: 16,
                  ),
                ),
            ],
          ),
        ],
      ),
    );

    return GestureDetector(
      onLongPress: () {
        // Add this debug print:
        debugPrint(
          "[GroupChatScreen LongPress] Checking admin status: _isAdmin = $_isAdmin (Current User ID: ${_currentUser?.id}, Creator ID: $_creatorId)",
        );

        if (_isAdmin && !isOptimistic && !failedToSend) {
          // Only allow admin to delete confirmed messages
          _showMessageAdminOptions(messageId);
        } else {
          // Optionally show standard info dialog for non-admins or pending messages
          _showMessageDetailsDialog(messageData);
        }
      },
      child: Opacity(
        opacity: isOptimistic ? 0.7 : 1.0,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment:
                isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              // Show sender name (existing logic)
              if (showSender && !isMe)
                Padding(
                  padding: const EdgeInsets.only(left: 48, bottom: 2),
                  child: Text(
                    sender,
                    style: TextStyle(
                      color: senderColor ?? Colors.grey[700],
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              Row(
                mainAxisAlignment:
                    isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (!isMe) // Avatar for others
                    Container(
                      width: 30,
                      height: 30,
                      margin: const EdgeInsets.only(right: 8, bottom: 5),
                      decoration: BoxDecoration(
                        color: senderColor ?? _getGroupColor(widget.groupIndex),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          sender.isNotEmpty ? sender[0].toUpperCase() : '?',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  Flexible(child: bubbleContent),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Builds the placeholder for a deleted message
  Widget _buildDeletedMessagePlaceholder(Map<String, dynamic> messageData) {
    final String time = _formatTime(messageData['time']);

    // Determine text based on whether the CURRENT USER is the admin
    final String deletedText =
        _isAdmin
            ? "You deleted this message" // If I am admin, I must have deleted it
            : "Message deleted by admin"; // If I am not admin, an admin deleted it

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        // Align based on original sender still? Or always left align deleted?
        // Let's keep alignment based on original sender for consistency.
        mainAxisAlignment:
            (messageData['isMe'] ?? false)
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
        children: [
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.7,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.delete_outline, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 8),
                  Text(
                    deletedText, // Use the determined text
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontStyle: FontStyle.italic,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    time,
                    style: TextStyle(color: Colors.grey[500], fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- Dialogs ---

  // NEW: Show options for admin on long press
  void _showMessageAdminOptions(String messageId) {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Wrap(
            children: <Widget>[
              ListTile(
                leading: Icon(Icons.delete_forever, color: Colors.red[700]),
                title: Text(
                  'Delete for Everyone',
                  style: TextStyle(color: Colors.red[700]),
                ),
                onTap: () {
                  Navigator.pop(context); // Close the bottom sheet
                  _showDeleteConfirmationDialog(messageId); // Show confirmation
                },
              ),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('Message Info'),
                onTap: () {
                  Navigator.pop(context);
                  // Find the message data to show details
                  final messageData = _messages.firstWhere(
                    (msg) => msg['id'] == messageId,
                    orElse: () => {},
                  );
                  if (messageData.isNotEmpty) {
                    _showMessageDetailsDialog(messageData);
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.cancel),
                title: const Text('Cancel'),
                onTap: () {
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // NEW: Confirmation dialog for deletion
  void _showDeleteConfirmationDialog(String messageId) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Delete Message?"),
          content: const Text(
            "This message will be deleted for everyone in the group. This action cannot be undone.",
          ),
          actions: <Widget>[
            TextButton(
              child: const Text("Cancel"),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red[700]),
              child: const Text("Delete"),
              onPressed: () {
                Navigator.of(context).pop(); // Close the dialog
                _deleteMessage(messageId); // Proceed with deletion
              },
            ),
          ],
        );
      },
    );
  }

  // Existing Message Details Dialog
  void _showMessageDetailsDialog(Map<String, dynamic> messageData) {
    final bool isMe = messageData['isMe'] ?? false;
    final bool isBurnout = messageData['isBurnout'] ?? false;
    final bool isScheduled = messageData['isScheduled'] ?? false;
    final String? scheduledAtStr = messageData['scheduledAt'];
    final bool actuallyExpired = messageData['actuallyExpired'] ?? false;
    final String senderName = messageData['senderName'] ?? 'Unknown Sender';
    final bool isDeleted =
        messageData['deleted_at'] != null; // Check if deleted

    DateTime? expireAt =
        messageData['expireAt'] != null
            ? DateTime.tryParse(messageData['expireAt'])?.toLocal()
            : null;
    DateTime? scheduledAt =
        scheduledAtStr != null
            ? DateTime.tryParse(scheduledAtStr)?.toLocal()
            : null;

    String title = "Message Info";
    List<Widget> content = [];
    final now = DateTime.now();

    if (isDeleted) {
      title = "Deleted Message";
      content.add(
        Text(
          isMe
              ? "You deleted this message."
              : "This message was deleted by the admin.",
        ),
      );
    } else {
      // Original logic for non-deleted messages
      content.add(
        Text(
          "Sender: $senderName",
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      );
      content.add(const SizedBox(height: 8));
      if (isScheduled && isMe && scheduledAt != null) {
        if (scheduledAt.isAfter(now)) {
          title = "Scheduled Message";
          content.add(const Text("You scheduled this message to send on:"));
        } else {
          title = "Sent Scheduled Message";
          content.add(
            const Text("This message was scheduled and sent around:"),
          );
        }
      } else if (isBurnout) {
        if (isMe) {
          if (actuallyExpired && expireAt != null) {
            title = "Expired Message";
            content.add(
              const Text("This message expired for other members on:"),
            );
          } else if (expireAt != null && expireAt.isAfter(now)) {
            title = "Burnout Message";
            content.add(
              const Text("This message will expire for other members on:"),
            );
          } else {
            title = "Message Status";
            content.add(
              const Text("Burnout status is unclear for this message."),
            );
          }
        } else {
          if (expireAt != null && expireAt.isAfter(now)) {
            title = "Burnout Message";
            content.add(const Text("This message will expire on:"));
          } else {
            title = "Expired Message";
            content.add(const Text("This message has expired."));
          }
        }
        if (expireAt != null && expireAt.isAfter(now)) {
          content.add(const SizedBox(height: 8));
          content.add(
            Text("Expires: ${_formatDateTimeUserFriendly(expireAt)}"),
          );
        } else if (expireAt != null) {
          content.add(const SizedBox(height: 8));
          content.add(
            Text(
              "(Expired: ${_formatDateTimeUserFriendly(expireAt)})",
              style: const TextStyle(color: Colors.grey),
            ),
          );
        }
      } else {
        content.add(const Text("Standard group message."));
        final String? timeStr = messageData['time'];
        final DateTime? sentTime =
            timeStr != null ? DateTime.tryParse(timeStr)?.toLocal() : null;
        if (sentTime != null) {
          content.add(const SizedBox(height: 8));
          content.add(Text("Sent: ${_formatDateTimeUserFriendly(sentTime)}"));
        }
      }

      if (scheduledAt != null) {
        content.add(const SizedBox(height: 8));
        content.add(
          Text("Scheduled: ${_formatDateTimeUserFriendly(scheduledAt)}"),
        );
      }
    }

    if (content.isEmpty) content.add(const Text("No details available."));

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(title),
            content: SingleChildScrollView(child: ListBody(children: content)),
            actions: [
              TextButton(
                child: const Text("OK"),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
    );
  }

  // Helper to get a consistent color for a user based on their name hash
  Color _getUserColor(int hashCode) {
    final colors = [
      Colors.blue,
      Colors.green,
      Colors.red,
      Colors.orange,
      Colors.purple,
      Colors.teal,
      Colors.brown,
      Colors.pink,
      Colors.indigo,
      Colors.cyan,
    ];
    return colors[hashCode.abs() % colors.length];
  }

  Color _getGroupColor(int index) {
    final colors = [
      _primaryColor,
      _secondaryColor,
      Colors.deepPurple,
      Colors.orange,
    ];
    return colors[index % colors.length];
  }

  // --- Date/Time Picker and Handlers (Copied & Corrected from ChatScreen) ---
  Future<DateTime?> _selectDateTime(
    BuildContext context,
    DateTime initialDateTime,
  ) async {
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDateTime,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );

    if (!mounted || pickedDate == null) return null;

    final TimeOfDay? pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initialDateTime),
    );

    if (!mounted || pickedTime == null) return null;

    final selectedDateTime = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );

    if (selectedDateTime.isAfter(DateTime.now())) {
      return selectedDateTime;
    } else {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selected time must be in the future.')),
      );
      return null;
    }
  }

  void _handleScheduleTap() async {
    if (_scheduledTime != null) {
      setState(() => _scheduledTime = null);
    } else {
      final initialTime = DateTime.now().add(const Duration(minutes: 10));
      final DateTime? selectedTime = await _selectDateTime(
        context,
        initialTime,
      );
      if (selectedTime != null) {
        setState(() {
          _scheduledTime = selectedTime;
          _burnoutTime = null;
        });
      }
    }
  }

  void _handleBurnoutTap() async {
    if (_burnoutTime != null) {
      setState(() => _burnoutTime = null);
    } else {
      final initialTime = DateTime.now().add(const Duration(hours: 1));
      final DateTime? selectedTime = await _selectDateTime(
        context,
        initialTime,
      );
      if (selectedTime != null) {
        setState(() {
          _burnoutTime = selectedTime;
          _scheduledTime = null;
        });
      }
    }
  }

  String _formatDateTimeUserFriendly(DateTime? time) {
    if (time == null) return '';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final targetDay = DateTime(time.year, time.month, time.day);

    String dayStr;
    if (targetDay == today) {
      dayStr = 'Today';
    } else if (targetDay == tomorrow) {
      dayStr = 'Tomorrow';
    } else {
      dayStr = DateFormat.MMMd().format(time);
    }
    return '$dayStr, ${DateFormat.jm().format(time)}';
  }

  // --- NEW: Delete Message Logic ---
  Future<void> _deleteMessage(String messageId) async {
    if (!_isAdmin || _currentUser == null) {
      debugPrint(
        "[GroupChatScreen DELETE] Not admin or user not loaded. Cannot delete.",
      );
      return;
    }

    debugPrint(
      "[GroupChatScreen DELETE] Attempting to delete message $messageId",
    );

    // Optional: Show a temporary loading indicator on the message itself?

    try {
      final response = await http
          .delete(
            Uri.parse('${ApiConfig.baseUrl}/messages/$messageId'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'userId':
                  _currentUser!.id, // Send current user ID for backend auth
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (!mounted) return;

      if (response.statusCode == 200) {
        debugPrint(
          "[GroupChatScreen DELETE] API call successful for message $messageId.",
        );
        // --- IMPORTANT: Update UI immediately for the admin ---
        // Find the index of the message
        final index = _messages.indexWhere((msg) => msg['id'] == messageId);
        if (index != -1) {
          // Create a new list with the updated message state
          final updatedMessages = List<Map<String, dynamic>>.from(_messages);
          updatedMessages[index] = {
            ...updatedMessages[index],
            'deleted_at':
                DateTime.now()
                    .toUtc()
                    .toIso8601String(), // Mark as deleted locally
          };
          // Update state immediately
          setState(() {
            _messages = updatedMessages;
          });
          debugPrint(
            "[GroupChatScreen DELETE] Updated local UI for deleted message $messageId.",
          );
        } else {
          debugPrint(
            "[GroupChatScreen DELETE] Message $messageId not found locally after successful delete?!",
          );
        }
        // --- End Immediate UI Update ---

        // Backend emits socket event to *other* users. No need for admin to wait for it.
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Message deleted.'),
            duration: Duration(seconds: 2),
          ),
        );
      } else {
        final errorBody = jsonDecode(response.body);
        debugPrint(
          "[GroupChatScreen DELETE] API Error: ${response.statusCode} - ${errorBody['error']}",
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to delete message: ${errorBody['error'] ?? 'Server error'}',
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint("[GroupChatScreen DELETE] Network Error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Network error deleting message: ${e.toString()}'),
          ),
        );
      }
    }
  }
}
