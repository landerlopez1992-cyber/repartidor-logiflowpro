import 'package:latlong2/latlong.dart';

/// Centro y zoom del mapa según el país de operación del tenant.
class PaisMapaCentro {
  const PaisMapaCentro({required this.center, required this.zoom});

  final LatLng center;
  final double zoom;

  /// Tenant Cubalink23 (producción).
  static const String cubalink23TenantId =
      '76b6a1e1-71fd-400f-ac17-4a62ceed325d';

  /// Zoom calle (demo Viajes Cubalink23): idle Habana o GPS al buscar.
  static const double cubalink23StreetZoom = 15.3;

  /// Vista calle Habana (10 de Octubre) — idle Cubalink23.
  static const PaisMapaCentro cubalink23HabanaViajes = PaisMapaCentro(
    center: LatLng(23.1092, -82.3680),
    zoom: cubalink23StreetZoom,
  );

  static bool esTenantCubalink23(String? tenantId) {
    final t = (tenantId ?? '').trim().toLowerCase();
    return t == cubalink23TenantId;
  }

  static PaisMapaCentro forPais(String? paisNombre) {
    final n = (paisNombre ?? 'Cuba').toLowerCase().trim();

    if (n.contains('cuba')) {
      // Interior (cerca de Santa Clara): el centro anterior 21.5,-79.5 caía en el mar.
      return const PaisMapaCentro(
        center: LatLng(22.25, -79.55),
        zoom: 6.4,
      );
    }
    if (n.contains('jamaica')) {
      return const PaisMapaCentro(
        center: LatLng(18.15, -77.30),
        zoom: 8.0,
      );
    }
    if (n.contains('méxico') || n.contains('mexico')) {
      return const PaisMapaCentro(
        center: LatLng(23.6, -102.5),
        zoom: 4.8,
      );
    }
    if (n.contains('estados unidos') ||
        n.contains('united states') ||
        n == 'usa' ||
        n == 'eeuu' ||
        n == 'ee.uu.') {
      return const PaisMapaCentro(
        center: LatLng(39.8, -98.5),
        zoom: 3.8,
      );
    }
    if (n.contains('españa') || n.contains('spain')) {
      return const PaisMapaCentro(
        center: LatLng(40.2, -3.7),
        zoom: 5.5,
      );
    }
    if (n.contains('colombia')) {
      return const PaisMapaCentro(
        center: LatLng(4.6, -74.1),
        zoom: 5.2,
      );
    }
    if (n.contains('venezuela')) {
      return const PaisMapaCentro(
        center: LatLng(6.4, -66.6),
        zoom: 5.5,
      );
    }
    if (n.contains('argentina')) {
      return const PaisMapaCentro(
        center: LatLng(-34.6, -58.4),
        zoom: 4.2,
      );
    }
    if (n.contains('chile')) {
      return const PaisMapaCentro(
        center: LatLng(-35.7, -71.5),
        zoom: 4.5,
      );
    }
    if (n.contains('perú') || n.contains('peru')) {
      return const PaisMapaCentro(
        center: LatLng(-9.2, -75.0),
        zoom: 5.0,
      );
    }
    if (n.contains('ecuador')) {
      return const PaisMapaCentro(
        center: LatLng(-1.8, -78.2),
        zoom: 6.0,
      );
    }
    if (n.contains('república dominicana') ||
        n.contains('republica dominicana') ||
        n.contains('dominican')) {
      return const PaisMapaCentro(
        center: LatLng(18.7, -70.2),
        zoom: 7.5,
      );
    }
    if (n.contains('puerto rico')) {
      return const PaisMapaCentro(
        center: LatLng(18.2, -66.4),
        zoom: 8.5,
      );
    }
    if (n.contains('panamá') || n.contains('panama')) {
      return const PaisMapaCentro(
        center: LatLng(8.5, -80.1),
        zoom: 7.0,
      );
    }
    if (n.contains('brasil') || n.contains('brazil')) {
      return const PaisMapaCentro(
        center: LatLng(-14.2, -51.9),
        zoom: 3.8,
      );
    }
    if (n.contains('canadá') || n.contains('canada')) {
      return const PaisMapaCentro(
        center: LatLng(56.1, -106.3),
        zoom: 3.2,
      );
    }

    // Fallback: interior de Cuba (tierra), no el golfo.
    return const PaisMapaCentro(
      center: LatLng(22.25, -79.55),
      zoom: 5.5,
    );
  }
}
