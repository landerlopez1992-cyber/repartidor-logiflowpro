import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Foto de perfil disponible sin red (archivo local).
///
/// Regla: el archivo local solo es válido si la URL remota asociada coincide.
/// Si el usuario elige otra foto local o cambia `foto_perfil` en BD, se invalida.
class RepartidorPerfilFotoCacheService {
  RepartidorPerfilFotoCacheService._();

  static String _keyPath(String repartidorId) => 'repartidor_foto_local_$repartidorId';
  static String _keyUrl(String repartidorId) => 'repartidor_foto_url_cached_$repartidorId';

  /// Ruta local solo si existe y (opcionalmente) corresponde a [urlEsperada].
  static Future<String?> rutaLocal(
    String repartidorId, {
    String? urlEsperada,
  }) async {
    if (kIsWeb || repartidorId.isEmpty) return null;
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString(_keyPath(repartidorId));
    if (path == null || path.isEmpty) return null;
    if (!await File(path).exists()) return null;
    if (urlEsperada != null && urlEsperada.trim().isNotEmpty) {
      final urlCacheada = prefs.getString(_keyUrl(repartidorId)) ?? '';
      if (urlCacheada.trim() != urlEsperada.trim()) {
        // Caché de otra foto (ej. subida local vieja vs URL nueva en BD).
        return null;
      }
    }
    return path;
  }

  /// Copia un archivo elegido por el usuario al almacenamiento de la app.
  /// Invalida la URL remota asociada hasta que se suba y se vincule.
  static Future<String?> guardarArchivoLocal({
    required String repartidorId,
    required File origen,
  }) async {
    if (kIsWeb || repartidorId.isEmpty) return null;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final dest = File(
        p.join(
          dir.path,
          'perfil_$repartidorId${DateTime.now().millisecondsSinceEpoch}.jpg',
        ),
      );
      await origen.copy(dest.path);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyPath(repartidorId), dest.path);
      // Obliga a re-descargar cuando llegue la URL pública nueva.
      await prefs.remove(_keyUrl(repartidorId));
      return dest.path;
    } catch (e) {
      print('⚠️ guardarArchivoLocal foto perfil: $e');
      return null;
    }
  }

  /// Descarga la URL remota y guarda copia local (solo con red).
  static Future<String?> descargarYCachear({
    required String repartidorId,
    required String url,
  }) async {
    if (kIsWeb || repartidorId.isEmpty || url.isEmpty) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      final urlCacheada = prefs.getString(_keyUrl(repartidorId));
      final pathExistente = prefs.getString(_keyPath(repartidorId));
      if (urlCacheada == url &&
          pathExistente != null &&
          await File(pathExistente).exists()) {
        return pathExistente;
      }

      final resp =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 20));
      if (resp.statusCode != 200) {
        // No devolver archivo de otra URL.
        if (urlCacheada == url &&
            pathExistente != null &&
            await File(pathExistente).exists()) {
          return pathExistente;
        }
        return null;
      }

      final dir = await getApplicationDocumentsDirectory();
      final dest = File(p.join(dir.path, 'perfil_$repartidorId.jpg'));
      await dest.writeAsBytes(resp.bodyBytes);
      await prefs.setString(_keyPath(repartidorId), dest.path);
      await prefs.setString(_keyUrl(repartidorId), url);
      return dest.path;
    } catch (e) {
      print('⚠️ descargarYCachear foto perfil: $e');
      return rutaLocal(repartidorId, urlEsperada: url);
    }
  }

  static Future<void> vincularUrlLocal({
    required String repartidorId,
    required String localPath,
    String? publicUrl,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyPath(repartidorId), localPath);
    if (publicUrl != null && publicUrl.isNotEmpty) {
      await prefs.setString(_keyUrl(repartidorId), publicUrl);
    } else {
      await prefs.remove(_keyUrl(repartidorId));
    }
  }

  /// Borra la asociación local (fuerza red/próxima descarga).
  static Future<void> invalidar(String repartidorId) async {
    if (repartidorId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyPath(repartidorId));
    await prefs.remove(_keyUrl(repartidorId));
  }
}
