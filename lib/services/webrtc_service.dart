import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'signaling_service.dart';

class WebRTCService {
  final void Function(String user, String message)? onMessage;
  WebRTCService({this.onMessage});
  void handleOffer(dynamic data, String from) {
    if (data is RTCSessionDescription) {
      _handleOffer(from, data);
    } else if (data is Map<String, dynamic>) {
      final offer = RTCSessionDescription(
        data['sdp'] as String,
        data['type'] as String,
      );
      _handleOffer(from, offer);
    }
  }

  void handleAnswer(dynamic data, String from) {
    if (data is RTCSessionDescription) {
      _handleAnswer(from, data);
    } else if (data is Map<String, dynamic>) {
      final answer = RTCSessionDescription(
        data['sdp'] as String,
        data['type'] as String,
      );
      _handleAnswer(from, answer);
    }
  }

  void handleCandidate(dynamic data, String from) {
    if (data is RTCIceCandidate) {
      _handleIceCandidate(from, data);
    } else if (data is Map<String, dynamic>) {
      final candidate = RTCIceCandidate(
        data['candidate'] as String,
        data['sdpMid'] as String?,
        data['sdpMLineIndex'] as int?,
      );
      _handleIceCandidate(from, candidate);
    }
  }

  final Map<String, RTCPeerConnection> _peerConnections = {};
  final Map<String, RTCDataChannel> _dataChannels = {};
  // Legacy single-connection fields removed in favor of per-peer maps
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
  final StreamController<bool> _dataChannelOpenController =
      StreamController<bool>.broadcast();

  // Public streams
  Stream<Map<String, dynamic>> get messageStream =>
      _messageStreamController.stream;
  Stream<String> get connectionStateStream => _connectionStateController.stream;
  Stream<List<String>> get peersStream => _peersController.stream;
  Stream<Map<String, dynamic>> get typingStream =>
      _typingStreamController.stream;
  Stream<bool> get dataChannelOpenStream => _dataChannelOpenController.stream;

  String? _currentRoom;
  String? _localUserName;
  final List<String> _connectedPeers = [];
  final Map<String, String> _peerIdToName = {};
  final Map<String, List<String>> _pendingMessagesByPeer = {};
  Timer? _reconnectionTimer;
  int _reconnectionAttempts = 0;
  static const int maxReconnectionAttempts = 5;
  bool _isDisposed = false;
  bool _isDataChannelOpen = false;

  /// Helper: expose display name for a given peer id
  String getPeerDisplayName(String peerId) {
    return _peerIdToName[peerId] ?? peerId;
  }

