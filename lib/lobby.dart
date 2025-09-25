import 'package:flutter/material.dart';

class LobbyPage extends StatefulWidget {
  final String userName;

  const LobbyPage({super.key, required this.userName});

  @override
  State<LobbyPage> createState() => _LobbyPageState();
}

class _LobbyPageState extends State<LobbyPage> {
  bool _showJoinModal = false;
  final TextEditingController _roomCodeController = TextEditingController();

  void _goToChat(String room) {
    Navigator.pushNamed(
      context,
      '/chat',
      arguments: {'userName': widget.userName, 'roomCode': room},
    );
  }

  void _joinGlobal() {
    _goToChat('global');
  }

  void _showJoinRoomModal() {
    setState(() {
      _showJoinModal = true;
    });
    Future.delayed(const Duration(milliseconds: 100), () {
      if (!mounted) return;
      _roomCodeController.clear();
      FocusScope.of(context).requestFocus(FocusNode());
    });
  }

  void _closeModal() {
    setState(() {
      _showJoinModal = false;
    });
    _roomCodeController.clear();
  }

  void _joinRoom() {
    final code = _roomCodeController.text.trim().toUpperCase();
    if (code.isNotEmpty) {
      _closeModal();
      _goToChat(code);
    }
  }

  void _createRoom() {
    final code = (DateTime.now().millisecondsSinceEpoch % 1000000)
        .toRadixString(36)
        .toUpperCase();
    _goToChat(code);
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
          child: Stack(
            children: [
              Center(
                child: SingleChildScrollView(
                  child: Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxWidth: 500),
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 40,
                          offset: const Offset(0, 20),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              '💬',
                              style: TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Text(
                              'P2P Chat',
                              style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Welcome, ${widget.userName}!\nChoose where you\'d like to chat.',
                          style: const TextStyle(
                            fontSize: 16,
                            color: Color(0xFF764ba2),
                          ),
                        ),
                        const SizedBox(height: 32),
                        Column(
                          children: [
                            _RoomCard(
                              icon: '🌍',
                              title: 'Global Chat',
                              description:
                                  'Join the public chat room where everyone can connect and share messages.',
                              onTap: _joinGlobal,
                              color: const Color(0xFF667eea),
                            ),
                            const SizedBox(height: 18),
                            _RoomCard(
                              icon: '🔐',
                              title: 'Join Private Room',
                              description:
                                  'Enter a room code to join a private conversation with specific people.',
                              onTap: _showJoinRoomModal,
                              color: const Color(0xFF764ba2),
                            ),
                            const SizedBox(height: 18),
                            _RoomCard(
                              icon: '✨',
                              title: 'Create Private Room',
                              description:
                                  'Generate a new private room and share the code with friends.',
                              onTap: _createRoom,
                              color: const Color(0xFFf39c12),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 16,
                left: 16,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Color(0xFF667eea)),
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                ),
              ),
              if (_showJoinModal)
                GestureDetector(
                  onTap: _closeModal,
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.3),
                    child: Center(
                      child: GestureDetector(
                        onTap: () {},
                        child: Container(
                          width: 320,
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'Join Private Room',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF764ba2),
                                ),
                              ),
                              const SizedBox(height: 18),
                              TextField(
                                controller: _roomCodeController,
                                maxLength: 10,
                                decoration: const InputDecoration(
                                  hintText: 'Enter room code (e.g., ABC123)',
                                  border: OutlineInputBorder(),
                                ),
                                onSubmitted: (_) => _joinRoom(),
                              ),
                              const SizedBox(height: 18),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  TextButton(
                                    onPressed: _closeModal,
                                    child: const Text('Cancel'),
                                  ),
                                  const SizedBox(width: 10),
                                  ElevatedButton(
                                    onPressed: _joinRoom,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Color(0xFF667eea),
                                      foregroundColor: Colors.white,
                                    ),
                                    child: const Text('Join Room'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoomCard extends StatelessWidget {
  final String icon;
  final String title;
  final String description;
  final VoidCallback onTap;
  final Color color;

  const _RoomCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(icon, style: TextStyle(fontSize: 32, color: color)),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF666666),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
