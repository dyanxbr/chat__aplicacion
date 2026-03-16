import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme.dart';

// ── Construye la URL correcta para archivos del storage de Laravel ─────────────
// La API puede devolver el path de varias formas:
//   "perfiles/foto.jpg"
//   "storage/perfiles/foto.jpg"
//   "chat/archivo.png"
// Siempre resulta en: https://dominio/storage/perfiles/foto.jpg
String storageUrl(String path) {
  if (path.startsWith('http')) return path;
  // Quitar prefijo "storage/" si ya viene incluido
  final clean = path.startsWith('storage/') ? path.substring(8) : path;
  return '$kApiBase/storage/$clean';
}

// ── Widget de imagen de red con fallback robusto ──────────────────────────────
class NetImage extends StatelessWidget {
  final String path;
  final double width;
  final double height;
  final BoxFit fit;
  final Widget Function()? fallback;

  const NetImage({
    super.key,
    required this.path,
    this.width = 200,
    this.height = 130,
    this.fit = BoxFit.cover,
    this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    final url = storageUrl(path);
    return Image.network(
      url,
      width: width,
      height: height,
      fit: fit,
      loadingBuilder: (_, child, progress) {
        if (progress == null) return child;
        return SizedBox(
          width: width,
          height: height,
          child: Center(
            child: CircularProgressIndicator(
              value: progress.expectedTotalBytes != null
                  ? progress.cumulativeBytesLoaded /
                      progress.expectedTotalBytes!
                  : null,
              color: kAccent,
              strokeWidth: 2,
            ),
          ),
        );
      },
      errorBuilder: (_, error, __) {
        // Si falla, intentar con la URL alternativa (sin /storage/)
        final altUrl = '$kApiBase/$path';
        if (altUrl != url) {
          return Image.network(
            altUrl,
            width: width,
            height: height,
            fit: fit,
            errorBuilder: (_, __, ___) =>
                fallback?.call() ?? _brokenIcon(),
          );
        }
        return fallback?.call() ?? _brokenIcon();
      },
    );
  }

  Widget _brokenIcon() => SizedBox(
        width: width,
        height: height,
        child: const Center(
          child: Icon(Icons.broken_image_outlined, color: kMuted, size: 28),
        ),
      );
}

// ── Avatar letra ──────────────────────────────────────────────────────────────
class LetterAvatar extends StatelessWidget {
  final String nombre;
  final double size;
  const LetterAvatar({super.key, required this.nombre, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final letter = nombre.isNotEmpty ? nombre[0].toUpperCase() : '?';
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
          color: kAccent.withValues(alpha: 0.18), shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(letter,
          style: TextStyle(
              color: kAccent,
              fontSize: size * 0.4,
              fontWeight: FontWeight.w700)),
    );
  }
}

// ── Avatar con foto de perfil real o letra ────────────────────────────────────
class UserAvatar extends StatelessWidget {
  final Map<String, dynamic> user;
  final double size;
  const UserAvatar({super.key, required this.user, this.size = 42});

  @override
  Widget build(BuildContext context) {
    final foto = user['foto'] as String?;
    if (foto != null && foto.isNotEmpty) {
      return ClipOval(
        child: NetImage(
          path: foto,
          width: size,
          height: size,
          fit: BoxFit.cover,
          fallback: () => LetterAvatar(
              nombre: user['nombre'] as String? ?? '', size: size),
        ),
      );
    }
    return LetterAvatar(nombre: user['nombre'] as String? ?? '', size: size);
  }
}

// ── Campo con etiqueta ────────────────────────────────────────────────────────
class LabeledField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final bool obscure;
  final TextInputType keyboardType;
  final String? hint;
  final Widget? suffix;
  const LabeledField({
    super.key,
    required this.label,
    required this.controller,
    this.obscure = false,
    this.keyboardType = TextInputType.text,
    this.hint,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
          style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: kMuted,
              letterSpacing: 0.5)),
      const SizedBox(height: 6),
      TextFormField(
        controller: controller,
        obscureText: obscure,
        keyboardType: keyboardType,
        style: const TextStyle(color: kText, fontSize: 14),
        decoration: InputDecoration(hintText: hint, suffixIcon: suffix),
      ),
    ]);
  }
}

