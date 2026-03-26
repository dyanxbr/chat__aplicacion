import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../theme.dart';
import '../screens/profile/face_scan_screen.dart';

class BiometricTestScreen extends StatefulWidget {
  const BiometricTestScreen({super.key});

  @override
  State<BiometricTestScreen> createState() => _BiometricTestScreenState();
}

class _BiometricTestScreenState extends State<BiometricTestScreen> {
  final LocalAuthentication _auth = LocalAuthentication();
  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  bool _iniciando  = true;
  bool _loading    = false;
  bool _disponible = false;
  bool _tieneHuella = false;

  String? _resultado;
  String? _tipoEscaneado;
  Map<String, String>? _credencial;

  @override
  void initState() {
    super.initState();
    _detectar();
  }

  Future<void> _detectar() async {
    try {
      final soporta = await _auth.isDeviceSupported();
      final puede   = await _auth.canCheckBiometrics;
      _disponible   = soporta || puede;

      if (_disponible) {
        final tipos = await _auth.getAvailableBiometrics();
        _tieneHuella = tipos.contains(BiometricType.fingerprint) ||
                       tipos.contains(BiometricType.strong)      ||
                       tipos.isNotEmpty;
      }
    } catch (_) {
      _disponible   = false;
      _tieneHuella  = false;
    }

    if (mounted) setState(() => _iniciando = false);
  }

  // ── Escanear huella ────────────────────────────────────────

