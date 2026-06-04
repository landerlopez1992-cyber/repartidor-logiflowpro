import '../main.dart';

/// Mensajes de soporte: solo la conversación del repartidor autenticado.
class RepartidorChatSoporteService {
  RepartidorChatSoporteService._();

  static bool _parseLeido(dynamic leidoValue) {
    if (leidoValue == null) return false;
    if (leidoValue is bool) return leidoValue;
    if (leidoValue is String) return leidoValue.toLowerCase() == 'true';
    if (leidoValue is int) return leidoValue == 1;
    return false;
  }

  /// Texto visible en lista / notificación (evita líneas vacías).
  static String textoPreview(Map<String, dynamic> mensaje) {
    final texto = mensaje['mensaje']?.toString().trim() ?? '';
    if (texto.isNotEmpty) return texto;
    final foto = mensaje['foto_url']?.toString().trim() ?? '';
    if (foto.isNotEmpty) return 'Imagen adjunta';
    return '';
  }

  static bool tieneContenidoVisible(Map<String, dynamic> mensaje) =>
      textoPreview(mensaje).isNotEmpty;

  /// IDs de conversaciones ABIERTAS del repartidor (tenant acotado si existe).
  static Future<List<String>> idsConversacionesRepartidor() async {
    final user = supabase.auth.currentUser;
    if (user == null) return [];

    String? tenantId;
    try {
      final userData = await supabase
          .from('usuarios')
          .select('tenant_id')
          .eq('auth_id', user.id)
          .maybeSingle();
      tenantId = userData?['tenant_id']?.toString();
    } catch (_) {}

    var query = supabase
        .from('conversaciones_soporte')
        .select('id')
        .eq('repartidor_auth_id', user.id)
        .eq('estado', 'ABIERTA');

    if (tenantId != null && tenantId.isNotEmpty) {
      query = query.eq('tenant_id', tenantId);
    }

    final rows = await query;
    return rows
        .map((r) => r['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toList();
  }

  static Future<int> contarMensajesNoLeidos() async {
    final user = supabase.auth.currentUser;
    if (user == null) return 0;

    final convIds = await idsConversacionesRepartidor();
    if (convIds.isEmpty) return 0;

    final mensajes = await supabase
        .from('mensajes_soporte')
        .select('id, leido, remitente_auth_id, mensaje, foto_url, conversacion_id')
        .inFilter('conversacion_id', convIds)
        .neq('remitente_auth_id', user.id);

    var total = 0;
    for (final m in mensajes) {
      if (_parseLeido(m['leido'])) continue;
      if (!tieneContenidoVisible(m)) continue;
      total++;
    }
    return total;
  }

  static Future<void> marcarTodosLeidosEnMisConversaciones() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final convIds = await idsConversacionesRepartidor();
    if (convIds.isEmpty) return;

    await supabase
        .from('mensajes_soporte')
        .update({'leido': true})
        .inFilter('conversacion_id', convIds)
        .eq('leido', false)
        .neq('remitente_auth_id', user.id);
  }

  static bool perteneceAMisConversaciones(
    String? conversacionId,
    List<String> misConversaciones,
  ) {
    if (conversacionId == null || conversacionId.isEmpty) return false;
    return misConversaciones.contains(conversacionId);
  }
}