// ── Error box ─────────────────────────────────────────────────────────────────
class ErrorBox extends StatelessWidget {
  final String message;
  const ErrorBox(this.message, {super.key});
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: kError.withValues(alpha: 0.08),
          border: Border.all(color: kError.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(message,
            style: const TextStyle(color: kError, fontSize: 13)),
      );
}

// ── Success box ───────────────────────────────────────────────────────────────
class SuccessBox extends StatelessWidget {
  final String message;
  const SuccessBox(this.message, {super.key});
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: kSuccess.withValues(alpha: 0.08),
          border: Border.all(color: kSuccess.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(message,
            style: const TextStyle(color: kSuccess, fontSize: 13)),
      );
}

// ── Burbuja de mensaje ────────────────────────────────────────────────────────
class MessageBubble extends StatelessWidget {
  final Map<String, dynamic> msg;
  final bool isMine;
  const MessageBubble({super.key, required this.msg, required this.isMine});

  String _time(String? s) {
    if (s == null) return '';
    try {
      final dt = DateTime.parse(s).toLocal();
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final text    = msg['contenido_cifrado'] as String?;
    final archivo = msg['archivo'] as String?;
    final time    = _time(msg['fecha_envio'] as String?);

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 12),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.74),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isMine ? kAccent : kCard,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMine ? 16 : 4),
            bottomRight: Radius.circular(isMine ? 4 : 16),
          ),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 4,
                offset: const Offset(0, 2))
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (text != null && text.isNotEmpty)
              Text(text,
                  style: TextStyle(
                      color: isMine ? Colors.white : kText, fontSize: 14)),
            if (archivo != null && archivo.isNotEmpty)
              _buildFile(context, archivo, isMine),
            const SizedBox(height: 2),
            Text(
              '$time${isMine ? ' ✓✓' : ''}',
              style: TextStyle(
                  fontSize: 10,
                  color: isMine
                      ? Colors.white.withValues(alpha: 0.65)
                      : kChatMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFile(BuildContext context, String archivo, bool isMine) {
    final ext   = archivo.split('.').last.toLowerCase();
    final url   = storageUrl(archivo);
    final isImg = ['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext);

    if (isImg) {
      return Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 2),
        child: GestureDetector(
          onTap: () => _openUrl(context, url),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: NetImage(
              path: archivo,
              width: 200,
              height: 160,
              fit: BoxFit.cover,
              fallback: () => Container(
                width: 200,
                height: 80,
                decoration: BoxDecoration(
                  color: isMine
                      ? Colors.white.withValues(alpha: 0.15)
                      : kSurface,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.broken_image_outlined,
                        color: isMine ? Colors.white60 : kMuted, size: 28),
                    const SizedBox(height: 4),
                    Text('No se pudo cargar',
                        style: TextStyle(
                            fontSize: 11,
                            color: isMine ? Colors.white60 : kMuted)),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    // Archivo no imagen — botón para abrir
    final nombre = archivo.split('/').last;
    return GestureDetector(
      onTap: () => _openUrl(context, url),
      child: Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isMine
              ? Colors.white.withValues(alpha: 0.18)
              : kAccent.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: isMine
                  ? Colors.white.withValues(alpha: 0.3)
                  : kAccent.withValues(alpha: 0.25)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(_fileIcon(ext),
              size: 24, color: isMine ? Colors.white : kAccent),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(nombre,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: isMine ? Colors.white : kText),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1),
                Text('Toca para abrir',
                    style: TextStyle(
                        fontSize: 11,
                        color: isMine
                            ? Colors.white.withValues(alpha: 0.65)
                            : kChatMuted)),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  IconData _fileIcon(String ext) {
    if (ext == 'pdf') return Icons.picture_as_pdf_outlined;
    if (['doc', 'docx'].contains(ext)) return Icons.description_outlined;
    if (['xls', 'xlsx'].contains(ext)) return Icons.table_chart_outlined;
    if (['ppt', 'pptx'].contains(ext)) return Icons.slideshow_outlined;
    if (['zip', 'rar', '7z'].contains(ext)) return Icons.folder_zip_outlined;
    if (['mp4', 'mov', 'avi'].contains(ext)) return Icons.videocam_outlined;
    if (['mp3', 'wav', 'm4a'].contains(ext)) return Icons.audiotrack_outlined;
    return Icons.insert_drive_file_outlined;
  }

  Future<void> _openUrl(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se puede abrir el archivo')));
    }
  }
}