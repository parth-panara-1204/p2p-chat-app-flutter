import 'package:flutter/material.dart';

class ChatRoomPage extends StatefulWidget {
  final String userName;
  final String roomCode;

  const ChatRoomPage({
    super.key,
    required this.userName,
    required this.roomCode,
  });

  @override
  State<ChatRoomPage> createState() => _ChatRoomPageState();
}

class _ChatRoomPageState extends State<ChatRoomPage> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  // TODO: Integrate WebRTC service properly
  // final WebRTCService _webrtcService = WebRTCService();

  final List<_ChatMessage> _messages = [];
  String? _systemMessage;
  bool _showScrollToBottom = false;
  final bool _someoneTyping = false;
  // TODO: Add these back when WebRTC is integrated
  // List<String> _connectedPeers = [];
  // String _connectionState = 'Disconnected';

  @override
  void initState() {
    super.initState();
    _showSystemMessage("Welcome to the chat! Messages will appear here.");
    _scrollController.addListener(_handleScroll);
    // TODO: Initialize WebRTC service here
    // _initializeWebRTC();
  }

  void _handleScroll() {
    final atBottom =
        _scrollController.offset >=
        _scrollController.position.maxScrollExtent - 10;
    setState(() {
      _showScrollToBottom = !atBottom;
    });
  }

  void _showSystemMessage(String text) {
    setState(() => _systemMessage = text);
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) setState(() => _systemMessage = null);
    });
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _messages.add(
        _ChatMessage(user: widget.userName, text: text, isOwn: true),
      );
      _messageController.clear();
    });
    _scrollToBottom();
    // TODO: Send message to peers via WebRTC/WebSocket
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF667eea), Color(0xFF764ba2)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Column(
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.95),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(30),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 20,
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        // Logo and user info
                        Expanded(
                          child: Row(
                            children: [
                              const Text(
                                '💬',
                                style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.userName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 13,
                                        backgroundColor: const Color(
                                          0xFF667eea,
                                        ),
                                        child: Text(
                                          widget.userName.isNotEmpty
                                              ? widget.userName[0].toUpperCase()
                                              : '',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        "Room: ${widget.roomCode}",
                                        style: const TextStyle(
                                          fontSize: 13,
                                          color: Color(0xFF764ba2),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        // Copy room code button
                        IconButton(
                          icon: const Icon(
                            Icons.copy,
                            color: Color(0xFF667eea),
                          ),
                          tooltip: "Copy Room Code",
                          onPressed: () {
                            // Clipboard logic here
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Room code "${widget.roomCode}" copied!',
                                ),
                              ),
                            );
                          },
                        ),
                        // Back button
                        IconButton(
                          icon: const Icon(Icons.arrow_back),
                          tooltip: "Back to Lobby",
                          onPressed: () {
                            Navigator.of(context).pop();
                          },
                        ),
                      ],
                    ),
                  ),
                  // Chat area
                  Expanded(
                    child: Container(
                      color: Colors.white.withValues(alpha: 0.95),
                      child: Stack(
                        children: [
                          // Messages list
                          Padding(
                            padding: const EdgeInsets.only(
                              left: 8,
                              right: 8,
                              bottom: 70,
                              top: 8,
                            ),
                            child: ListView.builder(
                              controller: _scrollController,
                              itemCount:
                                  _messages.length +
                                  (_systemMessage != null ? 1 : 0),
                              itemBuilder: (context, index) {
                                if (_systemMessage != null && index == 0) {
                                  return AnimatedOpacity(
                                    opacity: 1,
                                    duration: const Duration(milliseconds: 400),
                                    child: Center(
                                      child: Container(
                                        margin: const EdgeInsets.symmetric(
                                          vertical: 8,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 8,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.grey[200],
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: Text(
                                          _systemMessage!,
                                          style: const TextStyle(
                                            color: Color(0xFF764ba2),
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                }
                                final msg =
                                    _messages[index -
                                        (_systemMessage != null ? 1 : 0)];
                                return _ChatBubble(msg: msg);
                              },
                            ),
                          ),
                          // Typing indicator
                          if (_someoneTyping)
                            Positioned(
                              left: 16,
                              bottom: 60,
                              child: Row(
                                children: const [
                                  SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Color(0xFF667eea),
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    "Someone is typing...",
                                    style: TextStyle(
                                      color: Color(0xFF764ba2),
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          // Scroll to bottom button
                          if (_showScrollToBottom)
                            Positioned(
                              right: 16,
                              bottom: 80,
                              child: FloatingActionButton.small(
                                backgroundColor: const Color(0xFF667eea),
                                onPressed: _scrollToBottom,
                                child: const Icon(
                                  Icons.arrow_downward,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  // Input area
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    color: Colors.white.withValues(alpha: 0.95),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _messageController,
                            minLines: 1,
                            maxLines: 4,
                            decoration: InputDecoration(
                              hintText: "Type your message...",
                              filled: true,
                              fillColor: const Color(0xFFF8F9FA),
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 12,
                                horizontal: 16,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                  color: Color(0xFFE1E5E9),
                                  width: 2,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                  color: Color(0xFFE1E5E9),
                                  width: 2,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                  color: Color(0xFF667eea),
                                  width: 2,
                                ),
                              ),
                            ),
                            onSubmitted: (_) => _sendMessage(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: _sendMessage,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF667eea),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(
                              vertical: 16,
                              horizontal: 20,
                            ),
                          ),
                          child: const Text("Send"),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChatMessage {
  final String user;
  final String text;
  final bool isOwn;

  _ChatMessage({required this.user, required this.text, required this.isOwn});
}

class _ChatBubble extends StatelessWidget {
  final _ChatMessage msg;

  const _ChatBubble({required this.msg});

  @override
  Widget build(BuildContext context) {
    final isOwn = msg.isOwn;
    return Align(
      alignment: isOwn ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isOwn ? const Color(0xFF667eea) : Colors.grey[200],
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isOwn)
              CircleAvatar(
                radius: 13,
                backgroundColor: const Color(0xFF764ba2),
                child: Text(
                  msg.user.isNotEmpty ? msg.user[0].toUpperCase() : '',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            if (!isOwn) const SizedBox(width: 8),
            Column(
              crossAxisAlignment: isOwn
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Text(
                  msg.user,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isOwn ? Colors.white : const Color(0xFF764ba2),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  msg.text,
                  style: TextStyle(
                    color: isOwn ? Colors.white : Colors.black87,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
            if (isOwn) const SizedBox(width: 8),
            if (isOwn)
              CircleAvatar(
                radius: 13,
                backgroundColor: const Color(0xFF667eea),
                child: Text(
                  msg.user.isNotEmpty ? msg.user[0].toUpperCase() : '',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
