import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../config/webrtc_config.dart';

class SignalingService {
  WebSocketChannel? _channel;
  String? _currentRoom;
  String? _localUserId;

  // Callbacks for WebRTC events
  Function(String peerId, String userName)? onPeerJoined;
  Function(String peerId, String userName)? onPeerLeft;
  Function(String peerId, RTCSessionDescription offer)? onOfferReceived;
  Function(String peerId, RTCSessionDescription answer)? onAnswerReceived;
  Function(String peerId, RTCIceCandidate candidate)? onIceCandidateReceived;

  // Auto-configured signaling server URLs (from WebRTCConfig)
  static String get _signalingServerUrl => WebRTCConfig.signalingUrl;
  static String get _fallbackUrl => WebRTCConfig.fallbackSignalingUrl;
  bool get isConnected => _channel != null;

  /// Initialize signaling service
  Future<void> initialize() async {
    try {
      // Generate unique user ID
      _localUserId = DateTime.now().millisecondsSinceEpoch.toString();

      // Try to connect to signaling server, fallback to echo service
      await _connectToSignalingServer();
    } catch (e) {
      debugPrint('Signaling service initialization error: $e');
      rethrow;
    }
  }

  /// Connect to signaling server
  Future<void> _connectToSignalingServer() async {
    try {
      // First try the actual signaling server
      _channel = WebSocketChannel.connect(Uri.parse(_signalingServerUrl));
      debugPrint('Connected to signaling server');
    } catch (e) {
      debugPrint('Failed to connect to signaling server, using fallback: $e');

      // Fallback to echo service (for basic testing)
      try {
        _channel = WebSocketChannel.connect(Uri.parse(_fallbackUrl));
        debugPrint('Connected to fallback WebSocket service');
      } catch (fallbackError) {
        debugPrint('Failed to connect to fallback service: $fallbackError');
        rethrow;
      }
    }

    // Setup message listener
    _channel!.stream.listen(
      _handleSignalingMessage,
      onError: (error) {
        debugPrint('WebSocket error: $error');
      },
      onDone: () {
        debugPrint('WebSocket connection closed');
        _channel = null;
      },
    );

    // Send initial connection message
    _sendMessage({'type': 'connect', 'userId': _localUserId});
  }

  /// Handle incoming signaling messages
  void _handleSignalingMessage(dynamic data) {
    try {
      Map<String, dynamic> message;

      if (data is String) {
        // Try to parse as JSON
        try {
          message = json.decode(data);
        } catch (e) {
          // If it's not JSON, it might be an echo from fallback service
          debugPrint('Received echo message: $data');
          return;
        }
      } else {
        message = data as Map<String, dynamic>;
      }

      final messageType = message['type'] as String?;
      if (messageType == null) return;

      switch (messageType) {
        // Handle initial connection response with our ID and existing peers
        case 'id':
          final myId = message['id'] as String?;
          if (myId != null) {
            _localUserId = myId;
          }

          final peers = message['peers'] as List?;
          if (peers != null) {
            for (var peer in peers) {
              final peerId = peer['id'] as String?;
              final userName = peer['name'] as String?;
              if (peerId != null && userName != null) {
                onPeerJoined?.call(peerId, userName);
              }
            }
          }
          break;

        // Updated to match your Python server protocol
        case 'peer-connected':
          final peerId = message['id'] as String?;
          final userName = message['name'] as String?;
          if (peerId != null && userName != null) {
            onPeerJoined?.call(peerId, userName);
          }
          break;

        case 'peer-disconnected':
          final peerId = message['id'] as String?;
          final userName = message['name'] as String?;
          if (peerId != null && userName != null) {
            onPeerLeft?.call(peerId, userName);
          }
          break;

        // Handle WebRTC signaling messages
        case 'signal':
          final signalData = message['signal'] as Map<String, dynamic>?;
          final fromPeer = message['from'] as String?;

          if (signalData != null && fromPeer != null) {
            final signalType = signalData['type'] as String?;

            switch (signalType) {
              case 'offer':
                final offerData = signalData['offer'] as Map<String, dynamic>?;
                if (offerData != null) {
                  final offer = RTCSessionDescription(
                    offerData['sdp'] as String,
                    offerData['type'] as String,
                  );
                  onOfferReceived?.call(fromPeer, offer);
                }
                break;

              case 'answer':
                final answerData =
                    signalData['answer'] as Map<String, dynamic>?;
                if (answerData != null) {
                  final answer = RTCSessionDescription(
                    answerData['sdp'] as String,
                    answerData['type'] as String,
                  );
                  onAnswerReceived?.call(fromPeer, answer);
                }
                break;

              case 'ice-candidate':
                final candidateData =
                    signalData['candidate'] as Map<String, dynamic>?;
                if (candidateData != null) {
                  final candidate = RTCIceCandidate(
                    candidateData['candidate'] as String,
                    candidateData['sdpMid'] as String?,
                    candidateData['sdpMLineIndex'] as int?,
                  );
                  onIceCandidateReceived?.call(fromPeer, candidate);
                }
                break;
            }
          }
          break;

        case 'room-joined':
          debugPrint('Successfully joined room: ${message['room']}');
          break;

        case 'error':
          debugPrint('Signaling error: ${message['message']}');
          break;

        default:
          debugPrint('Unknown message type: $messageType');
      }
    } catch (e) {
      debugPrint('Error handling signaling message: $e');
    }
  }

