import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mysql1/mysql1.dart';
import 'auth_service.dart';

class MySQLConfig {
  static const String host = 'caboose.proxy.rlwy.net';
  static const int port = 11073;
  static const String user = 'root';
  static const String password = 'WclPxbBjxfGmCIgRymjPoqaWBocHrgmT';
  static const String database = 'railway';
}

class FaceEmbedding {
  final List<double> vector;
  final DateTime createdAt;

  FaceEmbedding({required this.vector, required this.createdAt});

  Map<String, dynamic> toJson() => {
        'vector': vector,
        'created_at': createdAt.toIso8601String(),
        'model': 'mlkit_landmarks_v1',
        'threshold': 0.6,
      };

  factory FaceEmbedding.fromJson(Map<String, dynamic> j) => FaceEmbedding(
        vector: List<double>.from(j['vector'] as List),
        createdAt: DateTime.parse(j['created_at'] as String),
      );

  static double cosineDistance(List<double> a, List<double> b) {
    double dot = 0, normA = 0, normB = 0;
    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    if (normA == 0 || normB == 0) return 1.0;
    return 1.0 - (dot / (math.sqrt(normA) * math.sqrt(normB)));
  }
}

class MySQLService {
  static MySqlConnection? _connection;
  static DateTime? _lastConnectionTime;
  static const int _maxConnectionAge = 30000; 

  static Future<MySqlConnection> getConnection() async {
    try {
      final needsReconnect = _connection == null ||
          _lastConnectionTime == null ||
          DateTime.now().difference(_lastConnectionTime!).inMilliseconds > _maxConnectionAge;
      
      if (needsReconnect) {
        await _createNewConnection();
      } else {
        try {
          await _connection!.query('SELECT 1');
        } catch (e) {
          debugPrint('Conexión muerta, reconectando...');
          await _createNewConnection();
        }
      }
      return _connection!;
    } catch (e) {
      debugPrint('❌ Error en getConnection: $e');
   
      await _createNewConnection();
      return _connection!;
    }
  }

  static Future<void> _createNewConnection() async {
    
    if (_connection != null) {
      try {
        await _connection!.close();
      } catch (e) {
      }
      _connection = null;
    }

    debugPrint('Intentando conectar a MySQL...');
    
    _connection = await MySqlConnection.connect(
      ConnectionSettings(
        host: MySQLConfig.host,
        port: MySQLConfig.port,
        user: MySQLConfig.user,
        password: MySQLConfig.password,
        db: MySQLConfig.database,
      ),
    );
    
    _lastConnectionTime = DateTime.now();
    debugPrint('✅ Conectado a MySQL correctamente');
  }

