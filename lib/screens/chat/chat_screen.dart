import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../../services/auth_service.dart';
import '../../services/chat_service.dart';
import '../../theme.dart';
import '../../widgets/common_widgets.dart';

class ChatScreen extends StatefulWidget {
  final Map<String, dynamic> peer;
  const ChatScreen({super.key, required this.peer});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  Timer? _poll;
  bool _sending = false;
  File? _file;
  String? _fileName;
  int? _myId;

  // Suscripción al stream de mensajes en foreground
  StreamSubscription<RemoteMessage>? _fcmSub;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final u = await AuthService.getUser();
    _myId = u?['id_usuario'] as int?;
    await _fetch();

    // Polling cada 3 segundos (lo mantenemos por compatibilidad)
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => _fetch());

    // ── Escucha notificaciones cuando la app está en primer plano ──
    _fcmSub = FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      // Solo recargamos si el mensaje es de esta conversación
      final senderId = int.tryParse(message.data['sender_id'] ?? '');
      final peerId = widget.peer['id_usuario'] as int?;

      if (senderId != null && senderId == peerId) {
        _fetch(); // recarga los mensajes inmediatamente
      }
    });
    // ──────────────────────────────────────────────────────────────
  }

  @override
  void dispose() {
    _poll?.cancel();
    _fcmSub?.cancel();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    try {
      final msgs =
          await ChatService.getConversacion(widget.peer['id_usuario'] as int);
      if (!mounted) return;
      final atBottom = _isAtBottom();
      setState(() => _messages = msgs);
      if (atBottom) _scrollToBottom();
    } catch (_) {}
  }

  bool _isAtBottom() {
    if (!_scrollCtrl.hasClients) return true;
    return _scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 60;
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;
    setState(() {
      _file = File(picked.path);
      _fileName = picked.name;
    });
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform
        .pickFiles(type: FileType.any, allowMultiple: false);
    if (result == null || result.files.single.path == null) return;
    setState(() {
      _file = File(result.files.single.path!);
      _fileName = result.files.single.name;
    });
  }

  void _removeFile() => setState(() {
        _file = null;
        _fileName = null;
      });

  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if ((text.isEmpty && _file == null) || _sending) return;
    _inputCtrl.clear();
    final fileCopy = _file;
    _removeFile();
    setState(() => _sending = true);
    try {
      final peerId = widget.peer['id_usuario'] as int;
      if (fileCopy != null) {
        await ChatService.enviarConArchivo(
            peerId, text.isNotEmpty ? text : null, fileCopy);
      } else {
        await ChatService.enviarMensaje(peerId, text);
      }
      await _fetch();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Error al enviar')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _dateLabel(String? s) {
    if (s == null) return '';
    try {
      final dt = DateTime.parse(s).toLocal();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final d = DateTime(dt.year, dt.month, dt.day);
      if (d == today) return 'Hoy';
      if (d == today.subtract(const Duration(days: 1))) return 'Ayer';
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final peerName =
        '${widget.peer['nombre'] ?? ''} ${widget.peer['apellido_p'] ?? ''}'
            .trim();

    return Scaffold(
      backgroundColor: kChatBg,
      appBar: AppBar(
        backgroundColor: kSurface,
        titleSpacing: 0,
        elevation: 0,
        bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(height: 1, color: kBorder)),
        leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: kText),
            onPressed: () => Navigator.of(context).pop()),
        title: Row(children: [
          UserAvatar(user: widget.peer, size: 34),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(peerName,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600, color: kText)),
            const Text('Conectado',
                style: TextStyle(fontSize: 11, color: kAccent)),
          ]),
        ]),
      ),
      body: Column(children: [
        Expanded(
          child: _messages.isEmpty
              ? const Center(
                  child: Text('No hay mensajes. ¡Escribe el primero!',
                      style: TextStyle(color: kChatMuted)))
              : _buildList(),
        ),
        if (_file != null) _buildFilePreview(),
        _buildInput(),
      ]),
    );
  }

  Widget _buildList() {
    String lastDate = '';
    final items = <Widget>[];
    for (final msg in _messages) {
      final lbl = _dateLabel(msg['fecha_envio'] as String?);
      if (lbl.isNotEmpty && lbl != lastDate) {
        lastDate = lbl;
        items.add(Center(
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
                color: kBorder, borderRadius: BorderRadius.circular(12)),
            child:
                Text(lbl, style: const TextStyle(fontSize: 11, color: kMuted)),
          ),
        ));
      }
      items.add(MessageBubble(msg: msg, isMine: msg['id_emisor'] == _myId));
    }
    return ListView(
        controller: _scrollCtrl,
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: items);
  }

  Widget _buildFilePreview() {
    final ext = _fileName?.split('.').last.toLowerCase() ?? '';
    final isImg = ['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: kAccent.withValues(alpha: 0.08),
        border: Border.all(color: kAccent.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(children: [
        isImg
            ? ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.file(_file!,
                    width: 44, height: 44, fit: BoxFit.cover))
            : const Icon(Icons.attach_file, color: kAccent, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(_fileName ?? '',
              style: const TextStyle(fontSize: 13, color: kText),
              overflow: TextOverflow.ellipsis),
        ),
        IconButton(
          icon: const Icon(Icons.close, size: 18, color: kMuted),
          onPressed: _removeFile,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
      ]),
    );
  }

  Widget _buildInput() {
    return Container(
      color: kSurface,
      padding: const EdgeInsets.fromLTRB(4, 8, 8, 12),
      child: SafeArea(
        top: false,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          IconButton(
              icon:
                  const Icon(Icons.image_outlined, color: kChatMuted, size: 22),
              onPressed: _pickImage),
          IconButton(
              icon: const Icon(Icons.attach_file, color: kChatMuted, size: 22),
              onPressed: _pickFile),
          Expanded(
            child: TextField(
              controller: _inputCtrl,
              minLines: 1,
              maxLines: 4,
              style: const TextStyle(color: kText, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Escribe un mensaje...',
                hintStyle: const TextStyle(color: kChatMuted),
                fillColor: kChatBg,
                filled: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide(color: kBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide(color: kBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: const BorderSide(color: kAccent),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _sending ? null : _send,
            child: Container(
              width: 44,
              height: 44,
              decoration:
                  const BoxDecoration(color: kAccent, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: _sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.send, color: Colors.white, size: 20),
            ),
          ),
        ]),
      ),
    );
  }
}
