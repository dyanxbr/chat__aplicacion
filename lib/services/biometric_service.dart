import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class BiometricService {
  static final LocalAuthentication _auth = LocalAuthentication();
  static const _storage = FlutterSecureStorage();

  // ── Huella / biométrico del dispositivo ──────────────────────────────────

  static Future<bool> authenticate() async {
    try {
      bool isSupported = await _auth.isDeviceSupported();
      bool canCheck    = await _auth.canCheckBiometrics;

      if (!isSupported || !canCheck) return false;

      final List<BiometricType> available =
          await _auth.getAvailableBiometrics();

      print("Biometría disponible: $available");

      bool authenticated = await _auth.authenticate(
        localizedReason: "Confirma tu identidad",
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );

      return authenticated;
    } catch (e) {
      print("Error biometria: $e");
      return false;
    }
  }

  // ── Registro facial ───────────────────────────────────────────────────────

  /// Verifica si el usuario ya registró su rostro en este dispositivo.
  static Future<bool> isFaceRegistered() async {
    final val = await _storage.read(key: 'face_registered');
    return val == 'true';
  }

  /// Marca o desmarca el registro facial.
  static Future<void> setFaceRegistered(bool value) async {
    await _storage.write(
      key: 'face_registered',
      value: value ? 'true' : 'false',
    );
  }
}