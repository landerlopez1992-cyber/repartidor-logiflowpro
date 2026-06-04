import 'package:flutter/material.dart';
import '../config/app_colors.dart';

/// Diálogo compacto VolonexPro+ (oscuro, ancho máximo fijo, sin estirar).
class VolonexDialog extends StatelessWidget {
  const VolonexDialog({
    super.key,
    required this.title,
    this.leading,
    this.maxWidth = AppLayout.dialogMaxWidth,
    this.actions,
    required this.child,
  });

  final String title;
  final Widget? leading;
  final double maxWidth;
  final List<Widget>? actions;
  final Widget child;

  static const Color _bg = AppColors.darkSurface;
  static const Color _headerBg = AppColors.header;
  static const Color _border = AppColors.darkBorder;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Center(
        child: Container(
          constraints: BoxConstraints(maxWidth: maxWidth),
          decoration: BoxDecoration(
            color: _bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                decoration: const BoxDecoration(
                  color: _headerBg,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(13)),
                ),
                child: Row(
                  children: [
                    if (leading != null) ...[
                      leading!,
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                child: DefaultTextStyle(
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.45,
                    color: AppColors.darkText,
                  ),
                  child: child,
                ),
              ),
              if (actions != null && actions!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: actions!,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Anchos máximos estándar (ventanas compactas, no estiradas).
class AppLayout {
  AppLayout._();

  static const double dialogMaxWidth = 400;
  static const double dialogWideMaxWidth = 420;
  static const double formMaxWidth = 340;
  static const double cardMaxWidth = 700;
  static const double contentMaxWidth = 600;
  static const double fieldMaxWidth = 400;
}

/// Contenedor centrado con ancho máximo (formularios, tarjetas).
class VolonexCentered extends StatelessWidget {
  const VolonexCentered({
    super.key,
    required this.child,
    this.maxWidth = AppLayout.contentMaxWidth,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: padding,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      ),
    );
  }
}

/// Botón de acción compacto y centrado (no ocupa todo el ancho).
class VolonexActionButton extends StatelessWidget {
  const VolonexActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.backgroundColor,
    this.foregroundColor,
    this.outlined = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final child = icon != null
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: 8),
              Text(label),
            ],
          )
        : Text(label);

    return Center(
      child: outlined
          ? OutlinedButton(
              onPressed: onPressed,
              style: OutlinedButton.styleFrom(
                foregroundColor: foregroundColor ?? AppColors.botonPrincipal,
                side: BorderSide(
                  color: foregroundColor ?? AppColors.botonPrincipal,
                  width: 1.5,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
              child: child,
            )
          : ElevatedButton(
              onPressed: onPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: backgroundColor ?? AppColors.botonPrincipal,
                foregroundColor: foregroundColor ?? Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                elevation: 2,
              ),
              child: child,
            ),
    );
  }
}

Future<bool> showVolonexConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String cancelLabel = 'Cancelar',
  String confirmLabel = 'Confirmar',
  Color confirmColor = AppColors.exito,
  IconData icon = Icons.help_outline,
  Color iconColor = AppColors.botonPrincipal,
  bool barrierDismissible = true,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (ctx) => VolonexDialog(
      title: title,
      leading: Icon(icon, color: iconColor, size: 24),
      child: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(
            cancelLabel,
            style: const TextStyle(color: AppColors.darkTextMuted),
          ),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          style: ElevatedButton.styleFrom(
            backgroundColor: confirmColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          ),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

Future<void> showVolonexMessageDialog(
  BuildContext context, {
  required String title,
  required String message,
  bool isError = true,
  String buttonLabel = 'Entendido',
}) {
  final color = isError ? AppColors.error : AppColors.exito;
  return showDialog<void>(
    context: context,
    builder: (ctx) => VolonexDialog(
      title: title,
      leading: Icon(
        isError ? Icons.error_outline : Icons.check_circle_outline,
        color: color,
        size: 26,
      ),
      child: SelectableText(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(
            buttonLabel,
            style: TextStyle(color: AppColors.botonPrincipal, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

Future<void> showVolonexProgressDialog(
  BuildContext context, {
  required String title,
  required String message,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => VolonexDialog(
      title: title,
      leading: const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.botonPrincipal),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}

void showVolonexSnackBar(
  BuildContext context,
  String message, {
  Color? backgroundColor,
  int seconds = 3,
}) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: backgroundColor ?? AppColors.header,
      behavior: SnackBarBehavior.floating,
      duration: Duration(seconds: seconds),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
  );
}
