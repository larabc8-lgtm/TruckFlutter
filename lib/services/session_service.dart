import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class SessionService {
  static const String _keyUsuario = 'usuario_sesion';

  static Future<void> guardarSesion(Map<String, dynamic> usuario) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUsuario, json.encode(usuario));
  }

  static Future<Map<String, dynamic>?> obtenerSesion() async {
    final prefs = await SharedPreferences.getInstance();
    final datos = prefs.getString(_keyUsuario);
    if (datos != null) {
      return json.decode(datos) as Map<String, dynamic>;
    }
    return null;
  }

  static Future<void> cerrarSesion() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyUsuario);
  }

  static Future<int?> obtenerIdUsuario() async {
    final sesion = await obtenerSesion();
    return sesion != null ? int.parse(sesion['id_usuario'].toString()) : null;
  }
}
