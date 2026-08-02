import 'dart:io';

import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../models/orden.dart';
import '../services/productos_orden_tienda_service.dart';
import '../utils/productos_orden_tienda_util.dart';

/// Lista centrada de productos de una compra de tienda (solo órdenes de compra).
/// Offline-first: pinta caché al instante y refresca en red si hay conexión.
class ProductosOrdenTiendaScreen extends StatefulWidget {
  const ProductosOrdenTiendaScreen({super.key, required this.orden});

  final Orden orden;

  @override
  State<ProductosOrdenTiendaScreen> createState() =>
      _ProductosOrdenTiendaScreenState();
}

class _ProductosOrdenTiendaScreenState extends State<ProductosOrdenTiendaScreen> {
  final _svc = ProductosOrdenTiendaService();
  bool _loading = true;
  bool _refrescando = false;
  /// Solo true tras fallar la red y usar datos guardados.
  bool _modoOffline = false;
  String? _error;
  List<ProductoOrdenTiendaLinea> _lineas = [];
  int _total = 0;
  String? _numero;
  String? _compradorNombre;
  String? _compradorAvatar;
  String? _destinatarioNombre;
  String? _destinatarioAvatar;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  void _aplicar(
    ProductosOrdenTiendaResultado r, {
    required bool loading,
    bool marcarOffline = false,
  }) {
    if (!r.ok && _lineas.isNotEmpty) {
      setState(() {
        _loading = false;
        _refrescando = false;
        _modoOffline = true;
      });
      return;
    }
    setState(() {
      _loading = loading && r.lineas.isEmpty;
      _refrescando = false;
      if (!r.ok) {
        _error = r.error ?? 'No se pudieron cargar los productos.';
        if (_lineas.isEmpty) {
          _lineas = [];
          _total = 0;
        }
      } else {
        _error = null;
        _lineas = r.lineas;
        _total = r.totalArticulos;
        _numero = r.numeroOrden ?? widget.orden.numeroOrden;
        _compradorNombre = (r.compradorNombre ?? '').trim().isNotEmpty
            ? r.compradorNombre!.trim()
            : widget.orden.emisor;
        _compradorAvatar = r.compradorAvatarUrl ?? _compradorAvatar;
        _destinatarioNombre = (r.destinatarioNombre ?? '').trim().isNotEmpty
            ? r.destinatarioNombre!.trim()
            : widget.orden.receptor;
        _destinatarioAvatar = r.destinatarioAvatarUrl ?? _destinatarioAvatar;
        _modoOffline = marcarOffline && r.desdeCache;
      }
    });
  }

  Future<void> _cargar() async {
    setState(() {
      _loading = true;
      _error = null;
      _modoOffline = false;
    });

    final cached = await _svc.cargarSoloCache(
      widget.orden.id,
      orden: widget.orden,
    );
    if (!mounted) return;
    if (cached != null && cached.ok && cached.lineas.isNotEmpty) {
      _aplicar(cached, loading: false, marcarOffline: false);
      setState(() => _refrescando = true);
    }

    final r = await _svc.cargar(widget.orden.id, orden: widget.orden);
    if (!mounted) return;
    _aplicar(r, loading: false, marcarOffline: r.desdeCache);
  }

