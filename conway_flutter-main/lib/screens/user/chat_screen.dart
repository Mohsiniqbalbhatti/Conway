import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import '../../models/user.dart';
import '../../helpers/database_helper.dart';
import '../../services/socket_service.dart';
import '../../utils/crypto_helper.dart';
import '../../constants/api_config.dart';

class ChatScreen extends StatefulWidget {
  final String userName;
  final int userIndex;
  final String userEmail;

  const ChatScreen({
    Key? key,
    required this.userName,
    required this.userIndex,
    required this.userEmail,
  }) : super(key: key);

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final Color _primaryColor = const Color(0xFF19BFB7);
  final Color _secondaryColor = const Color(0xFF59A52C);
  final SocketService _socketService = SocketService();
  
  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;
  User? _currentUser;
  StreamSubscription? _messageSubscription;

  // --- New State Variables ---
  bool _isBurnoutMode = false;
  DateTime? _scheduledTime;
  Duration? _burnoutDuration;
  // --- End New State Variables ---

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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error: Could not load user data.')),
      );
    }
  }

  void _setupSocketListeners() {
    _messageSubscription = _socketService.onMessageReceived.listen((messageData) {
       print("[ChatScreen RECEIVE] Raw message data from socket: $messageData");
       // ... (check if message is for current chat)
       final receivedForEmail = messageData['receiverEmail'];
       final senderEmail = messageData['senderEmail'];

       if (receivedForEmail == _currentUser?.email && senderEmail == widget.userEmail) {
         // REMOVE decryption call
         // final rawEncryptedText = messageData['text'] as String? ?? '';
         // print("[ChatScreen RECEIVE] Raw encrypted text before decrypt: $rawEncryptedText");
         // final decryptedText = CryptoHelper.decryptText(rawEncryptedText);
         final plainText = messageData['text'] as String? ?? ''; // Use text directly
         print("[ChatScreen RECEIVE] Plain text received: $plainText");

         if (mounted) {
            setState(() {
              _messages.add({
                'id': messageData['id'],
                'senderId': messageData['senderId'],
                'senderEmail': messageData['senderEmail'],
                'text': plainText, // Use plain text
                'time': messageData['time'],
                'isMe': false, 
              });
            });
            WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
         }
      }
    });
  }

  Future<void> _fetchMessages({bool scrollToBottom = true}) async {
    if (_currentUser == null) return;
    
    setState(() => _isLoading = true);
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/get-messages'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'senderEmail': _currentUser!.email,
          'receiverEmail': widget.userEmail,
        }),
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> fetchedMessages = data['messages'] ?? [];
        print("Fetched ${fetchedMessages.length} raw messages from API: $fetchedMessages"); 
        
        // REMOVE decryption loop
        final plainMessages = fetchedMessages.map((msg) {
            // final decryptedText = CryptoHelper.decryptText(msg['text']);
            final plainText = msg['text'] as String? ?? ''; // Use text directly
            final bool isMe = msg['senderEmail'] == _currentUser!.email;
            return {
              'id': msg['id'],
              'senderId': msg['senderId'],
              'senderEmail': msg['senderEmail'],
              'text': plainText, // Use plain text
              'time': msg['time'], 
              'isMe': isMe,
            };
        }).toList();
        print("Processed ${plainMessages.length} messages: $plainMessages");

        if (mounted) {
          setState(() {
            _messages = List<Map<String, dynamic>>.from(plainMessages);
            _isLoading = false;
          });
        }
        
        if (scrollToBottom) {
           WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
        }
      } else {
         if (mounted) setState(() => _isLoading = false);
         print('Error fetching messages: ${response.statusCode} ${response.body}');
         ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text('Error fetching message history: ${response.statusCode}')),
         );
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      print('Error fetching messages: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Network error fetching messages: ${e.toString()}')),
      );
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _messageSubscription?.cancel();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final messageText = _messageController.text.trim();
    if (messageText.isEmpty || _currentUser == null) return;
    
    _messageController.clear();

    // Read the current modes
    final bool isBurnout = _isBurnoutMode;
    final Duration? burnoutDur = _burnoutDuration;
    final DateTime? schedule = _scheduledTime;

    // Reset modes after getting the message text
    setState(() {
      _isBurnoutMode = false;
      _scheduledTime = null;
      _burnoutDuration = null;
    });

    final plainMessageText = messageText;

    // Optimistically add plain text message to UI
    final optimisticMessage = {
      'senderId': _currentUser!.id.toString(),
      'senderEmail': _currentUser!.email,
      'text': plainMessageText, 
      'time': DateTime.now().toIso8601String(),
      'isMe': true,
    };
    
    if (mounted) {
      setState(() {
        _messages.add(optimisticMessage);
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
    
    // Send plain text message via SocketService (will need modification later)
    print("[ChatScreen SEND] Mode - Burnout: $isBurnout ($burnoutDur), Scheduled: $schedule"); // Updated log
    _socketService.sendMessage(
      _currentUser!.id.toString(),
      _currentUser!.email,
      widget.userEmail,
      plainMessageText, // Send plain text for now
      // TODO: Pass isBurnout, burnoutDuration, schedule flags/time later
    );
  }

  String _formatTime(String? timeString) {
    if (timeString == null) return '';

    try {
      // Parse the ISO 8601 string (likely UTC from server)
      final DateTime utcTime = DateTime.parse(timeString);
      // Convert to local time zone
      final DateTime localTime = utcTime.toLocal();

      // Format as 12-hour time with AM/PM (e.g., 5:53 PM)
      int hour = localTime.hour;
      final String minute = localTime.minute.toString().padLeft(2, '0');
      final String period = hour < 12 ? 'AM' : 'PM';
      if (hour == 0) { // Handle midnight
        hour = 12;
      } else if (hour > 12) {
        hour -= 12;
      }
      return '$hour:$minute $period';
    } catch (e) {
      print("Error formatting time in ChatScreen '$timeString': $e");
      return ''; // Return empty on error
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
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _getUserColor(widget.userIndex),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.person,
                color: Colors.white,
                size: 20,
              ),
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
        decoration: BoxDecoration(
          color: Colors.grey[100],
        ),
        child: Column(
          children: [
            Expanded(
              child: _isLoading
                  ? Center(child: CircularProgressIndicator(color: _primaryColor))
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
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 20),
                          itemCount: _messages.length,
                itemBuilder: (context, index) {
                            final message = _messages[index];
                            final isMe = message['isMe'] ?? (message['senderEmail'] == _currentUser?.email);
                  
                  return _buildMessageBubble(
                              message: message['text'] ?? '',
                              time: _formatTime(message['time']),
                    isMe: isMe,
                  );
                },
              ),
            ),
            
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
                mainAxisSize: MainAxisSize.min, // Fit content vertically
                children: [
                  // Show scheduled time if set
                  if (_scheduledTime != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4.0),
                      child: Text(
                        'Scheduled for: ${_formatScheduleTime(_scheduledTime)}',
                        style: TextStyle(color: Colors.blue[700], fontSize: 12),
                      ),
                    ),
                  // Show burnout duration if set
                  if (_isBurnoutMode && _burnoutDuration != null)
                     Padding(
                       padding: const EdgeInsets.only(bottom: 4.0),
                       child: Text(
                         'Burnout Enabled: Expires in ${_burnoutDuration!.inSeconds}s',
                         style: TextStyle(color: Colors.orange[700], fontSize: 12),
                       ),
                     ),
                  Row(
                    children: [
                      // --- Burnout Mode Button ---
                      IconButton(
                        icon: Icon(
                          Icons.local_fire_department_outlined,
                          color: _isBurnoutMode ? Colors.orange[700] : Colors.grey[600],
                        ),
                        tooltip: 'Configure Burnout Mode',
                        onPressed: _showBurnoutDialog,
                      ),
                      // --- Schedule Message Button ---
                      IconButton(
                        icon: Icon(
                          Icons.schedule_outlined,
                          color: _scheduledTime != null ? Colors.blue[700] : Colors.grey[600],
                        ),
                        tooltip: _scheduledTime == null ? 'Schedule Message' : 'Cancel Schedule',
                        onPressed: _handleScheduleTap,
                      ),
                      // --- Text Input Field ---
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
                      // --- Send Button ---
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

  Widget _buildMessageBubble({
    required String message,
    required String time,
    required bool isMe,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
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
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
              decoration: BoxDecoration(
                color: isMe
                    ? _primaryColor
                    : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: isMe ? const Radius.circular(18) : Radius.zero,
                  bottomRight: isMe ? Radius.zero : const Radius.circular(18),
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
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    message,
                    style: TextStyle(
                      color: isMe ? Colors.white : Colors.black87,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    time,
                    style: TextStyle(
                      color: isMe ? Colors.white70 : Colors.grey[600],
                      fontSize: 12,
                    ),
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
                Icons.done_all,
                color: _primaryColor,
                size: 16,
              ),
            ),
        ],
      ),
    );
  }

  // --- Helper Methods ---
  void _handleScheduleTap() async {
    if (_scheduledTime != null) {
      // Cancel existing schedule
      setState(() {
        _scheduledTime = null;
      });
    } else {
      // Show date & time picker
      final now = DateTime.now();
      final DateTime? pickedDate = await showDatePicker(
        context: context,
        initialDate: now,
        firstDate: now, // Can only schedule for future
        lastDate: now.add(const Duration(days: 365)), // Limit to 1 year
      );

      if (pickedDate != null && mounted) {
        final TimeOfDay? pickedTime = await showTimePicker(
          context: context,
          initialTime: TimeOfDay.fromDateTime(now.add(const Duration(minutes: 5))), // Default to 5 mins from now
        );

        if (pickedTime != null) {
          final selectedDateTime = DateTime(
            pickedDate.year,
            pickedDate.month,
            pickedDate.day,
            pickedTime.hour,
            pickedTime.minute,
          );

          // Ensure the selected time is in the future
          if (selectedDateTime.isAfter(DateTime.now())) {
            setState(() {
              _scheduledTime = selectedDateTime;
              _isBurnoutMode = false; // Deactivate burnout mode
              _burnoutDuration = null; // Clear burnout duration
            });
          } else {
            // Show error if time is in the past
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Scheduled time must be in the future.')),
            );
          }
        }
      }
    }
  }

  String _formatScheduleTime(DateTime? time) {
    if (time == null) return '';
    // Use a more detailed format for scheduled time
    final day = time.day.toString().padLeft(2, '0');
    final month = time.month.toString().padLeft(2, '0');
    final year = time.year;
    int hour = time.hour;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = hour < 12 ? 'AM' : 'PM';
    if (hour == 0) hour = 12;
    if (hour > 12) hour -= 12;
    return '$day/$month/$year $hour:$minute $period';
  }

  // --- New Burnout Dialog Method ---
  void _showBurnoutDialog() {
    // Temporary variables to hold dialog state
    bool tempIsEnabled = _isBurnoutMode;
    Duration tempDuration = _burnoutDuration ?? const Duration(seconds: 10); // Default if null
    final List<Duration> availableDurations = [
      const Duration(seconds: 5),
      const Duration(seconds: 10),
      const Duration(seconds: 30),
      const Duration(minutes: 1),
    ];

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Configure Burnout Mode'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  SwitchListTile(
                    title: const Text('Enable Burnout'),
                    value: tempIsEnabled,
                    onChanged: (bool value) {
                      setDialogState(() {
                        tempIsEnabled = value;
                      });
                    },
                    activeColor: _primaryColor,
                  ),
                  if (tempIsEnabled)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0, left: 16.0, right: 16.0),
                      child: DropdownButtonFormField<Duration>(
                        value: tempDuration,
                        items: availableDurations.map((duration) {
                          return DropdownMenuItem<Duration>(
                            value: duration,
                            child: Text('${duration.inSeconds} seconds'),
                          );
                        }).toList(),
                        onChanged: (Duration? newValue) {
                          if (newValue != null) {
                             setDialogState(() {
                                tempDuration = newValue;
                             });
                          }
                        },
                        decoration: const InputDecoration(
                          labelText: 'Expire after',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                ],
              ),
              actions: <Widget>[
                TextButton(
                  child: const Text('Cancel'),
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                ),
                TextButton(
                  child: const Text('Set'),
                  onPressed: () {
                    // Update the main screen state
                    setState(() {
                      _isBurnoutMode = tempIsEnabled;
                      if (_isBurnoutMode) {
                        _burnoutDuration = tempDuration;
                        _scheduledTime = null; // Deactivate schedule mode
                      } else {
                        _burnoutDuration = null;
                      }
                    });
                    Navigator.of(context).pop();
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }
}
