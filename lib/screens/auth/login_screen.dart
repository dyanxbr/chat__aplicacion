import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../../services/auth_service.dart';
import '../../services/biometric_service.dart';
import '../../theme.dart';
import '../../widgets/common_widgets.dart';
import 'register_screen.dart';
import '../chat/chat_list_screen.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _correoCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final storage = const FlutterSecureStorage();

  bool _loading = false;
  String? _error;
  bool _showPass = false;

  @override
  void initState() {
    super.initState();
    _checkBiometricLogin();
  }

  @override
  void dispose() {
    _correoCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  /// Verifica si existe sesión biométrica y pide huella
  Future<void> _checkBiometricLogin() async {
    String? bioToken = await storage.read(key: "biometric_token");

    if (bioToken != null) {
      bool ok = await BiometricService.authenticate();

      if (!ok) return;

      /// Restaurar sesión
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString("chat_token", bioToken);

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const ChatListScreen()),
      );
    }
  }

  Future<void> _doLogin() async {
    if (_correoCtrl.text.trim().isEmpty || _passCtrl.text.isEmpty) {
      setState(() => _error = 'Completa todos los campos.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await AuthService.login(
        correo: _correoCtrl.text.trim(),
        password: _passCtrl.text,
      );

      /// Guardar token biométrico
      final token = await AuthService.getToken();
      if (token != null) {
        await storage.write(key: "biometric_token", value: token);
      }

      /// Subir token FCM
      await _uploadFcmToken();

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const ChatListScreen()),
      );
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Subir token FCM al backend
  Future<void> _uploadFcmToken() async {
    try {
      final messaging = FirebaseMessaging.instance;

      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      final token = await messaging.getToken();
      if (token == null) return;

      await AuthService.updateFirebaseToken(token);

      messaging.onTokenRefresh.listen((newToken) {
        AuthService.updateFirebaseToken(newToken);
      });
    } catch (_) {
      // ignoramos errores
    }
  }

  /// Login usando biometría manual
  Future<void> _loginBiometrico() async {
    print("Intentando biometría");

    bool ok = await BiometricService.authenticate();
    print("Resultado biometría: $ok");

    if (!ok) return;

    String? bioToken = await storage.read(key: "biometric_token");

    if (bioToken != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString("chat_token", bioToken);

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const ChatListScreen()),
      );
    } else {
      setState(() => _error = "Primero inicia sesión normalmente");
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
                    BoxShadow(
                      color: kAccent.withAlpha(25),
                      blurRadius: 40,
                      offset: const Offset(0, 16),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'A&F Chat',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: kAccent,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Text(
                          'Bienvenido — ',
                          style: TextStyle(color: kMuted, fontSize: 13),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const RegisterScreen(),
                            ),
                          ),
                          child: const Text(
                            '¿No tienes cuenta?',
                            style: TextStyle(
                              color: kAccent,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    if (_error != null) ...[
                      ErrorBox(_error!),
                      const SizedBox(height: 14),
                    ],
                    LabeledField(
                      label: 'CORREO ELECTRÓNICO',
                      controller: _correoCtrl,
                      keyboardType: TextInputType.emailAddress,
                      hint: 'ejemplo@correo.com',
                    ),
                    const SizedBox(height: 16),
                    LabeledField(
                      label: 'CONTRASEÑA',
                      controller: _passCtrl,
                      obscure: !_showPass,
                      hint: 'Contraseña',
                      suffix: IconButton(
                        icon: Icon(
                          _showPass ? Icons.visibility_off : Icons.visibility,
                          color: kMuted,
                          size: 20,
                        ),
                        onPressed: () => setState(() => _showPass = !_showPass),
                      ),
                    ),
                    const SizedBox(height: 28),
                    ElevatedButton(
                      onPressed: _loading ? null : _doLogin,
                      child: _loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text('Iniciar sesión'),
                    ),
                    const SizedBox(height: 20),
                    Center(
                      child: Column(
                        children: [
                          const Text(
                            "Entrar con biometría",
                            style: TextStyle(color: kMuted),
                          ),
                          const SizedBox(height: 10),
                          IconButton(
                            icon: const Icon(
                              Icons.fingerprint,
                              size: 40,
                              color: kAccent,
                            ),
                            onPressed: _loginBiometrico,
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
      ),
    );
  }
}
