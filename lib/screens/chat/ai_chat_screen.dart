import 'package:flutter/material.dart';
import '../../services/gemini_service.dart';
import '../../theme.dart';

class AIChatScreen extends StatefulWidget {
  const AIChatScreen({super.key});
  @override
  State<AIChatScreen> createState() => _AIChatScreenState();
}

class _AIMsg {
  final bool isUser;
  final String text;
  final DateTime time;
  _AIMsg({required this.isUser, required this.text}) : time = DateTime.now();
}

class _AIChatScreenState extends State<AIChatScreen> {
  final _gemini     = GeminiService();
  final _inputCtrl  = TextEditingController();
  final _scrollCtrl = ScrollController();
  final List<_AIMsg> _msgs = [];
  bool _waiting    = false;
  bool _showTyping = false;

  @override
  void initState() {
    super.initState();
    _msgs.add(_AIMsg(isUser: false,
        text: '¡Hola! Soy tu asistente IA. ¿En qué puedo ayudarte?'));
  }

  @override
  void dispose() {
    _inputCtrl.dispose(); _scrollCtrl.dispose(); super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _waiting) return;
    _inputCtrl.clear();
    setState(() {
      _msgs.add(_AIMsg(isUser: true, text: text));
      _waiting = true; _showTyping = true;
    });
    _scrollToBottom();
    try {
      final reply = await _gemini.sendMessage(text);
      if (!mounted) return;
      setState(() {
        _showTyping = false;
        _msgs.add(_AIMsg(isUser: false, text: reply));
        _waiting = false;
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _showTyping = false;
        _msgs.add(_AIMsg(isUser: false,
            text: e.toString().replaceFirst('Exception: ', '')));
        _waiting = false;
      });
      _scrollToBottom();
    }
  }

  @override
  Widget build(BuildContext context) {
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
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(
                color: kAccent.withValues(alpha: 0.15),
                shape: BoxShape.circle),
            alignment: Alignment.center,
            child: const Text('A',
                style: TextStyle(color: kAccent,
                    fontWeight: FontWeight.w700, fontSize: 15)),
          ),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Asistente IA',
                style: TextStyle(fontSize: 15,
                    fontWeight: FontWeight.w600, color: kText)),
            Text(_waiting ? 'Escribiendo...' : 'Gemini Flash',
                style: const TextStyle(fontSize: 11, color: kChatMuted)),
          ]),
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline, color: kMuted),
            onPressed: () {
              _gemini.clearHistory();
              setState(() {
                _msgs.clear();
                _msgs.add(_AIMsg(isUser: false,
                    text: '¡Hola! Soy tu asistente IA. ¿En qué puedo ayudarte?'));
              });
            },
          ),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: ListView.builder(
            controller: _scrollCtrl,
            padding: const EdgeInsets.symmetric(vertical: 12),
            itemCount: _msgs.length + (_showTyping ? 1 : 0),
            itemBuilder: (_, i) {
              if (i == _msgs.length && _showTyping) return _typingBubble();
              return _bubble(_msgs[i]);
            },
          ),
        ),
        _buildInput(),
      ]),
    );
  }

  Widget _bubble(_AIMsg msg) {
    final isMine = msg.isUser;
    final t = '${msg.time.hour.toString().padLeft(2,'0')}:${msg.time.minute.toString().padLeft(2,'0')}';
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 12),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.74),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isMine ? kAccent : kCard,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMine ? 16 : 4),
            bottomRight: Radius.circular(isMine ? 4 : 16),
          ),
          boxShadow: [BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 4, offset: const Offset(0, 2))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(msg.text,
              style: TextStyle(
                  color: isMine ? Colors.white : kText, fontSize: 14)),
          const SizedBox(height: 2),
          Text('$t${isMine ? ' ✓✓' : ''}',
              style: TextStyle(fontSize: 10,
                  color: isMine
                      ? Colors.white.withValues(alpha: 0.65) : kChatMuted)),
        ]),
      ),
    );
  }

  Widget _typingBubble() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: kCard,
          borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16), topRight: Radius.circular(16),
              bottomRight: Radius.circular(16), bottomLeft: Radius.circular(4)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 4, offset: const Offset(0, 2))],
        ),
        child: const _TypingDots(),
      ),
    );
  }

  Widget _buildInput() {
    return Container(
      color: kSurface,
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 12),
      child: SafeArea(top: false,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: TextField(
              controller: _inputCtrl,
              minLines: 1, maxLines: 4,
              enabled: !_waiting,
              style: const TextStyle(color: kText, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Escribe un mensaje...',
                hintStyle: const TextStyle(color: kChatMuted),
                fillColor: kChatBg, filled: true,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide(color: kBorder)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide(color: kBorder)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: const BorderSide(color: kAccent)),
              ),
              onSubmitted: (_) => _send(),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _waiting ? null : _send,
            child: Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                  color: _waiting ? kMuted : kAccent,
                  shape: BoxShape.circle),
              alignment: Alignment.center,
              child: _waiting
                  ? const SizedBox(width: 18, height: 18,
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

class _TypingDots extends StatefulWidget {
  const _TypingDots();
  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots> with TickerProviderStateMixin {
  late final List<AnimationController> _c;
  late final List<Animation<double>> _a;

  @override
  void initState() {
    super.initState();
    _c = List.generate(3, (i) => AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600)));
    for (var i = 0; i < 3; i++) {
      Future.delayed(Duration(milliseconds: i * 200), () {
        if (mounted) _c[i].repeat(reverse: true);
      });
    }
    _a = _c.map((c) => Tween<double>(begin: 0, end: -5)
        .animate(CurvedAnimation(parent: c, curve: Curves.easeInOut))).toList();
  }

  @override
  void dispose() {
    for (final c in _c) { c.dispose(); }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) => AnimatedBuilder(
        animation: _a[i],
        builder: (_, __) => Transform.translate(
          offset: Offset(0, _a[i].value),
          child: Container(
            width: 7, height: 7,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: const BoxDecoration(
                color: kChatMuted, shape: BoxShape.circle),
          ),
        ),
      )),
    );
  }
}
