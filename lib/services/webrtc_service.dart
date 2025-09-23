import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'signaling_service.dart';

class WebRTCService {
  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _dataChannel;
  final SignalingService _signalingService = SignalingService();

  // Stream controllers for UI updates
  final StreamController<Map<String, dynamic>> _messageStreamController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<String> _connectionStateController =
      StreamController<String>.broadcast();
  final StreamController<List<String>> _peersController =
      StreamController<List<String>>.broadcast();
  final StreamController<Map<String, dynamic>> _typingStreamController =
      StreamController<Map<String, dynamic>>.broadcast();

  // Public streams
  Stream<Map<String, dynamic>> get messageStream =>
      _messageStreamController.stream;
  Stream<String> get connectionStateStream => _connectionStateController.stream;
  Stream<List<String>> get peersStream => _peersController.stream;
  Stream<Map<String, dynamic>> get typingStream =>
      _typingStreamController.stream;

  String? _currentRoom;
  String? _localUserName;
  final List<String> _connectedPeers = [];
  Timer? _reconnectionTimer;
  int _reconnectionAttempts = 0;
  static const int maxReconnectionAttempts = 5;
  bool _isDisposed = false;

  // WebRTC Configuration
  final Map<String, dynamic> _configuration = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ],
    'sdpSemantics': 'unified-plan',
  };

  bool get isConnected =>
      _peerConnection?.connectionState ==
      RTCPeerConnectionState.RTCPeerConnectionStateConnected;
  List<String> get connectedPeers => List.from(_connectedPeers);

  /// Initialize WebRTC service and join a room
  Future<void> initialize(String userName, String roomCode) async {
    if (_isDisposed) return;

    try {
      _localUserName = userName;
      _currentRoom = roomCode;
      _reconnectionAttempts = 0;

      // Initialize signaling service
      await _signalingService.initialize();
      _setupSignalingListeners();

      // Join room through signaling
      await _signalingService.joinRoom(roomCode, userName);

      _connectionStateController.add('Initializing...');
    } catch (e) {
      debugPrint('WebRTC initialization error: $e');
      _connectionStateController.add('Failed to initialize');
      _attemptReconnection();
    }
  }

  /// Attempt to reconnect after connection failure
  void _attemptReconnection() {
    if (_isDisposed || _reconnectionAttempts >= maxReconnectionAttempts) {
      _connectionStateController.add(
        'Connection failed - max attempts reached',
      );
      return;
    }

    _reconnectionAttempts++;
    _connectionStateController.add(
      'Reconnecting... ($_reconnectionAttempts/$maxReconnectionAttempts)',
    );

    _reconnectionTimer = Timer(
      Duration(seconds: _reconnectionAttempts * 2),
      () {
        if (!_isDisposed && _localUserName != null && _currentRoom != null) {
          initialize(_localUserName!, _currentRoom!);
        }
      },
    );
  }

  /// Setup listeners for signaling events
  void _setupSignalingListeners() {
    _signalingService.onPeerJoined = (peerId, userName) async {
      debugPrint('Peer joined: $peerId ($userName)');
      if (!_connectedPeers.contains(userName)) {
        _connectedPeers.add(userName);
        _peersController.add(List.from(_connectedPeers));
      }

      // Create offer for new peer
      await _createPeerConnection();
      await _createOffer(peerId);
    };

    _signalingService.onPeerLeft = (peerId, userName) {
      debugPrint('Peer left: $peerId ($userName)');
      _connectedPeers.remove(userName);
      _peersController.add(List.from(_connectedPeers));
    };

    _signalingService.onOfferReceived = (peerId, offer) async {
      debugPrint('Offer received from: $peerId');
      await _createPeerConnection();
      await _handleOffer(peerId, offer);
    };

    _signalingService.onAnswerReceived = (peerId, answer) async {
      debugPrint('Answer received from: $peerId');
      await _handleAnswer(answer);
    };

    _signalingService.onIceCandidateReceived = (peerId, candidate) async {
      debugPrint('ICE candidate received from: $peerId');
      await _handleIceCandidate(candidate);
    };
  }

  /// Create peer connection
  Future<void> _createPeerConnection() async {
    if (_peerConnection != null) return;

    try {
      _peerConnection = await createPeerConnection(_configuration);

      // Setup connection state listener
      _peerConnection!.onConnectionState = (RTCPeerConnectionState state) {
        if (_isDisposed) return;

        debugPrint('Connection state changed: $state');
        switch (state) {
          case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
            _connectionStateController.add('Connected');
            _reconnectionAttempts =
                0; // Reset attempts on successful connection
            break;
          case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
            _connectionStateController.add('Disconnected');
            _attemptReconnection();
            break;
          case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
            _connectionStateController.add('Connection failed');
            _attemptReconnection();
            break;
          case RTCPeerConnectionState.RTCPeerConnectionStateConnecting:
            _connectionStateController.add('Connecting...');
            break;
          default:
            _connectionStateController.add('Connecting...');
        }
      };

      // Setup ICE candidate listener
      _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
        debugPrint('ICE candidate generated');
        // For now, send to all connected peers - in a full P2P implementation
        // this would be more targeted
        for (String peerId in _connectedPeers) {
          _signalingService.sendIceCandidate(_currentRoom!, peerId, candidate);
        }
      };

      // Create data channel
      _dataChannel = await _peerConnection!.createDataChannel(
        'messages',
        RTCDataChannelInit()..ordered = true,
      );

      _setupDataChannelListeners();

      // Handle incoming data channels
      _peerConnection!.onDataChannel = (RTCDataChannel channel) {
        debugPrint('Data channel received: ${channel.label}');
        _setupDataChannelListeners(channel);
      };
    } catch (e) {
      debugPrint('Error creating peer connection: $e');
      _connectionStateController.add('Failed to connect');
    }
  }

  /// Setup data channel listeners
  void _setupDataChannelListeners([RTCDataChannel? channel]) {
    final dataChannel = channel ?? _dataChannel;
    if (dataChannel == null) return;

    dataChannel.onDataChannelState = (RTCDataChannelState state) {
      debugPrint('Data channel state: $state');
    };

    dataChannel.onMessage = (RTCDataChannelMessage message) {
      try {
        final data = json.decode(message.text);
        final messageType = data['type'] as String? ?? 'message';

        debugPrint('Data received: $data');

        switch (messageType) {
          case 'message':
            _messageStreamController.add({
              'user': data['user'] ?? 'Unknown',
              'text': data['text'] ?? '',
              'timestamp': DateTime.now().millisecondsSinceEpoch,
              'isOwn': false,
            });
            break;
          case 'typing':
            _typingStreamController.add({
              'user': data['user'] ?? 'Unknown',
              'isTyping': data['isTyping'] ?? false,
            });
            break;
          default:
            debugPrint('Unknown message type: $messageType');
        }
      } catch (e) {
        debugPrint('Error parsing received message: $e');
      }
    };
  }

  /// Create and send offer
  Future<void> _createOffer(String peerId) async {
    if (_peerConnection == null) return;

    try {
      final offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);

      await _signalingService.sendOffer(_currentRoom!, peerId, offer);
    } catch (e) {
      debugPrint('Error creating offer: $e');
    }
  }

  /// Handle incoming offer
  Future<void> _handleOffer(String peerId, RTCSessionDescription offer) async {
    if (_peerConnection == null) return;

    try {
      await _peerConnection!.setRemoteDescription(offer);

      final answer = await _peerConnection!.createAnswer();
      await _peerConnection!.setLocalDescription(answer);

      await _signalingService.sendAnswer(_currentRoom!, peerId, answer);
    } catch (e) {
      debugPrint('Error handling offer: $e');
    }
  }

  /// Handle incoming answer
  Future<void> _handleAnswer(RTCSessionDescription answer) async {
    if (_peerConnection == null) return;

    try {
      await _peerConnection!.setRemoteDescription(answer);
    } catch (e) {
      debugPrint('Error handling answer: $e');
    }
  }

  /// Handle incoming ICE candidate
  Future<void> _handleIceCandidate(RTCIceCandidate candidate) async {
    if (_peerConnection == null) return;

    try {
      await _peerConnection!.addCandidate(candidate);
    } catch (e) {
      debugPrint('Error adding ICE candidate: $e');
    }
  }

  /// Send message to connected peers
  Future<void> sendMessage(String message) async {
    if (_dataChannel == null || _localUserName == null) {
      debugPrint('Data channel not ready or user name not set');
      return;
    }

    try {
      final messageData = {
        'type': 'message',
        'user': _localUserName!,
        'text': message,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      final jsonMessage = json.encode(messageData);

      if (_dataChannel!.state == RTCDataChannelState.RTCDataChannelOpen) {
        await _dataChannel!.send(RTCDataChannelMessage(jsonMessage));
        debugPrint('Message sent: $message');

        // Add to local message stream
        _messageStreamController.add({
          'user': _localUserName!,
          'text': message,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'isOwn': true,
        });
      } else {
        debugPrint('Data channel not open, state: ${_dataChannel!.state}');
      }
    } catch (e) {
      debugPrint('Error sending message: $e');
    }
  }

  /// Send typing indicator to connected peers
  Future<void> sendTypingIndicator(bool isTyping) async {
    if (_dataChannel == null || _localUserName == null) return;

    try {
      final typingData = {
        'type': 'typing',
        'user': _localUserName!,
        'isTyping': isTyping,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      final jsonMessage = json.encode(typingData);

      if (_dataChannel!.state == RTCDataChannelState.RTCDataChannelOpen) {
        await _dataChannel!.send(RTCDataChannelMessage(jsonMessage));
        debugPrint('Typing indicator sent: $isTyping');
      }
    } catch (e) {
      debugPrint('Error sending typing indicator: $e');
    }
  }

  /// Leave current room and cleanup
  Future<void> leaveRoom() async {
    try {
      if (_currentRoom != null) {
        await _signalingService.leaveRoom(_currentRoom!);
      }
      await cleanup();
    } catch (e) {
      debugPrint('Error leaving room: $e');
    }
  }

  /// Cleanup resources
  Future<void> cleanup() async {
    try {
      await _dataChannel?.close();
      await _peerConnection?.close();
      await _signalingService.disconnect();

      _dataChannel = null;
      _peerConnection = null;
      _currentRoom = null;
      _localUserName = null;
      _connectedPeers.clear();

      _connectionStateController.add('Disconnected');
      _peersController.add([]);
    } catch (e) {
      debugPrint('Error during cleanup: $e');
    }
  }

  /// Dispose of the service
  void dispose() {
    _isDisposed = true;
    _reconnectionTimer?.cancel();
    _messageStreamController.close();
    _connectionStateController.close();
    _peersController.close();
    _typingStreamController.close();
    cleanup();
  }
}
