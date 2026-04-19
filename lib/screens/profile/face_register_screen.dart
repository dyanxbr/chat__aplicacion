import 'dart:convert';
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../services/auth_service.dart';
import '../../services/biometric_service.dart';
import '../../services/face_embedding_service.dart';
import '../../theme.dart';

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
  bool _captured = false;

  _FaceStep _step = _FaceStep.instructions;
  String? _errorMsg;

  List<double>? _embedding;

  int _blinkCount = 0;
  bool _eyesClosed = false;
  static const _blinkTarget = 2;

  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulse;

  static const _hints = [
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

      _camera = CameraController(
        front,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.nv21,
      );
      await _camera!.initialize();

      _detector = FaceDetector(
        options: FaceDetectorOptions(
          enableLandmarks: true,
          enableContours: true,
          enableClassification: true,
          performanceMode: FaceDetectorMode.accurate,
          minFaceSize: 0.25,
        ),
      );

      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        setState(() {
          _step = _FaceStep.error;
          _errorMsg = 'No se pudo acceder a la cámara: $e';
        });
      }
    }
  }

  Future<void> _startScan() async {
    if (_camera == null || !_camera!.value.isInitialized) return;
    setState(() {
      _step = _FaceStep.scanning;
      _blinkCount = 0;
      _eyesClosed = false;
      _hintIdx = 0;
      _captured = false;
    });
    await _camera!.startImageStream(_processFrame);
    _cycleHints();
  }

  void _cycleHints() async {
    while (_step == _FaceStep.scanning && mounted) {
      await Future.delayed(const Duration(seconds: 2));
      if (mounted && _step == _FaceStep.scanning) {
        setState(() => _hintIdx = (_hintIdx + 1) % _hints.length);
      }
    }
  }

  Future<void> _processFrame(CameraImage image) async {
    if (_processing || _captured || _step != _FaceStep.scanning) return;
    _processing = true;

    try {
      final inputImage = _buildInputImage(image);
      if (inputImage == null) {
        _processing = false;
        return;
      }

      final faces = await _detector!.processImage(inputImage);
      if (faces.isEmpty) {
        _processing = false;
        return;
      }

      final face = faces.first;
      final leftOpen = face.leftEyeOpenProbability ?? 1.0;
      final rightOpen = face.rightEyeOpenProbability ?? 1.0;
      final bothClosed = leftOpen < 0.3 && rightOpen < 0.3;

      if (bothClosed && !_eyesClosed) {
        _eyesClosed = true;
      } else if (!bothClosed && _eyesClosed) {
        _eyesClosed = false;
        _blinkCount++;
        if (mounted) setState(() {});
      }

      if (_blinkCount >= _blinkTarget) {
        _captured = true;
        await _camera!.stopImageStream();

        final embedding = FaceEmbeddingService.generateEmbedding(face);

        if (mounted) {
          setState(() {
            _step = _FaceStep.confirm;
            _embedding = embedding;
          });
        }
      }
    } catch (e) {
      debugPrint('[FaceRegister] error en frame: $e');
    }

    _processing = false;
  }

  InputImage? _buildInputImage(CameraImage image) {
    if (_camera == null) return null;
    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) return null;
    final plane = image.planes[0];
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: _rotationFromSensor(_camera!.description.sensorOrientation),
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  InputImageRotation _rotationFromSensor(int sensor) {
    switch (sensor) {
      case 90:
        return InputImageRotation.rotation90deg;
      case 180:
        return InputImageRotation.rotation180deg;
      case 270:
        return InputImageRotation.rotation270deg;
      default:
        return InputImageRotation.rotation0deg;
    }
  }

  Future<void> _testMySQLConnection() async {
    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Probando conexión MySQL...'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      
      final email = await AuthService.getUserEmail();
      debugPrint('📧 Email del usuario: $email');
      
      if (email == null) {
        debugPrint('❌ No se encontró email de usuario');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No se encontró email de usuario. Inicia sesión nuevamente.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }
      
      final userId = await FaceEmbeddingService.getCurrentUserId();
      debugPrint('🆔 UserId obtenido: $userId');
      
      final isConnected = await FaceEmbeddingService.testConnection();
      
      if (isConnected && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Conexión MySQL exitosa!'),
            backgroundColor: Colors.green,
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Error de conexión MySQL'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Error de conexión MySQL: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error: ${e.toString().substring(0, 100)}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Future<void> _saveEmbedding() async {
    if (_embedding == null) return;
    setState(() => _step = _FaceStep.saving);

    try {
      final isLoggedIn = await AuthService.isLoggedIn();
      if (!isLoggedIn) {
        throw Exception('Usuario no autenticado. Por favor inicia sesión primero.');
      }

      final saved = await FaceEmbeddingService.saveToServer(_embedding!);
      
      if (!saved) {
        throw Exception('Error al guardar en la base de datos');
      }

      await BiometricService.setFaceRegistered(true);

      if (mounted) {
        setState(() => _step = _FaceStep.done);
        await Future.delayed(const Duration(milliseconds: 1200));
        if (mounted) Navigator.of(context).pop(true);
      }
    } catch (e) {
      debugPrint('[FaceRegister] Error guardando: $e');
      if (mounted) {
        setState(() {
          _step = _FaceStep.error;
          _errorMsg = 'Error al guardar: ${e.toString()}';
        });
      }
    }
  }

  void _retry() {
    setState(() {
      _step = _FaceStep.instructions;
      _embedding = null;
      _blinkCount = 0;
      _captured = false;
    });
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _camera?.dispose();
    _detector?.close();
    super.dispose();
  }

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
        actions: [
          IconButton(
            icon: const Icon(Icons.bug_report, color: kAccent),
            onPressed: _testMySQLConnection,
            tooltip: 'Probar conexión MySQL',
          ),
        ],
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
          hint: _hints[_hintIdx],
        );
      case _FaceStep.confirm:
        return _ConfirmView(onConfirm: _saveEmbedding, onRetry: _retry);
      case _FaceStep.saving:
        return const _LoadingView(message: 'Guardando datos biométricos...');
      case _FaceStep.done:
        return const _DoneView();
      case _FaceStep.error:
        return _ErrorView(
            message: _errorMsg ?? 'Error desconocido', onRetry: _retry);
    }
  }
}


