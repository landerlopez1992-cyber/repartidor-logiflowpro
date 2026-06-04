import 'dart:io';

import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../utils/entrega_foto_util.dart';

/// Miniatura compacta de la foto de entrega (esquina de tarjeta o bloque en detalle).
class FotoEntregaPreview extends StatelessWidget {
  const FotoEntregaPreview({
    super.key,
    required this.fotoUrl,
    this.ancho = 56,
    this.alto = 56,
    this.alineacion = Alignment.topRight,
    this.mostrarEtiqueta = false,
  });

  final String? fotoUrl;
  final double ancho;
  final double alto;
  final Alignment alineacion;
  final bool mostrarEtiqueta;

  @override
  Widget build(BuildContext context) {
    if (!EntregaFotoUtil.urlTieneFoto(fotoUrl)) {
      return const SizedBox.shrink();
    }

    final ruta = EntregaFotoUtil.rutaArchivoLocal(fotoUrl);
    final esRemota = ruta == null &&
        (fotoUrl!.startsWith('http://') || fotoUrl!.startsWith('https://'));

    Widget imagen;
    if (ruta != null) {
      imagen = Image.file(
        File(ruta),
        width: ancho,
        height: alto,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholder(),
      );
    } else if (esRemota) {
      imagen = Image.network(
        fotoUrl!,
        width: ancho,
        height: alto,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return SizedBox(
            width: ancho,
            height: alto,
            child: const Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        },
        errorBuilder: (_, __, ___) => _placeholder(),
      );
    } else {
      imagen = _placeholder();
    }

    final thumb = Container(
      width: ancho,
      height: alto,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.exito, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          imagen,
          Positioned(
            right: 2,
            bottom: 2,
            child: Icon(Icons.check_circle, color: AppColors.exito, size: alto > 64 ? 18 : 14),
          ),
        ],
      ),
    );

    if (!mostrarEtiqueta) {
      return Align(alignment: alineacion, child: thumb);
    }

    final centrar = alineacion == Alignment.center;
    return Column(
      crossAxisAlignment: centrar ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: centrar ? MainAxisAlignment.center : MainAxisAlignment.start,
          children: [
            Icon(Icons.photo_camera, size: 16, color: AppColors.exito),
            const SizedBox(width: 6),
            Text(
              'Foto de entrega',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textoPrincipal,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        thumb,
      ],
    );
  }

  Widget _placeholder() {
    return Container(
      color: const Color(0xFFE8F5E9),
      child: Icon(Icons.image_not_supported, size: alto * 0.4, color: AppColors.textoSecundario),
    );
  }
}