  @override
  Widget build(BuildContext context) {
    final numOrden = (_numero ?? widget.orden.numeroOrden).trim();
    return Scaffold(
      backgroundColor: AppColors.darkBg,
      appBar: AppBar(
        backgroundColor: AppColors.header,
        foregroundColor: AppColors.darkText,
        title: const Text(
          'Productos de la orden',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        actions: [
          if (_refrescando)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.botonPrincipal,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: AppColors.botonPrincipal,
                    ),
                  )
                : _error != null && _lineas.isEmpty
                    ? _errorView()
                    : _contenido(numOrden),
          ),
        ),
      ),
    );
  }

  Widget _errorView() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.info_outline, color: AppColors.darkTextMuted, size: 40),
          const SizedBox(height: 12),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.darkTextMuted, height: 1.4),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _cargar,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.header,
              foregroundColor: AppColors.darkText,
            ),
            child: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }

  Widget _contenido(String numOrden) {
    return Column(
      children: [
        if (_modoOffline)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Container(
              width: 400,
              constraints: const BoxConstraints(maxWidth: 400),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.darkElevated,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.offline_pin_outlined,
                      size: 16, color: AppColors.darkTextMuted),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Sin conexión · datos guardados en el dispositivo',
                      style: TextStyle(
                        color: AppColors.darkTextMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Container(
            width: 400,
            constraints: const BoxConstraints(maxWidth: 400),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.darkSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Column(
              children: [
                Text(
                  numOrden.isEmpty ? 'Orden' : '#$numOrden',
                  style: const TextStyle(
                    color: AppColors.darkText,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.inventory_2_outlined,
                        size: 18, color: AppColors.botonPrincipal),
                    const SizedBox(width: 8),
                    Text(
                      '$_total artículo${_total == 1 ? '' : 's'} en total',
                      style: const TextStyle(
                        color: AppColors.darkTextMuted,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: _lineas.isEmpty
              ? ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    const SizedBox(height: 40),
                    const Center(
                      child: Text(
                        'Esta orden no tiene productos listados.',
                        style: TextStyle(color: AppColors.darkTextMuted),
                      ),
                    ),
                    const SizedBox(height: 24),
                    _flujoCompradorDestinatario(),
                  ],
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: _lineas.length + 1,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    if (i < _lineas.length) {
                      return _productoCard(_lineas[i]);
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: _flujoCompradorDestinatario(),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _flujoCompradorDestinatario() {
    final comprador = (_compradorNombre ?? widget.orden.emisor).trim();
    final destinatario = (_destinatarioNombre ?? widget.orden.receptor).trim();
    return Center(
      child: Container(
        width: 400,
        constraints: const BoxConstraints(maxWidth: 400),
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
        decoration: BoxDecoration(
          color: AppColors.darkSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          children: [
            const Text(
              'Flujo de entrega',
              style: TextStyle(
                color: AppColors.darkTextMuted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _personaColumna(
                    nombre: comprador.isEmpty ? 'Comprador' : comprador,
                    avatarUrl: _compradorAvatar,
                    etiqueta: 'Compró',
                    acento: AppColors.botonPrincipal,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    children: [
                      Icon(
                        Icons.arrow_forward_rounded,
                        color: AppColors.botonPrincipal.withValues(alpha: 0.9),
                        size: 28,
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'entregar a',
                        style: TextStyle(
                          color: AppColors.darkTextMuted,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _personaColumna(
                    nombre: destinatario.isEmpty ? 'Destinatario' : destinatario,
                    avatarUrl: _destinatarioAvatar,
                    etiqueta: 'Recibe',
                    acento: const Color(0xFF4CAF50),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _personaColumna({
    required String nombre,
    required String? avatarUrl,
    required String etiqueta,
    required Color acento,
  }) {
    return Column(
      children: [
        _avatarCirculo(nombre: nombre, url: avatarUrl, borde: acento),
        const SizedBox(height: 8),
        Text(
          etiqueta,
          style: TextStyle(
            color: acento,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          nombre,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.darkText,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            height: 1.25,
          ),
        ),
      ],
    );
  }

  Widget _avatarCirculo({
    required String nombre,
    required String? url,
    required Color borde,
  }) {
    final iniciales = _iniciales(nombre);
    final foto = (url ?? '').trim();
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: borde, width: 2),
        color: AppColors.darkElevated,
      ),
      clipBehavior: Clip.antiAlias,
      child: foto.isNotEmpty && foto.startsWith('http')
          ? Image.network(
              foto,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _inicialesAvatar(iniciales, borde),
            )
          : _inicialesAvatar(iniciales, borde),
    );
  }

  Widget _inicialesAvatar(String iniciales, Color color) {
    return Center(
      child: Text(
        iniciales,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 16,
        ),
      ),
    );
  }

  String _iniciales(String nombre) {
    final parts = nombre
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      final s = parts.first;
      return s.substring(0, s.length >= 2 ? 2 : 1).toUpperCase();
    }
    return ('${parts[0][0]}${parts[1][0]}').toUpperCase();
  }

  Widget _fotoProducto(ProductoOrdenTiendaLinea p) {
    final local = (p.imagenLocalPath ?? '').trim();
    if (local.isNotEmpty) {
      final f = File(local);
      if (f.existsSync()) {
        return Image.file(
          f,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _fotoRedOPlaceholder(p),
        );
      }
    }
    return _fotoRedOPlaceholder(p);
  }

  Widget _fotoRedOPlaceholder(ProductoOrdenTiendaLinea p) {
    final url = (p.imagenUrl ?? '').trim();
    if (url.isEmpty || !url.startsWith('http')) {
      return const Icon(
        Icons.image_not_supported_outlined,
        color: AppColors.darkTextMuted,
        size: 28,
      );
    }
    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => const Icon(
        Icons.broken_image_outlined,
        color: AppColors.darkTextMuted,
        size: 28,
      ),
    );
  }

  Widget _productoCard(ProductoOrdenTiendaLinea p) {
    final origen = ProductosOrdenTiendaUtil.infoOrigen(p.origen);
    return Center(
      child: Container(
        width: 400,
        constraints: const BoxConstraints(maxWidth: 400),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.darkSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 72,
                height: 72,
                color: AppColors.darkElevated,
                child: _fotoProducto(p),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.nombre,
                    style: const TextStyle(
                      color: AppColors.darkText,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      height: 1.3,
                    ),
                  ),
                  if (p.detalle != null && p.detalle!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      p.detalle!,
                      style: const TextStyle(
                        color: AppColors.darkTextMuted,
                        fontSize: 11,
                        height: 1.3,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: origen.color.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: origen.color.withValues(alpha: 0.5),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(origen.icono, size: 14, color: origen.color),
                            const SizedBox(width: 4),
                            Text(
                              origen.etiqueta,
                              style: TextStyle(
                                color: origen.color,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        'Cantidad: ${p.cantidad}',
                        style: const TextStyle(
                          color: AppColors.darkTextMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
