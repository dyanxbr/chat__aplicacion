import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../services/auth_service.dart';
import '../../services/biometric_service.dart';
import '../../theme.dart';

// ─────────────────────────────────────────────
// MODELO: representa un embedding facial
// ─────────────────────────────────────────────
class FaceEmbedding {
  final List<double> vector; // 128 valores
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

  /// Distancia coseno entre dos vectores (0 = idénticos, 1 = opuestos)
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

// ─────────────────────────────────────────────
// SERVICIO: genera y guarda embeddings
// ─────────────────────────────────────────────
class FaceEmbeddingService {
  static const _storage = FlutterSecureStorage();
  static const _key = 'face_embedding_v1';

  /// Genera un vector de 128 valores a partir de los landmarks de ML Kit.
  /// En producción esto sería FaceNet/ArcFace corriendo en TFLite.
  static List<double> generateEmbedding(Face face) {
    final landmarks = face.landmarks;
    final contours  = face.contours;

    // Puntos de referencia clave
    final points = <double>[];

    // --- Landmarks (posición normalizada) ---
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

    // --- Contornos (bounding box normalizado) ---
    for (final type in FaceContourType.values) {
      final c = contours[type];
      if (c != null && c.points.isNotEmpty) {
        final xs = c.points.map((p) => p.x).toList();
        final ys = c.points.map((p) => p.y).toList();
        final minX = xs.reduce(math.min) / 1000.0;
        final maxX = xs.reduce(math.max) / 1000.0;
        final minY = ys.reduce(math.min) / 1000.0;
        final maxY = ys.reduce(math.max) / 1000.0;
        points.add(minX);
        points.add(maxX);
        points.add(minY);
        points.add(maxY);
      } else {
        points.addAll([0.0, 0.0, 0.0, 0.0]);
      }
    }

    // --- Atributos adicionales ---
    points.add(face.headEulerAngleY ?? 0.0);
    points.add(face.headEulerAngleZ ?? 0.0);
    points.add(face.leftEyeOpenProbability ?? 0.5);
    points.add(face.rightEyeOpenProbability ?? 0.5);
    points.add(face.smilingProbability ?? 0.0);

    // Normalizar a exactamente 128 valores
    final raw = _padOrTrunc(points, 128);

    // L2 normalización (para comparación coseno)
    final norm = math.sqrt(raw.fold(0.0, (s, v) => s + v * v));
    return norm == 0
        ? raw
        : raw.map((v) => v / norm).toList();
  }

  static List<double> _padOrTrunc(List<double> v, int size) {
    if (v.length >= size) return v.sublist(0, size);
    return [...v, ...List.filled(size - v.length, 0.0)];
  }

  /// Guarda el embedding localmente (cifrado con flutter_secure_storage)
  static Future<void> saveLocal(FaceEmbedding embedding) async {
    await _storage.write(
        key: _key, value: jsonEncode(embedding.toJson()));
  }

