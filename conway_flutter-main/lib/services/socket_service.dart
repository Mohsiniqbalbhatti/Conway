import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'dart:async';
import '../constants/api_config.dart'; // For base URL

class SocketService {
  // --- Singleton Setup ---
  static final SocketService _instance = SocketService._internal();
  factory SocketService() {
    return _instance;
  }
  SocketService._internal();
  // --- End Singleton Setup ---

  IO.Socket? _socket;
  // Streams for Direct Messages
  final StreamController<Map<String, dynamic>> _messageController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<String> _messageExpiredController =
      StreamController<String>.broadcast();
  final StreamController<Map<String, dynamic>> _messageSentController =
      StreamController<Map<String, dynamic>>.broadcast();

  // Streams for Group Messages (NEW)
  final StreamController<Map<String, dynamic>> _groupMessageController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _groupMessageSentController =
      StreamController<Map<String, dynamic>>.broadcast();

  // NEW Stream for Group Message Expiry
  final StreamController<Map<String, dynamic>> _groupMessageExpiredController =
      StreamController<Map<String, dynamic>>.broadcast();

  // NEW Stream for Group Message Deletion
  final StreamController<Map<String, dynamic>> _groupMessageDeletedController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get onMessageReceived =>
      _messageController.stream;
  Stream<String> get onMessageExpired => _messageExpiredController.stream;
  Stream<Map<String, dynamic>> get onMessageSent =>
      _messageSentController.stream;

  // Public Streams for Group Messages (NEW)
  Stream<Map<String, dynamic>> get onGroupMessageReceived =>
      _groupMessageController.stream;
  Stream<Map<String, dynamic>> get onGroupMessageSent =>
      _groupMessageSentController.stream;

  // NEW Public Stream for Group Message Expiry
  Stream<Map<String, dynamic>> get onGroupMessageExpired =>
      _groupMessageExpiredController.stream;

  // NEW Public Stream for Group Message Deletion
  Stream<Map<String, dynamic>> get onGroupMessageDeleted =>
      _groupMessageDeletedController.stream;

  String? _userId;
  bool get isConnected => _socket?.connected ?? false;

  void connect(String userId) {
    if (userId.isEmpty) {
      print("[SocketService] Connect called with empty userId. Aborting.");
      return;
    }

    // If trying to connect for the *same* user and already connected, ensure join is emitted.
    if (_userId == userId && isConnected) {
      print(
        "[SocketService] Already connected for user $userId. Re-emitting join event.",
      );
      _socket!.emit(
        'join',
        _userId,
      ); // Re-emit join just in case state is inconsistent
      return;
    }

    // If switching users or connecting for the first time/after disconnect
    print(
      "[SocketService] Attempting to connect/reconnect for user: $userId (Previous userId: $_userId)",
    );
    _userId = userId; // Set userId *before* initiating connection attempt

    // Ensure previous socket is disposed if exists
    if (_socket != null) {
      print("[SocketService] Disposing existing socket before new connection.");
      _socket!.dispose();
      _socket = null;
    }

    try {
      final uri = Uri.parse(ApiConfig.baseUrl);
      final socketUrl = '${uri.scheme}://${uri.host}:${uri.port}';
      print('[SocketService] Connecting socket to: $socketUrl');

      _socket = IO.io(socketUrl, <String, dynamic>{
        'transports': ['websocket'],
        'autoConnect': false, // Connect manually after listeners are set
        'reconnection': true,
        'reconnectionAttempts': 5,
        'reconnectionDelay': 1000,
        // 'forceNew': true, // Might be needed if reconnection issues persist
      });

      // Setup listeners BEFORE connecting
      _setupListeners();

      // Manually connect
      print('[SocketService] Calling socket.connect()...');
      _socket!.connect();
    } catch (e) {
      print('[SocketService] Socket connection exception: $e');
    }
  }

