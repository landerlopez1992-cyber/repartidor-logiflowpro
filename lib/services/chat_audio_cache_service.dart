import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Caché en disco de notas de voz del chat (reproducir sin internet).
class ChatAudioCache {
  ChatAudioCache._();

  static String _keyFromUrl(String url) {
    final u = url.trim();
    final hash = u.hashCode.toUnsigned(32).toRadixString(16);
    final ext = u.toLowerCase().contains('.ogg')
        ? 'ogg'
        : u.toLowerCase().contains('.mp3')
            ? 'mp3'
            : 'm4a';
    return 'chat_voz_$hash.$ext';
  }

  static Future<Directory> _dir() async {
    final base = await getApplicationDocumentsDirectory();
    final d = Directory('${base.path}/chat_audio_cache');
    if (!await d.exists()) {
      await d.create(recursive: true);
    }
    return d;
  }

  /// Ruta local si ya está en caché.
  static Future<String?> pathIfCached(String url) async {
    if (url.trim().isEmpty) return null;
    try {
      final f = File('${(await _dir()).path}/${_keyFromUrl(url)}');
      if (await f.exists() && await f.length() > 0) return f.path;
    } catch (_) {}
    return null;
  }

  /// Guarda una copia local (p. ej. justo después de grabar/enviar).
  static Future<void> saveFromFile(String url, String localPath) async {
    if (url.trim().isEmpty || localPath.trim().isEmpty) return;
    try {
      final src = File(localPath);
      if (!await src.exists()) return;
      final dest = File('${(await _dir()).path}/${_keyFromUrl(url)}');
      await src.copy(dest.path);
    } catch (_) {}
  }

  /// Descarga a caché si hace falta; devuelve ruta local o null.
  static Future<String?> ensureLocal(String url) async {
    final existing = await pathIfCached(url);
    if (existing != null) return existing;
    final u = url.trim();
    if (u.isEmpty || !u.startsWith('http')) return null;
    try {
      final res = await http.get(Uri.parse(u)).timeout(const Duration(seconds: 45));
      if (res.statusCode < 200 || res.statusCode >= 300) return null;
      if (res.bodyBytes.isEmpty) return null;
      final dest = File('${(await _dir()).path}/${_keyFromUrl(u)}');
      await dest.writeAsBytes(res.bodyBytes, flush: true);
      return dest.path;
    } catch (_) {
      return null;
    }
  }

  /// Prefetch en segundo plano (no bloquea UI).
  static Future<void> prefetch(String url) async {
    await ensureLocal(url);
  }
}