  /// Lee el embedding local
  static Future<FaceEmbedding?> loadLocal() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return null;
    try {
      return FaceEmbedding.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Elimina el embedding local
  static Future<void> deleteLocal() async =>
      await _storage.delete(key: _key);

  /// Sube el embedding al servidor Laravel
  /// POST /api/usuario/face-embedding
  /// Body: { "embedding": [128 floats], "model": "...", "threshold": 0.6 }
  static Future<bool> uploadToServer(FaceEmbedding embedding) async {
    try {
      final token = await AuthService.getToken();
      final resp = await http.post(
        Uri.parse('$kApiBase/api/usuario/face-embedding'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(embedding.toJson()),
      );
      return resp.statusCode == 200 || resp.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  /// Compara un embedding nuevo contra el guardado localmente.
  /// Retorna true si la distancia coseno < threshold (0.4 recomendado).
  static Future<bool> verifyLocal(List<double> newVector,
      {double threshold = 0.4}) async {
    final saved = await loadLocal();
    if (saved == null) return false;
    final dist = FaceEmbedding.cosineDistance(saved.vector, newVector);
    return dist < threshold;
  }
}

// ─────────────────────────────────────────────
// PANTALLA
// ─────────────────────────────────────────────
enum _FaceStep { instructions, scanning, confirm, saving, done, error }

class FaceRegisterScreen extends StatefulWidget {
  const FaceRegisterScreen({super.key});

  @override
  State<FaceRegisterScreen> createState() => _FaceRegisterScreenState();
}

class _FaceRegisterScreenState extends State<FaceRegisterScreen>
    with SingleTickerProviderStateMixin {
  CameraController? _camera;
  FaceDetector? _detector;
  bool _processing = false;

  _FaceStep _step = _FaceStep.instructions;
  String? _errorMsg;

  Face? _detectedFace;
  List<double>? _embedding;

  // Progreso de liveness (parpadeo)
  int _blinkCount = 0;
  bool _eyesClosed = false;
  static const _blinkTarget = 2;

  // Animación del anillo
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulse;

  // Instrucciones liveness
  static const _livenessHints = [
    'Mira directo a la cámara',
    'Mantén el rostro centrado',
    'Parpadea naturalmente',
  ];
  int _hintIdx = 0;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
    _pulse = Tween(begin: 1.0, end: 1.06).animate(
        CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      final front = cameras.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.front,
          orElse: () => cameras.first);

      _camera = CameraController(front, ResolutionPreset.high,
          enableAudio: false, imageFormatGroup: ImageFormatGroup.nv21);
      await _camera!.initialize();

      _detector = FaceDetector(
        options: FaceDetectorOptions(
          enableLandmarks: true,
          enableContours: true,
          enableClassification: true, // ojos, sonrisa
          performanceMode: FaceDetectorMode.accurate,
          minFaceSize: 0.25,
        ),
      );

      if (mounted) setState(() {});
    } catch (e) {
      setState(() {
        _step = _FaceStep.error;
        _errorMsg = 'No se pudo acceder a la cámara: $e';
      });
    }
  }

  Future<void> _startScan() async {
    if (_camera == null || !_camera!.value.isInitialized) return;
    setState(() {
      _step = _FaceStep.scanning;
      _blinkCount = 0;
      _eyesClosed = false;
      _hintIdx = 0;
    });
    _camera!.startImageStream(_processFrame);
    _cycleHints();
  }

  void _cycleHints() async {
    while (_step == _FaceStep.scanning && mounted) {
      await Future.delayed(const Duration(seconds: 2));
      if (mounted && _step == _FaceStep.scanning) {
        setState(() => _hintIdx = (_hintIdx + 1) % _livenessHints.length);
      }
    }
  }

  Future<void> _processFrame(CameraImage image) async {
    if (_processing || _step != _FaceStep.scanning) return;
    _processing = true;

    try {
      final inputImage = _buildInputImage(image);
      if (inputImage == null) { _processing = false; return; }

      final faces = await _detector!.processImage(inputImage);
      if (faces.isEmpty) { _processing = false; return; }

      final face = faces.first;

      // ── Liveness: detectar parpadeo ──
      final leftOpen  = face.leftEyeOpenProbability  ?? 1.0;
      final rightOpen = face.rightEyeOpenProbability ?? 1.0;
      final bothClosed = leftOpen < 0.3 && rightOpen < 0.3;

      if (bothClosed && !_eyesClosed) {
        _eyesClosed = true; // ojos se cerraron
      } else if (!bothClosed && _eyesClosed) {
        _eyesClosed = false; // ojos se abrieron → parpadeo completo
        _blinkCount++;
        if (mounted) setState(() {});
      }

      // ── Una vez alcanzado el parpadeo requerido, capturar ──
      if (_blinkCount >= _blinkTarget && !_processing) {
        await _camera!.stopImageStream();

        final embedding = FaceEmbeddingService.generateEmbedding(face);

        if (mounted) {
          setState(() {
            _step       = _FaceStep.confirm;
            _detectedFace = face;
            _embedding  = embedding;
          });
        }
      }
    } catch (_) {}

    _processing = false;
  }

  InputImage? _buildInputImage(CameraImage image) {
    if (_camera == null) return null;
    final rotation = _rotationFromSensor(
        _camera!.description.sensorOrientation);

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) return null;

    final plane = image.planes[0];
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  InputImageRotation _rotationFromSensor(int sensor) {
    switch (sensor) {
      case 90:  return InputImageRotation.rotation90deg;
      case 180: return InputImageRotation.rotation180deg;
      case 270: return InputImageRotation.rotation270deg;
      default:  return InputImageRotation.rotation0deg;
    }
  }

  Future<void> _saveEmbedding() async {
    if (_embedding == null) return;
    setState(() => _step = _FaceStep.saving);

    try {
      final emb = FaceEmbedding(
          vector: _embedding!, createdAt: DateTime.now());

      // 1. Guardar local (cifrado)
      await FaceEmbeddingService.saveLocal(emb);

      // 2. Subir al servidor (no bloquear si falla)
      final uploaded = await FaceEmbeddingService.uploadToServer(emb);

      // 3. Marcar como registrado en BiometricService
      await BiometricService.setFaceRegistered(true);

      if (mounted) {
        setState(() => _step = _FaceStep.done);
        await Future.delayed(const Duration(milliseconds: 1200));
        if (mounted) Navigator.of(context).pop(true);
      }

      if (!uploaded) {
        // El embedding quedó local; se puede sincronizar después
        debugPrint('[Face] Embedding guardado local. Sincronización pendiente.');
      }
    } catch (e) {
      setState(() {
        _step     = _FaceStep.error;
        _errorMsg = 'Error al guardar: $e';
      });
    }
  }

  void _retry() {
    setState(() {
      _step      = _FaceStep.instructions;
      _embedding = null;
      _blinkCount = 0;
    });
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _camera?.dispose();
    _detector?.close();
    super.dispose();
  }

  // ─────────── UI ───────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kBg,
        elevation: 0,
        title: const Text('Reconocimiento facial',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: _buildStep(),
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case _FaceStep.instructions:
        return _InstructionsView(onStart: _startScan);
      case _FaceStep.scanning:
        return _ScanningView(
          camera: _camera,
          pulse: _pulse,
          blinkCount: _blinkCount,
          blinkTarget: _blinkTarget,
          hint: _livenessHints[_hintIdx],
        );
      case _FaceStep.confirm:
        return _ConfirmView(
          onConfirm: _saveEmbedding,
          onRetry: _retry,
        );
      case _FaceStep.saving:
        return const _LoadingView(message: 'Guardando datos biométricos...');
      case _FaceStep.done:
        return const _DoneView();
      case _FaceStep.error:
        return _ErrorView(message: _errorMsg ?? 'Error desconocido',
            onRetry: _retry);
    }
  }
}

// ─────────────────────────────────────────────
// VISTAS PARCIALES
// ─────────────────────────────────────────────

class _InstructionsView extends StatelessWidget {
  final VoidCallback onStart;
  const _InstructionsView({required this.onStart});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        children: [
          const SizedBox(height: 20),
          Container(
            width: 100, height: 100,
            decoration: BoxDecoration(
              color: kAccent.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.face_retouching_natural,
                color: kAccent, size: 52),
          ),
          const SizedBox(height: 28),
          const Text('Registra tu rostro',
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w700, color: kText)),
          const SizedBox(height: 12),
          const Text(
            'Tu rostro se convierte en un vector matemático.\n'
            'Nunca se guarda la imagen, solo datos numéricos.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: kMuted, height: 1.5),
          ),
          const SizedBox(height: 32),
          _Tip(icon: Icons.light_mode_outlined,
              text: 'Busca buena iluminación frontal'),
          const SizedBox(height: 10),
          _Tip(icon: Icons.remove_red_eye_outlined,
              text: 'Parpadea $_blinkTarget veces cuando se te indique'),
          const SizedBox(height: 10),
          _Tip(icon: Icons.no_photography_outlined,
              text: 'No uses lentes de sol ni cubrebocas'),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: onStart,
            icon: const Icon(Icons.camera_alt_outlined),
            label: const Text('Iniciar escaneo'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 52),
            ),
          ),
        ],
      ),
    );
  }

  static int get _blinkTarget => 2;
}

