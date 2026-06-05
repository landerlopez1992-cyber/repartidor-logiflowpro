import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Foto de perfil disponible sin red (archivo local).
class RepartidorPerfilFotoCacheService {
  RepartidorPerfilFotoCacheService._();

  static String _keyPath(String repartidorId) => 'repartidor_foto_local_$repartidorId';
  static String _keyUrl(String repartidorId) => 'repartidor_foto_url_cached_$repartidorId';

  static Future<String?> rutaLocal(String repartidorId) async {
    if (kIsWeb || repartidorId.isEmpty) return null;
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString(_keyPath(repartidorId));
    if (path == null || path.isEmpty) return null;
    if (!await File(path).exists()) return null;
    return path;
  }

  /// Copia un archivo elegido por el usuario al almacenamiento de la app.
  static Future<String?> guardarArchivoLocal({
    required String repartidorId,
    required File origen,
  }) async {
    if (kIsWeb || repartidorId.isEmpty) return null;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final dest = File(
        p.join(dir.path, 'perfil_$repartidorId${DateTime.now().millisecondsSinceEpoch}.jpg'),
      );
      await origen.copy(dest.path);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyPath(repartidorId), dest.path);
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

      final resp = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 20));
      if (resp.statusCode != 200) return pathExistente;

      final dir = await getApplicationDocumentsDirectory();
      final dest = File(p.join(dir.path, 'perfil_$repartidorId.jpg'));
      await dest.writeAsBytes(resp.bodyBytes);
      await prefs.setString(_keyPath(repartidorId), dest.path);
      await prefs.setString(_keyUrl(repartidorId), url);
      return dest.path;
    } catch (e) {
      print('⚠️ descargarYCachear foto perfil: $e');
      return rutaLocal(repartidorId);
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
    }
  }
}
