import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../theme.dart';
import '../../widgets/common_widgets.dart';
import '../chat/chat_list_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nombreCtrl    = TextEditingController();
  final _apellidoPCtrl = TextEditingController();
  final _apellidoMCtrl = TextEditingController();
  final _correoCtrl    = TextEditingController();
  DateTime? _fecha;
  bool _loading = false;
  String? _error;
  String? _success;

  @override
  void dispose() {
    _nombreCtrl.dispose(); _apellidoPCtrl.dispose();
    _apellidoMCtrl.dispose(); _correoCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: DateTime(2000),
      firstDate: DateTime(1920),
      lastDate: DateTime(2020, 12, 31),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
            colorScheme: const ColorScheme.light(primary: kAccent)),
        child: child!,
      ),
    );
    if (d != null) setState(() => _fecha = d);
  }

  Future<void> _doRegister() async {
    if (_nombreCtrl.text.trim().isEmpty || _apellidoPCtrl.text.trim().isEmpty ||
        _apellidoMCtrl.text.trim().isEmpty || _correoCtrl.text.trim().isEmpty ||
        _fecha == null) {
      setState(() => _error = 'Completa todos los campos.');
      return;
    }
    final fechaStr =
        '${_fecha!.year}-${_fecha!.month.toString().padLeft(2,'0')}-${_fecha!.day.toString().padLeft(2,'0')}';
    setState(() { _loading = true; _error = null; _success = null; });
    try {
      final correo = await AuthService.register(
        nombre: _nombreCtrl.text.trim(),
        apellidoP: _apellidoPCtrl.text.trim(),
        apellidoM: _apellidoMCtrl.text.trim(),
        fechaNacimiento: fechaStr,
        correo: _correoCtrl.text.trim(),
      );
      if (!mounted) return;
      setState(() => _success =
          '✅ Cuenta creada. Revisa tu correo $correo para ver tu contraseña.');
      await Future.delayed(const Duration(seconds: 3));
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
    final fechaLabel = _fecha != null
        ? '${_fecha!.day.toString().padLeft(2,'0')}/${_fecha!.month.toString().padLeft(2,'0')}/${_fecha!.year}'
        : 'Seleccionar fecha';

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
                  color: kCard, borderRadius: BorderRadius.circular(24),
                  boxShadow: [BoxShadow(color: kAccent.withValues(alpha: 0.10),
                      blurRadius: 40, offset: const Offset(0, 16))],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('A&F Chat',
                        style: TextStyle(fontSize: 28,
                            fontWeight: FontWeight.w700, color: kAccent)),
                    const SizedBox(height: 6),
                    Row(children: [
                      const Text('Crea tu cuenta — ',
                          style: TextStyle(color: kMuted, fontSize: 13)),
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: const Text('¿Ya tienes cuenta?',
                            style: TextStyle(color: kAccent, fontSize: 13,
                                fontWeight: FontWeight.w600)),
                      ),
                    ]),
                    const SizedBox(height: 24),
                    if (_error != null) ...[ErrorBox(_error!), const SizedBox(height: 12)],
                    if (_success != null) ...[SuccessBox(_success!), const SizedBox(height: 12)],
                    LabeledField(label: 'NOMBRE', controller: _nombreCtrl, hint: 'Nombre'),
                    const SizedBox(height: 12),
                    LabeledField(label: 'APELLIDO PATERNO', controller: _apellidoPCtrl, hint: 'Apellido paterno'),
                    const SizedBox(height: 12),
                    LabeledField(label: 'APELLIDO MATERNO', controller: _apellidoMCtrl, hint: 'Apellido materno'),
                    const SizedBox(height: 12),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('FECHA DE NACIMIENTO',
                          style: TextStyle(fontSize: 12,
                              fontWeight: FontWeight.w600, color: kMuted,
                              letterSpacing: 0.5)),
                      const SizedBox(height: 6),
                      GestureDetector(
                        onTap: _pickDate,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            color: kSurface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: kBorder),
                          ),
                          child: Row(children: [
                            const Icon(Icons.calendar_today,
                                size: 16, color: kMuted),
                            const SizedBox(width: 10),
                            Text(fechaLabel,
                                style: TextStyle(
                                    color: _fecha != null ? kText : kMuted,
                                    fontSize: 14)),
                          ]),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 12),
                    LabeledField(label: 'CORREO ELECTRÓNICO',
                        controller: _correoCtrl,
                        keyboardType: TextInputType.emailAddress,
                        hint: 'ejemplo@correo.com'),
                    const SizedBox(height: 8),
                    const Text('Tu contraseña será enviada a tu correo.',
                        style: TextStyle(color: kMuted, fontSize: 12)),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: _loading ? null : _doRegister,
                      child: _loading
                          ? const SizedBox(width: 20, height: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                          : const Text('Crear cuenta'),
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