  static Future<void> closeConnection() async {
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
  static Future<bool> testConnection() async {
    try {
      final conn = await getConnection();
      final result = await conn.query('SELECT 1 as test, NOW() as time, DATABASE() as db');
      debugPrint('✅ Prueba de conexión exitosa');
      debugPrint('📊 Base de datos: ${result.first[2]}');
      debugPrint('🕐 Hora del servidor: ${result.first[1]}');
      return true;
    } catch (e) {
      debugPrint('❌ Prueba de conexión fallida: $e');
      return false;
    }
  }

  static Future<bool> saveFaceEmbedding(int userId, List<double> vector,
      {String model = 'mlkit_landmarks_v1', double threshold = 0.45}) async {
    try {
      final conn = await getConnection();
      final vectorJson = jsonEncode(vector);

      final checkResult = await conn.query(
        'SELECT id FROM face_embeddings WHERE user_id = ?',
        [userId],
      );

      if (checkResult.isNotEmpty) {
        await conn.query(
          '''UPDATE face_embeddings 
             SET vector = ?, model = ?, threshold = ?, updated_at = NOW() 
             WHERE user_id = ?''',
          [vectorJson, model, threshold, userId],
        );
        debugPrint('✅ Embedding actualizado para usuario $userId');
      } else {
        await conn.query(
          '''INSERT INTO face_embeddings (user_id, vector, model, threshold, created_at, updated_at) 
             VALUES (?, ?, ?, ?, NOW(), NOW())''',
          [userId, vectorJson, model, threshold],
        );
        debugPrint('✅ Embedding insertado para usuario $userId');
      }

      await conn.query(
        'UPDATE usuarios SET face_registered_at = NOW(), face_model_version = ? WHERE id_usuario = ?',
        [model, userId],
      );

      return true;
    } catch (e) {
      debugPrint('❌ Error guardando embedding: $e');
      return false;
    }
  }

  static Future<List<double>?> getFaceEmbedding(int userId) async {
    try {
      final conn = await getConnection();
      final results = await conn.query(
        'SELECT vector FROM face_embeddings WHERE user_id = ?',
        [userId],
      );

      if (results.isEmpty) return null;

      final vectorJson = results.first[0].toString();
      return List<double>.from(jsonDecode(vectorJson));
    } catch (e) {
      debugPrint('❌ Error obteniendo embedding: $e');
      return null;
    }
  }

  static Future<bool> hasFaceEmbedding(int userId) async {
    try {
      final conn = await getConnection();
      final results = await conn.query(
        'SELECT COUNT(*) as count FROM face_embeddings WHERE user_id = ?',
        [userId],
      );
      return (results.first[0] as int) > 0;
    } catch (e) {
      debugPrint('❌ Error verificando embedding: $e');
      return false;
    }
  }

  static Future<int?> getUserIdByEmail(String email) async {
    try {
      final conn = await getConnection();
      final results = await conn.query(
        'SELECT id_usuario FROM usuarios WHERE correo = ?',
        [email],
      );
      if (results.isEmpty) return null;
      final userId = results.first[0] as int;
      debugPrint('✅ Usuario encontrado: ID=$userId, Email=$email');
      return userId;
    } catch (e) {
      debugPrint('❌ Error obteniendo userId: $e');
      return null;
    }
  }

  static Future<int?> getCurrentUserId() async {
    try {
      final email = await AuthService.getUserEmail();
      if (email == null) {
        debugPrint('❌ No se encontró email de usuario');
        return null;
      }
      debugPrint('📧 Email obtenido: $email');
      return await getUserIdByEmail(email);
    } catch (e) {
      debugPrint('❌ Error obteniendo usuario actual: $e');
      return null;
    }
  }
}

class FaceEmbeddingService {
  static const _storage = FlutterSecureStorage();
  static const _localKey = 'face_embedding_cache_v1';

  static List<double> generateEmbedding(Face face) {
    final landmarks = face.landmarks;
    final contours = face.contours;
    final points = <double>[];

    for (final type in FaceLandmarkType.values) {
      final lm = landmarks[type];
      if (lm != null) {
        points.add(lm.position.x / 1000.0);
        points.add(lm.position.y / 1000.0);
      } else {
        points.add(0.0);
        points.add(0.0);
      }
    }

    for (final type in FaceContourType.values) {
      final c = contours[type];
      if (c != null && c.points.isNotEmpty) {
        final xs = c.points.map((p) => p.x).toList();
        final ys = c.points.map((p) => p.y).toList();
        points.add(xs.reduce(math.min) / 1000.0);
        points.add(xs.reduce(math.max) / 1000.0);
        points.add(ys.reduce(math.min) / 1000.0);
        points.add(ys.reduce(math.max) / 1000.0);
      } else {
        points.addAll([0.0, 0.0, 0.0, 0.0]);
      }
    }

    points.add(face.headEulerAngleY ?? 0.0);
    points.add(face.headEulerAngleZ ?? 0.0);
    points.add(face.leftEyeOpenProbability ?? 0.5);
    points.add(face.rightEyeOpenProbability ?? 0.5);
    points.add(face.smilingProbability ?? 0.0);

    final raw = _padOrTrunc(points, 128);
    final norm = math.sqrt(raw.fold(0.0, (s, v) => s + v * v));
    return norm == 0 ? raw : raw.map((v) => v / norm).toList();
  }

  static List<double> _padOrTrunc(List<double> v, int size) {
    if (v.length >= size) return v.sublist(0, size);
    return [...v, ...List.filled(size - v.length, 0.0)];
  }


  
  static Future<void> saveLocalCache(FaceEmbedding embedding) async {
    await _storage.write(key: _localKey, value: jsonEncode(embedding.toJson()));
  }