  void _setupListeners() {
    if (_socket == null) {
      print('[SocketService setupListeners] Error: Socket is null.');
      return;
    }

    // Remove previous listeners to avoid duplicates
    _socket!.off('connect');
    _socket!.off('connect_error');
    _socket!.off('error');
    _socket!.off('disconnect');
    _socket!.off('receiveMessage');
    _socket!.off('messageError');
    _socket!.off('messageSent');
    _socket!.off('messageExpired');
    _socket!.off('messageSentConfirmation');
    // Add new group listeners
    _socket!.off('receiveGroupMessage');
    _socket!.off('groupMessageSent');
    _socket!.off('groupMessageExpired');
    _socket!.off('groupMessageDeleted');

    _socket!.onConnect((_) {
      print('[SocketService ON connect] Socket connected! ID: ${_socket?.id}');
      if (_userId != null && _userId!.isNotEmpty) {
        print(
          '[SocketService ON connect] Emitting join event for userId: $_userId',
        );
        _socket!.emit('join', _userId);
      } else {
        print(
          '[SocketService ON connect] Warning: Cannot emit join, userId is null or empty.',
        );
      }
    });

    _socket!.onConnectError(
      (data) => print('[SocketService ON connect_error] Error: $data'),
    );
    _socket!.onError((data) => print('[SocketService ON error] Error: $data'));
    _socket!.onDisconnect((reason) {
      print('[SocketService ON disconnect] Disconnected. Reason: $reason');
      // No need to manually clear _userId here, connect() handles it if needed
    });

    _socket!.on('receiveMessage', (data) {
      print('[SocketService ON receiveMessage] Raw Data Received: $data');
      if (data is Map<String, dynamic>) {
        print(
          '[SocketService ON receiveMessage] Pushing data to stream controller...',
        );
        _messageController.add(data);
      } else {
        print(
          '[SocketService ON receiveMessage] Received invalid message format',
        );
      }
    });

    // --- NEW Group Message Listener ---
    _socket!.on('receiveGroupMessage', (data) {
      print('[SocketService ON receiveGroupMessage] Raw Data Received: $data');
      if (data is Map<String, dynamic>) {
        print(
          '[SocketService ON receiveGroupMessage] Pushing data to group stream controller...',
        );
        _groupMessageController.add(data);
      } else {
        print(
          '[SocketService ON receiveGroupMessage] Received invalid group message format',
        );
      }
    });
    // --- End NEW Group Message Listener ---

    _socket!.on('messageError', (data) {
      print('[SocketService ON messageError] Error from server: $data');
    });

    _socket!.on('messageSent', (data) {
      print(
        '[SocketService ON messageSent Confirmation] Raw Data Received: $data',
      );
      if (data is Map<String, dynamic>) {
        print(
          '[SocketService ON messageSent Confirmation] Pushing data to sent stream controller...',
        );
        _messageSentController.add(data);
      } else {
        print(
          '[SocketService ON messageSent Confirmation] Received invalid confirmation format',
        );
      }
    });

    // --- NEW Group Message Sent Confirmation Listener ---
    _socket!.on('groupMessageSent', (data) {
      print(
        '[SocketService ON groupMessageSent Confirmation] Raw Data Received: $data',
      );
      if (data is Map<String, dynamic>) {
        print(
          '[SocketService ON groupMessageSent Confirmation] Pushing data to group sent stream controller...',
        );
        _groupMessageSentController.add(data);
      } else {
        print(
          '[SocketService ON groupMessageSent Confirmation] Received invalid group confirmation format',
        );
      }
    });
    // --- End NEW Group Message Sent Confirmation Listener ---

    // --- NEW Group Message Expired Listener ---
    _socket!.on('groupMessageExpired', (data) {
      print('[SocketService ON groupMessageExpired] Raw Data Received: $data');
      if (data is Map<String, dynamic> &&
          data['messageId'] is String &&
          data['groupId'] is String) {
        print(
          '[SocketService ON groupMessageExpired] Pushing data to group expiry stream controller...',
        );
        _groupMessageExpiredController.add(
          data,
        ); // Pass the whole map (messageId, groupId)
      } else {
        print(
          '[SocketService ON groupMessageExpired] Received invalid group expiry format',
        );
      }
    });
    // --- End NEW Group Message Expired Listener ---

    // This handles direct message expiry
    _socket!.on('messageExpired', (data) {
      print('[SocketService ON messageExpired] Raw Data Received: $data');
      if (data is Map<String, dynamic> && data['messageId'] is String) {
        final messageId = data['messageId'] as String;
        print(
          '[SocketService ON messageExpired] Pushing message ID $messageId to expiry stream...',
        );
        _messageExpiredController.add(messageId);
      } else {
        print(
          '[SocketService ON messageExpired] Received invalid expiry data format',
        );
      }
    });

    // --- NEW Group Message Deleted Listener ---
    _socket!.on('groupMessageDeleted', (data) {
      print('[SocketService ON groupMessageDeleted] Raw Data Received: $data');
      if (data is Map<String, dynamic> &&
          data['messageId'] is String &&
          data['groupId'] is String) {
        print(
          '[SocketService ON groupMessageDeleted] Pushing data to group deletion stream controller...',
        );
        _groupMessageDeletedController.add(data); // Pass the whole map
      } else {
        print(
          '[SocketService ON groupMessageDeleted] Received invalid group deletion format',
        );
      }
    });
    // --- End NEW Group Message Deleted Listener ---
  }

  // --- Modified emit for General Purpose ---
  // Use this instead of specific sendMessage/sendGroupMessage methods
  void emit(String event, Map<String, dynamic> data) {
    if (isConnected) {
      print('[SocketService] Emitting event \'$event\' with data: $data');
      _socket!.emit(event, data);
    } else {
      print(
        '[SocketService] Cannot emit event \'$event\': Socket not connected.',
      );
      // Optionally queue the event or show an error
    }
  }

  // DEPRECATE specific sendMessage method in favor of generic emit
  /*
  void sendMessage({
    required String senderId,
    required String senderEmail,
    required String receiverEmail,
    required String plainMessageText,
    required String tempId,
    DateTime? burnoutDateTime,
    DateTime? scheduleDateTime,
  }) {
    if (isConnected) {
      print('[SocketService] Sending message via socket:');
      final messagePayload = {
        'senderId': senderId,
        'senderEmail': senderEmail,
        'receiverEmail': receiverEmail,
        'messageText': plainMessageText,
        'tempId': tempId,
        if (burnoutDateTime != null)
          'burnoutDateTime': burnoutDateTime.toIso8601String(),
        if (scheduleDateTime != null)
          'scheduleDateTime': scheduleDateTime.toIso8601String(),
      };
      print('[SocketService] Payload: $messagePayload');
      // Use the generic emit now
      emit('sendMessage', messagePayload);
      // _socket!.emit('sendMessage', messagePayload);
    } else {
      print('[SocketService] Cannot send message: Socket not connected.');
    }
  }
  */

  void disconnect() {
    print(
      "[SocketService] disconnect() called. Disposing socket for userId: $_userId",
    );
    _userId = null; // Clear userId on explicit disconnect
    _socket?.dispose();
    _socket = null;
  }

  // Close stream controllers when service is disposed (though as singleton, likely lives forever)
  void disposeStreams() {
    _messageController.close();
    _messageExpiredController.close();
    _messageSentController.close();
    _groupMessageController.close();
    _groupMessageSentController.close();
    _groupMessageExpiredController.close();
    _groupMessageDeletedController.close(); // Close the new controller
  }
}
