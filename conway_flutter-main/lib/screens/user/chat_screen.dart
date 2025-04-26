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

    // REMOVE encryption call
    // final encryptedMessage = CryptoHelper.encryptText(messageText);
    final plainMessageText = messageText; // Use plain text directly
    
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
    
    // Send plain text message via SocketService
    _socketService.sendMessage(
      _currentUser!.id.toString(),
      _currentUser!.email,
      widget.userEmail,
      plainMessageText, // Send plain text
    );
  }

  String _formatTime(String? timeString) {
    if (timeString == null) return '';
    
    try {
      final DateTime time = DateTime.parse(timeString).toLocal();
      return '${time.hour}:${time.minute.toString().padLeft(2, '0')}';
    } catch (e) {
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
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.emoji_emotions_outlined, color: _primaryColor),
                    onPressed: () {
                      // Implement emoji picker
                    },
                  ),
                  IconButton(
                    icon: Icon(Icons.attach_file, color: _primaryColor),
                    onPressed: () {
                      // Implement file attachment
                    },
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
}
