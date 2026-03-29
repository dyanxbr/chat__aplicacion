import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/auth_service.dart';
import '../../theme.dart';
import '../../widgets/common_widgets.dart';
import '../../services/biometric_service.dart';
import 'face_register_screen.dart'; // ← NUEVA IMPORTACIÓN

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _nombreCtrl    = TextEditingController();
  final _apellidoPCtrl = TextEditingController();
  final _apellidoMCtrl = TextEditingController();
  final _passCtrl      = TextEditingController();
  final _passConfCtrl  = TextEditingController();
  bool _showPass = false, _showConf = false;
  bool _loading  = false;
  String? _error, _success;
  File? _newPhoto;
  Map<String, dynamic>? _user;

  // Estado del registro facial
  bool _faceRegistered = false;

  @override
  void initState() {
    super.initState();
    _loadUser();
    _checkFaceRegistered();
  }

  Future<void> _checkFaceRegistered() async {
    final registered = await BiometricService.isFaceRegistered();
    if (mounted) setState(() => _faceRegistered = registered);
  }

  Future<void> _loadUser() async {
    _user = await AuthService.getUser();
    if (_user != null) {
      _nombreCtrl.text    = _user!['nombre'] as String? ?? '';
      _apellidoPCtrl.text = _user!['apellido_p'] as String? ?? '';
      _apellidoMCtrl.text = _user!['apellido_m'] as String? ?? '';
    }
    setState(() {});
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _apellidoPCtrl.dispose();
    _apellidoMCtrl.dispose();
    _passCtrl.dispose();
    _passConfCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
        source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;
    setState(() => _newPhoto = File(picked.path));
  }

  Future<void> _save() async {
    if (_passCtrl.text.isNotEmpty &&
        _passCtrl.text != _passConfCtrl.text) {
      setState(() => _error = 'Las contraseñas no coinciden.');
      return;
    }

    setState(() { _loading = true; _error = null; _success = null; });

    try {
      final token = await AuthService.getToken();

      final request = http.MultipartRequest(
          'POST', Uri.parse('$kApiBase/api/usuario/update'));
      request.headers['Authorization'] = 'Bearer $token';
      request.headers['Accept']        = 'application/json';

      request.fields['nombre']     = _nombreCtrl.text.trim();
      request.fields['apellido_p'] = _apellidoPCtrl.text.trim();
      request.fields['apellido_m'] = _apellidoMCtrl.text.trim();

      if (_passCtrl.text.isNotEmpty) {
        request.fields['password']              = _passCtrl.text;
        request.fields['password_confirmation'] = _passConfCtrl.text;
      }

      if (_newPhoto != null) {
        request.files.add(
            await http.MultipartFile.fromPath('foto', _newPhoto!.path));
      }

      final streamed = await request.send();
      final body     = await streamed.stream.bytesToString();

      if (streamed.statusCode != 200 && streamed.statusCode != 201) {
        final data   = jsonDecode(body) as Map<String, dynamic>;
        final errors = data['errors'] as Map<String, dynamic>?;
        throw Exception(errors != null
            ? errors.values.expand((e) => e as List).join(' ')
            : (data['message'] ?? 'Error al actualizar perfil'));
      }

      final currentUser = await AuthService.getUser() ?? {};
      currentUser['nombre']     = _nombreCtrl.text.trim();
      currentUser['apellido_p'] = _apellidoPCtrl.text.trim();
      currentUser['apellido_m'] = _apellidoMCtrl.text.trim();

      try {
        final respData = jsonDecode(body) as Map<String, dynamic>;
        final updUser  = respData['user'] as Map<String, dynamic>?;
        if (updUser != null && updUser['foto'] != null) {
          currentUser['foto'] = updUser['foto'];
        }
      } catch (_) {}

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('chat_user', jsonEncode(currentUser));

      _passCtrl.clear();
      _passConfCtrl.clear();

      setState(() {
        _newPhoto = null;
        _user     = currentUser;
        _success  = 'Perfil actualizado correctamente.';
      });
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fotoUrl = _user?['foto'] as String?;

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: const Text('Mi perfil'),
        leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop()),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: kCard,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                      color: kAccent.withValues(alpha: 0.08),
                      blurRadius: 30,
                      offset: const Offset(0, 10))
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Avatar ──
                  Center(
                    child: Stack(children: [
                      GestureDetector(
                        onTap: _pickPhoto,
                        child: _newPhoto != null
                            ? ClipOval(
                                child: Image.file(_newPhoto!,
                                    width: 90, height: 90,
                                    fit: BoxFit.cover))
                            : (fotoUrl != null && fotoUrl.isNotEmpty)
                                ? ClipOval(
                                    child: Image.network(
                                      storageUrl(fotoUrl),
                                      width: 90, height: 90,
                                      fit: BoxFit.cover,
                                      loadingBuilder: (_, child, prog) {
                                        if (prog == null) return child;
                                        return LetterAvatar(
                                            nombre: _user?['nombre'] as String? ?? '',
                                            size: 90);
                                      },
                                      errorBuilder: (_, __, ___) =>
                                          LetterAvatar(
                                              nombre: _user?['nombre'] as String? ?? '',
                                              size: 90),
                                    ),
                                  )
                                : LetterAvatar(
                                    nombre: _user?['nombre'] as String? ?? '',
                                    size: 90),
                      ),
                      Positioned(
                        bottom: 0, right: 0,
                        child: GestureDetector(
                          onTap: _pickPhoto,
                          child: Container(
                            width: 28, height: 28,
                            decoration: const BoxDecoration(
                                color: kAccent, shape: BoxShape.circle),
                            child: const Icon(Icons.camera_alt,
                                color: Colors.white, size: 14),
                          ),
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      '${_user?['nombre'] ?? ''} ${_user?['apellido_p'] ?? ''}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                          color: kText),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ── Botón huella dactilar ──
                  GestureDetector(
                    onTap: () async {
                      bool ok = await BiometricService.authenticate();
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            ok
                                ? 'Autenticación biométrica exitosa'
                                : 'No se pudo autenticar',
                          ),
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: kAccent.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: kAccent.withValues(alpha: 0.35),
                            width: 1.5),
                      ),
                      child: const Row(children: [
                        Icon(Icons.fingerprint, color: kAccent, size: 28),
                        SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Huella dactilar',
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: kText)),
                              SizedBox(height: 2),
                              Text('Autenticar con huella del dispositivo',
                                  style: TextStyle(
                                      fontSize: 12, color: kMuted)),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right, color: kMuted),
                      ]),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // ── Botón facial (NUEVO) ──
                  GestureDetector(
                    onTap: () async {
                      final result = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(
                          builder: (_) => const FaceRegisterScreen(),
                        ),
                      );
                      // Si regresó con éxito, refrescar estado
                      if (result == true) {
                        await _checkFaceRegistered();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Rostro registrado correctamente'),
                            ),
                          );
                        }
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: _faceRegistered
                            ? const Color(0xFF22C55E).withValues(alpha: 0.08)
                            : kSurface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: _faceRegistered
                              ? const Color(0xFF22C55E).withValues(alpha: 0.5)
                              : kBorder,
                          width: 1.5,
                        ),
                      ),
                      child: Row(children: [
                        Icon(
                          _faceRegistered
                              ? Icons.face_retouching_natural
                              : Icons.face_outlined,
                          color: _faceRegistered
                              ? const Color(0xFF22C55E)
                              : kMuted,
                          size: 28,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Reconocimiento facial',
                                style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: kText),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _faceRegistered
                                    ? 'Rostro registrado — toca para actualizar'
                                    : 'Registra tu rostro para login facial',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: _faceRegistered
                                        ? const Color(0xFF22C55E)
                                        : kMuted),
                              ),
                            ],
                          ),
                        ),
                        if (_faceRegistered)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFF22C55E)
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text('Activo',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF22C55E))),
                          )
                        else
                          const Icon(Icons.chevron_right, color: kMuted),
                      ]),
                    ),
                  ),

                  const SizedBox(height: 24),

                  if (_error != null) ...[
                    ErrorBox(_error!),
                    const SizedBox(height: 12)
                  ],
                  if (_success != null) ...[
                    SuccessBox(_success!),
                    const SizedBox(height: 12)
                  ],

                  LabeledField(label: 'NOMBRE', controller: _nombreCtrl),
                  const SizedBox(height: 12),
                  LabeledField(
                      label: 'APELLIDO PATERNO',
                      controller: _apellidoPCtrl),
                  const SizedBox(height: 12),
                  LabeledField(
                      label: 'APELLIDO MATERNO',
                      controller: _apellidoMCtrl),
                  const SizedBox(height: 20),

                  const Text('Cambiar contraseña (opcional)',
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: kText)),
                  const SizedBox(height: 4),
                  const Text('Deja en blanco si no deseas cambiarla.',
                      style: TextStyle(fontSize: 12, color: kMuted)),
                  const SizedBox(height: 10),

                  LabeledField(
                    label: 'NUEVA CONTRASEÑA',
                    controller: _passCtrl,
                    obscure: !_showPass,
                    hint: '••••••••',
                    suffix: IconButton(
                      icon: Icon(
                          _showPass ? Icons.visibility_off : Icons.visibility,
                          color: kMuted, size: 20),
                      onPressed: () =>
                          setState(() => _showPass = !_showPass),
                    ),
                  ),
                  const SizedBox(height: 12),
                  LabeledField(
                    label: 'CONFIRMAR CONTRASEÑA',
                    controller: _passConfCtrl,
                    obscure: !_showConf,
                    hint: '••••••••',
                    suffix: IconButton(
                      icon: Icon(
                          _showConf ? Icons.visibility_off : Icons.visibility,
                          color: kMuted, size: 20),
                      onPressed: () =>
                          setState(() => _showConf = !_showConf),
                    ),
                  ),
                  const SizedBox(height: 28),

                  ElevatedButton(
                    onPressed: _loading ? null : _save,
                    child: _loading
                        ? const SizedBox(
                            width: 20, height: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : const Text('Guardar cambios'),
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