import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

class ApiService {
  // Autodetección del emulador / dispositivo:
  static String get baseUrl {
      return "https://trucktime-production.up.railway.app";
/*
    if (kIsWeb) {
      return "http://localhost/trucktime";
    } else if (Platform.isAndroid) {
      return "http://10.0.2.2/trucktime"; // Emulador Android
    } else {
      return "http://127.0.0.1/trucktime"; // Simulador iOS / macOS
    }*/
  }

  // Headers comunes para todas las peticiones JSON
  static const Map<String, String> _headers = {
    'Content-Type': 'application/json',
  };

  // Helper para manejar errores de conexión y no repetir código
  Map<String, dynamic> _errorConexion(Object e) {
    return {"status": "error", "message": "Error de conexión: $e"};
  }

  // --- LOGIN ---
  Future<Map<String, dynamic>> login(String email, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/usuarios/login'),
        headers: _headers,
        body: json.encode({'email': email, 'password': password}),
      );
      return json.decode(response.body);
    } catch (e) { return _errorConexion(e); }
  }

  // --- REGISTRO ---
  Future<Map<String, dynamic>> registro(String nombre, String apellidos, String email,
    String password,) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/usuarios/registro'),
        headers: _headers,
        body: json.encode({
          'nombre': nombre,
          'apellidos': apellidos,
          'email': email,
          'password': password,
        }),
      );
      return json.decode(response.body);
    } catch (e) { return _errorConexion(e); }
  }

  // --- ABRIR JORNADA ---
  Future<Map<String, dynamic>> abrirJornada(int idUsuario) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/jornadas/abrir'),
        headers: _headers,
        body: json.encode({'id_usuario': idUsuario}),
      );
      return json.decode(response.body);
    } catch (e) { return _errorConexion(e); }
  }

  // --- CERRAR JORNADA ---
  Future<Map<String, dynamic>> cerrarJornada(int idJornada) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/jornadas/cerrar/$idJornada'),
        headers: _headers,
      );
      return json.decode(response.body);
    } catch (e) { return _errorConexion(e); }
  }

  // --- JORNADA ACTIVA ---
  Future<Map<String, dynamic>> getJornadaActiva(int idUsuario) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/jornadas/activa/$idUsuario'),
        headers: _headers,
      );
      return json.decode(response.body);
    } catch (e) { return _errorConexion(e); }
  }

  // --- REGISTRAR ACTIVIDAD ---
  Future<Map<String, dynamic>> registrarActividad(int idJornada, String tipo, {
    double? latitud, double? longitud,}) async {
    try {
      final Map<String, dynamic> bodyData = {
        'id_jornada': idJornada,
        'tipo_actividad': tipo,
      };
      // Solo añadimos coordenadas si vienen informadas
      if (latitud != null) bodyData['latitud'] = latitud;
      if (longitud != null) bodyData['longitud'] = longitud;

      final response = await http.post(
        Uri.parse('$baseUrl/registros/iniciar'),
        headers: _headers,
        body: json.encode(bodyData),
      );
      return json.decode(response.body);
    } catch (e) { return _errorConexion(e); }
  }

  // --- MINUTOS DE CONDUCCIÓN (para el temporizador) ---
  Future<Map<String, dynamic>> getMinutosConduccion(int idJornada) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/registros/conduccion/$idJornada'),
        headers: _headers,
      );
      return json.decode(response.body);
    } catch (e) { return _errorConexion(e); }
  }

  // --- REGISTROS DE UNA JORNADA (para historial) ---
  Future<Map<String, dynamic>> getRegistrosJornada(int idJornada) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/registros/jornada/$idJornada'),
        headers: _headers,
      );
      return json.decode(response.body);
    } catch (e) { return _errorConexion(e); }
  }

  // --- RESUMEN SEMANAL Y MENSUAL REAL (basado en descanso largo CE 561/2006) ---
  Future<Map<String, dynamic>> getResumenConduccion(int idUsuario) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/jornadas/resumen/$idUsuario'),
        headers: _headers,
      );
      return json.decode(response.body);
    } catch (e) { return _errorConexion(e); }
  }

  // --- HISTORIAL DE JORNADAS ---
  Future<Map<String, dynamic>> getJornadasUsuario(int id) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/jornadas/usuario/$id'),
        headers: _headers,
      );
      return json.decode(response.body);
    } catch (e) { return _errorConexion(e); }
  }

  // --- COMPROBAR ALERTAS (llama a la normativa CE 561/2006) ---
  Future<Map<String, dynamic>> comprobarAlertas(int idJornada) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/alertas/comprobar'),
        headers: _headers,
        body: json.encode({'id_jornada': idJornada}),
      );
      return json.decode(response.body);
    } catch (e) { return _errorConexion(e); }
  }

  // --- ALERTAS NO LEÍDAS ---
  Future<Map<String, dynamic>> getAlertasNoLeidas(int idUsuario) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/alertas/noleidas/$idUsuario'),
        headers: _headers,
      );
      return json.decode(response.body);
    } catch (e) { return _errorConexion(e); }
  }

  // --- MARCAR ALERTA COMO LEÍDA ---
  Future<Map<String, dynamic>> marcarAlertaLeida(int idAlerta) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/alertas/leer/$idAlerta'),
        headers: _headers,
      );
      return json.decode(response.body);
    } catch (e) { return _errorConexion(e); }
  }

  // --- DESCANSO SEMANAL: marcar un registro como descanso semanal ---
  Future<Map<String, dynamic>> marcarDescansoSemanal(
    int idRegistro,
    int idUsuario,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/descanso-semanal/marcar'),
        headers: _headers,
        body: json.encode({'id_registro': idRegistro, 'id_usuario': idUsuario}),
      );
      return json.decode(response.body);
    } catch (e) { return _errorConexion(e); }
  }

  // --- DESCANSO SEMANAL: estado actual (días trabajados, compensaciones) ---
  Future<Map<String, dynamic>> getEstadoDescansoSemanal(int idUsuario) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/descanso-semanal/estado/$idUsuario'),
        headers: _headers,
      );
      return json.decode(response.body);
    } catch (e) { return _errorConexion(e); }
  }

  // --- DESCANSO SEMANAL: comprobar alertas al iniciar jornada ---
  Future<Map<String, dynamic>> comprobarAlertasSemanales(
    int idJornada,
    int idUsuario,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/descanso-semanal/comprobar'),
        headers: _headers,
        body: json.encode({'id_jornada': idJornada, 'id_usuario': idUsuario}),
      );
      return json.decode(response.body);
    } catch (e) { return _errorConexion(e); }
  }

  // --- DESCANSO SEMANAL: último descanso completado ---
  Future<Map<String, dynamic>> getUltimoDescansoSemanal(int idUsuario) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/descanso-semanal/ultimo/$idUsuario'),
        headers: _headers,
      );
      return json.decode(response.body);
    } catch (e) { return _errorConexion(e); }
  }
}
