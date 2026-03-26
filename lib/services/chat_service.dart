import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../theme.dart';
import 'auth_service.dart';

class ChatService {
  static Future<Map<String, String>> _headers() async {
    final token = await AuthService.getToken();
    return {'Accept': 'application/json', 'Authorization': 'Bearer $token'};
  }

  static Future<List<Map<String, dynamic>>> getUsuarios() async {
    final res = await http.get(
        Uri.parse('$kApiBase/api/usuarios'), headers: await _headers());
    if (res.statusCode != 200) throw Exception('Error al cargar usuarios');
    final data = jsonDecode(res.body);
    final list = data is List ? data : (data['data'] as List? ?? []);
    return list.cast<Map<String, dynamic>>();
  }

  static Future<List<Map<String, dynamic>>> getConversacion(int userId) async {
    final res = await http.get(
        Uri.parse('$kApiBase/api/chat/$userId'), headers: await _headers());
    if (res.statusCode != 200) throw Exception('Error al cargar mensajes');
    final data = jsonDecode(res.body);
    final list = data is List ? data : (data['data'] as List? ?? []);
    return list.cast<Map<String, dynamic>>();
  }

  static Future<void> enviarMensaje(int userId, String mensaje) async {
    final token = await AuthService.getToken();
    final res = await http.post(
      Uri.parse('$kApiBase/api/chat/$userId'),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'mensaje': mensaje}),
    );
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception('Error al enviar mensaje');
    }
  }

  static Future<void> enviarConArchivo(
      int userId, String? mensaje, File archivo) async {
    final token = await AuthService.getToken();
    final request = http.MultipartRequest(
        'POST', Uri.parse('$kApiBase/api/chat/$userId'));
    request.headers['Authorization'] = 'Bearer $token';
    request.headers['Accept']        = 'application/json';
    if (mensaje != null && mensaje.isNotEmpty) {
      request.fields['mensaje'] = mensaje;
    }
    request.files
        .add(await http.MultipartFile.fromPath('archivo', archivo.path));
    final resp = await request.send();
    if (resp.statusCode != 200 && resp.statusCode != 201) {
      throw Exception('Error al enviar archivo');
    }
  }

  static Future<void> actualizarPerfil({
    required String nombre,
    required String apellidoP,
    required String apellidoM,
    String? password,
    File? foto,
  }) async {
    final token = await AuthService.getToken();
    final request = http.MultipartRequest(
        'POST', Uri.parse('$kApiBase/api/usuario/update'));
    request.headers['Authorization'] = 'Bearer $token';
    request.headers['Accept']        = 'application/json';
    request.fields['nombre']     = nombre;
    request.fields['apellido_p'] = apellidoP;
    request.fields['apellido_m'] = apellidoM;
    if (password != null && password.isNotEmpty) {
      request.fields['password'] = password;
    }
    if (foto != null) {
      request.files
          .add(await http.MultipartFile.fromPath('foto', foto.path));
    }
    final resp = await request.send();
    if (resp.statusCode != 200) throw Exception('Error al actualizar perfil');
  }
}
