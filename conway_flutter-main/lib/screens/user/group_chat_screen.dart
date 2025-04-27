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
  User? _currentUser;

  // Socket Service and Subscriptions
  final SocketService _socketService = SocketService();
  StreamSubscription? _groupMessageSubscription;
  StreamSubscription? _groupMessageSentSubscription;
  StreamSubscription? _groupMessageExpiredSubscription; // NEW: For expiry

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
    _loadUserDataAndMessages();
    // Connect socket after user data is loaded (or in _loadUserDataAndMessages)
  }

  Future<void> _loadUserDataAndMessages() async {
    await _loadUserData();
    if (_currentUser != null) {
      // Connect socket here after confirming user ID
      _socketService.connect(_currentUser!.id.toString());
      _setupSocketListeners();
      await _fetchGroupMessages(); // Fetch initial messages
    } else {
      // Handle error: user data not found
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error: Could not load user data.')),
        );
        setState(() => _isLoading = false);
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

    // Ignore expired burnout messages on arrival
    if (isBurnout && expireAt != null && expireAt.isBefore(DateTime.now())) {
      debugPrint(
        "[GroupChatScreen RECEIVE] Burnout message $messageId already expired. Ignoring.",
      );
      return;
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
    };

    if (mounted) {
      setState(() {
        _messages.add(newMessage);
        _sortMessages(); // Ensure messages are sorted by time
      });
      // Scroll only if the user is near the bottom
      // TODO: Add logic to check scroll position before auto-scrolling
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

  Future<void> _loadUserData() async {
    final user = await DBHelper().getUser();
    // No setState here, it will be called in _loadUserDataAndMessages
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
              '${ApiConfig.baseUrl}/group-messages/${widget.groupId}?userId=${_currentUser!.id}',
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
                        // Mark already expired sent messages
                        'actuallyExpired': msg['actuallyExpired'] ?? false,
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
    _groupMessageExpiredSubscription?.cancel(); // NEW
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
              );
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
                  _isLoading
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
                          final isMe =
                              message['isMe'] ?? false; // Get isMe flag

                          // Use the actual sender name from the message data
                          final senderName = message['senderName'] ?? 'Unknown';

                          // Pass necessary data to _buildMessageBubble
                          return _buildMessageBubble(
                            sender: senderName,
                            message: message['text'] ?? '',
                            time: _formatTime(message['time']), // Format time
                            isMe: isMe,
                            senderColor:
                                isMe
                                    ? null
                                    : _getUserColor(
                                      senderName.hashCode,
                                    ), // Assign color based on sender hash
                            showSender:
                                !isMe &&
                                _shouldShowSender(index), // Show sender logic
                            isOptimistic:
                                message['isOptimistic'] ??
                                false, // Pass optimistic flag
                            failedToSend:
                                message['failedToSend'] ??
                                false, // Pass failed flag
                            isBurnout: message['isBurnout'] ?? false,
                            expireAtStr: message['expireAt'],
                            isScheduled: message['isScheduled'] ?? false,
                            scheduledAtStr: message['scheduledAt'],
                            actuallyExpired:
                                message['actuallyExpired'] ?? false,
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
                    color: Colors.grey.withOpacity(0.2),
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
    required String sender,
    required String message,
    required String time,
    required bool isMe,
    Color? senderColor,
    required bool showSender,
    required bool isOptimistic,
    required bool failedToSend,
    required bool isBurnout,
    String? expireAtStr,
    required bool isScheduled,
    String? scheduledAtStr,
    required bool actuallyExpired,
  }) {
    final Color messageColor = isMe ? _primaryColor : Colors.white;
    final Color textColor = isMe ? Colors.white : Colors.black87;

    // NEW: Check if message is pending schedule (only relevant if it's mine)
    final bool isPendingSchedule =
        isMe &&
        isScheduled &&
        scheduledAtStr != null &&
        (DateTime.tryParse(scheduledAtStr)?.isAfter(DateTime.now()) ?? false);

    return GestureDetector(
      // Wrap with GestureDetector for long-press
      onLongPress:
          () => _showMessageDetailsDialog({
            // Pass all relevant data to dialog
            'text': message, 'time': time, 'isMe': isMe,
            'isBurnout': isBurnout, 'expireAt': expireAtStr,
            'isScheduled': isScheduled, 'scheduledAt': scheduledAtStr,
            'actuallyExpired': actuallyExpired,
            'senderName': sender, // Pass sender name
          }),
      child: Opacity(
        // Wrap with Opacity for optimistic UI
        opacity: isOptimistic ? 0.7 : 1.0,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment:
                isMe
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start, // Align text based on sender
            children: [
              // Show sender name if needed
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
                  if (!isMe) // Show avatar for others
                    Container(
                      width: 30,
                      height: 30,
                      margin: const EdgeInsets.only(right: 8, bottom: 5),
                      decoration: BoxDecoration(
                        color:
                            senderColor ??
                            _getGroupColor(
                              widget.groupIndex,
                            ), // Use sender specific color
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        // Center initial letter
                        child: Text(
                          sender.isNotEmpty
                              ? sender[0].toUpperCase()
                              : '?', // Display first letter
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  Flexible(
                    child: Container(
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.7,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 15,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: messageColor,
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(18),
                          topRight: const Radius.circular(18),
                          bottomLeft:
                              isMe ? const Radius.circular(18) : Radius.zero,
                          bottomRight:
                              isMe ? Radius.zero : const Radius.circular(18),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withOpacity(0.1),
                            spreadRadius: 1,
                            blurRadius: 1,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment:
                            isMe
                                ? CrossAxisAlignment.end
                                : CrossAxisAlignment
                                    .start, // Align text based on sender
                        children: [
                          Text(
                            message,
                            style: TextStyle(color: textColor, fontSize: 16),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            // Put time and status icon in a row
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // NEW: Add icons for schedule/burnout
                              if (isPendingSchedule)
                                Icon(
                                  Icons.alarm,
                                  size: 14,
                                  color:
                                      isMe
                                          ? Colors.white70
                                          : Colors
                                              .blue[700], // Consistent with ChatScreen
                                ),
                              if (isPendingSchedule) const SizedBox(width: 4),
                              if (isBurnout)
                                Icon(
                                  Icons.local_fire_department,
                                  size: 14,
                                  color:
                                      actuallyExpired
                                          ? (isMe
                                              ? Colors.white54
                                              : Colors
                                                  .grey[500]) // Dim if expired
                                          : (isMe
                                              ? Colors.white70
                                              : Colors
                                                  .orange[700]), // Bright if active
                                ),
                              if (isBurnout) const SizedBox(width: 4),
                              // END NEW Icons
                              Text(
                                time,
                                style: TextStyle(
                                  color:
                                      isMe ? Colors.white70 : Colors.grey[600],
                                  fontSize: 12,
                                ),
                              ),
                              if (isMe &&
                                  !isOptimistic &&
                                  !failedToSend) // Show sent icon only for confirmed own messages
                                Padding(
                                  padding: const EdgeInsets.only(left: 4.0),
                                  child: Icon(
                                    Icons
                                        .done_all, // Use done_all for sent confirmation
                                    color: Colors.white70, // Match time color
                                    size: 16,
                                  ),
                                ),
                              if (isMe && isOptimistic) // Show pending icon
                                Padding(
                                  padding: const EdgeInsets.only(left: 4.0),
                                  child: Icon(
                                    Icons.access_time,
                                    color: Colors.white70,
                                    size: 16,
                                  ),
                                ),
                              if (isMe && failedToSend) // Show error icon
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
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
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

    if (pickedDate != null && mounted) {
      final TimeOfDay? pickedTime = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(initialDateTime),
      );

      if (pickedTime != null && mounted) {
        final selectedDateTime = DateTime(
          pickedDate.year,
          pickedDate.month,
          pickedDate.day,
          pickedTime.hour,
          pickedTime.minute,
        );

        if (selectedDateTime.isAfter(
          DateTime.now().subtract(const Duration(minutes: 1)),
        )) {
          return selectedDateTime;
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Selected time must be in the future.'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return null;
        }
      }
    }
    return null;
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

  // Update Dialog to show message details (Adapted from ChatScreen)
  void _showMessageDetailsDialog(Map<String, dynamic> messageData) {
    final bool isMe = messageData['isMe'] ?? false;
    final bool isBurnout = messageData['isBurnout'] ?? false;
    final String? expireAtStr = messageData['expireAt'];
    final bool isScheduled = messageData['isScheduled'] ?? false;
    final String? scheduledAtStr = messageData['scheduledAt'];
    final bool actuallyExpired = messageData['actuallyExpired'] ?? false;
    final String senderName = messageData['senderName'] ?? 'Unknown Sender';

    DateTime? expireAt =
        expireAtStr != null ? DateTime.tryParse(expireAtStr)?.toLocal() : null;
    DateTime? scheduledAt =
        scheduledAtStr != null
            ? DateTime.tryParse(scheduledAtStr)?.toLocal()
            : null;

    String title = "Message Info";
    List<Widget> content = [];
    final now = DateTime.now();

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
        content.add(const Text("This message was scheduled and sent around:"));
      }
      // No need to add separate timing info below if scheduled time is primary info
    } else if (isBurnout) {
      if (isMe) {
        if (actuallyExpired && expireAt != null) {
          title = "Expired Message";
          content.add(const Text("This message expired for other members on:"));
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
      // Add expiry time if relevant
      if (expireAt != null && expireAt.isAfter(now)) {
        content.add(const SizedBox(height: 8));
        content.add(Text("Expires: ${_formatDateTimeUserFriendly(expireAt)}"));
      } else if (expireAt != null) {
        // Show past expiry if it existed
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
      // Add sent time for standard messages
      final String? timeStr =
          messageData['time']; // Assuming the map has the original ISO string time
      final DateTime? sentTime =
          timeStr != null ? DateTime.tryParse(timeStr)?.toLocal() : null;
      if (sentTime != null) {
        content.add(const SizedBox(height: 8));
        content.add(Text("Sent: ${_formatDateTimeUserFriendly(sentTime)}"));
      }
    }

    // Add schedule time if it was scheduled (separate from main logic)
    if (scheduledAt != null) {
      content.add(const SizedBox(height: 8));
      content.add(
        Text("Scheduled: ${_formatDateTimeUserFriendly(scheduledAt)}"),
      );
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
}
