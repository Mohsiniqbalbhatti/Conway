import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import '../../models/user.dart';
import '../../helpers/database_helper.dart';
import '../../services/socket_service.dart';
import '../../constants/api_config.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:profanity_filter/profanity_filter.dart';

class ChatScreen extends StatefulWidget {
  final String userName;
  final int userIndex;
  final String userEmail;
  final String? profileUrl;

  const ChatScreen({
    super.key,
    required this.userName,
    required this.userIndex,
    required this.userEmail,
    this.profileUrl,
  });

  @override
  State<ChatScreen> createState() => ChatScreenState();
}

class ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final Color _primaryColor = const Color(0xFF19BFB7);
  final Color _secondaryColor = const Color(0xFF59A52C);
  final SocketService _socketService = SocketService();
  final ProfanityFilter _filter = ProfanityFilter();

  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;
  User? _currentUser;
  StreamSubscription? _messageSubscription;
  StreamSubscription? _messageExpiredSubscription;
  StreamSubscription? _messageSentSubscription;

  DateTime? _scheduledTime;
  DateTime? _burnoutTime;

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _loadUserDataAndConnect();
  }

  Future<void> _loadUserDataAndConnect() async {
    final user = await DBHelper().getUser();
    if (!mounted) return;
    setState(() {
      _currentUser = user;
    });
    if (_currentUser != null) {
      _socketService.connect(_currentUser!.id.toString());
      _setupSocketListeners();
      await _fetchMessages();
    } else {
      setState(() => _isLoading = false);
      // Guard the ScaffoldMessenger call
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error: Could not load user data.')),
        );
      }
    }
  }

  void _setupSocketListeners() {
    _messageSubscription = _socketService.onMessageReceived.listen((
      messageData,
    ) {
      debugPrint(
        "[ChatScreen RECEIVE] Raw message data from socket: $messageData",
      );
      _handleReceivedMessage(messageData);
    });

    _messageExpiredSubscription = _socketService.onMessageExpired.listen((
      messageId,
    ) {
      debugPrint(
        "[ChatScreen EXPIRE] Received expiry for message ID: $messageId",
      );
      _handleMessageExpiry(messageId);
    });

    _messageSentSubscription = _socketService.onMessageSent.listen((sentData) {
      debugPrint("[ChatScreen SENT CONFIRM] Received confirmation: $sentData");
      _handleMessageSentConfirmation(sentData);
    });
  }

  void _handleReceivedMessage(Map<String, dynamic> messageData) {
    final receivedForEmail = messageData['receiverEmail'];
    final senderEmail = messageData['senderEmail'];
    final messageId = messageData['id'];

    if (!((receivedForEmail == _currentUser?.email &&
            senderEmail == widget.userEmail) ||
        (senderEmail == _currentUser?.email &&
            receivedForEmail == widget.userEmail))) {
      return;
    }

    if (_messages.any((msg) => msg['id'] == messageId)) {
      debugPrint(
        "[ChatScreen RECEIVE] Message ID $messageId already exists. Ignoring.",
      );
      return;
    }

    final plainText = messageData['text'] as String? ?? '';
    final bool isBurnout = messageData['isBurnout'] as bool? ?? false;
    final String? expireAtStr = messageData['expireAt'] as String?;
    final bool isScheduled = messageData['isScheduled'] as bool? ?? false;
    final String? scheduledAtStr = messageData['scheduledAt'] as String?;
    DateTime? expireAt =
        expireAtStr != null ? DateTime.tryParse(expireAtStr)?.toLocal() : null;

    debugPrint(
      "[ChatScreen RECEIVE] Text: $plainText, Burnout: $isBurnout, Expires: $expireAt, WasScheduled: $isScheduled",
    );

    if (isBurnout && expireAt != null && expireAt.isBefore(DateTime.now())) {
      debugPrint("[ChatScreen RECEIVE] Burnout message expired. Ignoring.");
      return;
    }

    if (mounted) {
      setState(() {
        _messages.add({
          'id': messageId,
          'senderId': messageData['senderId'],
          'senderEmail': senderEmail,
          'text': plainText,
          'time': messageData['time'],
          'isMe': senderEmail == _currentUser?.email,
          'isBurnout': isBurnout,
          'expireAt': expireAtStr,
          'isScheduled': isScheduled,
          'scheduledAt': scheduledAtStr,
        });
        _sortMessages();
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
  }

  void _handleMessageExpiry(String messageId) {
    if (!mounted) return;
    setState(() {
      final index = _messages.indexWhere((msg) => msg['id'] == messageId);
      if (index != -1) {
        if (!_messages[index]['isMe']) {
          debugPrint(
            "[ChatScreen EXPIRE] Hiding expired message ID $messageId for receiver.",
          );
          _messages[index]['visuallyExpired'] = true;
        } else {
          debugPrint(
            "[ChatScreen EXPIRE] Sender received expiry for $messageId. Keeping visible.",
          );
          _messages[index]['actuallyExpired'] = true;
        }
      } else {
        debugPrint(
          "[ChatScreen EXPIRE] Message ID $messageId not found in current list.",
        );
      }
    });
  }

  void _handleMessageSentConfirmation(Map<String, dynamic> sentData) {
    final tempId = sentData['tempId'] as String?;
    final dbId = sentData['dbId'] as String?;
    final serverTimeStr = sentData['time'] as String?;

    if (tempId == null || dbId == null) {
      debugPrint(
        "[ChatScreen SENT CONFIRM] Invalid confirmation data (missing tempId or dbId).",
      );
      return;
    }

    if (!mounted) return;

    setState(() {
      final index = _messages.indexWhere((msg) => msg['id'] == tempId);
      if (index != -1) {
        debugPrint(
          "[ChatScreen SENT CONFIRM] Found optimistic message $tempId. Updating to ID $dbId.",
        );
        _messages[index]['id'] = dbId;
        _messages[index]['isOptimistic'] = false;
        if (serverTimeStr != null) {
          _messages[index]['time'] = serverTimeStr;
        }
        _sortMessages();
      } else {
        debugPrint(
          "[ChatScreen SENT CONFIRM] Optimistic message $tempId not found.",
        );
      }
    });
  }

  Future<void> _fetchMessages({bool scrollToBottom = true}) async {
    if (_currentUser == null) return;

    setState(() => _isLoading = true);
    try {
      final response = await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/api/get-messages'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'senderEmail': _currentUser!.email,
              'receiverEmail': widget.userEmail,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> fetchedMessages = data['messages'] ?? [];
        debugPrint("Fetched ${fetchedMessages.length} raw messages from API");

        final validMessages =
            fetchedMessages
                .map((msg) {
                  final plainText = msg['text'] as String? ?? '';
                  final bool isMe = msg['senderEmail'] == _currentUser!.email;
                  final bool isBurnout = msg['isBurnout'] as bool? ?? false;
                  final String? expireAtStr = msg['expireAt'] as String?;
                  final bool isScheduled = msg['isScheduled'] as bool? ?? false;
                  final String? scheduledAtStr = msg['scheduledAt'] as String?;
                  DateTime? expireAt =
                      expireAtStr != null
                          ? DateTime.tryParse(expireAtStr)?.toLocal()
                          : null;

                  if (isBurnout &&
                      expireAt != null &&
                      expireAt.isBefore(DateTime.now())) {
                    if (isMe) {
                      return {
                        'id': msg['id'],
                        'senderId': msg['senderId'],
                        'senderEmail': msg['senderEmail'],
                        'text': plainText,
                        'time': msg['time'],
                        'isMe': isMe,
                        'isBurnout': isBurnout,
                        'expireAt': expireAtStr,
                        'isScheduled': isScheduled,
                        'scheduledAt': scheduledAtStr,
                        'actuallyExpired': true,
                      };
                    } else {
                      return null;
                    }
                  }

                  return {
                    'id': msg['id'],
                    'senderId': msg['senderId'],
                    'senderEmail': msg['senderEmail'],
                    'text': plainText,
                    'time': msg['time'],
                    'isMe': isMe,
                    'isBurnout': isBurnout,
                    'expireAt': expireAtStr,
                    'isScheduled': isScheduled,
                    'scheduledAt': scheduledAtStr,
                    'actuallyExpired': false,
                  };
                })
                .where((msg) => msg != null)
                .toList();

        debugPrint(
          "Processed ${validMessages.length} valid messages for display",
        );

        if (mounted) {
          setState(() {
            _messages = List<Map<String, dynamic>>.from(validMessages);
            _sortMessages();
            _isLoading = false;
          });
        }

        if (scrollToBottom) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _scrollToBottom(),
          );
        }
      } else {
        if (mounted) setState(() => _isLoading = false);
        debugPrint(
          'Error fetching messages: ${response.statusCode} ${response.body}',
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Error fetching message history: ${response.statusCode}',
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      debugPrint('Error fetching messages: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Network error fetching messages: ${e.toString()}'),
          ),
        );
      }
    }
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

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _messageSubscription?.cancel();
    _messageExpiredSubscription?.cancel();
    _messageSentSubscription?.cancel();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final messageText = _messageController.text.trim();
    if (messageText.isEmpty || _currentUser == null) return;

    if (_filter.hasProfanity(messageText)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Message contains inappropriate language and cannot be sent.',
          ),
          backgroundColor: Colors.orangeAccent,
        ),
      );
      return;
    }

    final tempId = 'optimistic_${DateTime.now().millisecondsSinceEpoch}';
    _messageController.clear();

    final DateTime? scheduleTime = _scheduledTime;
    final DateTime? burnTime = _burnoutTime;

    setState(() {
      _scheduledTime = null;
      _burnoutTime = null;
    });

    final plainMessageText = messageText;

    final optimisticMessage = {
      'id': tempId,
      'senderId': _currentUser!.id.toString(),
      'senderEmail': _currentUser!.email,
      'text': plainMessageText,
      'time': DateTime.now().toUtc().toIso8601String(),
      'isMe': true,
      'isBurnout': burnTime != null,
      'expireAt': burnTime?.toUtc().toIso8601String(),
      'isScheduled': scheduleTime != null,
      'scheduledAt': scheduleTime?.toUtc().toIso8601String(),
      'isOptimistic': true,
    };

    if (mounted) {
      setState(() {
        _messages.add(optimisticMessage);
        _sortMessages();
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }

    debugPrint(
      "[ChatScreen SEND] Burnout: ${burnTime?.toIso8601String()}, Scheduled: ${scheduleTime?.toIso8601String()}",
    );

    // Create the payload map
    final messagePayload = {
      'senderId': _currentUser!.id.toString(),
      'senderEmail': _currentUser!.email,
      'receiverEmail': widget.userEmail,
      'messageText': plainMessageText,
      'tempId': tempId,
      if (burnTime != null)
        'burnoutDateTime': burnTime.toUtc().toIso8601String(),
      if (scheduleTime != null)
        'scheduleDateTime': scheduleTime.toUtc().toIso8601String(),
    };

    // Use the generic emit method
    _socketService.emit('sendMessage', messagePayload);
  }

  String _formatTime(String? timeString) {
    if (timeString == null) return '';
    try {
      final DateTime utcTime = DateTime.parse(timeString);
      final DateTime localTime = utcTime.toLocal();
      return DateFormat.jm().format(localTime);
    } catch (e) {
      debugPrint("Error formatting time in ChatScreen '$timeString': $e");
      return '';
    }
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

  @override
  Widget build(BuildContext context) {
    final bool hasProfileUrl =
        widget.profileUrl != null && widget.profileUrl!.isNotEmpty;

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
          onTap: () {
            // Implement user profile tap functionality
          },
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: _getUserColor(widget.userIndex),
                backgroundImage:
                    hasProfileUrl
                        ? CachedNetworkImageProvider(widget.profileUrl!)
                        : null,
                child:
                    !hasProfileUrl
                        ? const Icon(
                          Icons.person,
                          color: Colors.white,
                          size: 20,
                        )
                        : null,
              ),
              const SizedBox(width: 10),
              Text(
                widget.userName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.call, color: Colors.white),
            onPressed: () {
              // Implement call functionality
            },
          ),
          IconButton(
            icon: const Icon(Icons.videocam, color: Colors.white),
            onPressed: () {
              // Implement video call functionality
            },
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(color: Colors.grey[100]),
        child: Column(
          children: [
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
                              'No messages yet',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w500,
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Start the conversation!',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      )
                      : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 20,
                        ),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final message = _messages[index];

                          if (message['visuallyExpired'] == true) {
                            return const SizedBox.shrink();
                          }

                          return _buildMessageBubble(messageData: message);
                        },
                      ),
            ),
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
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                  Row(
                    children: [
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
                          onSubmitted: (_) => _sendMessage(),
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

  Widget _buildMessageBubble({required Map<String, dynamic> messageData}) {
    final String message = messageData['text'] ?? '';
    final String time = _formatTime(messageData['time']);
    final bool isMe = messageData['isMe'] ?? false;
    final bool isBurnout = messageData['isBurnout'] ?? false;
    // final String? expireAtStr = messageData['expireAt']; // Unused
    final bool isScheduled = messageData['isScheduled'] ?? false;
    final String? scheduledAtStr = messageData['scheduledAt'];
    final bool isOptimistic = messageData['isOptimistic'] ?? false;
    final bool actuallyExpired = messageData['actuallyExpired'] ?? false;

    final bool isPendingSchedule =
        isMe &&
        isScheduled &&
        scheduledAtStr != null &&
        (DateTime.tryParse(scheduledAtStr)?.isAfter(DateTime.now()) ?? false);

    return GestureDetector(
      onLongPress: () => _showMessageDetailsDialog(messageData),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Opacity(
          opacity: isOptimistic ? 0.7 : 1.0,
          child: Row(
            mainAxisAlignment:
                isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isMe)
                Container(
                  width: 30,
                  height: 30,
                  margin: const EdgeInsets.only(right: 8, bottom: 5),
                  decoration: BoxDecoration(
                    color: _getUserColor(widget.userIndex),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.person,
                    color: Colors.white,
                    size: 16,
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
                    color: isMe ? _primaryColor : Colors.white,
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
                        color: Colors.grey.withAlpha(26),
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
                            : CrossAxisAlignment.start,
                    children: [
                      Text(
                        message,
                        style: TextStyle(
                          color: isMe ? Colors.white : Colors.black87,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
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
                                      ? (isMe
                                          ? Colors.white54
                                          : Colors.grey[500])
                                      : (isMe
                                          ? Colors.white70
                                          : Colors.orange[700]),
                            ),
                          if (isBurnout) const SizedBox(width: 4),
                          Text(
                            time,
                            style: TextStyle(
                              color: isMe ? Colors.white70 : Colors.grey[600],
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (isMe)
                Container(
                  width: 18,
                  height: 18,
                  margin: const EdgeInsets.only(left: 5, bottom: 5),
                  child: Icon(
                    isOptimistic ? Icons.access_time : Icons.done_all,
                    color: _primaryColor,
                    size: 16,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showMessageDetailsDialog(Map<String, dynamic> messageData) {
    final bool isMe = messageData['isMe'] ?? false;
    final bool isBurnout = messageData['isBurnout'] ?? false;
    final bool isScheduled = messageData['isScheduled'] ?? false;
    final String? scheduledAtStr = messageData['scheduledAt'];
    final bool actuallyExpired = messageData['actuallyExpired'] ?? false;

    DateTime? expireAt =
        messageData['expireAt'] != null
            ? DateTime.tryParse(messageData['expireAt'])?.toLocal()
            : null;
    DateTime? scheduledAt =
        scheduledAtStr != null
            ? DateTime.tryParse(scheduledAtStr)?.toLocal()
            : null;

    String title = "Message Details";
    List<Widget> content = [];
    final now = DateTime.now();

    if (isScheduled && isMe && scheduledAt != null) {
      if (scheduledAt.isAfter(now)) {
        title = "Scheduled Message";
        content.add(Text("This message is scheduled to be sent on:"));
      } else {
        title = "Sent Scheduled Message";
        content.add(Text("This message was scheduled and sent around:"));
      }
      content.add(SizedBox(height: 8));
      content.add(
        Text(
          _formatDateTimeUserFriendly(scheduledAt),
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      );
    } else if (isBurnout) {
      if (isMe) {
        if (actuallyExpired && expireAt != null) {
          title = "Expired Message";
          content.add(Text("This message expired for the receiver on:"));
          content.add(SizedBox(height: 8));
          content.add(
            Text(
              _formatDateTimeUserFriendly(expireAt),
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          );
        } else if (expireAt != null && expireAt.isAfter(now)) {
          title = "Burnout Message";
          content.add(Text("This message will expire for the receiver on:"));
          content.add(SizedBox(height: 8));
          content.add(
            Text(
              _formatDateTimeUserFriendly(expireAt),
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          );
        } else {
          title = "Message Status";
          content.add(Text("Burnout status is unclear for this message."));
        }
      } else {
        if (expireAt != null && expireAt.isAfter(now)) {
          title = "Burnout Message";
          content.add(Text("This message will expire on:"));
          content.add(SizedBox(height: 8));
          content.add(
            Text(
              _formatDateTimeUserFriendly(expireAt),
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          );
        } else {
          title = "Expired Message";
          content.add(Text("This message has expired."));
        }
      }
    } else {
      content.add(Text("This is a standard message."));
      final String? timeStr = messageData['time'];
      final DateTime? sentTime =
          timeStr != null ? DateTime.tryParse(timeStr)?.toLocal() : null;
      if (sentTime != null) {
        content.add(SizedBox(height: 8));
        content.add(Text("Sent: ${_formatDateTimeUserFriendly(sentTime)}"));
      }
    }

    if (content.isEmpty) return;

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(title),
            content: SingleChildScrollView(child: ListBody(children: content)),
            actions: [
              TextButton(
                child: Text("OK"),
                onPressed: () {
                  if (mounted) {
                    Navigator.of(context).pop();
                  }
                },
              ),
            ],
          ),
    );
  }

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
      setState(() {
        _scheduledTime = null;
      });
    } else {
      final initialTime = DateTime.now().add(const Duration(minutes: 10));
      final DateTime? selectedTime = await _selectDateTime(
        context,
        initialTime,
      );

      // Guard setState after await
      if (mounted && selectedTime != null) {
        setState(() {
          _scheduledTime = selectedTime;
          _burnoutTime = null;
        });
      }
    }
  }

  void _handleBurnoutTap() async {
    if (_burnoutTime != null) {
      setState(() {
        _burnoutTime = null;
      });
    } else {
      final initialTime = DateTime.now().add(const Duration(hours: 1));
      final DateTime? selectedTime = await _selectDateTime(
        context,
        initialTime,
      );

      // Guard setState after await
      if (mounted && selectedTime != null) {
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
}