  /// Join a room (Updated for Python server protocol)
  Future<void> joinRoom(String roomCode, String userName) async {
    if (_channel == null) {
      throw Exception('Not connected to signaling server');
    }

    _currentRoom = roomCode;

    // Updated message format to match your Python server
    _sendMessage({'type': 'join', 'room': roomCode, 'name': userName});

    debugPrint('Joining room: $roomCode as $userName');
  }

  /// Leave current room
  Future<void> leaveRoom(String roomCode) async {
    if (_channel == null) return;

    _sendMessage({
      'type': 'leave-room',
      'room': roomCode,
      'userId': _localUserId,
    });

    _currentRoom = null;
    debugPrint('Left room: $roomCode');
  }

  /// Send offer to peer (Updated for Python server protocol)
  Future<void> sendOffer(
    String roomCode,
    String peerId,
    RTCSessionDescription offer,
  ) async {
    _sendMessage({
      'type': 'signal',
      'to': peerId,
      'signal': {
        'type': 'offer',
        'offer': {'sdp': offer.sdp, 'type': offer.type},
      },
    });
  }

  /// Send answer to peer (Updated for Python server protocol)
  Future<void> sendAnswer(
    String roomCode,
    String peerId,
    RTCSessionDescription answer,
  ) async {
    _sendMessage({
      'type': 'signal',
      'to': peerId,
      'signal': {
        'type': 'answer',
        'answer': {'sdp': answer.sdp, 'type': answer.type},
      },
    });
  }

  /// Send ICE candidate to peer (Updated for Python server protocol)
  Future<void> sendIceCandidate(
    String roomCode,
    String peerId,
    RTCIceCandidate candidate,
  ) async {
    _sendMessage({
      'type': 'signal',
      'to': peerId,
      'signal': {
        'type': 'ice-candidate',
        'candidate': {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        },
      },
    });
  }

  /// Send message through WebSocket
  void _sendMessage(Map<String, dynamic> message) {
    if (_channel == null) {
      debugPrint('Cannot send message: not connected to signaling server');
      return;
    }

    try {
      final jsonMessage = json.encode(message);
      _channel!.sink.add(jsonMessage);
      debugPrint('Sent signaling message: ${message['type']}');
    } catch (e) {
      debugPrint('Error sending message: $e');
    }
  }

  /// Disconnect from signaling server
  Future<void> disconnect() async {
    try {
      if (_currentRoom != null) {
        await leaveRoom(_currentRoom!);
      }

      await _channel?.sink.close(status.goingAway);
      _channel = null;
      _currentRoom = null;
      _localUserId = null;

      debugPrint('Disconnected from signaling server');
    } catch (e) {
      debugPrint('Error disconnecting: $e');
    }
  }
}