class _InstructionsView extends StatelessWidget {
  final VoidCallback onStart;
  const _InstructionsView({required this.onStart});

  static const _blinkTarget = 2;

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(28),
      child: Column(children: [
        SizedBox(height: 20),
        _IconCircle(),
        SizedBox(height: 28),
        Text('Registra tu rostro',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: kText)),
        SizedBox(height: 12),
        Text(
          'Tu rostro se convierte en un vector matemático.\n'
          'Nunca se guarda la imagen, solo datos numéricos.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: kMuted, height: 1.5),
        ),
        SizedBox(height: 32),
        _Tip(icon: Icons.light_mode_outlined, text: 'Busca buena iluminación frontal'),
        SizedBox(height: 10),
        _Tip(icon: Icons.remove_red_eye_outlined, text: 'Parpadea 2 veces cuando se te indique'),
        SizedBox(height: 10),
        _Tip(icon: Icons.no_photography_outlined, text: 'No uses lentes de sol ni cubrebocas'),
        Spacer(),
        _StartButton(),
      ]),
    );
  }
}

class _IconCircle extends StatelessWidget {
  const _IconCircle();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        color: kAccent.withValues(alpha: 0.1),
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.face_retouching_natural, color: kAccent, size: 52),
    );
  }
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
      Expanded(
        child: Text(text, style: const TextStyle(fontSize: 13, color: kText)),
      ),
    ]);
  }
}

class _StartButton extends StatelessWidget {
  const _StartButton();

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: () {
        final state = context.findAncestorStateOfType<_FaceRegisterScreenState>();
        state?._startScan();
      },
      icon: const Icon(Icons.camera_alt_outlined),
      label: const Text('Iniciar escaneo'),
      style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
    );
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
      Container(color: Colors.black.withValues(alpha: 0.45)),
      Center(
        child: AnimatedBuilder(
          animation: pulse,
          builder: (_, child) => Transform.scale(scale: pulse.value, child: child),
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
      Positioned(
        left: 0,
        right: 0,
        bottom: 48,
        child: Column(children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(blinkTarget, (i) => Container(
              margin: const EdgeInsets.symmetric(horizontal: 6),
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < blinkCount ? kAccent : kAccent.withValues(alpha: 0.25),
                border: Border.all(color: kAccent, width: 1.5),
              ),
              child: Icon(
                i < blinkCount ? Icons.check : Icons.remove_red_eye_outlined,
                color: Colors.white,
                size: 18,
              ),
            )),
          ),
          const SizedBox(height: 16),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            child: Container(
              key: ValueKey(hint),
              margin: const EdgeInsets.symmetric(horizontal: 40),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Text(hint,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 14)),
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
            width: 90,
            height: 90,
            decoration: BoxDecoration(
              color: const Color(0xFF22C55E).withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_circle_outline, color: Color(0xFF22C55E), size: 48),
          ),
          const SizedBox(height: 24),
          const Text('Rostro detectado',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: kText)),
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
            style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
            child: const Text('Guardar registro facial'),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: onRetry,
            child: const Text('Volver a escanear', style: TextStyle(color: kMuted)),
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
        Text(message, style: const TextStyle(color: kMuted, fontSize: 14)),
      ]),
    );
  }
}

class _DoneView extends StatelessWidget {
  const _DoneView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.verified_user_outlined, color: Color(0xFF22C55E), size: 64),
        SizedBox(height: 20),
        Text('¡Listo!',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Color(0xFF22C55E))),
        SizedBox(height: 8),
        Text('Tu rostro fue registrado correctamente.',
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
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: kText)),
        const SizedBox(height: 8),
        Text(message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: kMuted)),
        const SizedBox(height: 28),
        ElevatedButton(
          onPressed: onRetry,
          style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
          child: const Text('Intentar de nuevo'),
        ),
      ]),
    );
  }
}