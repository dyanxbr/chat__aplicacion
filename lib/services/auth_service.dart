import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../theme.dart';

class AuthService {
  static const _tokenKey = 'chat_token';
  static const _userKey = 'chat_user';
  static const _userEmailKey = 'user_email';

  static Future<String?> getToken() async =>
      (await SharedPreferences.getInstance()).getString(_tokenKey);

  static Future<Map<String, dynamic>?> getUser() async {
    final raw = (await SharedPreferences.getInstance()).getString(_userKey);
    if (raw == null) return null;
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  static Future<String?> getUserEmail() async {
    final prefs = await SharedPreferences.getInstance();
    String? email = prefs.getString(_userEmailKey);
    
    if (email == null) {
      final user = await getUser();
      if (user != null) {
        email = user['correo'] as String?;
        if (email != null) {
         
          await prefs.setString(_userEmailKey, email);
        }
      }
    }
    
    debugPrint('📧 Email recuperado: $email');
    return email;
  }

  static Future<void> saveUserEmail(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userEmailKey, email);
    debugPrint('📧 Email guardado: $email');
  }

  static Future<int?> getUserId() async {
    final user = await getUser();
    if (user == null) return null;
    return user['id_usuario'] as int?;
  }

  static Future<String?> getUserFullName() async {
    final user = await getUser();
    if (user == null) return null;
    final nombre = user['nombre'] ?? '';
    final apellidoP = user['apellido_p'] ?? '';
    final apellidoM = user['apellido_m'] ?? '';
    return '$nombre $apellidoP $apellidoM'.trim();
  }

  static Future<bool> isLoggedIn() async => (await getToken()) != null;

  static Future<void> _save(String token, Map<String, dynamic> user) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_tokenKey, token);
    await p.setString(_userKey, jsonEncode(user));
    final email = user['correo'] as String?;
    if (email != null) {
      await p.setString(_userEmailKey, email);
    }
    debugPrint('✅ Sesión guardada - Token: ${token.substring(0, 20)}..., Email: $email');
  }

  static Future<void> clearSession() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_tokenKey);
    await p.remove(_userKey);
    await p.remove(_userEmailKey);
    debugPrint('🗑️ Sesión eliminada');
  }

  static Future<void> login(
      {required String correo, required String password}) async {
    debugPrint('🔐 Intentando login con: $correo');
    
    final res = await http.post(
      Uri.parse('$kApiBase/api/login'),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json'
      },
      body: jsonEncode({'correo': correo, 'password': password}),
    );
    
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    
    if (res.statusCode != 200) {
      final errors = data['errors'] as Map<String, dynamic>?;
      throw Exception(errors != null
          ? errors.values.expand((e) => e as List).join(' ')
          : (data['message'] ?? 'Credenciales incorrectas.'));
    }
    
    await _save(data['token'] as String, data['user'] as Map<String, dynamic>);
    debugPrint('✅ Login exitoso');
  }

  static Future<String> register({
    required String nombre,
    required String apellidoP,
    required String apellidoM,
    required String fechaNacimiento,
    required String correo,
  }) async {
    debugPrint('📝 Intentando registro para: $correo');
    
    final res = await http.post(
      Uri.parse('$kApiBase/api/register'),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json'
      },
      body: jsonEncode({
        'nombre': nombre,
        'apellido_p': apellidoP,
        'apellido_m': apellidoM,
        'fecha_nacimiento': fechaNacimiento,
        'correo': correo,
      }),
    );
    
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    
    if (res.statusCode != 200 && res.statusCode != 201) {
      final errors = data['errors'] as Map<String, dynamic>?;
      throw Exception(errors != null
          ? errors.values.expand((e) => e as List).join(' ')
          : (data['message'] ?? 'Error al crear la cuenta.'));
    }
    
    await _save(data['token'] as String, data['user'] as Map<String, dynamic>);
    debugPrint('✅ Registro exitoso');
    return correo;
  }

  static Future<void> logout() async {
    final token = await getToken();
    debugPrint('🚪 Cerrando sesión...');

    if (token != null) {
      try {
        await http.post(
          Uri.parse('$kApiBase/api/logout'),
          headers: {
            'Accept': 'application/json',
            'Authorization': 'Bearer $token',
          },
        );
      } catch (_) {}
    }

    await clearSession();
    debugPrint('✅ Sesión cerrada');
  }

  static Future<void> updateFirebaseToken(String firebaseToken) async {
    try {
      final token = await getToken();
      if (token == null) return;

      final res = await http.post(
        Uri.parse('$kApiBase/api/firebase-token'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'firebase_token': firebaseToken}),
      );

      if (res.statusCode != 200) {
        debugPrint('FCM token upload failed: ${res.body}');
      }
    } catch (e) {
      debugPrint('FCM token error: $e');
    }
  }
  
  static Future<bool> validateToken() async {
    final token = await getToken();
    if (token == null) return false;
    
    try {
      final response = await http.get(
        Uri.parse('$kApiBase/api/validate-token'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error validando token: $e');
      return false;
    }
  }
}