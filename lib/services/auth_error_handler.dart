import 'package:supabase_flutter/supabase_flutter.dart';

/// Servicio para manejar errores de autenticación y convertirlos en mensajes amigables
class AuthErrorHandler {
  /// Convierte un error de autenticación en un mensaje amigable para el usuario
  static String getFriendlyErrorMessage(dynamic error) {
    if (error == null) {
      return 'Ocurrió un error inesperado. Por favor, intenta nuevamente.';
    }

    final errorString = error.toString().toLowerCase();

    // Verificar si es un AuthApiException de Supabase
    if (error is AuthException) {
      return _handleAuthException(error);
    }

    // Manejar errores de red/conexión
    if (errorString.contains('network') || 
        errorString.contains('connection') ||
        errorString.contains('socket') ||
        errorString.contains('timeout')) {
      return 'No se pudo conectar al servidor. Verifica tu conexión a internet e intenta nuevamente.';
    }

    // Manejar errores de credenciales inválidas
    if (errorString.contains('invalid login credentials') ||
        errorString.contains('invalid_credentials') ||
        errorString.contains('invalid credentials') ||
        errorString.contains('email or password') ||
        errorString.contains('wrong password')) {
      return 'Correo electrónico o contraseña incorrectos. Verifica tus credenciales e intenta nuevamente.';
    }

    // Manejar errores de email no confirmado
    if (errorString.contains('email not confirmed') ||
        errorString.contains('email_not_confirmed') ||
        errorString.contains('email_not_verified') ||
        errorString.contains('verification')) {
      return 'Tu cuenta existe en el sistema, pero necesitas confirmar tu correo electrónico antes de acceder.\n\n'
          'Por favor, revisa tu bandeja de entrada y haz clic en el enlace de confirmación que te enviamos.';
    }

    // Manejar errores de usuario no encontrado
    if (errorString.contains('user not found') ||
        errorString.contains('user_not_found') ||
        errorString.contains('no user found')) {
      return 'No se encontró una cuenta con este correo electrónico. Verifica que el correo sea correcto o contacta al administrador.';
    }

    // Manejar errores de cuenta deshabilitada
    if (errorString.contains('disabled') ||
        errorString.contains('banned') ||
        errorString.contains('suspended')) {
      return 'Tu cuenta ha sido deshabilitada. Por favor, contacta al administrador para más información.';
    }

    // Manejar errores de demasiados intentos
    if (errorString.contains('too many requests') ||
        errorString.contains('rate limit') ||
        errorString.contains('too_many_requests')) {
      return 'Demasiados intentos de inicio de sesión. Por favor, espera unos minutos e intenta nuevamente.';
    }

    // Manejar errores de formato de email
    if (errorString.contains('invalid email') ||
        errorString.contains('email format') ||
        errorString.contains('malformed')) {
      return 'El formato del correo electrónico no es válido. Por favor, verifica que esté escrito correctamente.';
    }

    // Manejar errores de contraseña débil
    if (errorString.contains('password') && 
        (errorString.contains('weak') || errorString.contains('short'))) {
      return 'La contraseña es demasiado débil. Debe tener al menos 6 caracteres.';
    }

    // Error genérico si no se pudo identificar
    return 'Ocurrió un error al iniciar sesión. Por favor, verifica tus credenciales e intenta nuevamente.\n\n'
        'Si el problema persiste, contacta al administrador.';
  }

  /// Maneja específicamente los errores AuthException de Supabase
  static String _handleAuthException(AuthException error) {
    final message = error.message.toLowerCase();
    final statusCode = error.statusCode?.toString();

    // Error 400: Bad Request - generalmente credenciales inválidas
    if (statusCode == '400') {
      if (message.contains('email not confirmed') || 
          message.contains('email_not_confirmed')) {
        return 'Tu cuenta existe en el sistema, pero necesitas confirmar tu correo electrónico antes de acceder.\n\n'
            'Por favor, revisa tu bandeja de entrada y haz clic en el enlace de confirmación que te enviamos.';
      }
      
      if (message.contains('invalid') && 
          (message.contains('credentials') || message.contains('password'))) {
        return 'Correo electrónico o contraseña incorrectos. Verifica tus credenciales e intenta nuevamente.';
      }
    }

    // Error 401: Unauthorized
    if (statusCode == '401') {
      return 'No tienes autorización para acceder. Verifica tus credenciales e intenta nuevamente.';
    }

    // Error 422: Unprocessable Entity - generalmente email no confirmado
    if (statusCode == '422') {
      if (message.contains('email not confirmed') || 
          message.contains('email_not_confirmed')) {
        return 'Tu cuenta existe en el sistema, pero necesitas confirmar tu correo electrónico antes de acceder.\n\n'
            'Por favor, revisa tu bandeja de entrada y haz clic en el enlace de confirmación que te enviamos.';
      }
    }

    // Error 429: Too Many Requests
    if (statusCode == '429') {
      return 'Demasiados intentos de inicio de sesión. Por favor, espera unos minutos e intenta nuevamente.';
    }

    // Error 500: Internal Server Error
    if (statusCode == '500' || statusCode == '502' || statusCode == '503') {
      return 'El servidor está experimentando problemas. Por favor, intenta nuevamente en unos momentos.';
    }

    // Si el mensaje contiene información específica, usarla
    if (error.message.isNotEmpty) {
      // Intentar extraer un mensaje más amigable del mensaje original
      final originalMessage = error.message.toLowerCase();
      
      if (originalMessage.contains('email not confirmed')) {
        return 'Tu cuenta existe en el sistema, pero necesitas confirmar tu correo electrónico antes de acceder.\n\n'
            'Por favor, revisa tu bandeja de entrada y haz clic en el enlace de confirmación que te enviamos.';
      }
    }

    // Mensaje genérico para otros errores de AuthException
    return 'Ocurrió un error al iniciar sesión. Por favor, verifica tus credenciales e intenta nuevamente.';
  }

  /// Verifica si el error es específicamente de email no confirmado
  static bool isEmailNotConfirmedError(dynamic error) {
    if (error == null) return false;
    
    final errorString = error.toString().toLowerCase();
    
    if (error is AuthException) {
      final message = error.message.toLowerCase();
      final statusCode = error.statusCode?.toString();
      
      return message.contains('email not confirmed') ||
             message.contains('email_not_confirmed') ||
             statusCode == '422';
    }
    
    return errorString.contains('email not confirmed') ||
           errorString.contains('email_not_confirmed') ||
           errorString.contains('email_not_verified') ||
           errorString.contains('verification');
  }
}
