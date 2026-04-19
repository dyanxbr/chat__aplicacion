import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../../services/auth_service.dart';
import '../../services/biometric_service.dart';
import '../../services/face_embedding_service.dart';
import '../../theme.dart';
import '../../widgets/common_widgets.dart';
import 'register_screen.dart';
import '../chat/chat_list_screen.dart';
import '../profile/face_login_screen.dart';
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
  bool _hasFaceRegistered = false;
  bool _isBiometricSupported = false;
  String _availableBiometrics = '';
  bool _isFaceValid = true;

  @override
  void initState() {
    super.initState();
    _initializeLoginScreen();
  }

  @override
  void dispose() {
    _correoCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _initializeLoginScreen() async {
    await _checkBiometricStatus();
    await _checkBiometricLogin();
    await _checkFaceRegistration();
  }

  Future<void> _checkBiometricStatus() async {
    try {
      final isSupported = await BiometricService.isBiometricSupported();
      final availableTypes = await BiometricService.getAvailableBiometricsDescription();
      final isFaceValid = await BiometricService.isFaceRegistrationValid();
      
      if (mounted) {
        setState(() {
          _isBiometricSupported = isSupported;
          _availableBiometrics = availableTypes;
          _isFaceValid = isFaceValid;
        });
      }
    } catch (e) {
      debugPrint('Error verificando estado biométrico: $e');
    }
  }

  Future<void> _checkFaceRegistration() async {
    try {
      final hasFace = await BiometricService.hasFaceRegistered();
      final isFaceValid = await BiometricService.isFaceRegistrationValid();
      
      if (mounted) {
        setState(() {
          _hasFaceRegistered = hasFace && isFaceValid;
        });
      }
    } catch (e) {
      debugPrint('Error verificando registro facial: $e');
    }
  }

  Future<void> _checkBiometricLogin() async {
    try {
      String? bioToken = await storage.read(key: "biometric_token");

      if (bioToken != null) {
        if (!_isBiometricSupported) {
          await storage.delete(key: "biometric_token");
          return;
        }

        bool ok = await BiometricService.authenticate(
          reason: "Inicia sesión automáticamente con tu biometría"
        );

        if (!ok) return;

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString("chat_token", bioToken);

        if (!mounted) return;
        
        final isValid = await AuthService.validateToken();
        if (!isValid) {
          await storage.delete(key: "biometric_token");
          setState(() => _error = "Sesión expirada. Inicia sesión nuevamente.");
          return;
        }
        
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const ChatListScreen()),
          );
        }
      }
    } catch (e) {
      debugPrint('Error en checkBiometricLogin: $e');
      await storage.delete(key: "biometric_token");
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

      final token = await AuthService.getToken();
      if (token != null && _isBiometricSupported) {
        await storage.write(key: "biometric_token", value: token);
      }

      await _syncFaceDataAfterLogin();
      await _uploadFcmToken();

      if (!mounted) return;
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const ChatListScreen()),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _syncFaceDataAfterLogin() async {
    try {
      final hasServer = await FaceEmbeddingService.hasServerRegistration();
      final hasLocal = await FaceEmbeddingService.loadLocalCache() != null;

      if (hasServer && !hasLocal) {
        await FaceEmbeddingService.syncFromServer();
        await BiometricService.setFaceRegistered(true);
        if (mounted) {
          setState(() => _hasFaceRegistered = true);
        }
      }
      
      final isFaceValid = await BiometricService.isFaceRegistrationValid();
      if (await BiometricService.hasFaceRegistered() && !isFaceValid && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tu registro facial ha expirado. Por favor, registra tu rostro nuevamente.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error sincronizando datos faciales: $e');
    }
  }

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
    } catch (_) {}
  }

  Future<void> _loginBiometrico() async {
    if (!_isBiometricSupported) {
      setState(() => _error = "Tu dispositivo no soporta biometría o no está configurada.");
      return;
    }

    bool ok = await BiometricService.authenticate(
      reason: "Verifica tu identidad para iniciar sesión"
    );

    if (!ok) return;

    String? bioToken = await storage.read(key: "biometric_token");

    if (bioToken != null) {
      final isValid = await AuthService.validateToken();
      if (!isValid) {
        await storage.delete(key: "biometric_token");
        setState(() => _error = "Sesión expirada. Inicia sesión con tu contraseña.");
        return;
      }
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString("chat_token", bioToken);

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const ChatListScreen()),
        );
      }
    } else {
      setState(() => _error = "Primero inicia sesión normalmente para guardar tus datos biométricos");
    }
  }

  Future<void> _loginFacial() async {
    if (!_hasFaceRegistered) {
      setState(() => _error = "No tienes rostro registrado o tu registro ha expirado.");
      return;
    }

    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const FaceLoginScreen()),
    );

    if (result == true && mounted) {
      final token = await AuthService.getToken();
      if (token != null && _isBiometricSupported) {
        await storage.write(key: "biometric_token", value: token);
      }
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const ChatListScreen()),
        );
      }
    } else if (result == false && mounted) {
      setState(() => _error = "No se pudo verificar tu rostro. Intenta de nuevo.");
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
                    if (_isBiometricSupported && _availableBiometrics.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: kAccent.withAlpha(25),
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ],
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
                    const SizedBox(height: 24),
                    const Divider(color: kBorder),
                    const SizedBox(height: 16),
                    const Text(
                      "Acceso rápido",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: kMuted, fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildBiometricButton(
                          icon: Icons.fingerprint,
                          label: 'Huella',
                          onPressed: _loginBiometrico,
                          enabled: _isBiometricSupported,
                        ),
                        const SizedBox(width: 24),
                        _buildBiometricButton(
                          icon: Icons.face_retouching_natural,
                          label: 'Rostro',
                          onPressed: _loginFacial,
                          enabled: _hasFaceRegistered,
                        ),
                      ],
                    ),
                    if (!_hasFaceRegistered) ...[
                      const SizedBox(height: 12),
                      Text(
                        'No tienes rostro registrado. Ve a tu perfil para registrar tu rostro.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: kMuted.withAlpha(179),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBiometricButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    bool enabled = true,
  }) {
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: enabled ? kAccent.withAlpha(25) : kMuted.withAlpha(25),
          ),
          child: IconButton(
            icon: Icon(
              icon,
              size: 32,
              color: enabled ? kAccent : kMuted,
            ),
            onPressed: enabled ? onPressed : null,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: enabled ? kText : kMuted,
          ),
        ),
      ],
    );
  }
}