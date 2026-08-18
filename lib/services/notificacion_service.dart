import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'notificacion_storage_service.dart';

class NotificacionService {
  static final NotificacionService _instance = NotificacionService._internal();
  factory NotificacionService() => _instance;
  NotificacionService._internal();

  final FlutterLocalNotificationsPlugin _notificaciones =
      FlutterLocalNotificationsPlugin();

  bool _inicializado = false;

  Future<void> inicializar() async {
    if (_inicializado) return;

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/launcher_icon',
    );
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
    );

    await _notificaciones.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationResponse,
    );

    _inicializado = true;
  }

  void _onNotificationResponse(NotificationResponse response) {
  }

  Future<void> solicitarPermisos() async {
    // Permisos para Android
    final android = _notificaciones
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      await android.requestNotificationsPermission();
    }

    // Permisos para iOS/Darwin
    final ios = _notificaciones
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (ios != null) {
      await ios.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
    }
  }

  Future<void> mostrarNotificacion({
    required int id,
    required String titulo,
    required String cuerpo,
    String? canalId,
    String? canalNombre,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'trucktime_alertas',
      'Alertas de conducción',
      channelDescription: 'Alertas de tiempo de conducción',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );

    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
    );

    await _notificaciones.show(id, titulo, cuerpo, details);
    String tipo = 'info';
    final tituloLower = titulo.toLowerCase();
    final cuerpoLower = cuerpo.toLowerCase();
    
    if (tituloLower.contains('conduc') || cuerpoLower.contains('conduc')) {
      tipo = 'conduccion';
    } else if (tituloLower.contains('descanso') || cuerpoLower.contains('pausa')) {
      tipo = 'descanso';
    } else if (tituloLower.contains('jornada')) {
      tipo = 'jornada';
    }

    await NotificacionStorageService().agregar(
      titulo: titulo,
      cuerpo: cuerpo,
      tipo: tipo,
    );
  }

  Future<void> cancelarNotificacion(int id) async {
    await _notificaciones.cancel(id);
  }

  Future<void> cancelarTodas() async {
    await _notificaciones.cancelAll();
  }
}
