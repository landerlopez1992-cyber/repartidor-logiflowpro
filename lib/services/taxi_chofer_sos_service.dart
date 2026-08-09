import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class TaxiChoferContactoConfianza {
  const TaxiChoferContactoConfianza({
    required this.id,
    required this.nombre,
    this.telefono,
    this.email,
    this.contactoUsuarioWebId,
    this.contactoNombreApp,
  });

  final String id;
  final String nombre;
  final String? telefono;
  final String? email;
  final String? contactoUsuarioWebId;
  final String? contactoNombreApp;

  bool get tieneTelefono =>
      (telefono ?? '').trim().replaceAll(RegExp(r'[^0-9+]'), '').length >= 7;

  String get subtitulo {
    final parts = <String>[];
    if (tieneTelefono) parts.add(telefono!.trim());
    if ((email ?? '').contains('@')) parts.add(email!.trim());
    if ((contactoUsuarioWebId ?? '').isNotEmpty) {
      parts.add(
        'App: ${(contactoNombreApp ?? '').trim().isEmpty ? 'usuario' : contactoNombreApp!.trim()}',
      );
    }
    return parts.isEmpty ? 'Sin canales' : parts.join(' · ');
  }

  factory TaxiChoferContactoConfianza.fromJson(Map<String, dynamic> m) {
    return TaxiChoferContactoConfianza(
      id: m['id']?.toString() ?? '',
      nombre: m['nombre']?.toString() ?? '',
      telefono: m['telefono']?.toString(),
      email: m['email']?.toString(),
      contactoUsuarioWebId: m['contacto_usuario_web_id']?.toString(),
      contactoNombreApp: m['contacto_nombre_app']?.toString(),
    );
  }
}

class TaxiChoferUsuarioAppHit {
  const TaxiChoferUsuarioAppHit({
    required this.id,
    required this.nombre,
    required this.email,
    this.telefono,
  });

  final String id;
  final String nombre;
  final String email;
  final String? telefono;

  factory TaxiChoferUsuarioAppHit.fromJson(Map<String, dynamic> m) {
    final n = (m['nombre']?.toString() ?? '').trim();
    final a = (m['apellidos']?.toString() ?? '').trim();
    final full = [n, a].where((e) => e.isNotEmpty).join(' ');
    return TaxiChoferUsuarioAppHit(
      id: m['id']?.toString() ?? '',
      nombre: full.isNotEmpty ? full : (m['email']?.toString() ?? 'Usuario'),
      email: m['email']?.toString() ?? '',
      telefono: m['telefono']?.toString(),
    );
  }
}

class TaxiChoferSosService {
  TaxiChoferSosService._();
  static final instance = TaxiChoferSosService._();

  SupabaseClient get _db => Supabase.instance.client;

  Future<({bool ok, List<TaxiChoferContactoConfianza> items, String? err})>
      listarContactos() async {
    try {
      final res = await _db.rpc('taxi_chofer_contactos_listar');
      final map = Map<String, dynamic>.from(res as Map);
      if (map['ok'] != true) {
        return (
          ok: false,
          items: const <TaxiChoferContactoConfianza>[],
          err: map['error']?.toString(),
        );
      }
      final list = <TaxiChoferContactoConfianza>[];
      final raw = map['items'];
      if (raw is List) {
        for (final e in raw) {
          if (e is Map) {
            list.add(
              TaxiChoferContactoConfianza.fromJson(
                Map<String, dynamic>.from(e),
              ),
            );
          }
        }
      }
      return (ok: true, items: list, err: null);
    } catch (e) {
      return (
        ok: false,
        items: const <TaxiChoferContactoConfianza>[],
        err: e.toString(),
      );
    }
  }

  Future<List<TaxiChoferUsuarioAppHit>> buscarUsuariosApp(String query) async {
    try {
      final res = await _db.rpc(
        'taxi_chofer_buscar_usuarios_app',
        params: {'p_query': query, 'p_limit': 8},
      );
      final list = <TaxiChoferUsuarioAppHit>[];
      if (res is List) {
        for (final e in res) {
          if (e is Map) {
            list.add(
              TaxiChoferUsuarioAppHit.fromJson(Map<String, dynamic>.from(e)),
            );
          }
        }
      }
      return list;
    } catch (_) {
      return const [];
    }
  }

  Future<({bool ok, String? err})> upsertContacto({
    required String nombre,
    String? telefono,
    String? email,
    String? contactoUsuarioWebId,
    String? id,
  }) async {
    try {
      final res = await _db.rpc(
        'taxi_chofer_contactos_upsert',
        params: {
          'p_nombre': nombre,
          'p_telefono': telefono,
          'p_id': id,
          'p_email': email,
          'p_contacto_usuario_web_id': contactoUsuarioWebId,
        },
      );
      final map = Map<String, dynamic>.from(res as Map);
      if (map['ok'] != true) {
        return (
          ok: false,
          err: map['mensaje']?.toString() ?? map['error']?.toString(),
        );
      }
      return (ok: true, err: null);
    } catch (e) {
      return (ok: false, err: e.toString());
    }
  }

