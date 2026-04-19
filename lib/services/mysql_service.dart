import 'package:mysql1/mysql1.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;

class MySQLService {
  static final MySQLService _instance = MySQLService._internal();
  factory MySQLService() => _instance;
  MySQLService._internal();
  
  static MySqlConnection? _connection;
  
  // Configuración de tu base de datos
  static final _settings = ConnectionSettings(
    host: 'caboose.proxy.rlwy.net',
    port: 11073,
    user: 'root',
    password: 'WclPxbBjxfGmCIgRymjPoqaWBocHrgmT',
    db: 'railway',
  );
  
  /// Conectar a MySQL
  static Future<MySqlConnection> getConnection() async {
    try {
      if (_connection == null) {
        _connection = await MySqlConnection.connect(_settings);
        debugPrint('✅ Conectado a MySQL en ${_settings.host}:${_settings.port}');
      } else {
        // Verificar si la conexión sigue activa
        try {
          await _connection!.query('SELECT 1');
        } catch (e) {
          // Si hay error, reconectar
          _connection = await MySqlConnection.connect(_settings);
          debugPrint('✅ Reconectado a MySQL');
        }
      }
      return _connection!;
    } catch (e) {
      debugPrint('❌ Error conectando a MySQL: $e');
      rethrow;
    }
  }
  
  /// Cerrar conexión
  static Future<void> close() async {
    if (_connection != null) {
      try {
        await _connection!.close();
        _connection = null;
        debugPrint('🔌 Conexión MySQL cerrada');
      } catch (e) {
        debugPrint('❌ Error cerrando conexión: $e');
      }
    }
  }
  
  /// Ejecutar query con manejo de errores
  static Future<Results?> executeQuery(String sql, [List<Object?>? params]) async {
    try {
      final conn = await getConnection();
      final results = await conn.query(sql, params);
      return results;
    } catch (e) {
      debugPrint('❌ Error en query: $e');
      debugPrint('SQL: $sql');
      return null;
    }
  }
  
  /// Insertar o actualizar embedding facial
  static Future<bool> saveFaceEmbedding(int userId, List<double> vector, 
      {String model = 'mlkit_landmarks_v1', double threshold = 0.45}) async {
    try {
      final conn = await getConnection();
      
      // Verificar si ya existe
      final check = await conn.query(
        'SELECT id FROM face_embeddings WHERE user_id = ?',
        [userId]
      );
      
      final vectorJson = jsonEncode(vector);
      
      if (check.isNotEmpty) {
        // Actualizar existente
        await conn.query(
          '''UPDATE face_embeddings 
             SET vector = ?, model = ?, threshold = ?, updated_at = NOW() 
             WHERE user_id = ?''',
          [vectorJson, model, threshold, userId]
        );
        debugPrint('✅ Embedding actualizado para user_id: $userId');
      } else {
        // Insertar nuevo
        await conn.query(
          '''INSERT INTO face_embeddings (user_id, vector, model, threshold, created_at, updated_at) 
             VALUES (?, ?, ?, ?, NOW(), NOW())''',
          [userId, vectorJson, model, threshold]
        );
        debugPrint('✅ Embedding insertado para user_id: $userId');
      }
      
      // Actualizar campo en usuarios
      await conn.query(
        'UPDATE usuarios SET face_registered_at = NOW(), face_model_version = ? WHERE id_usuario = ?',
        [model, userId]
      );
      
      return true;
    } catch (e) {
      debugPrint('❌ Error guardando embedding: $e');
      return false;
    }
  }
  
  /// Obtener embedding facial del usuario
  static Future<List<double>?> getFaceEmbedding(int userId) async {
    try {
      final conn = await getConnection();
      final results = await conn.query(
        'SELECT vector FROM face_embeddings WHERE user_id = ?',
        [userId]
      );
      
      if (results.isEmpty) return null;
      
      final vectorJson = results.first[0].toString();
      final vector = List<double>.from(jsonDecode(vectorJson));
      return vector;
    } catch (e) {
      debugPrint('❌ Error obteniendo embedding: $e');
      return null;
    }
  }
  
  /// Verificar si el usuario tiene embedding facial
  static Future<bool> hasFaceEmbedding(int userId) async {
    try {
      final conn = await getConnection();
      final results = await conn.query(
        'SELECT COUNT(*) as count FROM face_embeddings WHERE user_id = ?',
        [userId]
      );
      final count = results.first[0] as int;
      return count > 0;
    } catch (e) {
      debugPrint('❌ Error verificando embedding: $e');
      return false;
    }
  }
  
  /// Obtener ID del usuario por email
  static Future<int?> getUserIdByEmail(String email) async {
    try {
      final conn = await getConnection();
      final results = await conn.query(
        'SELECT id_usuario FROM usuarios WHERE correo = ?',
        [email]
      );
      if (results.isEmpty) return null;
      return results.first[0] as int;
    } catch (e) {
      debugPrint('❌ Error obteniendo user_id: $e');
      return null;
    }
  }
  
  /// Obtener ID del usuario actual (logueado)
  static Future<int?> getCurrentUserId() async {
    try {
      // Aquí deberías obtener el email del usuario logueado
      // Por ahora lo dejamos como método que necesita el email
      return null;
    } catch (e) {
      debugPrint('❌ Error obteniendo usuario actual: $e');
      return null;
    }
  }
}