  static Future<FaceEmbedding?> loadLocalCache() async {
    final raw = await _storage.read(key: _localKey);
    if (raw == null) return null;
    try {
      return FaceEmbedding.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static Future<void> deleteLocalCache() async {
    await _storage.delete(key: _localKey);
  }

 
  
  static Future<int?> getCurrentUserId() async {
    return await MySQLService.getCurrentUserId();
  }

  static Future<bool> testConnection() async {
    return await MySQLService.testConnection();
  }

  
  static Future<bool> saveToServer(List<double> vector) async {
    try {
      final userId = await MySQLService.getCurrentUserId();
      if (userId == null) {
        debugPrint('❌ Usuario no autenticado');
        return false;
      }

      final success = await MySQLService.saveFaceEmbedding(userId, vector);
      
      if (success) {
        final embedding = FaceEmbedding(vector: vector, createdAt: DateTime.now());
        await saveLocalCache(embedding);
      }
      
      return success;
    } catch (e) {
      debugPrint('❌ Error guardando en servidor: $e');
      return false;
    }
  }

  static Future<FaceEmbedding?> loadFromServer() async {
    try {
      final userId = await MySQLService.getCurrentUserId();
      if (userId == null) return null;

      final vector = await MySQLService.getFaceEmbedding(userId);
      if (vector == null) return null;
      
      final embedding = FaceEmbedding(vector: vector, createdAt: DateTime.now());
      await saveLocalCache(embedding);
      return embedding;
    } catch (e) {
      debugPrint('❌ Error cargando desde servidor: $e');
      return null;
    }
  }

  static Future<bool> hasServerRegistration() async {
    try {
      final userId = await MySQLService.getCurrentUserId();
      if (userId == null) return false;
      return await MySQLService.hasFaceEmbedding(userId);
    } catch (e) {
      debugPrint('❌ Error verificando registro: $e');
      return false;
    }
  }

  
  static Future<bool> verifyFace(List<double> newVector,
      {double threshold = 0.45}) async {
    try {
      final localCache = await loadLocalCache();
      if (localCache != null) {
        final dist = FaceEmbedding.cosineDistance(localCache.vector, newVector);
        if (dist < threshold) {
          debugPrint('[Face] ✅ Verificado localmente - distancia: $dist');
          return true;
        }
      }
      
      final userId = await MySQLService.getCurrentUserId();
      if (userId == null) {
        debugPrint('[Face] ❌ Usuario no autenticado');
        return false;
      }
      
      final serverVector = await MySQLService.getFaceEmbedding(userId);
      if (serverVector == null) {
        debugPrint('[Face] ❌ No hay embedding en servidor');
        return false;
      }
      
      final dist = FaceEmbedding.cosineDistance(serverVector, newVector);
      debugPrint('[Face] 📊 Distancia coseno: $dist (umbral: $threshold)');
      
      final isMatch = dist < threshold;
      
      if (isMatch) {
        final embedding = FaceEmbedding(vector: serverVector, createdAt: DateTime.now());
        await saveLocalCache(embedding);
        debugPrint('[Face] ✅ Rostro verificado con servidor');
      }
      
      return isMatch;
    } catch (e) {
      debugPrint('[Face] ❌ Error en verificación: $e');
      return false;
    }
  }

  
  static Future<void> saveLocal(FaceEmbedding embedding) async {
    await saveLocalCache(embedding);
  }

  static Future<FaceEmbedding?> loadLocal() async {
    return await loadLocalCache();
  }

  static Future<void> deleteLocal() async {
    await deleteLocalCache();
  }

  static Future<bool> uploadToServer(FaceEmbedding embedding) async {
    return await saveToServer(embedding.vector);
  }

  static Future<FaceEmbedding?> syncFromServer() async {
    return await loadFromServer();
  }

  static Future<bool> verifyWithServer(List<double> newVector) async {
    return await verifyFace(newVector);
  }

  static Future<bool> verifyLocal(List<double> newVector,
      {double threshold = 0.45}) async {
    final saved = await loadLocalCache();
    if (saved == null) return false;
    final dist = FaceEmbedding.cosineDistance(saved.vector, newVector);
    debugPrint('[Face] distancia coseno: $dist (umbral: $threshold)');
    return dist < threshold;
  }

  static Future<bool> hasServerEmbedding() async {
    return await hasServerRegistration();
  }
}