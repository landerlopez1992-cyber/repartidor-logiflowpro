import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../config/app_colors.dart';
import '../main.dart';
import '../services/repartidor_perfil_cache_service.dart';
import '../services/repartidor_perfil_foto_cache_service.dart';
import '../services/sync_service.dart';

/// Modal: sin foto de perfil → anima a subirla (más confianza / más órdenes).
class RepartidorFotoPerfilPromptDialog extends StatefulWidget {
  const RepartidorFotoPerfilPromptDialog({
    super.key,
    required this.repartidorId,
    this.onFotoGuardada,
  });

  final String repartidorId;
  final void Function(String? localPath, String? publicUrl)? onFotoGuardada;

  static Future<bool?> show(
    BuildContext context, {
    required String repartidorId,
    void Function(String? localPath, String? publicUrl)? onFotoGuardada,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => RepartidorFotoPerfilPromptDialog(
        repartidorId: repartidorId,
        onFotoGuardada: onFotoGuardada,
      ),
    );
  }

  @override
  State<RepartidorFotoPerfilPromptDialog> createState() =>
      _RepartidorFotoPerfilPromptDialogState();
}

class _RepartidorFotoPerfilPromptDialogState
    extends State<RepartidorFotoPerfilPromptDialog> {
  final ImagePicker _picker = ImagePicker();
  bool _guardando = false;
  String? _previewPath;
  String? _error;

  Future<void> _elegirFuente() async {
    if (_guardando) return;
    final fuente = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppColors.darkElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.darkBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: AppColors.botonPrincipal),
              title: const Text(
                'Tomar foto',
                style: TextStyle(color: AppColors.darkText),
              ),
              subtitle: const Text(
                'Recomendado — pecho hacia arriba',
                style: TextStyle(color: AppColors.darkTextMuted, fontSize: 12),
              ),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: AppColors.darkTextMuted),
              title: const Text(
                'Elegir de galería',
                style: TextStyle(color: AppColors.darkText),
              ),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (fuente == null || !mounted) return;
    await _tomarYGuardar(fuente);
  }

  Future<void> _tomarYGuardar(ImageSource source) async {
    setState(() {
      _error = null;
      _guardando = true;
    });
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 80,
        preferredCameraDevice: CameraDevice.front,
      );
      if (image == null) {
        if (mounted) setState(() => _guardando = false);
        return;
      }

      final file = File(image.path);
      final localPath =
          await RepartidorPerfilFotoCacheService.guardarArchivoLocal(
        repartidorId: widget.repartidorId,
        origen: file,
      );
      final pathUsado = localPath ?? image.path;
      if (mounted) setState(() => _previewPath = pathUsado);

      final online = SyncService().isOnline;
      if (!online) {
        await SyncService().addOperation(
          type: 'upload_foto_perfil',
          ordenId: widget.repartidorId,
          data: {
            'repartidor_id': widget.repartidorId,
            'file_path': pathUsado,
          },
        );
        final perfilCache =
            await RepartidorPerfilCacheService.getCachedPerfilData();
        if (perfilCache != null) {
          await RepartidorPerfilCacheService.cachePerfilData({
            ...perfilCache,
            'foto_perfil_local': pathUsado,
          });
        }
        widget.onFotoGuardada?.call(pathUsado, null);
        if (!mounted) return;
        Navigator.of(context).pop(true);
        return;
      }

      final fileName =
          '${widget.repartidorId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await supabase.storage.from('fotos-perfil').upload(fileName, file);
      final publicUrl =
          supabase.storage.from('fotos-perfil').getPublicUrl(fileName);

      await supabase
          .from('usuarios')
          .update({'foto_perfil': publicUrl})
          .eq('id', widget.repartidorId);

      final perfilCache =
          await RepartidorPerfilCacheService.getCachedPerfilData();
      if (perfilCache != null) {
        await RepartidorPerfilCacheService.cachePerfilData({
          ...perfilCache,
          'foto_perfil': publicUrl,
          'foto_perfil_local': pathUsado,
        });
      }
      await RepartidorPerfilFotoCacheService.vincularUrlLocal(
        repartidorId: widget.repartidorId,
        localPath: pathUsado,
        publicUrl: publicUrl,
      );

      widget.onFotoGuardada?.call(pathUsado, publicUrl);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _guardando = false;
          _error = 'No se pudo guardar la foto. Inténtalo de nuevo.';
        });
      }
      print('❌ Foto perfil prompt: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          decoration: BoxDecoration(
            color: AppColors.darkSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.darkBorder),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  tooltip: 'Cerrar',
                  onPressed: _guardando
                      ? null
                      : () => Navigator.of(context).pop(false),
                  icon: const Icon(Icons.close, color: AppColors.darkTextMuted),
                ),
              ),
              // Guía visual: pecho hacia arriba
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.darkElevated,
                  border: Border.all(
                    color: AppColors.botonPrincipal.withValues(alpha: 0.7),
                    width: 2,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: _previewPath != null
                    ? Image.file(
                        File(_previewPath!),
                        fit: BoxFit.cover,
                      )
                    : const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.person,
                            size: 64,
                            color: AppColors.botonPrincipal,
                          ),
                          SizedBox(height: 4),
                          Icon(
                            Icons.arrow_upward,
                            size: 18,
                            color: AppColors.darkTextMuted,
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Foto de pecho hacia arriba',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.darkTextMuted,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Añade tu foto de perfil',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.darkText,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Los repartidores con foto de perfil tienen más posibilidades de recibir más órdenes: el cliente ve a una persona real y eso genera más confianza.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.darkTextMuted,
                  fontSize: 14,
                  height: 1.35,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.error,
                    fontSize: 13,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _guardando ? null : _elegirFuente,
                  icon: _guardando
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.camera_alt),
                  label: Text(
                    _guardando ? 'Guardando…' : 'Subir y guardar foto',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.botonPrincipal,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              TextButton(
                onPressed: _guardando
                    ? null
                    : () => Navigator.of(context).pop(false),
                child: const Text(
                  'Ahora no',
                  style: TextStyle(color: AppColors.darkTextMuted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
