// 🚀 P2P Chat WebRTC Configuration
//
// ⚡ QUICK SETUP:
// 1. Replace 'YOUR_SERVER_IP' below with your server IP/domain
// 2. That's it! All other files will auto-update
//
// 💡 Examples:
//    - Local: '192.168.1.100'
//    - Domain: 'myserver.com'
//    - Public IP: '203.0.113.1'

import 'package:flutter/foundation.dart';

/// WebRTC Configuration constants and settings
class WebRTCConfig {
  // ========================================
  // 🔧 MAIN CONFIGURATION - CHANGE ONLY HERE
  // ========================================

  /// Your signaling server IP/domain - CHANGE THIS TO YOUR SERVER
  static const String serverIP = 'localhost'; // 👈 ONLY CHANGE THIS LINE
  static const int serverPort = 8765; // Updated to match your Python server

  // ========================================
  // 🚫 DO NOT MODIFY BELOW - AUTO-GENERATED
  // ========================================

  /// Quick setup method - call this to verify your configuration
  static void printConfiguration() {
    debugPrint('🔧 WebRTC Configuration:');
    debugPrint('📡 Server IP: $serverIP');
    debugPrint('🔌 Port: $serverPort');
    debugPrint('🌐 WebSocket URL: $signalingUrl');
    debugPrint('🔒 Secure URL: $secureSignalingUrl');
  }

  // STUN servers for NAT traversal
  static const List<Map<String, dynamic>> stunServers = [
    {'urls': 'stun:stun.l.google.com:19302'},
    {'urls': 'stun:stun1.l.google.com:19302'},
    {'urls': 'stun:stun2.l.google.com:19302'},
    {'urls': 'stun:stun3.l.google.com:19302'},
    {'urls': 'stun:stun4.l.google.com:19302'},
  ];

  // TURN servers (add your own TURN servers for production)
  static const List<Map<String, dynamic>> turnServers = [
    // Example TURN server configuration
    // {
    //   'urls': 'turn:your-turn-server.com:3478',
    //   'username': 'your-username',
    //   'credential': 'your-password',
    // },
  ];

  // Complete ICE servers configuration
  static List<Map<String, dynamic>> get iceServers {
    return [...stunServers, ...turnServers];
  }

  // Peer connection configuration
  static const Map<String, dynamic> peerConnectionConfig = {
    'sdpSemantics': 'unified-plan',
    'iceTransportPolicy': 'all',
    'bundlePolicy': 'max-bundle',
    'rtcpMuxPolicy': 'require',
  };

  // Data channel configuration
  static const Map<String, dynamic> dataChannelConfig = {
    'ordered': true,
    'maxRetransmits': null,
    'maxPacketLifeTime': null,
    'protocol': '',
  };

  // Auto-generated signaling URLs based on serverIP
  static String get signalingUrl => 'ws://$serverIP:$serverPort';
  static String get secureSignalingUrl => 'wss://$serverIP:$serverPort';
  static String get fallbackSignalingUrl => 'wss://echo.websocket.org';

  // Legacy compatibility (automatically uses serverIP)
  static String get defaultSignalingUrl => signalingUrl;

  // Connection timeouts (in seconds)
  static const int connectionTimeout = 30;
  static const int iceGatheringTimeout = 10;

  // Media constraints (if video/audio is added later)
  static const Map<String, dynamic> mediaConstraints = {
    'audio': false,
    'video': false,
  };

  // Get complete RTCConfiguration
  static Map<String, dynamic> getRTCConfiguration() {
    return {'iceServers': iceServers, ...peerConnectionConfig};
  }

  // Environment-specific configurations
  static Map<String, dynamic> getConfigForEnvironment(String environment) {
    switch (environment) {
      case 'development':
        return {
          'signalingUrl': signalingUrl,
          'debug': true,
          'iceServers': stunServers, // Only use STUN in development
        };
      case 'production':
        return {
          'signalingUrl': secureSignalingUrl, // Use WSS in production
          'debug': false,
          'iceServers': iceServers, // Use both STUN and TURN in production
        };
      default:
        return {
          'signalingUrl': fallbackSignalingUrl,
          'debug': true,
          'iceServers': stunServers,
        };
    }
  }
}
