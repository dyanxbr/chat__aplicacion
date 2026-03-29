import 'package:local_auth/local_auth.dart';

class BiometricService {
  static final LocalAuthentication _auth = LocalAuthentication();

  static Future<bool> authenticate() async {
    try {
      bool isSupported = await _auth.isDeviceSupported();
      bool canCheck = await _auth.canCheckBiometrics;

      if (!isSupported || !canCheck) {
        return false;
      }

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
}
