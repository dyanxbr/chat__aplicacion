import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../../services/face_embedding_service.dart';
import '../../services/auth_service.dart';
import '../../theme.dart';

enum _LoginStep { instructions, scanning, verifying, success, error }

class FaceLoginScreen extends StatefulWidget {
  const FaceLoginScreen({super.key});

  @override
  State<FaceLoginScreen> createState() => _FaceLoginScreenState();
}

class _FaceLoginScreenState extends State<FaceLoginScreen>
    with SingleTickerProviderStateMixin {
  CameraController? _camera;
  FaceDetector? _detector;
  bool _processing = false;
  bool _verified = false;
  _LoginStep _step = _LoginStep.instructions;
  String? _errorMsg;
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulse;
  
  int _attemptCount = 0;
  static const int _maxAttempts = 3;

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
          _step = _LoginStep.error;
          _errorMsg = 'No se pudo acceder a la cámara: $e';
        });
      }
    }
  }

  Future<void> _startVerification() async {
    if (_camera == null || !_camera!.value.isInitialized) return;
    
    setState(() {
      _step = _LoginStep.scanning;
      _verified = false;
      _attemptCount = 0;
    });
    
    await _camera!.startImageStream(_processFrame);
  }

  Future<void> _processFrame(CameraImage image) async {
    if (_processing || _verified || _step != _LoginStep.scanning) return;
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
      final newEmbedding = FaceEmbeddingService.generateEmbedding(face);

      setState(() => _step = _LoginStep.verifying);

      final isMatch = await FaceEmbeddingService.verifyFace(newEmbedding);
      
      bool localMatch = false;
      if (!isMatch) {
        localMatch = await FaceEmbeddingService.verifyLocal(newEmbedding);
      }

      if ((isMatch || localMatch) && !_verified) {
        _verified = true;
        await _camera!.stopImageStream();

        if (mounted) {
          setState(() => _step = _LoginStep.success);
          await Future.delayed(const Duration(milliseconds: 1500));
          if (mounted) {
            Navigator.of(context).pop(true);
          }
        }
      } else if (!isMatch && !localMatch && _step == _LoginStep.verifying) {
        _attemptCount++;
        
        if (_attemptCount >= _maxAttempts) {
          if (mounted) {
            setState(() {
              _step = _LoginStep.error;
              _errorMsg = 'No se reconoció tu rostro después de $_maxAttempts intentos. Asegúrate de tener buena iluminación y estar mirando directamente a la cámara.';
            });
            await _camera!.stopImageStream();
          }
        } else {
          setState(() => _step = _LoginStep.scanning);
        }
      }
    } catch (e) {
      debugPrint('[FaceLogin] error: $e');
      if (mounted && _step == _LoginStep.verifying) {
        setState(() {
          _step = _LoginStep.error;
          _errorMsg = 'Error al verificar: ${e.toString()}';
        });
        await _camera!.stopImageStream();
      }
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

  void _retry() {
    setState(() {
      _step = _LoginStep.instructions;
      _verified = false;
      _attemptCount = 0;
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
        title: const Text('Inicio facial',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
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
      case _LoginStep.instructions:
        return _InstructionsView(onStart: _startVerification);
      case _LoginStep.scanning:
        return _ScanningView(
          camera: _camera,
          pulse: _pulse,
          message: 'Mirando a la cámara... (Intento ${_attemptCount + 1}/$_maxAttempts)',
        );
      case _LoginStep.verifying:
        return const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: kAccent),
              SizedBox(height: 20),
              Text('Verificando rostro...',
                  style: TextStyle(color: kMuted, fontSize: 14)),
            ],
          ),
        );
      case _LoginStep.success:
        return const _SuccessView();
      case _LoginStep.error:
        return _ErrorView(message: _errorMsg ?? 'Error', onRetry: _retry);
    }
  }
}

class _InstructionsView extends StatelessWidget {
  final VoidCallback onStart;
  const _InstructionsView({required this.onStart});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(28),
      child: Column(
        children: [
          SizedBox(height: 20),
          _IconCircle(),
          SizedBox(height: 28),
          Text('Iniciar sesión con tu rostro',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: kText)),
          SizedBox(height: 12),
          Text(
            'Mira directamente a la cámara para verificar tu identidad.\n'
            'Tu rostro se compara con el registro guardado en la base de datos.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: kMuted, height: 1.5),
          ),
          SizedBox(height: 32),
          _Tip(icon: Icons.light_mode_outlined, text: 'Busca buena iluminación frontal'),
          SizedBox(height: 10),
          _Tip(icon: Icons.center_focus_strong_outlined, text: 'Mantén el rostro centrado'),
          SizedBox(height: 10),
          _Tip(icon: Icons.remove_red_eye_outlined, text: 'Abre bien los ojos'),
          Spacer(),
          _StartButton(),
        ],
      ),
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
          child: Text(text, style: const TextStyle(fontSize: 13, color: kText))),
    ]);
  }
}

class _StartButton extends StatelessWidget {
  const _StartButton();

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: () {
        final state = context.findAncestorStateOfType<_FaceLoginScreenState>();
        state?._startVerification();
      },
      icon: const Icon(Icons.camera_alt_outlined),
      label: const Text('Iniciar verificación'),
      style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
    );
  }
}

class _ScanningView extends StatelessWidget {
  final CameraController? camera;
  final Animation<double> pulse;
  final String message;

  const _ScanningView({
    required this.camera,
    required this.pulse,
    required this.message,
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
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 40),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(30),
          ),
          child: Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 14)),
        ),
      ),
    ]);
  }
}

class _SuccessView extends StatelessWidget {
  const _SuccessView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.verified_user_outlined, color: Color(0xFF22C55E), size: 64),
        SizedBox(height: 20),
        Text('¡Bienvenido!',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Color(0xFF22C55E))),
        SizedBox(height: 8),
        Text('Identidad verificada correctamente.',
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
        const Text('No se pudo verificar',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: kText)),
        const SizedBox(height: 8),
        Text(message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: kMuted)),
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