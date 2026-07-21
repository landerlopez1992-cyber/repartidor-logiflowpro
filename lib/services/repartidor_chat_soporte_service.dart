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

  /// Crea o reabre la conversación del repartidor con su empresa (tenant)
  /// y la pone en cola de atención humana.
  static Future<String> obtenerOCrearConversacionEmpresa() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      throw Exception('Sesión no válida');
    }

    String? tenantId;
    try {
      final userData = await supabase
          .from('usuarios')
          .select('tenant_id')
          .eq('auth_id', user.id)
          .maybeSingle();
      tenantId = userData?['tenant_id']?.toString();
    } catch (_) {}

    if (tenantId == null || tenantId.isEmpty) {
      throw Exception('No se encontró la empresa de tu cuenta');
    }

    var queryAbierta = supabase
        .from('conversaciones_soporte')
        .select('id')
        .eq('repartidor_auth_id', user.id)
        .eq('tenant_id', tenantId)
        .eq('estado', 'ABIERTA')
        .limit(1);

    final abiertas = await queryAbierta;
    if (abiertas.isNotEmpty) {
      final id = abiertas[0]['id']?.toString();
      if (id != null && id.isNotEmpty) {
        try {
          await supabase.from('conversaciones_soporte').update({
            'esperando_aceptacion_agente': true,
          }).eq('id', id);
        } catch (_) {}
        return id;
      }
    }

    // Reabrir la más reciente cerrada del mismo tenant, si existe.
    final cerradas = await supabase
        .from('conversaciones_soporte')
        .select('id')
        .eq('repartidor_auth_id', user.id)
        .eq('tenant_id', tenantId)
        .order('updated_at', ascending: false)
        .limit(1);

    if (cerradas.isNotEmpty) {
      final id = cerradas[0]['id']?.toString();
      if (id != null && id.isNotEmpty) {
        await supabase.from('conversaciones_soporte').update({
          'estado': 'ABIERTA',
          'esperando_aceptacion_agente': true,
          'agente_atiende_auth_id': null,
          'atencion_finalizada_at': null,
        }).eq('id', id);
        return id;
      }
    }

    final nueva = await supabase
        .from('conversaciones_soporte')
        .insert({
          'repartidor_auth_id': user.id,
          'tenant_id': tenantId,
          'estado': 'ABIERTA',
          'esperando_aceptacion_agente': true,
        })
        .select('id')
        .single();

    final id = nueva['id']?.toString();
    if (id == null || id.isEmpty) {
      throw Exception('No se pudo crear la conversación');
    }
    return id;
  }
}
