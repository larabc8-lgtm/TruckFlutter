import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Modelo de una notificación almacenada localmente.
class NotificacionLocal {
  final String id;
  final String titulo;
  final String cuerpo;
  final String tipo; // 'conduccion', 'descanso', 'jornada', 'semanal', 'info'
  final DateTime fecha;
  bool leida;

  NotificacionLocal({
    required this.id,
    required this.titulo,
    required this.cuerpo,
    required this.tipo,
    required this.fecha,
    this.leida = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'titulo': titulo,
    'cuerpo': cuerpo,
    'tipo': tipo,
    'fecha': fecha.toIso8601String(),
    'leida': leida,
  };

  factory NotificacionLocal.fromJson(Map<String, dynamic> json) {
    return NotificacionLocal(
      id: json['id'] as String,
      titulo: json['titulo'] as String,
      cuerpo: json['cuerpo'] as String,
      tipo: json['tipo'] as String? ?? 'info',
      fecha: DateTime.parse(json['fecha'] as String),
      leida: json['leida'] as bool? ?? false,
    );
  }
}

/// Servicio que persiste las notificaciones localmente usando SharedPreferences.
/// Patrón Singleton para acceder desde cualquier parte de la app.
class NotificacionStorageService {
  static final NotificacionStorageService _instance =
      NotificacionStorageService._internal();
  factory NotificacionStorageService() => _instance;
  NotificacionStorageService._internal();

  static const String _key = 'notificaciones_locales';
  static const int _maxNotificaciones = 100; // Límite para no saturar storage

  List<NotificacionLocal> _cache = [];
  bool _cargado = false;

  /// Carga las notificaciones desde SharedPreferences (se llama una vez).
  Future<void> cargar() async {
    if (_cargado) return;
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_key);
    if (data != null) {
      final List<dynamic> lista = json.decode(data);
      _cache = lista
          .map((e) => NotificacionLocal.fromJson(e as Map<String, dynamic>))
          .toList();
      // Ordenar por fecha descendente (más recientes primero)
      _cache.sort((a, b) => b.fecha.compareTo(a.fecha));
    }
    _cargado = true;
  }

  /// Guarda el estado actual en SharedPreferences.
  Future<void> _guardar() async {
    final prefs = await SharedPreferences.getInstance();
    final data = json.encode(_cache.map((n) => n.toJson()).toList());
    await prefs.setString(_key, data);
  }

  /// Añade una nueva notificación y la persiste.
  Future<void> agregar({
    required String titulo,
    required String cuerpo,
    String tipo = 'info',
  }) async {
    await cargar();
    final notif = NotificacionLocal(
      id: '${DateTime.now().millisecondsSinceEpoch}_${_cache.length}',
      titulo: titulo,
      cuerpo: cuerpo,
      tipo: tipo,
      fecha: DateTime.now(),
    );
    _cache.insert(0, notif); // Insertar al principio (más reciente)

    // Limitar la cantidad total
    if (_cache.length > _maxNotificaciones) {
      _cache = _cache.sublist(0, _maxNotificaciones);
    }

    await _guardar();
  }

  /// Devuelve todas las notificaciones (más recientes primero).
  Future<List<NotificacionLocal>> obtenerTodas() async {
    await cargar();
    return List.unmodifiable(_cache);
  }

  /// Devuelve solo las no leídas.
  Future<List<NotificacionLocal>> obtenerNoLeidas() async {
    await cargar();
    return _cache.where((n) => !n.leida).toList();
  }

  /// Cantidad de no leídas.
  Future<int> contarNoLeidas() async {
    await cargar();
    return _cache.where((n) => !n.leida).length;
  }

  /// Marca una notificación como leída.
  Future<void> marcarLeida(String id) async {
    await cargar();
    final idx = _cache.indexWhere((n) => n.id == id);
    if (idx != -1) {
      _cache[idx].leida = true;
      await _guardar();
    }
  }

  /// Marca todas como leídas.
  Future<void> marcarTodasLeidas() async {
    await cargar();
    for (final n in _cache) {
      n.leida = true;
    }
    await _guardar();
  }

  /// Elimina una notificación por ID.
  Future<void> eliminar(String id) async {
    await cargar();
    _cache.removeWhere((n) => n.id == id);
    await _guardar();
  }

  /// Elimina todas las notificaciones.
  Future<void> eliminarTodas() async {
    _cache.clear();
    await _guardar();
  }
}
