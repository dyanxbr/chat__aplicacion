import 'dart:convert';
import 'package:http/http.dart' as http;
import '../theme.dart';

class GeminiService {
  final List<Map<String, dynamic>> _history = [];

  void clearHistory() => _history.clear();

  Future<String> sendMessage(String text) async {
    _history.add({'role': 'user', 'parts': [{'text': text}]});
    final res = await http.post(
      Uri.parse(kGeminiUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'contents': _history}),
    );
    if (res.statusCode == 429) {
      _history.removeLast();
      throw Exception('Límite de cuota alcanzado. Espera unos segundos.');
    }
    if (res.statusCode != 200) {
      _history.removeLast();
      throw Exception('Error ${res.statusCode}. Intenta de nuevo.');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final reply = data['candidates']?[0]?['content']?['parts']?[0]?['text']
            as String? ??
        'Sin respuesta.';
    _history.add({'role': 'model', 'parts': [{'text': reply}]});
    return reply;
  }
}
