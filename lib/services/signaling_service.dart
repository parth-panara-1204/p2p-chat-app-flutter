import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../config/webrtc_config.dart';

class SignalingService {
  /// Dispose of the service and close the WebSocket connection
  void dispose() {
    disconnect();
  }

  /// Public method to start the connection (calls initialize)
  Future<void> connect() async {
    await initialize();
  }

  /// Send a generic signaling message to a peer
  void sendSignal(String type, dynamic data, String to) {
    if (_channel == null) {
      debugPrint('Cannot send signal: not connected to signaling server');
      return;
    }
    final signalMessage = {
      'type': 'signal',
      'to': to,
      'from': _localUserId,
      'signal': {'type': type, ...data is Map<String, dynamic> ? data : {}},
    };
    try {
      final jsonMessage = json.encode(signalMessage);
      _channel!.sink.add(jsonMessage);
      debugPrint('Sent signal: $type to $to');
    } catch (e) {
      debugPrint('Error sending signal: $e');
    }
  }

  final String? userName;
  final String? roomCode;
  final void Function(List<String>)? onPeerList;
  final void Function(String)? onConnectionState;
  final void Function(String type, dynamic data, String from)? onSignal;
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
  bool get isConnected => _channel != null;

  /// Constructor with named parameters
  SignalingService({
    this.userName,
    this.roomCode,
    this.onPeerList,
    this.onConnectionState,
    this.onSignal,
    this.onPeerJoined,
    this.onPeerLeft,
    this.onOfferReceived,
    this.onAnswerReceived,
    this.onIceCandidateReceived,
  }) {}

  /// Initialize signaling service
  Future<void> initialize() async {
    try {
      // Generate unique user ID
      _localUserId = DateTime.now().millisecondsSinceEpoch.toString();

      // Try to connect to signaling server, fallback to echo service
      await _connectToSignalingServer();

      // Auto-join room if parameters provided
      if (roomCode != null && userName != null) {
        await joinRoom(roomCode!, userName!);
      }
    } catch (e) {
      debugPrint('Signaling service initialization error: $e');
      rethrow;
    }
  }

  /// Connect to signaling server
  Future<void> _connectToSignalingServer() async {
    try {
      _channel = WebSocketChannel.connect(Uri.parse(_signalingServerUrl));
      debugPrint('Connected to signaling server');
      onConnectionState?.call('Connected');
    } catch (e) {
      debugPrint('Failed to connect to signaling server: $e');
      onConnectionState?.call('Disconnected');
      rethrow;
    }

    // Setup message listener
    _channel!.stream.listen(
      _handleSignalingMessage,
      onError: (error) {
        debugPrint('WebSocket error: $error');
        onConnectionState?.call('Error');
      },
      onDone: () {
        debugPrint('WebSocket connection closed');
        _channel = null;
        onConnectionState?.call('Disconnected');
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
            // Notify peer list callback
            if (onPeerList != null) {
              final peerIds = <String>[];
              for (var peer in peers) {
                final peerId = peer['id'] as String?;
                if (peerId != null) peerIds.add(peerId);
              }
              onPeerList!(peerIds);
            }
            // Also call onPeerJoined for each peer
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
          final fromPeer = message['from'] as String?;
          final signalData = message['signal'] as Map<String, dynamic>?;

          // Path A: nested 'signal' present
          if (signalData != null && fromPeer != null) {
            final signalType = signalData['type'] as String?;

            if (onSignal != null) {
              onSignal!(signalType ?? '', signalData, fromPeer);
            }

            switch (signalType) {
              case 'offer':
                final offerData =
                    (signalData['offer'] as Map<String, dynamic>?) ??
                    <String, dynamic>{
                      'sdp': signalData['sdp'],
                      'type': signalData['sdpType'],
                    };
                if (offerData['sdp'] != null && offerData['type'] != null) {
                  final offer = RTCSessionDescription(
                    offerData['sdp'] as String,
                    offerData['type'] as String,
                  );
                  onOfferReceived?.call(fromPeer, offer);
                }
                break;

              case 'answer':
                final answerData =
                    (signalData['answer'] as Map<String, dynamic>?) ??
                    <String, dynamic>{
                      'sdp': signalData['sdp'],
                      'type': signalData['sdpType'],
                    };
                if (answerData['sdp'] != null && answerData['type'] != null) {
                  final answer = RTCSessionDescription(
                    answerData['sdp'] as String,
                    answerData['type'] as String,
                  );
                  onAnswerReceived?.call(fromPeer, answer);
                }
                break;

              case 'ice-candidate':
              case 'candidate':
                final candidateData =
                    (signalData['candidate'] as Map<String, dynamic>?) ??
                    (signalData['iceCandidate'] as Map<String, dynamic>?);
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
            break;
          }

          // Path B: no nested 'signal'; use top-level 'sdp' or 'candidate'
          final topLevelSdp = message['sdp'];
          final topLevelCandidate = message['candidate'];
          if (fromPeer != null && topLevelSdp != null) {
            final sdpMap = topLevelSdp as Map<String, dynamic>;
            final desc = RTCSessionDescription(
              sdpMap['sdp'] as String,
              sdpMap['type'] as String,
            );
            if (desc.type == 'offer') {
              onOfferReceived?.call(fromPeer, desc);
            } else if (desc.type == 'answer') {
              onAnswerReceived?.call(fromPeer, desc);
            }
          }
          if (fromPeer != null && topLevelCandidate != null) {
            final c = topLevelCandidate as Map<String, dynamic>;
            final cand = RTCIceCandidate(
              c['candidate'] as String,
              c['sdpMid'] as String?,
              c['sdpMLineIndex'] as int?,
            );
            onIceCandidateReceived?.call(fromPeer, cand);
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
      'from': _localUserId,
      // Top-level SDP for compatibility with web clients expecting { sdp }
      'sdp': {'sdp': offer.sdp, 'type': offer.type},
      'signal': {
        'type': 'offer',
        'offer': {'sdp': offer.sdp, 'type': offer.type},
        // Compatibility for clients expecting flat fields
        'sdp': offer.sdp,
        'sdpType': offer.type,
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
      'from': _localUserId,
      // Top-level SDP for compatibility with web clients expecting { sdp }
      'sdp': {'sdp': answer.sdp, 'type': answer.type},
      'signal': {
        'type': 'answer',
        'answer': {'sdp': answer.sdp, 'type': answer.type},
        // Compatibility for clients expecting flat fields
        'sdp': answer.sdp,
        'sdpType': answer.type,
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
      'from': _localUserId,
      // Top-level candidate for compatibility with web clients expecting { candidate }
      'candidate': {
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      },
      'signal': {
        // Use 'candidate' for broad compatibility
        'type': 'candidate',
        'candidate': {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        },
        // Also include alias for receivers expecting 'ice-candidate'
        'iceCandidate': {
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
