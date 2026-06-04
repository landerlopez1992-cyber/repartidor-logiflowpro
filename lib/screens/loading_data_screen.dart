import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../widgets/volonex_dialog.dart';

/// Pantalla de carga que muestra progreso mientras se cargan datos reales
/// Esta pantalla ejecuta tareas en segundo plano y muestra el progreso
class LoadingDataScreen extends StatefulWidget {
  final String? userName;
  final String? empresaNombre;
  final String? empresaLogoUrl;
  final Future<void> Function(Function(double progress, String message) updateProgress)? onLoadData;
  final VoidCallback? onComplete;

  const LoadingDataScreen({
    super.key,
    this.userName,
    this.empresaNombre,
    this.empresaLogoUrl,
    this.onLoadData,
    this.onComplete,
  });

  @override
  State<LoadingDataScreen> createState() => _LoadingDataScreenState();
}

class _LoadingDataScreenState extends State<LoadingDataScreen> {
  double _progress = 0.0;
  String _currentMessage = 'Iniciando...';

  @override
  void initState() {
    super.initState();
    _startLoadingProcess();
  }

  Future<void> _startLoadingProcess() async {
    try {
      if (widget.onLoadData != null) {
        // Ejecutar la función de carga de datos proporcionada
        await widget.onLoadData!((progress, message) {
          if (mounted) {
            setState(() {
              _progress = progress;
              _currentMessage = message;
            });
          }
        });
      } else {
        // Si no hay función de carga, simplemente simular carga
        await _simulateLoading();
      }

      // Asegurar que llegue al 100%
      if (mounted) {
        setState(() {
          _progress = 1.0;
          _currentMessage = 'Completado';
        });
        
        // Pequeño delay antes de llamar onComplete
        await Future.delayed(const Duration(milliseconds: 300));
        
        // Llamar al callback de completado
        if (widget.onComplete != null) {
          widget.onComplete!();
        }
      }
    } catch (e) {
      print('❌ Error en proceso de carga: $e');
      if (mounted) {
        setState(() {
          _currentMessage = 'Error: $e';
        });
        
        // Aún así completar para no dejar al usuario bloqueado
        await Future.delayed(const Duration(seconds: 2));
        if (widget.onComplete != null) {
          widget.onComplete!();
        }
      }
    }
  }

  Future<void> _simulateLoading() async {
    final stages = [
      {'text': 'Inicializando sistema', 'duration': 1.0},
      {'text': 'Cargando configuración', 'duration': 1.0},
      {'text': 'Preparando interfaz', 'duration': 1.0},
      {'text': 'Verificando conexión', 'duration': 1.0},
      {'text': 'Finalizando', 'duration': 1.0},
    ];

    double totalDuration = stages.fold(0.0, (sum, stage) => sum + (stage['duration'] as double));
    double accumulatedProgress = 0.0;

    for (var stage in stages) {
      if (!mounted) return;
      
      setState(() {
        _currentMessage = stage['text'] as String;
      });

      double stageDuration = stage['duration'] as double;
      double stageProgressIncrement = (stageDuration / totalDuration);

      int steps = 20;
      double stepProgress = stageProgressIncrement / steps;
      double stepDuration = stageDuration / steps;

      for (int j = 0; j < steps; j++) {
        await Future.delayed(Duration(milliseconds: (stepDuration * 1000).round()));
        if (mounted) {
          setState(() {
            accumulatedProgress += stepProgress;
            _progress = accumulatedProgress;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBg,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.header,
              Color(0xFF263238),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: AppLayout.formMaxWidth),
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo de la empresa
                  if (widget.empresaLogoUrl != null && widget.empresaLogoUrl!.isNotEmpty)
                    Container(
                      width: 120,
                      height: 120,
                      margin: const EdgeInsets.only(bottom: 32),
                      decoration: BoxDecoration(
                        color: AppColors.darkSurface,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.network(
                          widget.empresaLogoUrl!,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              color: AppColors.darkSurface,
                              child: Center(
                                child: Text(
                                  widget.empresaNombre?.isNotEmpty == true
                                      ? widget.empresaNombre![0].toUpperCase()
                                      : 'L',
                                  style: const TextStyle(
                                    fontSize: 48,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.header,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    )
                  else if (widget.empresaNombre != null && widget.empresaNombre!.isNotEmpty)
                    Container(
                      width: 120,
                      height: 120,
                      margin: const EdgeInsets.only(bottom: 32),
                      decoration: BoxDecoration(
                        color: AppColors.darkSurface,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          widget.empresaNombre![0].toUpperCase(),
                          style: const TextStyle(
                            fontSize: 48,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF37474F),
                          ),
                        ),
                      ),
                    )
                  else
                    // Usar logo local si no hay logo de empresa
                    Container(
                      width: 120,
                      height: 120,
                      margin: const EdgeInsets.only(bottom: 32),
                      decoration: BoxDecoration(
                        color: AppColors.darkSurface,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.asset(
                          'assets/logo_julio.png',
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) {
                            return const Center(
                              child: Icon(
                                Icons.delivery_dining,
                                size: 60,
                                color: AppColors.header,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  
                  // Nombre de la empresa
                  if (widget.empresaNombre != null && widget.empresaNombre!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        widget.empresaNombre!,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: AppColors.darkSurface,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  
                  const SizedBox(height: 48),
                  
                  // Mensaje actual
                  Text(
                    _currentMessage,
                    style: const TextStyle(
                      fontSize: 18,
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Barra de progreso
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: _progress,
                      minHeight: 8,
                      backgroundColor: Colors.white.withValues(alpha: 0.2),
                      valueColor: const AlwaysStoppedAnimation<Color>(AppColors.exito),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Porcentaje
                  Text(
                    '${(_progress * 100).toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white.withValues(alpha: 0.8),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
