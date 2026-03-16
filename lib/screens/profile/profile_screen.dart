import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/auth_service.dart';
import '../../theme.dart';
import '../../widgets/common_widgets.dart';

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

  @override
  void initState() {
    super.initState();
    _loadUser();
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

      // Contraseña solo si fue ingresada
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

      // Actualizar datos locales
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
      setState(
          () => _error = e.toString().replaceFirst('Exception: ', ''));
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
                  // ── Foto de perfil ──────────────────────────────
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
                                      width: 90,
                                      height: 90,
                                      fit: BoxFit.cover,
                                      loadingBuilder: (_, child, prog) {
                                        if (prog == null) return child;
                                        return LetterAvatar(
                                            nombre: _user?['nombre']
                                                    as String? ??
                                                '',
                                            size: 90);
                                      },
                                      errorBuilder: (_, __, ___) =>
                                          LetterAvatar(
                                              nombre: _user?['nombre']
                                                      as String? ??
                                                  '',
                                              size: 90),
                                    ),
                                  )
                                : LetterAvatar(
                                    nombre:
                                        _user?['nombre'] as String? ?? '',
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
                          _showPass
                              ? Icons.visibility_off
                              : Icons.visibility,
                          color: kMuted,
                          size: 20),
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
                          _showConf
                              ? Icons.visibility_off
                              : Icons.visibility,
                          color: kMuted,
                          size: 20),
                      onPressed: () =>
                          setState(() => _showConf = !_showConf),
                    ),
                  ),
                  const SizedBox(height: 28),

                  ElevatedButton(
                    onPressed: _loading ? null : _save,
                    child: _loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
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