import 'package:flutter/material.dart';

/// Clave global para deep links FCM / notificaciones locales.
class RepartidorNavigator {
  RepartidorNavigator._();

  static final GlobalKey<NavigatorState> key = GlobalKey<NavigatorState>();

  static NavigatorState? get state => key.currentState;

  static BuildContext? get context => key.currentContext;
}
