import 'package:flutter/material.dart';

class GroupChatScreen extends StatefulWidget {
  final String groupName;
  final String members;
  final int groupIndex;
  final String groupId;

  const GroupChatScreen({
    Key? key,
    required this.groupName,
    required this.members,
    required this.groupIndex,
    required this.groupId,
  }) : super(key: key);

  @override
  _GroupChatScreenState createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final Color _primaryColor = const Color(0xFF19BFB7);
  final Color _secondaryColor = const Color(0xFF59A52C);
  
  // Mock conversation data with multiple users
  final List<Map<String, dynamic>> _mockMessages = [
    {
      'sender': 'John',
      'text': 'Hey everyone! Welcome to the group chat!',
      'time': '10:30 AM',
      'color': Colors.deepPurple,
    },
    {
      'sender': 'Emma',
      'text': 'Thanks for creating this group, John!',
      'time': '10:31 AM',
      'color': Colors.orange,
    },
    {
      'sender': 'Michael',
      'text': 'Great to be here. I was thinking we should start planning the project this week.',
      'time': '10:33 AM',
      'color': Colors.blue,
    },
    {
      'sender': 'You',
      'text': 'I agree with Michael. We should set up a project timeline.',
      'time': '10:34 AM',
      'color': null,
    },
    {
      'sender': 'Sophia',
      'text': 'I can help with the design aspects of the project.',
      'time': '10:35 AM',
      'color': Colors.pink,
    },
    {
      'sender': 'Daniel',
      'text': 'And I can handle the backend development.',
      'time': '10:36 AM',
      'color': Colors.green,
    },
    {
      'sender': 'John',
      'text': 'Perfect! This is coming together nicely.',
      'time': '10:37 AM',
      'color': Colors.deepPurple,
    },
    {
      'sender': 'Emma',
      'text': 'Should we schedule a video call to discuss further?',
      'time': '10:38 AM',
      'color': Colors.orange,
    },
    {
      'sender': 'You',
      'text': 'Good idea. How about tomorrow at 3 PM?',
      'time': '10:39 AM',
      'color': null,
    },
    {
      'sender': 'Michael',
      'text': 'Works for me!',
      'time': '10:40 AM',
      'color': Colors.blue,
    },
    {
      'sender': 'Sophia',
      'text': 'I\'ll be there.',
      'time': '10:41 AM',
      'color': Colors.pink,
    },
    {
      'sender': 'Daniel',
      'text': 'Count me in too.',
      'time': '10:42 AM',
      'color': Colors.green,
    },
  ];

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void initState() {
    super.initState();
    // Scroll to bottom after rendering is complete
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _sendMessage() {
    if (_messageController.text.trim().isEmpty) return;

    setState(() {
      _mockMessages.add({
        'sender': 'You',
        'text': _messageController.text.trim(),
        'time': '${DateTime.now().hour}:${DateTime.now().minute} ${DateTime.now().hour >= 12 ? 'PM' : 'AM'}',
        'color': null,
      });
      _messageController.clear();
    });

    // Scroll to the bottom after adding a new message
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });
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
                color: _getGroupColor(widget.groupIndex),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.group,
                color: Colors.white,
                size: 20,
              ),
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
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.videocam, color: Colors.white),
            onPressed: () {
              // Implement video call functionality
            },
          ),
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onPressed: () {
              // Show group options
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
            // Group info banner
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              color: Colors.grey[200],
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 16, color: Colors.grey),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'You\'re chatting with ${widget.groupName}. Tap here to view group info.',
                      style: TextStyle(
                        color: Colors.grey[700],
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            
            // Chat messages
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 20),
                itemCount: _mockMessages.length,
                itemBuilder: (context, index) {
                  final message = _mockMessages[index];
                  final isMe = message['sender'] == 'You';
                  
                  return _buildMessageBubble(
                    sender: message['sender'],
                    message: message['text'],
                    time: message['time'],
                    isMe: isMe,
                    senderColor: message['color'],
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
  
  // Check if we should show the sender name (show it for first message or when sender changes)
  bool _shouldShowSender(int index) {
    if (index == 0) return true;
    final currentSender = _mockMessages[index]['sender'];
    final previousSender = _mockMessages[index - 1]['sender'];
    return currentSender != previousSender;
  }

  Widget _buildMessageBubble({
    required String sender,
    required String message,
    required String time,
    required bool isMe,
    Color? senderColor,
    required bool showSender,
  }) {
    final Color messageColor = isMe ? _primaryColor : Colors.white;
    final Color textColor = isMe ? Colors.white : Colors.black87;
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
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
            mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isMe)
                Container(
                  width: 30,
                  height: 30,
                  margin: const EdgeInsets.only(right: 8, bottom: 5),
                  decoration: BoxDecoration(
                    color: senderColor ?? _getGroupColor(widget.groupIndex),
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
                    color: messageColor,
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
                          color: textColor,
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
        ],
      ),
    );
  }
}
