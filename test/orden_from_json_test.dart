import 'package:flutter_test/flutter_test.dart';
import 'package:repartidor_logiflow_pro/models/orden.dart';

void main() {
  group('Orden.fromJson', () {
    test('maps entrega_por_vendedor and vendedor contact fields', () {
      final json = <String, dynamic>{
        'id': '550e8400-e29b-41d4-a716-446655440000',
        'numero_orden': 'WEB-99',
        'emisor_nombre': 'Tienda',
        'destinatario_nombre': 'Cliente',
        'descripcion': 'Pedido',
        'direccion_destino': 'Calle 1',
        'estado': 'POR ENVIAR',
        'fecha_creacion': '2026-05-01T12:00:00.000Z',
        'tenant_id': 'tenant-uuid-1',
        'entrega_por_vendedor': true,
        'vendedor_contacto_nombre': 'María',
        'vendedor_contacto_telefono': '+53000000',
        'vendedor_contacto_email': 'v@example.com',
        'avisos_recogida_vendedor': [
          {'msg': 'Llamar antes'},
        ],
      };

      final o = Orden.fromJson(json);

      expect(o.id, '550e8400-e29b-41d4-a716-446655440000');
      expect(o.numeroOrden, 'WEB-99');
      expect(o.tenantId, 'tenant-uuid-1');
      expect(o.entregaPorVendedor, isTrue);
      expect(o.vendedorContactoNombre, 'María');
      expect(o.vendedorContactoTelefono, '+53000000');
      expect(o.vendedorContactoEmail, 'v@example.com');
      expect(o.avisosRecogidaVendedor, isNotNull);
      expect(o.avisosRecogidaVendedor!.length, 1);
      expect(o.avisosRecogidaVendedor![0]['msg'], 'Llamar antes');
    });

    test('accepts camelCase numeroOrden for offline cache', () {
      final json = <String, dynamic>{
        'id': 'a',
        'numeroOrden': 'OFF-1',
        'emisor_nombre': 'E',
        'destinatario_nombre': 'D',
        'descripcion': '',
        'direccion_destino': '',
        'estado': 'POR ENVIAR',
        'fecha_creacion': '2026-05-01T12:00:00.000Z',
      };

      final o = Orden.fromJson(json);
      expect(o.numeroOrden, 'OFF-1');
    });

    test('parses repartidor_nombre into repartidor', () {
      final json = <String, dynamic>{
        'id': 'b',
        'numero_orden': 'X',
        'emisor_nombre': 'E',
        'destinatario_nombre': 'D',
        'descripcion': '',
        'direccion_destino': '',
        'estado': 'EN CAMINO',
        'fecha_creacion': '2026-05-01T12:00:00.000Z',
        'repartidor_nombre': 'Driver Uno',
      };

      final o = Orden.fromJson(json);
      expect(o.repartidor, 'Driver Uno');
    });
  });
}
