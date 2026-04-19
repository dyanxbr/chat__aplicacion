import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart' show debugPrint;

class BiometricService {
  static final LocalAuthentication _auth = LocalAuthentication();
  static const _storage = FlutterSecureStorage();
  
  static const _faceRegisteredKey = 'face_registered';
  static const _faceRegisteredAtKey = 'face_registered_at';
  static const _faceModelVersionKey = 'face_model_version';
  static Future<bool> authenticate({String reason = "Confirma tu identidad"}) async {
    try {
      bool isSupported = await _auth.isDeviceSupported();
      bool canCheck = await _auth.canCheckBiometrics;

      if (!isSupported || !canCheck) {
        debugPrint("Biometría no soportada o no disponible");
        return false;
      }

      final List<BiometricType> available = await _auth.getAvailableBiometrics();
      debugPrint("Biometría disponible: $available");

      bool authenticated = await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );

      return authenticated;
    } catch (e) {
      debugPrint("Error biometria: $e");
      return false;
    }
  }

  static Future<bool> isBiometricSupported() async {
    try {
      return await _auth.isDeviceSupported();
    } catch (e) {
      return false;
    }
  }

  static Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _auth.getAvailableBiometrics();
    } catch (e) {
      return [];
    }
  }


  static Future<bool> isFaceRegistered() async {
    final val = await _storage.read(key: _faceRegisteredKey);
    return val == 'true';
  }
  static Future<bool> hasFaceRegistered() async {
    return await isFaceRegistered();
  }
  static Future<void> setFaceRegistered(bool value) async {
    await _storage.write(
      key: _faceRegisteredKey,
      value: value ? 'true' : 'false',
    );
    
    if (value) {
      await _storage.write(
        key: _faceRegisteredAtKey,
        value: DateTime.now().toIso8601String(),
      );
      await _storage.write(
        key: _faceModelVersionKey,
        value: 'v1',
      );
    } else {
      await _storage.delete(key: _faceRegisteredAtKey);
      await _storage.delete(key: _faceModelVersionKey);
    }
  }

  static Future<DateTime?> getFaceRegisteredAt() async {
    final dateStr = await _storage.read(key: _faceRegisteredAtKey);
    if (dateStr == null) return null;
    try {
      return DateTime.parse(dateStr);
    } catch (_) {
      return null;
    }
  }

  static Future<String?> getFaceModelVersion() async {
    return await _storage.read(key: _faceModelVersionKey);
  }

  static Future<bool> isFaceRegistrationValid({Duration maxAge = const Duration(days: 365)}) async {
    final hasFace = await isFaceRegistered();
    if (!hasFace) return false;
    
    final registeredAt = await getFaceRegisteredAt();
    if (registeredAt == null) return false;
    
    final age = DateTime.now().difference(registeredAt);
    return age < maxAge;
  }

  static Future<void> clearFaceRegistration() async {
    await _storage.delete(key: _faceRegisteredKey);
    await _storage.delete(key: _faceRegisteredAtKey);
    await _storage.delete(key: _faceModelVersionKey);
  }


  static Future<bool> hasAnyBiometricMethod() async {
    final hasFingerprint = await _hasFingerprintConfigured();
    final hasFace = await isFaceRegistered();
    return hasFingerprint || hasFace;
  }

  static Future<bool> _hasFingerprintConfigured() async {
    try {
      final available = await getAvailableBiometrics();
      final hasFingerprint = available.contains(BiometricType.fingerprint) ||
                             available.contains(BiometricType.strong);
      
      return hasFingerprint;
    } catch (e) {
      return false;
    }
  }

  static Future<String> getAvailableBiometricsDescription() async {
    final available = await getAvailableBiometrics();
    final descriptions = <String>[];
    
    for (final type in available) {
      switch (type) {
        case BiometricType.fingerprint:
          descriptions.add("huella dactilar");
          break;
        case BiometricType.face:
          descriptions.add("reconocimiento facial (dispositivo)");
          break;
        case BiometricType.iris:
          descriptions.add("iris");
          break;
        case BiometricType.strong:
          descriptions.add("biometría fuerte");
          break;
        case BiometricType.weak:
          descriptions.add("biometría débil");
          break;
      }
    }
    
    if (descriptions.isEmpty) return "ninguno";
    return descriptions.join(", ");
  }
}