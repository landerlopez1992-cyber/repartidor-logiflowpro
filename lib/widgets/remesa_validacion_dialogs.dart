import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../utils/remesa_pura_entrega_ui.dart';
import 'volonex_dialog.dart';

/// Modales de validación de remesa — tema oscuro Volonex (legibles offline y online).
class RemesaValidacionDialogs {
  RemesaValidacionDialogs._();

  /// Confirmación cuando la orden incluye remesa (no remesa pura).
  static Future<bool> confirmarEntregaEnOrden({
    required BuildContext context,
    required double cantidadRemesa,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (ctx) => VolonexDialog(
        title: 'Confirmar entrega de remesa',
        leading: const Icon(Icons.attach_money, color: RemesaPuraUiTheme.acento, size: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Antes de continuar, verifica:',
              style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.darkText),
            ),
            const SizedBox(height: 14),
            _cajaDestacada(
              label: 'Cantidad de remesa',
              valor: '\$${cantidadRemesa.toStringAsFixed(2)}',
            ),
            const SizedBox(height: 14),
            _cajaAviso('¿Entregaste la remesa correctamente al cliente?'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar', style: TextStyle(color: AppColors.darkTextMuted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.exito,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            child: const Text('Sí, confirmar', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  static Future<bool> confirmarEntregaFinal({
    required BuildContext context,
    required String numeroRemesa,
    required double cantidad,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (ctx) => VolonexDialog(
        title: 'Confirmar entrega de remesa',
        leading: const Icon(
          Icons.check_circle_outline,
          color: RemesaPuraUiTheme.acento,
          size: 26,
        ),
        child: Text(
          '¿Confirmas que entregaste la remesa #$numeroRemesa al destinatario?\n\n'
          'Cantidad: \$${cantidad.toStringAsFixed(2)}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(
              'Cancelar',
              style: TextStyle(color: AppColors.darkTextMuted),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: RemesaPuraUiTheme.acentoFuerte,
              foregroundColor: AppColors.onAccentButton,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            child: const Text('Confirmar', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  static Future<bool?> mostrarValidacionRemesa({
    required BuildContext context,
    required String numeroRemesa,
    required String nombreDestinatario,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (ctx) => VolonexDialog(
        title: 'Validación de remesa',
        leading: const Icon(Icons.security, color: RemesaPuraUiTheme.acento, size: 26),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _cajaDestacada(
                label: 'Número de remesa',
                valor: '#$numeroRemesa',
                valorGrande: true,
              ),
              const SizedBox(height: 16),
              const Text(
                'Instrucciones de seguridad',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppColors.darkText,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '1. Pregunta al destinatario por el número: #$numeroRemesa',
                style: _pasoStyle,
              ),
              const SizedBox(height: 8),
              const Text('2. Verifica el documento de identidad del destinatario', style: _pasoStyle),
              const SizedBox(height: 4),
              Text(
                '   Nombre en sistema: $nombreDestinatario',
                style: _pasoSecundario,
              ),
              const SizedBox(height: 8),
              const Text(
                '3. Confirma que el nombre del documento coincide con el destinatario de la remesa',
                style: _pasoStyle,
              ),
            ],
          ),
        ),
        actions: _accionesContinuarCancelar(ctx),
      ),
    );
  }

  static Future<bool?> pedirNumeroRmsa({
    required BuildContext context,
    required String numeroRemesaEsperado,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (ctx) => VolonexDialog(
        title: 'Verificar número RMSA',
        leading: const Icon(Icons.verified_user, color: RemesaPuraUiTheme.acento, size: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Pregunta al cliente si conoce el número de remesa:',
              style: TextStyle(color: AppColors.darkText, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 16),
            _cajaDestacada(
              label: 'Número de remesa',
              valor: '#$numeroRemesaEsperado',
              valorGrande: true,
            ),
            const SizedBox(height: 14),
            _cajaInfo(
              'Pregunta al cliente por el número y confirma que lo conoce correctamente.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar', style: TextStyle(color: AppColors.darkTextMuted)),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.of(ctx).pop(true),
            icon: const Icon(Icons.check_circle, size: 18),
            label: const Text('Verificar', style: TextStyle(fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: RemesaPuraUiTheme.acentoFuerte,
              foregroundColor: AppColors.onAccentButton,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
          ),
        ],
      ),
    );
  }

  static Future<bool?> verificarIdDestinatario({
    required BuildContext context,
    required String nombreDestinatarioEsperado,
  }) {
    final controller = TextEditingController();

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (ctx) => VolonexDialog(
        title: 'Verificar ID / carné',
        leading: const Icon(Icons.credit_card, color: RemesaPuraUiTheme.acento, size: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Verifica el documento de identidad del destinatario:',
              style: TextStyle(color: AppColors.darkText),
            ),
            const SizedBox(height: 12),
            _cajaInfoAzul(
              titulo: 'Nombre esperado',
              valor: nombreDestinatarioEsperado,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              style: const TextStyle(color: AppColors.darkText),
              decoration: InputDecoration(
                labelText: 'Nombre en el documento',
                hintText: 'Como aparece en el ID',
                labelStyle: const TextStyle(color: AppColors.darkTextMuted),
                hintStyle: const TextStyle(color: AppColors.darkTextMuted),
                filled: true,
                fillColor: AppColors.darkElevated,
                prefixIcon: const Icon(Icons.person, color: AppColors.darkTextMuted),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.darkBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: RemesaPuraUiTheme.acento, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _cajaAviso(
              'El nombre y apellido deben coincidir con el destinatario de la remesa.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar', style: TextStyle(color: AppColors.darkTextMuted)),
          ),
          ElevatedButton(
            onPressed: () {
              final nombreID = controller.text.trim().toUpperCase();
              final nombreEsperado = nombreDestinatarioEsperado.toUpperCase();
              final palabras = nombreEsperado.split(' ');
              final coincide = palabras.any(
                    (p) => p.isNotEmpty && nombreID.contains(p),
                  ) ||
                  nombreID.contains(nombreEsperado);

              if (coincide || nombreID == nombreEsperado) {
                Navigator.of(ctx).pop(true);
              } else {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'El nombre del documento no coincide con el destinatario',
                    ),
                    backgroundColor: AppColors.botonPrincipal,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: RemesaPuraUiTheme.acentoFuerte,
              foregroundColor: AppColors.onAccentButton,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            child: const Text('Confirmar', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  static const TextStyle _pasoStyle = TextStyle(
    fontSize: 14,
    color: AppColors.darkText,
    height: 1.45,
  );

  static const TextStyle _pasoSecundario = TextStyle(
    fontSize: 13,
    color: AppColors.darkTextMuted,
    fontStyle: FontStyle.italic,
    height: 1.4,
  );

  static List<Widget> _accionesContinuarCancelar(BuildContext ctx) => [
    TextButton(
      onPressed: () => Navigator.of(ctx).pop(false),
      child: const Text('Cancelar', style: TextStyle(color: AppColors.darkTextMuted)),
    ),
    ElevatedButton(
      onPressed: () => Navigator.of(ctx).pop(true),
      style: ElevatedButton.styleFrom(
        backgroundColor: RemesaPuraUiTheme.acentoFuerte,
        foregroundColor: AppColors.onAccentButton,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      ),
      child: const Text('Continuar', style: TextStyle(fontWeight: FontWeight.bold)),
    ),
  ];

  static Widget _cajaDestacada({
    required String label,
    required String valor,
    bool valorGrande = false,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: RemesaPuraUiTheme.fondoDestacado,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: RemesaPuraUiTheme.borde, width: 1.5),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.darkTextMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            valor,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: valorGrande ? 26 : 16,
              fontWeight: FontWeight.bold,
              color: RemesaPuraUiTheme.acento,
              letterSpacing: valorGrande ? 1.2 : 0,
            ),
          ),
        ],
      ),
    );
  }

  static Widget _cajaInfo(String texto) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.darkElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.info.withValues(alpha: 0.6)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: AppColors.info, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(texto, style: const TextStyle(fontSize: 13, color: AppColors.darkText)),
          ),
        ],
      ),
    );
  }

  static Widget _cajaInfoAzul({required String titulo, required String valor}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.darkElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.info),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: const TextStyle(fontSize: 12, color: AppColors.darkTextMuted),
          ),
          const SizedBox(height: 4),
          Text(
            valor,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.info,
            ),
          ),
        ],
      ),
    );
  }

  static Widget _cajaAviso(String texto) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.botonPrincipal.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.botonPrincipal.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: AppColors.botonPrincipal, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              texto,
              style: const TextStyle(fontSize: 12, color: AppColors.darkText),
            ),
          ),
        ],
      ),
    );
  }
}
