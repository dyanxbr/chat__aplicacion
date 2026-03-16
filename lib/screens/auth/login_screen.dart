import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../theme.dart';
import '../../widgets/common_widgets.dart';
import 'register_screen.dart';
import '../chat/chat_list_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _correoCtrl   = TextEditingController();
  final _passCtrl     = TextEditingController();
  bool _loading       = false;
  String? _error;
  bool _showPass      = false;

  @override
  void dispose() { _correoCtrl.dispose(); _passCtrl.dispose(); super.dispose(); }

  Future<void> _doLogin() async {
    if (_correoCtrl.text.trim().isEmpty || _passCtrl.text.isEmpty) {
      setState(() => _error = 'Completa todos los campos.');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await AuthService.login(
          correo: _correoCtrl.text.trim(), password: _passCtrl.text);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const ChatListScreen()));
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: kCard,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(color: kAccent.withValues(alpha: 0.10),
                        blurRadius: 40, offset: const Offset(0, 16))
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('A&F Chat',
                        style: TextStyle(fontSize: 28,
                            fontWeight: FontWeight.w700, color: kAccent)),
                    const SizedBox(height: 6),
                    Row(children: [
                      const Text('Bienvenido — ',
                          style: TextStyle(color: kMuted, fontSize: 13)),
                      GestureDetector(
                        onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const RegisterScreen())),
                        child: const Text('¿No tienes cuenta?',
                            style: TextStyle(color: kAccent,
                                fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                    ]),
                    const SizedBox(height: 28),
                    if (_error != null) ...[
                      ErrorBox(_error!), const SizedBox(height: 14)
                    ],
                    LabeledField(label: 'CORREO ELECTRÓNICO',
                        controller: _correoCtrl,
                        keyboardType: TextInputType.emailAddress,
                        hint: 'ejemplo@correo.com'),
                    const SizedBox(height: 16),
                    LabeledField(
                      label: 'CONTRASEÑA',
                      controller: _passCtrl,
                      obscure: !_showPass,
                      hint: 'Contraseña',
                      suffix: IconButton(
                        icon: Icon(_showPass
                            ? Icons.visibility_off : Icons.visibility,
                            color: kMuted, size: 20),
                        onPressed: () => setState(() => _showPass = !_showPass),
                      ),
                    ),
                    const SizedBox(height: 28),
                    ElevatedButton(
                      onPressed: _loading ? null : _doLogin,
                      child: _loading
                          ? const SizedBox(width: 20, height: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                          : const Text('Iniciar sesión'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