class _Tip extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Tip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, color: kAccent, size: 20),
      const SizedBox(width: 12),
      Expanded(child: Text(text,
          style: const TextStyle(fontSize: 13, color: kText))),
    ]);
  }
}

class _ScanningView extends StatelessWidget {
  final CameraController? camera;
  final Animation<double> pulse;
  final int blinkCount;
  final int blinkTarget;
  final String hint;

  const _ScanningView({
    required this.camera,
    required this.pulse,
    required this.blinkCount,
    required this.blinkTarget,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Stack(children: [
      // Fondo cámara
      if (camera != null && camera!.value.isInitialized)
        SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: camera!.value.previewSize!.height,
              height: camera!.value.previewSize!.width,
              child: CameraPreview(camera!),
            ),
          ),
        )
      else
        Container(color: Colors.black),

      // Overlay oscuro
      Container(color: Colors.black.withValues(alpha: 0.45)),

      // Anillo pulsante
      Center(
        child: AnimatedBuilder(
          animation: pulse,
          builder: (_, child) => Transform.scale(
            scale: pulse.value,
            child: child,
          ),
          child: Container(
            width: size.width * 0.68,
            height: size.width * 0.68,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: kAccent, width: 3),
            ),
          ),
        ),
      ),

      // HUD inferior
      Positioned(
        left: 0, right: 0, bottom: 48,
        child: Column(children: [
          // Progreso parpadeo
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(blinkTarget, (i) => Container(
              margin: const EdgeInsets.symmetric(horizontal: 6),
              width: 36, height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < blinkCount
                    ? kAccent
                    : kAccent.withValues(alpha: 0.25),
                border: Border.all(color: kAccent, width: 1.5),
              ),
              child: Icon(
                i < blinkCount
                    ? Icons.check
                    : Icons.remove_red_eye_outlined,
                color: Colors.white,
                size: 18,
              ),
            )),
          ),
          const SizedBox(height: 16),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 40),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(30),
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              child: Text(
                hint,
                key: ValueKey(hint),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
          ),
        ]),
      ),
    ]);
  }
}

