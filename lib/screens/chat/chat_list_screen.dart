import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../services/chat_service.dart';
import '../../theme.dart';
import '../../widgets/common_widgets.dart';
import '../auth/login_screen.dart';
import '../profile/profile_screen.dart';
import 'chat_screen.dart';
import 'ai_chat_screen.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});
  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  List<Map<String, dynamic>> _users = [];
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _me;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _me = await AuthService.getUser();
    await _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() { _loading = true; _error = null; });
    try {
      final all  = await ChatService.getUsuarios();
      final myId = _me?['id_usuario'];
      // Filtrar mi propio usuario de la lista
      setState(() {
        _users = all.where((u) => u['id_usuario'] != myId).toList();
      });
    } catch (_) {
      _error = 'Error al cargar usuarios';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _logout() async {
    await AuthService.logout();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final nombre =
        '${_me?['nombre'] ?? ''} ${_me?['apellido_p'] ?? ''}'.trim();

    return Scaffold(
      backgroundColor: kChatBg,
      appBar: AppBar(
        backgroundColor: kSurface,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: kBorder),
        ),
        title: const Text('A&F Chat',
            style: TextStyle(
                color: kAccent,
                fontWeight: FontWeight.w700,
                fontSize: 18,
                letterSpacing: -0.5)),
        actions: [
          if (_me != null)
            GestureDetector(
              onTap: () async {
                await Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ProfileScreen()));
                _me = await AuthService.getUser();
                setState(() {});
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Row(children: [
                  Text(nombre,
                      style:
                          const TextStyle(fontSize: 12, color: kChatMuted)),
                  const SizedBox(width: 6),
                  UserAvatar(user: _me!, size: 30),
                ]),
              ),
            ),
          TextButton(
            onPressed: _logout,
            child: const Text('Salir',
                style: TextStyle(color: kChatMuted, fontSize: 12)),
          ),
        ],
      ),
      body: Column(children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: const Text('CONVERSACIONES',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                  color: kChatMuted)),
        ),
        _buildAIItem(),
        const Divider(height: 1, color: kBorder),
        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: kAccent))
              : _error != null
                  ? Center(
                      child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                        Text(_error!,
                            style: const TextStyle(color: kMuted)),
                        const SizedBox(height: 12),
                        ElevatedButton(
                            onPressed: _loadUsers,
                            child: const Text('Reintentar')),
                      ]))
                  : _users.isEmpty
                      ? const Center(
                          child: Text('No hay otros usuarios',
                              style: TextStyle(color: kMuted)))
                      : RefreshIndicator(
                          onRefresh: _loadUsers,
                          color: kAccent,
                          child: ListView.separated(
                            itemCount: _users.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1, color: kBorder),
                            itemBuilder: (_, i) =>
                                _buildUserItem(_users[i]),
                          ),
                        ),
        ),
      ]),
    );
  }

  Widget _buildAIItem() {
    return InkWell(
      onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AIChatScreen())),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
                color: kAccent.withValues(alpha: 0.15),
                shape: BoxShape.circle),
            alignment: Alignment.center,
            child: const Text('A',
                style: TextStyle(
                    color: kAccent,
                    fontWeight: FontWeight.w700,
                    fontSize: 18)),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Asistente IA',
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: kText)),
                  SizedBox(height: 2),
                  Text('Toca para chatear',
                      style: TextStyle(fontSize: 12, color: kChatMuted)),
                ]),
          ),
          const Icon(Icons.chevron_right, color: kBorder),
        ]),
      ),
    );
  }

  Widget _buildUserItem(Map<String, dynamic> user) {
    final nombre   = user['nombre'] as String? ?? '';
    final apellido = user['apellido_p'] as String? ?? '';
    return InkWell(
      onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ChatScreen(peer: user))),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          UserAvatar(user: user, size: 44),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$nombre $apellido',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: kText)),
                  const SizedBox(height: 2),
                  const Text('Toca para chatear',
                      style: TextStyle(fontSize: 12, color: kChatMuted)),
                ]),
          ),
          const Icon(Icons.chevron_right, color: kBorder),
        ]),
      ),
    );
  }
}