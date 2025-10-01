import 'dart:convert';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

typedef OnMessageReceived = void Function(String user, String message);

class P2PConnection {
  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _dataChannel;
  WebSocketChannel? _ws;
  String? _clientId;
  String? _peerId;
  OnMessageReceived? onMessageReceived;

  Future<void> connectToServer({
    required String userName,
    required String roomCode,
    required OnMessageReceived onMessage,
    required String wsUrl, // e.g. ws://<AWS_PUBLIC_IP>:8765
  }) async {
    onMessageReceived = onMessage;

    _ws = WebSocketChannel.connect(Uri.parse(wsUrl));
    _ws!.stream.listen(
      _handleSignal,
      onDone: () {
        // Use debugPrint for logging in production
        debugPrint("WebSocket closed");
      },
    );

    // Send join message
    _ws!.sink.add(
      jsonEncode({"type": "join", "room": roomCode, "name": userName}),
    );
  }

  Future<void> _initPeerConnection({bool isCaller = false}) async {
    final config = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ],
    };
    _peerConnection = await createPeerConnection(config);

    // Data channel for messaging
    if (isCaller) {
      _dataChannel = await _peerConnection!.createDataChannel(
        'chat',
        RTCDataChannelInit(),
      );
      _setupDataChannel(_dataChannel!);
    } else {
      _peerConnection!.onDataChannel = (channel) {
        _dataChannel = channel;
        _setupDataChannel(channel);
      };
    }

    // ICE candidate handling
    _peerConnection!.onIceCandidate = (candidate) {
      if (_peerId != null) {
        _ws?.sink.add(
          jsonEncode({
            "type": "signal",
            "to": _peerId,
            "from": _clientId,
            "signal": {"type": "candidate", "candidate": candidate.toMap()},
          }),
        );
      }
    };
  }

  void _setupDataChannel(RTCDataChannel channel) {
    channel.onMessage = (RTCDataChannelMessage message) {
      if (onMessageReceived != null) {
        onMessageReceived!("Peer", message.text);
      }
    };
  }

  void _handleSignal(dynamic raw) async {
    final msg = jsonDecode(raw);

    // Handle ID assignment and peer discovery
    if (msg["type"] == "id") {
      _clientId = msg["id"];
      // If there are peers, connect to the first one
      if (msg["peers"] != null && msg["peers"].isNotEmpty) {
        _peerId = msg["peers"][0]["id"];
        await _initPeerConnection(isCaller: true);
        // Create offer
        final offer = await _peerConnection!.createOffer();
        await _peerConnection!.setLocalDescription(offer);
        _ws?.sink.add(
          jsonEncode({
            "type": "signal",
            "to": _peerId,
            "from": _clientId,
            "signal": {
              "type": "offer",
              "sdp": offer.sdp,
              "sdpType": offer.type,
            },
          }),
        );
      }
    }

    // Handle peer connection notification
    if (msg["type"] == "peer-connected") {
      _peerId = msg["id"];
      await _initPeerConnection(isCaller: false);
    }

    // Handle signaling messages
    if (msg["type"] == "signal" && msg["signal"] != null) {
      final signal = msg["signal"];
      if (signal["type"] == "offer") {
        await _peerConnection!.setRemoteDescription(
          RTCSessionDescription(signal["sdp"], signal["sdpType"]),
        );
        final answer = await _peerConnection!.createAnswer();
        await _peerConnection!.setLocalDescription(answer);
        _ws?.sink.add(
          jsonEncode({
            "type": "signal",
            "to": msg["from"],
            "from": _clientId,
            "signal": {
              "type": "answer",
              "sdp": answer.sdp,
              "sdpType": answer.type,
            },
          }),
        );
      } else if (signal["type"] == "answer") {
        await _peerConnection!.setRemoteDescription(
          RTCSessionDescription(signal["sdp"], signal["sdpType"]),
        );
      } else if (signal["type"] == "candidate") {
        final c = signal["candidate"];
        await _peerConnection!.addCandidate(
          RTCIceCandidate(c["candidate"], c["sdpMid"], c["sdpMLineIndex"]),
        );
      }
    }
  }

  void sendMessage(String message) {
    _dataChannel?.send(RTCDataChannelMessage(message));
  }

  Future<void> dispose() async {
    await _dataChannel?.close();
    await _peerConnection?.close();
    _ws?.sink.close();
  }
}
