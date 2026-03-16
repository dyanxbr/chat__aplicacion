import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../theme.dart';

class AuthService {
  static const _tokenKey = 'chat_token';
  static const _userKey  = 'chat_user';

  static Future<String?> getToken() async =>
      (await SharedPreferences.getInstance()).getString(_tokenKey);

  static Future<Map<String, dynamic>?> getUser() async {
    final raw = (await SharedPreferences.getInstance()).getString(_userKey);
    if (raw == null) return null;
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  static Future<bool> isLoggedIn() async => (await getToken()) != null;

  static Future<void> _save(String token, Map<String, dynamic> user) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_tokenKey, token);
    await p.setString(_userKey, jsonEncode(user));
  }

  static Future<void> clearSession() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_tokenKey);
    await p.remove(_userKey);
  }

  // ── Login ──────────────────────────────────────────────────────
  static Future<void> login(
      {required String correo, required String password}) async {
    final res = await http.post(
      Uri.parse('$kApiBase/api/login'),
      headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
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
  }

  // ── Registro ───────────────────────────────────────────────────
  static Future<String> register({
    required String nombre,
    required String apellidoP,
    required String apellidoM,
    required String fechaNacimiento,
    required String correo,
  }) async {
    final res = await http.post(
      Uri.parse('$kApiBase/api/register'),
      headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
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
    return correo;
  }

  // ── Logout ─────────────────────────────────────────────────────
  static Future<void> logout() async {
    final token = await getToken();
    if (token != null) {
      try {
        await http.post(Uri.parse('$kApiBase/api/logout'), headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        });
      } catch (_) {}
    }
    await clearSession();
  }
}
