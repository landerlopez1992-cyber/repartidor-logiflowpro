import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'repartidor_jornada_service.dart';

/// Odómetro GPS filtrado solo durante jornada activa (auditoría, no pago).
/// Filtros: precisión, saltos imposibles, idle.
class RepartidorGpsOdometroService {
  RepartidorGpsOdometroService._();
  static final RepartidorGpsOdometroService instance =
      RepartidorGpsOdometroService._();

  static const _prefsKey = 'rep_gps_odometro_km_';
  static const double _maxAccuracyM = 50;
  static const double _maxJumpM = 200; // teleport en un tick
  static const double _minMoveM = 8;
  static const Duration _syncEvery = Duration(seconds: 45);

  StreamSubscription<Position>? _sub;
  String? _jornadaId;
  String? _repartidorId;
  double _kmAcumulado = 0;
  Position? _last;
  DateTime? _lastSync;
  bool _enRuta = false;

  double get kmAcumulado => _kmAcumulado;

  Future<void> start({
    required String repartidorId,
    required String jornadaId,
    double? seedKm,
  }) async {
    await stop(sync: false);
    _repartidorId = repartidorId;
    _jornadaId = jornadaId;
    _kmAcumulado = seedKm ?? await _loadLocal(jornadaId);
    _last = null;
    _enRuta = true;

    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) return;

    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      return;
    }

    _sub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen(_onPosition, onError: (_) {});
  }

  /// Pausar acumulación (idle / no navegando). No detiene el stream.
  void setEnRuta(bool value) => _enRuta = value;

  Future<void> stop({bool sync = true}) async {
    await _sub?.cancel();
    _sub = null;
    if (sync && _jornadaId != null) {
      await _syncRemote(force: true);
    }
    if (_jornadaId != null) {
      await _saveLocal(_jornadaId!, _kmAcumulado);
    }
    _jornadaId = null;
    _repartidorId = null;
    _last = null;
  }

  void _onPosition(Position pos) {
    if (!_enRuta || _jornadaId == null) {
      _last = pos;
      return;
    }
    if (pos.accuracy > _maxAccuracyM) return;

    final prev = _last;
    _last = pos;
    if (prev == null) return;

    final metros = Geolocator.distanceBetween(
      prev.latitude,
      prev.longitude,
      pos.latitude,
      pos.longitude,
    );
    if (metros < _minMoveM) return;
    if (metros > _maxJumpM) return; // teleport

    final dtMs = pos.timestamp.difference(prev.timestamp).inMilliseconds;
    if (dtMs > 0) {
      final mps = metros / (dtMs / 1000.0);
      // > ~160 km/h imposible en ciudad de entrega típica
      if (mps > 45) return;
    }

    _kmAcumulado += metros / 1000.0;
    _saveLocal(_jornadaId!, _kmAcumulado);
    _syncRemote();
  }

  Future<void> _syncRemote({bool force = false}) async {
    final id = _jornadaId;
    if (id == null) return;
    final now = DateTime.now();
    if (!force &&
        _lastSync != null &&
        now.difference(_lastSync!) < _syncEvery) {
      return;
    }
    _lastSync = now;
    try {
      await RepartidorJornadaService.sincronizarKmGps(
        jornadaId: id,
        kmGps: _kmAcumulado,
      );
    } catch (_) {}
  }

  Future<double> _loadLocal(String jornadaId) async {
    final p = await SharedPreferences.getInstance();
    return p.getDouble('$_prefsKey$jornadaId') ?? 0;
  }

  Future<void> _saveLocal(String jornadaId, double km) async {
    final p = await SharedPreferences.getInstance();
    await p.setDouble('$_prefsKey$jornadaId', km);
  }
}
