/// Pasos del proceso de entrega guardados en dispositivo (offline-first).
enum EntregaPaso {
  cobro,
  remesa,
  foto,
  firma,
  bultos,
}

class EntregaProgreso {
  final String ordenId;
  final bool cobroConfirmado;
  final DateTime? cobroAt;
  final String? cobroMontoEtiqueta;
  final bool remesaConfirmada;
  final DateTime? remesaAt;
  final String? remesaMontoEtiqueta;
  final bool fotoConfirmada;
  final DateTime? fotoAt;
  final bool firmaConfirmada;
  final DateTime? firmaAt;
  final bool bultosConfirmados;
  final DateTime? bultosAt;
  final DateTime updatedAt;

  const EntregaProgreso({
    required this.ordenId,
    this.cobroConfirmado = false,
    this.cobroAt,
    this.cobroMontoEtiqueta,
    this.remesaConfirmada = false,
    this.remesaAt,
    this.remesaMontoEtiqueta,
    this.fotoConfirmada = false,
    this.fotoAt,
    this.firmaConfirmada = false,
    this.firmaAt,
    this.bultosConfirmados = false,
    this.bultosAt,
    required this.updatedAt,
  });

  factory EntregaProgreso.vacio(String ordenId) => EntregaProgreso(
        ordenId: ordenId,
        updatedAt: DateTime.now().toUtc(),
      );

  bool pasoCompleto(EntregaPaso paso) {
    switch (paso) {
      case EntregaPaso.cobro:
        return cobroConfirmado;
      case EntregaPaso.remesa:
        return remesaConfirmada;
      case EntregaPaso.foto:
        return fotoConfirmada;
      case EntregaPaso.firma:
        return firmaConfirmada;
      case EntregaPaso.bultos:
        return bultosConfirmados;
    }
  }

  EntregaProgreso copyWith({
    bool? cobroConfirmado,
    DateTime? cobroAt,
    String? cobroMontoEtiqueta,
    bool? remesaConfirmada,
    DateTime? remesaAt,
    String? remesaMontoEtiqueta,
    bool? fotoConfirmada,
    DateTime? fotoAt,
    bool? firmaConfirmada,
    DateTime? firmaAt,
    bool? bultosConfirmados,
    DateTime? bultosAt,
    DateTime? updatedAt,
  }) {
    return EntregaProgreso(
      ordenId: ordenId,
      cobroConfirmado: cobroConfirmado ?? this.cobroConfirmado,
      cobroAt: cobroAt ?? this.cobroAt,
      cobroMontoEtiqueta: cobroMontoEtiqueta ?? this.cobroMontoEtiqueta,
      remesaConfirmada: remesaConfirmada ?? this.remesaConfirmada,
      remesaAt: remesaAt ?? this.remesaAt,
      remesaMontoEtiqueta: remesaMontoEtiqueta ?? this.remesaMontoEtiqueta,
      fotoConfirmada: fotoConfirmada ?? this.fotoConfirmada,
      fotoAt: fotoAt ?? this.fotoAt,
      firmaConfirmada: firmaConfirmada ?? this.firmaConfirmada,
      firmaAt: firmaAt ?? this.firmaAt,
      bultosConfirmados: bultosConfirmados ?? this.bultosConfirmados,
      bultosAt: bultosAt ?? this.bultosAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'orden_id': ordenId,
        'cobro_confirmado': cobroConfirmado,
        'cobro_at': cobroAt?.toIso8601String(),
        'cobro_monto': cobroMontoEtiqueta,
        'remesa_confirmada': remesaConfirmada,
        'remesa_at': remesaAt?.toIso8601String(),
        'remesa_monto': remesaMontoEtiqueta,
        'foto_confirmada': fotoConfirmada,
        'foto_at': fotoAt?.toIso8601String(),
        'firma_confirmada': firmaConfirmada,
        'firma_at': firmaAt?.toIso8601String(),
        'bultos_confirmados': bultosConfirmados,
        'bultos_at': bultosAt?.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory EntregaProgreso.fromJson(Map<String, dynamic> json) {
    DateTime? parseDt(dynamic v) {
      if (v == null) return null;
      try {
        return DateTime.parse(v.toString()).toUtc();
      } catch (_) {
        return null;
      }
    }

    return EntregaProgreso(
      ordenId: json['orden_id']?.toString() ?? '',
      cobroConfirmado: json['cobro_confirmado'] == true,
      cobroAt: parseDt(json['cobro_at']),
      cobroMontoEtiqueta: json['cobro_monto']?.toString(),
      remesaConfirmada: json['remesa_confirmada'] == true,
      remesaAt: parseDt(json['remesa_at']),
      remesaMontoEtiqueta: json['remesa_monto']?.toString(),
      fotoConfirmada: json['foto_confirmada'] == true,
      fotoAt: parseDt(json['foto_at']),
      firmaConfirmada: json['firma_confirmada'] == true,
      firmaAt: parseDt(json['firma_at']),
      bultosConfirmados: json['bultos_confirmados'] == true,
      bultosAt: parseDt(json['bultos_at']),
      updatedAt: parseDt(json['updated_at']) ?? DateTime.now().toUtc(),
    );
  }
}