  Future<void> _escanearHuella() async {
    setState(() {
      _loading       = true;
      _resultado     = null;
      _tipoEscaneado = null;
      _credencial    = null;
    });

    try {
      final ok = await _auth.authenticate(
        localizedReason: 'Usa tu huella digital para generar tu credencial',
        options: const AuthenticationOptions(
          stickyAuth:    true,
          biometricOnly: true,
        ),
      );

      if (!mounted) return;

      if (!ok) {
        setState(() { _loading = false; _resultado = 'Autenticación cancelada.'; });
        return;
      }

      final ts     = DateTime.now().millisecondsSinceEpoch;
      final bioKey = 'BIO-HUELLA-$ts';

      await _storage.write(key: 'bio_temp_key',  value: bioKey);
      await _storage.write(key: 'bio_temp_tipo', value: 'huella');

      final keyGuardado  = await _storage.read(key: 'bio_temp_key');
      final tipoGuardado = await _storage.read(key: 'bio_temp_tipo');

      if (!mounted) return;
      setState(() {
        _loading       = false;
        _tipoEscaneado = 'huella';
        _resultado     = '¡Escaneo exitoso!';
        _credencial    = {
          'tipo':  tipoGuardado ?? 'huella',
          'clave': keyGuardado  ?? bioKey,
          'fecha': DateTime.now().toString().substring(0, 19),
        };
      });

    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _resultado = _mensajeError(e.code); });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _resultado = 'Error: ${e.toString()}'; });
    }
  }

  String _mensajeError(String code) {
    switch (code) {
      case 'NotEnrolled':        return 'No hay huella registrada en el dispositivo.';
      case 'LockedOut':          return 'Demasiados intentos. Espera un momento.';
      case 'PermanentlyLockedOut': return 'Bloqueado. Desbloquea con PIN primero.';
      case 'NotAvailable':       return 'Biométrico no disponible ahora.';
      default:                   return 'Error al autenticar ($code).';
    }
  }

  // ── UI ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(title: const Text('Datos biométricos')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [

            const Text('Escaneo biométrico',
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w700, color: kText)),
            const SizedBox(height: 6),
            const Text('Elige el método para generar tu credencial.',
                style: TextStyle(fontSize: 13, color: kMuted)),
            const SizedBox(height: 32),

            // ── Detectando ──
            if (_iniciando)
              const Center(
                child: Column(children: [
                  CircularProgressIndicator(color: kAccent),
                  SizedBox(height: 12),
                  Text('Detectando biométrico...',
                      style: TextStyle(fontSize: 13, color: kMuted)),
                ]),
              ),

            // ── Sin biométrico ──
            if (!_iniciando && !_disponible)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: kError.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: kError.withValues(alpha: 0.25)),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded, color: kError, size: 24),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Tu dispositivo no tiene biométrico configurado.\nVe a Ajustes → Seguridad.',
                        style: TextStyle(color: kError, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),

            // ── Botones ──
            if (!_iniciando && _disponible)
              Row(children: [

                // Huella — usa local_auth
                Expanded(
                  child: _BioButton(
                    icon:    Icons.fingerprint,
                    label:   'Huella\ndigital',
                    loading: _loading,
                    onTap:   _escanearHuella,
                  ),
                ),

                const SizedBox(width: 14),

                // Cara — abre FaceScanScreen con ML Kit
                Expanded(
                  child: _BioButton(
                    icon:    Icons.face_retouching_natural,
                    label:   'Reconocimiento\nfacial',
                    loading: false,
                    onTap:   () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const FaceScanScreen()),
                    ),
                  ),
                ),
              ]),

            const SizedBox(height: 32),

            if (_loading)
              const Center(child: CircularProgressIndicator(color: kAccent)),

            // ── Resultado huella ──
            if (_resultado != null && !_loading) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _credencial != null
                      ? kAccent.withValues(alpha: 0.08)
                      : kError.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _credencial != null
                        ? kAccent.withValues(alpha: 0.3)
                        : kError.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(children: [
                  Icon(
                    _credencial != null
                        ? Icons.check_circle
                        : Icons.error_outline,
                    color: _credencial != null ? kAccent : kError,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(_resultado!,
                        style: TextStyle(
                            color: _credencial != null ? kAccent : kError,
                            fontSize: 14,
                            fontWeight: FontWeight.w600)),
                  ),
                ]),
              ),
              const SizedBox(height: 20),
            ],

            // ── Credencial huella generada ──
            if (_credencial != null && !_loading) ...[
              const Text('CREDENCIAL GENERADA',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: kMuted,
                      letterSpacing: 1.2)),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: kSurface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: kBorder),
                ),
                child: Column(children: [
                  Icon(
                    _tipoEscaneado == 'cara'
                        ? Icons.face_retouching_natural
                        : Icons.fingerprint,
                    size: 56, color: kAccent,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _tipoEscaneado == 'cara'
                        ? 'Reconocimiento facial'
                        : 'Huella digital',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700, color: kText),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: kAccent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text('Verificado',
                        style: TextStyle(
                            fontSize: 12, color: kAccent,
                            fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(height: 20),
                  const Divider(color: kBorder),
                  const SizedBox(height: 14),
                  _CredRow(icon: Icons.vpn_key_outlined,
                      label: 'Clave',  value: _credencial!['clave']!),
                  const SizedBox(height: 10),
                  _CredRow(icon: Icons.category_outlined,
                      label: 'Tipo',   value: _credencial!['tipo']!.toUpperCase()),
                  const SizedBox(height: 10),
                  _CredRow(icon: Icons.schedule_outlined,
                      label: 'Fecha',  value: _credencial!['fecha']!),
                ]),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: kBorder.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(children: [
                  Icon(Icons.info_outline, size: 16, color: kMuted),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Próximamente esta credencial se vinculará a tu cuenta para autenticación multi-dispositivo.',
                      style: TextStyle(fontSize: 11, color: kMuted),
                    ),
                  ),
                ]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────

class _BioButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool loading;
  final VoidCallback onTap;
  const _BioButton({
    required this.icon, required this.label,
    required this.loading, required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: loading ? null : onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 12),
          decoration: BoxDecoration(
            color: loading ? kSurface.withValues(alpha: 0.5) : kSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: kAccent.withValues(alpha: loading ? 0.2 : 0.4),
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 44, color: loading ? kMuted : kAccent),
              const SizedBox(height: 10),
              Text(label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: loading ? kMuted : kText)),
              const SizedBox(height: 4),
              Text(
                loading ? 'Escaneando...' : 'Toca para escanear',
                style: TextStyle(
                    fontSize: 11,
                    color: loading ? kMuted : kAccent),
              ),
            ],
          ),
        ),
      );
}

class _CredRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _CredRow(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: kMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(fontSize: 11, color: kMuted)),
                const SizedBox(height: 2),
                Text(value,
                    style: const TextStyle(
                        fontSize: 13,
                        color: kText,
                        fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      );
}