class _ConfirmView extends StatelessWidget {
  final VoidCallback onConfirm;
  final VoidCallback onRetry;
  const _ConfirmView({required this.onConfirm, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 90, height: 90,
            decoration: BoxDecoration(
              color: const Color(0xFF22C55E).withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_circle_outline,
                color: Color(0xFF22C55E), size: 48),
          ),
          const SizedBox(height: 24),
          const Text('Rostro detectado',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: kText)),
          const SizedBox(height: 10),
          const Text(
            'Se generó tu vector biométrico de 128 dimensiones.\n'
            '¿Deseas guardar este registro?',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: kMuted, height: 1.5),
          ),
          const SizedBox(height: 36),
          ElevatedButton(
            onPressed: onConfirm,
            style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 52)),
            child: const Text('Guardar registro facial'),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: onRetry,
            child: const Text('Volver a escanear',
                style: TextStyle(color: kMuted)),
          ),
        ],
      ),
    );
  }
}

class _LoadingView extends StatelessWidget {
  final String message;
  const _LoadingView({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const CircularProgressIndicator(color: kAccent),
        const SizedBox(height: 20),
        Text(message,
            style: const TextStyle(color: kMuted, fontSize: 14)),
      ]),
    );
  }
}

class _DoneView extends StatelessWidget {
  const _DoneView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.verified_user_outlined,
            color: Color(0xFF22C55E), size: 64),
        const SizedBox(height: 20),
        const Text('¡Listo!',
            style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: Color(0xFF22C55E))),
        const SizedBox(height: 8),
        const Text('Tu rostro fue registrado correctamente.',
            style: TextStyle(color: kMuted, fontSize: 14)),
      ]),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.error_outline, color: kError, size: 56),
        const SizedBox(height: 16),
        const Text('Algo salió mal',
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w700, color: kText)),
        const SizedBox(height: 8),
        Text(message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: kMuted)),
        const SizedBox(height: 28),
        ElevatedButton(
          onPressed: onRetry,
          style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 52)),
          child: const Text('Intentar de nuevo'),
        ),
      ]),
    );
  }
}