  // WebRTC Configuration
  final Map<String, dynamic> _configuration = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ],
    'sdpSemantics': 'unified-plan',
  };

  bool get isConnected => _peerConnections.values.any(
    (pc) =>
        pc.connectionState ==
        RTCPeerConnectionState.RTCPeerConnectionStateConnected,
  );
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
      if (!_connectedPeers.contains(peerId)) {
        _connectedPeers.add(peerId);
        _peersController.add(List.from(_connectedPeers));
      }
      _peerIdToName[peerId] = userName;

      // Create new connection as initiator and send offer
      await _createPeerConnection(peerId, isInitiator: true);
      await _createOffer(peerId);
    };

    _signalingService.onPeerLeft = (peerId, userName) {
      debugPrint('Peer left: $peerId ($userName)');
      _connectedPeers.remove(peerId);
      _peerIdToName.remove(peerId);
      _peersController.add(List.from(_connectedPeers));
    };

    _signalingService.onOfferReceived = (peerId, offer) async {
      debugPrint('Offer received from: $peerId');
      await _createPeerConnection(peerId, isInitiator: false);
      await _handleOffer(peerId, offer);
    };

    _signalingService.onAnswerReceived = (peerId, answer) async {
      debugPrint('Answer received from: $peerId');
      await _handleAnswer(peerId, answer);
    };

    _signalingService.onIceCandidateReceived = (peerId, candidate) async {
      debugPrint('ICE candidate received from: $peerId');
      await _handleIceCandidate(peerId, candidate);
    };
  }

  /// Create peer connection for a specific peer
  Future<void> _createPeerConnection(
    String peerId, {
    required bool isInitiator,
  }) async {
    if (_peerConnections.containsKey(peerId)) return;

    try {
      final pc = await createPeerConnection(_configuration);
      _peerConnections[peerId] = pc;

      pc.onConnectionState = (RTCPeerConnectionState state) {
        if (_isDisposed) return;
        debugPrint('Connection state [$peerId] changed: $state');
        switch (state) {
          case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
            _connectionStateController.add('Connected');
            _reconnectionAttempts = 0;
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

      pc.onIceCandidate = (RTCIceCandidate candidate) {
        debugPrint('ICE candidate generated for $peerId');
        _signalingService.sendIceCandidate(_currentRoom!, peerId, candidate);
      };

      if (isInitiator) {
        final ch = await pc.createDataChannel(
          'messages',
          RTCDataChannelInit()..ordered = true,
        );
        _dataChannels[peerId] = ch;
        _setupDataChannelListenersForPeer(peerId, ch);
      }

      pc.onDataChannel = (RTCDataChannel channel) {
        debugPrint('Data channel received from $peerId: ${channel.label}');
        _dataChannels[peerId] = channel;
        _setupDataChannelListenersForPeer(peerId, channel);
      };
    } catch (e) {
      debugPrint('Error creating peer connection for $peerId: $e');
      _connectionStateController.add('Failed to connect');
    }
  }

  /// Setup data channel listeners for a specific peer
  void _setupDataChannelListenersForPeer(
    String peerId,
    RTCDataChannel dataChannel,
  ) {
    dataChannel.onDataChannelState = (RTCDataChannelState state) {
      debugPrint('Data channel state: $state');
      _isDataChannelOpen = state == RTCDataChannelState.RTCDataChannelOpen
          ? true
          : false;
      _dataChannelOpenController.add(_isDataChannelOpen);

      if (_isDataChannelOpen) {
        final queue = _pendingMessagesByPeer[peerId] ?? const <String>[];
        for (final queued in List<String>.from(queue)) {
          dataChannel.send(RTCDataChannelMessage(queued)).catchError((_) {});
          _pendingMessagesByPeer[peerId]?.remove(queued);
        }
      }
    };

    dataChannel.onMessage = (RTCDataChannelMessage message) {
      final displayName = _peerIdToName[peerId] ?? 'Peer';
      final raw = message.text;
      // Fast path: treat as plain text if it doesn't look like JSON
      final firstChar = raw.trimLeft().isNotEmpty ? raw.trimLeft()[0] : '';
      final looksLikeJson = firstChar == '{' || firstChar == '[';
      if (!looksLikeJson) {
        _messageStreamController.add({
          'user': displayName,
          'text': raw,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'isOwn': false,
        });
        if (onMessage != null) {
          onMessage!(displayName, raw);
        }
        return;
      }

      try {
        final data = json.decode(raw);
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
            if (onMessage != null) {
              onMessage!(data['user'] ?? 'Unknown', data['text'] ?? '');
            }
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
      } catch (_) {
        // If JSON parsing still fails, silently treat as text
        _messageStreamController.add({
          'user': displayName,
          'text': raw,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'isOwn': false,
        });
        if (onMessage != null) {
          onMessage!(displayName, raw);
        }
      }
    };
  }

  /// Create and send offer
  Future<void> _createOffer(String peerId) async {
    final pc = _peerConnections[peerId];
    if (pc == null) return;

    try {
      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);

      await _signalingService.sendOffer(_currentRoom!, peerId, offer);
    } catch (e) {
      debugPrint('Error creating offer: $e');
    }
  }

  /// Handle incoming offer
  Future<void> _handleOffer(String peerId, RTCSessionDescription offer) async {
    final pc = _peerConnections[peerId];
    if (pc == null) return;

    try {
      await pc.setRemoteDescription(offer);

      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);

      await _signalingService.sendAnswer(_currentRoom!, peerId, answer);
    } catch (e) {
      debugPrint('Error handling offer: $e');
    }
  }

  /// Handle incoming answer
  Future<void> _handleAnswer(
    String peerId,
    RTCSessionDescription answer,
  ) async {
    final pc = _peerConnections[peerId];
    if (pc == null) return;

    try {
      await pc.setRemoteDescription(answer);
    } catch (e) {
      debugPrint('Error handling answer: $e');
    }
  }

  /// Handle incoming ICE candidate
  Future<void> _handleIceCandidate(
    String peerId,
    RTCIceCandidate candidate,
  ) async {
    final pc = _peerConnections[peerId];
    if (pc == null) return;

    try {
      await pc.addCandidate(candidate);
    } catch (e) {
      debugPrint('Error adding ICE candidate: $e');
    }
  }

  /// Send message to connected peers
  Future<void> sendMessage(String message) async {
    if (_localUserName == null) {
      debugPrint('User name not set');
      return;
    }

    try {
      // Send to all open peer data channels; queue per peer otherwise
      for (final entry in _dataChannels.entries) {
        final peerId = entry.key;
        final ch = entry.value;
        if (ch.state == RTCDataChannelState.RTCDataChannelOpen) {
          await ch.send(RTCDataChannelMessage(message));
        } else {
          (_pendingMessagesByPeer[peerId] ??= []).add(message);
        }
      }

      // Add to local message stream once (as own message)
      _messageStreamController.add({
        'user': _localUserName!,
        'text': message,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'isOwn': true,
      });
    } catch (e) {
      debugPrint('Error sending message: $e');
    }
  }

  /// Send typing indicator to connected peers
  Future<void> sendTypingIndicator(bool isTyping) async {
    if (_localUserName == null) return;

    try {
      final typingData = {
        'type': 'typing',
        'user': _localUserName!,
        'isTyping': isTyping,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      final jsonMessage = json.encode(typingData);

      for (final ch in _dataChannels.values) {
        if (ch.state == RTCDataChannelState.RTCDataChannelOpen) {
          await ch.send(RTCDataChannelMessage(jsonMessage));
        }
      }
      debugPrint('Typing indicator sent: $isTyping');
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
      for (final ch in _dataChannels.values) {
        await ch.close();
      }
      for (final pc in _peerConnections.values) {
        await pc.close();
      }
      _dataChannels.clear();
      _peerConnections.clear();
      await _signalingService.disconnect();

      // Legacy fields removed
      _currentRoom = null;
      _localUserName = null;
      _connectedPeers.clear();
      _pendingMessagesByPeer.clear();

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