  Future<({bool ok, String? err})> eliminarContacto(String id) async {
    try {
      final res = await _db.rpc(
        'taxi_chofer_contactos_eliminar',
        params: {'p_id': id},
      );
      final map = Map<String, dynamic>.from(res as Map);
      if (map['ok'] != true) {
        return (ok: false, err: map['error']?.toString());
      }
      return (ok: true, err: null);
    } catch (e) {
      return (ok: false, err: e.toString());
    }
  }

  Future<({bool ok, String? err})> enviarUbicacion({
    String? solicitudId,
    double? latFallback,
    double? lngFallback,
  }) async {
    try {
      double? lat = latFallback;
      double? lng = lngFallback;
      try {
        final p = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 8),
          ),
        );
        lat = p.latitude;
        lng = p.longitude;
      } catch (_) {}
      if (lat == null || lng == null) {
        return (ok: false, err: 'No se pudo obtener la ubicación.');
      }

      final res = await _db.rpc(
        'taxi_sos_disparar',
        params: {
          'p_lat': lat,
          'p_lng': lng,
          'p_solicitud_id': solicitudId,
        },
      );
      final map = Map<String, dynamic>.from(res as Map);
      if (map['ok'] != true) {
        return (ok: false, err: map['error']?.toString());
      }

      final alertaId = map['alerta_id']?.toString();
      final tenantId = map['tenant_id']?.toString() ?? '';
      final emisor = map['emisor_nombre']?.toString() ?? 'Conductor';
      final mapsUrl = map['maps_url']?.toString() ??
          'https://maps.google.com/?q=$lat,$lng';
      final emails = _asStringList(map['emails']);
      final authIds = _asStringList(map['auth_user_ids']);
      final telefonos = _asStringList(map['telefonos']);

      var emailsOk = 0;
      var emailsFail = 0;
      for (final mail in emails) {
        try {
          final inv = await _db.functions.invoke(
            'send-order-email',
            body: {
              'tipo': 'taxi_sos_ubicacion',
              'email': mail,
              'tenant_id': tenantId,
              'orden': {
                'emisor_nombre': emisor,
                'maps_url': mapsUrl,
                'lat': lat,
                'lng': lng,
                'alerta_id': alertaId,
              },
            },
          );
          final st = inv.status;
          if (st >= 200 && st < 300) {
            emailsOk++;
          } else {
            emailsFail++;
            print('⚠️ SOS email $mail status=$st data=${inv.data}');
          }
        } catch (e) {
          emailsFail++;
          print('⚠️ SOS email $mail error: $e');
        }
      }

      if (authIds.isNotEmpty && tenantId.isNotEmpty && alertaId != null) {
        try {
          await _db.functions.invoke(
            'enviar-broadcast-push-cliente',
            body: {
              'action': 'taxi_sos',
              'tenant_id': tenantId,
              'alerta_id': alertaId,
              'auth_user_ids': authIds,
            },
          );
        } catch (e) {
          print('⚠️ SOS push: $e');
        }
      }

      var smsOk = false;
      if (telefonos.isNotEmpty) {
        final digits = telefonos.first.replaceAll(RegExp(r'[^0-9+]'), '');
        final smsBody = Uri.encodeComponent(
          'EMERGENCIA: $emisor necesita ayuda. Ubicación: $mapsUrl',
        );
        if (digits.length >= 7) {
          final uri = Uri.parse('sms:$digits?body=$smsBody');
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri);
            smsOk = true;
          }
        }
      }

      if (emails.isEmpty && authIds.isEmpty && telefonos.isEmpty) {
        return (
          ok: false,
          err: 'Configura contactos de confianza (email, app o teléfono).',
        );
      }
      if (emails.isNotEmpty && emailsOk == 0 && !smsOk && authIds.isEmpty) {
        return (
          ok: false,
          err: emailsFail > 0
              ? 'No se pudo enviar el email de alerta. Intenta de nuevo.'
              : 'No se envió ningún aviso.',
        );
      }
      if (emails.isNotEmpty && emailsOk == 0 && emailsFail > 0) {
        return (
          ok: false,
          err:
              'No se pudo enviar el email de alerta. La ubicación quedó registrada; intenta de nuevo o usa SMS.',
        );
      }
      return (ok: true, err: null);
    } catch (e) {
      return (ok: false, err: e.toString());
    }
  }

  List<String> _asStringList(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .map((e) => e?.toString().trim() ?? '')
        .where((e) => e.isNotEmpty)
        .toList();
  }

  /// Abre el marcador del teléfono (`tel:`).
  Future<({bool ok, String? err})> llamarTelefono(String raw) async {
    final digits = raw.replaceAll(RegExp(r'[^0-9+]'), '');
    if (digits.length < 3) {
      return (ok: false, err: 'Número no válido.');
    }
    final uri = Uri(scheme: 'tel', path: digits);
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) return (ok: false, err: 'No se pudo abrir la llamada.');
      return (ok: true, err: null);
    } catch (e) {
      return (ok: false, err: 'No se pudo llamar: $e');
    }
  }
}
