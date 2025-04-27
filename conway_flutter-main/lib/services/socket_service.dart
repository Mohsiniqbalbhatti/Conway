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
  final StreamController<Map<String, dynamic>> _messageController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<String> _messageExpiredController =
      StreamController<String>.broadcast();
  final StreamController<Map<String, dynamic>> _messageSentController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get onMessageReceived =>
      _messageController.stream;
  Stream<String> get onMessageExpired => _messageExpiredController.stream;
  Stream<Map<String, dynamic>> get onMessageSent =>
      _messageSentController.stream;

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
  }

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
      _socket!.emit('sendMessage', messagePayload);
    } else {
      print('[SocketService] Cannot send message: Socket not connected.');
    }
  }

  void disconnect() {
    print(
      "[SocketService] disconnect() called. Disposing socket for userId: $_userId",
    );
    _userId = null; // Clear userId on explicit disconnect
    _socket?.dispose();
    _socket = null;
  }
}
