import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../../theme.dart';

class FaceScanScreen extends StatefulWidget {
  const FaceScanScreen({super.key});

  @override
  State<FaceScanScreen> createState() => _FaceScanScreenState();
}

class _FaceScanScreenState extends State<FaceScanScreen> {
  CameraController? _camCtrl;
  FaceDetector?     _detector;

  bool _iniciando     = true;
  bool _procesando    = false;
  bool _caraDetectada = false;
  bool _escaneando    = false;
  bool _exitoso       = false;

  List<Face> _caras = [];
  Size _previewSize  = Size.zero;

  Map<String, String>? _credencial;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _detector = FaceDetector(
      options: FaceDetectorOptions(
        enableLandmarks:      true,
        enableClassification: true,
        enableContours:       true,
        performanceMode:      FaceDetectorMode.accurate,
        minFaceSize:          0.20,
      ),
    );

    final camaras = await availableCameras();
    final frontal = camaras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => camaras.first,
    );

    _camCtrl = CameraController(
      frontal,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.nv21,
    );

    await _camCtrl!.initialize();
    if (!mounted) return;

    // En versiones recientes de camera el previewSize ya viene orientado
    _previewSize = Size(
      _camCtrl!.value.previewSize!.height,
      _camCtrl!.value.previewSize!.width,
    );

    setState(() => _iniciando = false);
    _camCtrl!.startImageStream(_procesarFrame);
  }

  Future<void> _procesarFrame(CameraImage image) async {
    if (_procesando || _exitoso) return;
    _procesando = true;

    try {
      final inputImage = _toInputImage(image);
      if (inputImage == null) { _procesando = false; return; }

      final caras = await _detector!.processImage(inputImage);
      if (!mounted) { _procesando = false; return; }

      setState(() {
        _caras         = caras;
        _caraDetectada = caras.isNotEmpty;
      });
    } catch (_) {}

    _procesando = false;
  }

  InputImage? _toInputImage(CameraImage image) {
    final camDesc  = _camCtrl!.description;
    final rotation = _rotacion(camDesc.sensorOrientation);
    final format   = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) return null;

    // API nueva: InputImageMetadata en lugar de InputImageData
    final metadata = InputImageMetadata(
      size:     Size(image.width.toDouble(), image.height.toDouble()),
      rotation: rotation,
      format:   format,
      bytesPerRow: image.planes.first.bytesPerRow,
    );

    return InputImage.fromBytes(
      bytes:    _unirPlanos(image.planes),
      metadata: metadata,
    );
  }

  Uint8List _unirPlanos(List<Plane> planes) {
    final buffer = WriteBuffer();
    for (final p in planes) {
      buffer.putUint8List(p.bytes);
    }
    return buffer.done().buffer.asUint8List();
  }

  InputImageRotation _rotacion(int sensor) {
    switch (sensor) {
      case 90:  return InputImageRotation.rotation90deg;
      case 180: return InputImageRotation.rotation180deg;
      case 270: return InputImageRotation.rotation270deg;
      default:  return InputImageRotation.rotation0deg;
    }
  }

  // ── Capturar ───────────────────────────────────────────────

  Future<void> _capturar() async {
    if (!_caraDetectada || _caras.isEmpty) return;
    setState(() => _escaneando = true);

    await Future.delayed(const Duration(milliseconds: 800));

    final cara = _caras.first;
    final ts   = DateTime.now().millisecondsSinceEpoch;
    final puntos = _extraerPuntos(cara);

    if (!mounted) return;
    setState(() {
      _escaneando = false;
      _exitoso    = true;
      _credencial = {
        'tipo':          'cara',
        'clave':         'BIO-CARA-$ts',
        'fecha':         DateTime.now().toString().substring(0, 19),
        'puntos':        puntos.isNotEmpty ? puntos : 'detectados',
        'ojos_abiertos': _ojosAbiertos(cara),
        'angulo_y':      cara.headEulerAngleY?.toStringAsFixed(1) ?? '0',
      };
    });

    await _camCtrl?.stopImageStream();
  }

  String _extraerPuntos(Face cara) {
    final lm     = cara.landmarks;
    final partes = <String>[];
    if (lm[FaceLandmarkType.leftEye]    != null) partes.add('ojo izq');
    if (lm[FaceLandmarkType.rightEye]   != null) partes.add('ojo der');
    if (lm[FaceLandmarkType.noseBase]   != null) partes.add('nariz');
    if (lm[FaceLandmarkType.leftMouth]  != null) partes.add('boca izq');
    if (lm[FaceLandmarkType.rightMouth] != null) partes.add('boca der');
    if (lm[FaceLandmarkType.leftEar]    != null) partes.add('oreja izq');
    if (lm[FaceLandmarkType.rightEar]   != null) partes.add('oreja der');
    return partes.join(', ');
  }

  String _ojosAbiertos(Face cara) {
    final l = cara.leftEyeOpenProbability;
    final r = cara.rightEyeOpenProbability;
    if (l == null && r == null) return 'N/A';
    final prom = ((l ?? 0) + (r ?? 0)) / 2;
    return '${(prom * 100).toStringAsFixed(0)}%';
  }

  Future<void> _reiniciar() async {
    setState(() {
      _exitoso       = false;
      _credencial    = null;
      _caraDetectada = false;
      _caras         = [];
    });
    await _camCtrl?.startImageStream(_procesarFrame);
  }

  @override
  void dispose() {
    _camCtrl?.stopImageStream();
    _camCtrl?.dispose();
    _detector?.close();
    super.dispose();
  }

  // ── Build ──────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Reconocimiento facial'),
      ),
      body: _iniciando
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: kAccent),
                  SizedBox(height: 16),
                  Text('Iniciando cámara...',
                      style: TextStyle(color: Colors.white70, fontSize: 14)),
                ],
              ),
            )
          : _exitoso
              ? _buildResultado()
              : _buildCamara(),
    );
  }

  // ── Vista cámara ───────────────────────────────────────────

  Widget _buildCamara() {
    return Column(
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              ClipRect(child: CameraPreview(_camCtrl!)),

              // Puntos faciales
              if (_caras.isNotEmpty)
                CustomPaint(
                  painter: _FacePainter(
                    caras:      _caras,
                    imageSize:  _previewSize,
                    esEspejo:   true,
                  ),
                ),

              // Marco oval
              Center(
                child: Container(
                  width: 220, height: 280,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: _caraDetectada ? kAccent : Colors.white38,
                      width: 2.5,
                    ),
                    borderRadius: BorderRadius.circular(140),
                  ),
                ),
              ),

              // Estado
              Positioned(
                top: 20, left: 0, right: 0,
                child: Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 8),
                    decoration: BoxDecoration(
                      color: _caraDetectada
                          ? kAccent.withValues(alpha: 0.85)
                          : Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _escaneando
                          ? 'Capturando...'
                          : _caraDetectada
                              ? '✓ Cara detectada'
                              : 'Coloca tu cara en el óvalo',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),

              // Puntos badge
              if (_caraDetectada && !_escaneando)
                Positioned(
                  bottom: 100, left: 0, right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _extraerPuntos(_caras.first).isNotEmpty
                            ? 'Puntos: ${_extraerPuntos(_caras.first)}'
                            : 'Analizando...',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 11),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),

        // Botón capturar
        Container(
          color: Colors.black,
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 32),
          child: Column(children: [
            if (_escaneando)
              const CircularProgressIndicator(color: kAccent)
            else
              GestureDetector(
                onTap: _caraDetectada ? _capturar : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: 72, height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _caraDetectada ? kAccent : Colors.white24,
                    boxShadow: _caraDetectada
                        ? [BoxShadow(
                            color: kAccent.withValues(alpha: 0.5),
                            blurRadius: 20, spreadRadius: 4)]
                        : [],
                  ),
                  child: Icon(
                    Icons.face_retouching_natural,
                    color: _caraDetectada ? Colors.white : Colors.white38,
                    size: 32,
                  ),
                ),
              ),
            const SizedBox(height: 10),
            Text(
              _caraDetectada ? 'Toca para capturar' : 'Esperando detección...',
              style: TextStyle(
                  color: _caraDetectada ? Colors.white70 : Colors.white38,
                  fontSize: 12),
            ),
          ]),
        ),
      ],
    );
  }

  // ── Vista resultado ────────────────────────────────────────

  Widget _buildResultado() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: kAccent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: kAccent.withValues(alpha: 0.4)),
            ),
            child: const Row(children: [
              Icon(Icons.check_circle, color: kAccent, size: 24),
              SizedBox(width: 10),
              Text('¡Reconocimiento facial exitoso!',
                  style: TextStyle(
                      color: kAccent,
                      fontSize: 14,
                      fontWeight: FontWeight.w700)),
            ]),
          ),
          const SizedBox(height: 20),

          const Text('CREDENCIAL GENERADA',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.white54,
                  letterSpacing: 1.2)),
          const SizedBox(height: 10),

          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF111111),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(children: [
              const Icon(Icons.face_retouching_natural,
                  size: 56, color: kAccent),
              const SizedBox(height: 12),
              const Text('Reconocimiento facial',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white)),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: kAccent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text('Verificado',
                    style: TextStyle(
                        fontSize: 12,
                        color: kAccent,
                        fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 20),
              const Divider(color: Colors.white12),
              const SizedBox(height: 14),
              _CredRow(icon: Icons.vpn_key_outlined,
                  label: 'Clave',           value: _credencial!['clave']!),
              const SizedBox(height: 10),
              _CredRow(icon: Icons.track_changes,
                  label: 'Puntos faciales',  value: _credencial!['puntos']!),
              const SizedBox(height: 10),
              _CredRow(icon: Icons.remove_red_eye_outlined,
                  label: 'Ojos abiertos',   value: _credencial!['ojos_abiertos']!),
              const SizedBox(height: 10),
              _CredRow(icon: Icons.rotate_left,
                  label: 'Ángulo facial',   value: '${_credencial!['angulo_y']}°'),
              const SizedBox(height: 10),
              _CredRow(icon: Icons.schedule_outlined,
                  label: 'Fecha',           value: _credencial!['fecha']!),
            ]),
          ),

          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(children: [
              Icon(Icons.info_outline, size: 16, color: Colors.white38),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Próximamente esta credencial se vinculará a tu cuenta para autenticación multi-dispositivo.',
                  style: TextStyle(fontSize: 11, color: Colors.white38),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 20),

          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: kAccent,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _reiniciar,
            icon: const Icon(Icons.refresh),
            label: const Text('Escanear de nuevo'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white70,
              side: const BorderSide(color: Colors.white24),
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Volver al perfil'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────
//  PAINTER
// ─────────────────────────────────────────

class _FacePainter extends CustomPainter {
  final List<Face> caras;
  final Size imageSize;
  final bool esEspejo;

  const _FacePainter({
    required this.caras,
    required this.imageSize,
    required this.esEspejo,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paintPunto = Paint()
      ..color = kAccent
      ..style = PaintingStyle.fill;

    final paintLinea = Paint()
      ..color       = kAccent.withValues(alpha: 0.5)
      ..style       = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final paintCaja = Paint()
      ..color       = kAccent.withValues(alpha: 0.6)
      ..style       = PaintingStyle.stroke
      ..strokeWidth = 2;

    for (final cara in caras) {
      final rect = _escalarRect(cara.boundingBox, size);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(12)),
        paintCaja,
      );

      final puntos = <Offset>[];
      for (final tipo in FaceLandmarkType.values) {
        final lm = cara.landmarks[tipo];
        if (lm != null) {
          final pos = _escalarPunto(
            Offset(lm.position.x.toDouble(), lm.position.y.toDouble()),
            size,
          );
          puntos.add(pos);
          canvas.drawCircle(pos, 4, paintPunto);
        }
      }

      for (int i = 0; i < puntos.length - 1; i++) {
        if ((puntos[i] - puntos[i + 1]).distance < 80) {
          canvas.drawLine(puntos[i], puntos[i + 1], paintLinea);
        }
      }
    }
  }

  Rect _escalarRect(Rect rect, Size canvas) {
    final sx   = canvas.width  / imageSize.width;
    final sy   = canvas.height / imageSize.height;
    final left = esEspejo
        ? canvas.width - rect.right * sx
        : rect.left * sx;
    return Rect.fromLTWH(left, rect.top * sy, rect.width * sx, rect.height * sy);
  }

  Offset _escalarPunto(Offset p, Size canvas) {
    final sx = canvas.width  / imageSize.width;
    final sy = canvas.height / imageSize.height;
    final x  = esEspejo ? canvas.width - p.dx * sx : p.dx * sx;
    return Offset(x, p.dy * sy);
  }

  @override
  bool shouldRepaint(_FacePainter old) => old.caras != caras;
}

// ─────────────────────────────────────────

class _CredRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _CredRow(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.white38),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 11, color: Colors.white38)),
                const SizedBox(height: 2),
                Text(value,
                    style: const TextStyle(
                        fontSize: 13,
                        color: Colors.white,
                        fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      );
}