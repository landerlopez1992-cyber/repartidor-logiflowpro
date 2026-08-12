import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../config/app_colors.dart';
import '../models/orden.dart';
import '../services/direccion_navegacion_service.dart';
import '../widgets/repartidor_map_tile_layer.dart';

/// Mapa Volonex (mismo tile layer que taxi) con el destino de entrega.
class MapaDestinoEntregaScreen extends StatefulWidget {
  final Orden orden;
  final Map<String, dynamic>? sucursal;
  final String? paisOperacion;

  const MapaDestinoEntregaScreen({
    super.key,
    required this.orden,
    this.sucursal,
    this.paisOperacion,
  });

  @override
  State<MapaDestinoEntregaScreen> createState() =>
      _MapaDestinoEntregaScreenState();
}

class _MapaDestinoEntregaScreenState extends State<MapaDestinoEntregaScreen> {
  final MapController _mapController = MapController();
  bool _loading = true;
  String? _error;
  LatLng? _destino;
  LatLng? _yo;
  String _direccionLabel = '';

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = DireccionNavegacionService.resolver(
        orden: widget.orden,
        sucursal: widget.sucursal,
        paisOperacion: widget.paisOperacion,
      );
      _direccionLabel = res.direccionCompleta;

      LatLng? dest;
      final lat = widget.orden.latitudEntrega;
      final lng = widget.orden.longitudEntrega;
      if (lat != null && lng != null && lat.abs() > 0.01 && lng.abs() > 0.01) {
        dest = LatLng(lat, lng);
      } else {
        final geo = await DireccionNavegacionService.geocodificarConFallback(res);
        if (geo != null) {
          dest = LatLng(geo.lat, geo.lon);
        }
      }

      LatLng? yo;
      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 6),
          ),
        );
        yo = LatLng(pos.latitude, pos.longitude);
      } catch (_) {}

      if (!mounted) return;
      if (dest == null) {
        setState(() {
          _loading = false;
          _error = res.esValida
              ? 'No se pudo ubicar la dirección en el mapa.'
              : 'No hay dirección completa para navegar.';
        });
        return;
      }

      setState(() {
        _destino = dest;
        _yo = yo;
        _loading = false;
      });

      Future.delayed(const Duration(milliseconds: 80), () {
        if (!mounted || _destino == null) return;
        if (_yo != null) {
          final bounds = LatLngBounds.fromPoints([_yo!, _destino!]);
          _mapController.fitCamera(
            CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(48)),
          );
        } else {
          _mapController.move(_destino!, 15);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Error al cargar el mapa: $e';
      });
    }
  }

  Future<void> _abrirGoogleMaps() async {
    await DireccionNavegacionService.abrirDestinoEnGoogleMaps(
      orden: widget.orden,
      sucursal: widget.sucursal,
      paisOperacion: widget.paisOperacion,
      latitudFallback: widget.orden.latitudEntrega,
      longitudFallback: widget.orden.longitudEntrega,
    );
  }

  @override
  Widget build(BuildContext context) {
    final num =
        widget.orden.numeroRemesa?.isNotEmpty == true
            ? widget.orden.numeroRemesa!
            : widget.orden.numeroOrden;

    return Scaffold(
      backgroundColor: AppColors.darkBg,
      appBar: AppBar(
        backgroundColor: const Color(0xFF37474F),
        title: Text(
          'Destino #$num',
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            tooltip: 'Abrir en Google Maps',
            onPressed: _abrirGoogleMaps,
            icon: const Icon(Icons.open_in_new, color: Colors.white),
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFFF9800)),
            )
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.map_outlined,
                            size: 48, color: Color(0xFF9CA3AF)),
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppColors.darkText),
                        ),
                        if (_direccionLabel.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            _direccionLabel,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: AppColors.darkTextMuted,
                              fontSize: 13,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _abrirGoogleMaps,
                          icon: const Icon(Icons.navigation),
                          label: const Text('Abrir en Google Maps'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF4CAF50),
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : Stack(
                  children: [
                    FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: _destino!,
                        initialZoom: 15,
                        minZoom: 5,
                        maxZoom: 18,
                      ),
                      children: [
                        RepartidorMapTileLayer(
                          preferOnline: true,
                          maxZoom: 18,
                          tenantId: widget.orden.tenantId,
                        ),
                        MarkerLayer(
                          markers: [
                            if (_yo != null)
                              Marker(
                                point: _yo!,
                                width: 40,
                                height: 40,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1976D2),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: Colors.white, width: 2),
                                  ),
                                  child: const Icon(
                                    Icons.navigation,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ),
                              ),
                            Marker(
                              point: _destino!,
                              width: 48,
                              height: 48,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFF9800),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: Colors.white, width: 3),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.25),
                                      blurRadius: 6,
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.location_on,
                                  color: Colors.white,
                                  size: 26,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 16 + MediaQuery.paddingOf(context).bottom,
                      child: Material(
                        color: AppColors.darkSurface,
                        elevation: 4,
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Dirección de entrega',
                                style: TextStyle(
                                  color: AppColors.darkTextMuted,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _direccionLabel.isNotEmpty
                                    ? _direccionLabel
                                    : 'Destino',
                                style: const TextStyle(
                                  color: AppColors.darkText,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Center(
                                child: ElevatedButton.icon(
                                  onPressed: _abrirGoogleMaps,
                                  icon: const Icon(Icons.navigation, size: 18),
                                  label: const Text('Navegar (Google Maps)'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF4CAF50),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 10,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}
