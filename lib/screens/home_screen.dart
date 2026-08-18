import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/session_service.dart';
import '../services/notificacion_service.dart';
import 'historial_screen.dart';
import 'descanso_semanal_widget.dart';
import 'notificaciones_screen.dart';
import '../services/notificacion_storage_service.dart';

class HomeScreen extends StatefulWidget {
  final Map<String, dynamic> userData;
  final int? jornadaActivaId;
  final VoidCallback onLogout;
  final VoidCallback onThemeToggle;
  const HomeScreen({
    required this.userData,
    this.jornadaActivaId,
    required this.onLogout,
    required this.onThemeToggle,
    super.key,
  });
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}
class _HomeScreenState extends State<HomeScreen> {
  final ApiService _api = ApiService();
  final NotificacionService _notif = NotificacionService();
  int? idJornada;
  String actividadActual = "Ninguna";
  bool cargando = false;
  bool _inicializado = false;
  Timer? _timer;
  DateTime? _inicioJornada;
  DateTime? _inicioActividad;
  int _segundosJornada = 0;
  int _segundosConduccionTotal = 0;
  int _segundosConduccionActiva = 0;
  int _segundosDescanso = 0;
  int _acumuladoConduccionActiva = 0;
  int _acumuladoConduccionTotal = 0;
  DateTime? _inicioConduccionActiva;
  // Tracking de pausas para descanso fraccionado
  bool _huboPausaReciente = false;
  String _tiempoJornada = "00:00:00";
  String _tiempoActividad = "00:00:00";
  String _tiempoConduccionTotal = "00:00:00";
  String _tiempoConduccionActiva = "00:00:00";
  String _tiempoDescanso = "00:00:00";
  // Info del descanso previo, se rellena al abrir jornada
  String? _tipoDescanso;
  int _descansosReducidos = 0;
  int _descansosRestantes = 3;
  // Alertas y notificaciones
  int _alertasNoLeidas = 0;
  // Tracking de alertas enviadas
  bool _alerta4hEnviada = false;
  bool _alerta4h15Enviada = false;
  bool _alerta4h30Enviada = false;
  int? _idUltimoRegistro;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
      const Duration(seconds: 1),
          (_) => _actualizarTiempos(),
    );
    _cargarJornadaActiva();
    _cargarAlertas();
  }

  void _cargarAlertas() async {
    final idUsuario = int.parse(widget.userData['id_usuario'].toString());
    var res = await _api.getAlertasNoLeidas(idUsuario);
    if (!mounted) return;
    
    if (res['status'] == 'success' && res['data'] != null && res['data']['alertas'] != null) {
      List<dynamic> backendAlertas = res['data']['alertas'] as List<dynamic>;
      for (var a in backendAlertas) {
        String tipo = 'info';
        String tipoAlertaStr = a['tipo_alerta']?.toString().toLowerCase() ?? '';
        if (tipoAlertaStr.contains('descanso') || tipoAlertaStr.contains('insuficiente') || tipoAlertaStr.contains('reducido')) {
          tipo = 'descanso';
        } else if (tipoAlertaStr.contains('semanal')) {
          tipo = 'semanal';
        } else if (tipoAlertaStr.contains('compensacion')) {
          tipo = 'info';
        }

        await NotificacionStorageService().agregar(
          titulo: 'Alerta: ${a['tipo_alerta']?.toString() ?? ''}',
          cuerpo: a['mensaje']?.toString() ?? '',
          tipo: tipo,
        );

        final idAlerta = a['id_alerta'] as int?;
        if (idAlerta != null) {
          await _api.marcarAlertaLeida(idAlerta);
        }
      }
    }
    _actualizarContadorNotificaciones();
  }

  Future<void> _actualizarContadorNotificaciones() async {
    int noLeidas = await NotificacionStorageService().contarNoLeidas();
    if (mounted) {
      setState(() {
        _alertasNoLeidas = noLeidas;
      });
    }
  }

  Future<void> _cargarJornadaActiva() async {
    if (widget.jornadaActivaId != null && !_inicializado) {
      setState(() => cargando = true);
      try {
        final idUsuario = int.parse(widget.userData['id_usuario'].toString());
        debugPrint('DEBUG: Cargando jornada activa para usuario $idUsuario');
        final res = await _api.getJornadaActiva(idUsuario).timeout(
          const Duration(seconds: 10),
          onTimeout: () => {"status": "error", "message": "Timeout"},
        );
        debugPrint('DEBUG: Respuesta getJornadaActiva: $res');
        if (!mounted) return;
        if (res['status'] == 'success' && res['data'] != null) {
          final datosJornada = res['data'];
          final jornId = datosJornada['id_jornada'] as int;

          final resResumen = await _api.getMinutosConduccion(jornId);

          setState(() {
            idJornada = jornId;
            _inicioJornada = DateTime.tryParse(
              datosJornada['fecha_inicio'] ?? '',
            );
            _inicioActividad = DateTime.now();

            if (resResumen['status'] == 'success' && resResumen['data'] != null) {
              final data = resResumen['data'];
              
              // Sincronizamos contadores con los valores procesados del backend
              _segundosConduccionActiva = (data['conduccion_activa'] ?? 0);
              _segundosConduccionTotal = (data['conduccion_total'] ?? 0);
              _huboPausaReciente = data['pausa_parte1_cumplida'] ?? false;
              
              _acumuladoConduccionActiva = _segundosConduccionActiva;
              _acumuladoConduccionTotal = _segundosConduccionTotal;

              // Sincronizar actividad actual y tiempos
              String backendActividad = (data['actividad_actual'] ?? "").toString().toLowerCase();
              int segundosEnActividad = (data['tiempo_actual'] ?? 0);

              if (backendActividad == "conduccion") {
                actividadActual = "CONDUCIR";
                _inicioConduccionActiva = DateTime.now();
              } else if (backendActividad == "pausa" || backendActividad == "descanso") {
                actividadActual = "PAUSA / DESCANSO";
                _segundosDescanso = segundosEnActividad;
                _inicioActividad = DateTime.now().subtract(Duration(seconds: segundosEnActividad));
              } else if (backendActividad == "otros_trabajos") {
                actividadActual = "OTROS TRABAJOS";
                _inicioActividad = DateTime.now().subtract(Duration(seconds: segundosEnActividad));
              } else {
                actividadActual = "Jornada Iniciada";
              }

              _tiempoConduccionActiva = _formatearSegundos(_segundosConduccionActiva);
              _tiempoConduccionTotal = _formatearSegundos(_segundosConduccionTotal);
            }

            _inicializado = true;
            cargando = false;
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("Jornada activa recuperada"),
                backgroundColor: Colors.blue,
              ),
            );
          }
        } else {
          debugPrint('DEBUG: No hay jornada activa o error');
          setState(() {
            _inicializado = true;
            cargando = false;
          });
        }
      } catch (e) {
        debugPrint('DEBUG: Error al cargar jornada activa: $e');
        if (mounted) {
          setState(() {
            _inicializado = true;
            cargando = false;
          });
        }
      }
    } else {
      _inicializado = true;
    }
  }
  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
  void _actualizarTiempos() {
    if (!mounted) return;
    final ahora = DateTime.now();
    setState(() {
      if (_inicioJornada != null) {
        _segundosJornada = ahora.difference(_inicioJornada!).inSeconds;
        _tiempoJornada = _formatearSegundos(_segundosJornada);
      }
      if (_inicioActividad != null) {
        _tiempoActividad = _formatearTiempo(
          ahora.difference(_inicioActividad!),
        );
      }
      if (actividadActual == "CONDUCIR") {
        if (_inicioConduccionActiva != null) {
          final diff = ahora.difference(_inicioConduccionActiva!).inSeconds;
          _segundosConduccionActiva = _acumuladoConduccionActiva + diff;
          _segundosConduccionTotal = _acumuladoConduccionTotal + diff;
        }
        _tiempoConduccionActiva = _formatearSegundos(_segundosConduccionActiva);
        _tiempoConduccionTotal = _formatearSegundos(_segundosConduccionTotal);
        _segundosDescanso = 0;
        _tiempoDescanso = "00:00:00";
      } else if (actividadActual == "PAUSA / DESCANSO") {
        if (_inicioConduccionActiva != null) {
          _acumuladoConduccionActiva = _segundosConduccionActiva;
          _acumuladoConduccionTotal = _segundosConduccionTotal;
          _inicioConduccionActiva = null;
        }
        _segundosDescanso++;
        _tiempoDescanso = _formatearSegundos(_segundosDescanso);
        if (_segundosDescanso >= 2670) {
          // Caso 1: Pausa única de 45 min
          _segundosConduccionActiva = 0;
          _acumuladoConduccionActiva = 0;
          _tiempoConduccionActiva = "00:00:00";
          _huboPausaReciente = false;
          debugPrint('RESET: Pausa 45min');
        } else if (_segundosDescanso >= 1770 && _huboPausaReciente) {
          // Caso 2: Segunda parte de pausa fraccionada (30 min habiendo hecho 15 previos)
          _segundosConduccionActiva = 0;
          _acumuladoConduccionActiva = 0;
          _tiempoConduccionActiva = "00:00:00";
          _huboPausaReciente = false;
          debugPrint('RESET: Pausa 30min con pausa previa');
        } else if (_segundosDescanso >= 870) {
          // Si llegamos a 15 min, marcamos que esta pausa sirve como primera fracción
          _huboPausaReciente = true;
          debugPrint('Pausa 15min, _huboPausaReciente=true');
        }
      } else if (actividadActual == "OTROS TRABAJOS") {
        if (_inicioConduccionActiva != null) {
          _acumuladoConduccionActiva = _segundosConduccionActiva;
          _acumuladoConduccionTotal = _segundosConduccionTotal;
          _inicioConduccionActiva = null;
        }
        _segundosDescanso = 0;
        _tiempoDescanso = "00:00:00";
      }
      // ALERTAS DE CONDUCCIÓN
      _checkAlertasConduccion();
    });
  }
  void _checkAlertasConduccion() {
    if (actividadActual != "CONDUCIR") return;
    final segundos = _segundosConduccionActiva;
    // 4h = 14400 seg
    if (segundos >= 14400 && !_alerta4hEnviada) {
      _alerta4hEnviada = true;
      _notif.mostrarNotificacion(
        id: 1,
        titulo: '⏰ TruckTime - Aviso de conducción',
        cuerpo: 'Has conducido 4 horas. En 30min debes hacer una pausa.',
      );
    }
    // 4h15 = 15300 seg
    if (segundos >= 15300 && !_alerta4h15Enviada) {
      _alerta4h15Enviada = true;
      _notif.mostrarNotificacion(
        id: 2,
        titulo: '⚠️ TruckTime - Descanso obligatorio',
        cuerpo: 'Debes hacer una pausa en 15min.',
      );
    }
    // 4h30 = 16200 seg
    if (segundos >= 16200 && !_alerta4h30Enviada) {
      _alerta4h30Enviada = true;
      _notif.mostrarNotificacion(
        id: 3,
        titulo: '🚛 TruckTime - FIN DE CONDUCCIÓN',
        cuerpo: 'Has conducido 4h30min. DEBES PARAR ahora.',
      );
    }
  }
  void _resetAlertasConduccion() {
    _alerta4hEnviada = false;
    _alerta4h15Enviada = false;
    _alerta4h30Enviada = false;
  }
  String _formatearTiempo(Duration duracion) {
    final horas = duracion.inHours.toString().padLeft(2, '0');
    final minutos = (duracion.inMinutes % 60).toString().padLeft(2, '0');
    final segundos = (duracion.inSeconds % 60).toString().padLeft(2, '0');
    return "$horas:$minutos:$segundos";
  }
  String _formatearSegundos(int segundos) {
    final horas = (segundos ~/ 3600).toString().padLeft(2, '0');
    final mins = ((segundos % 3600) ~/ 60).toString().padLeft(2, '0');
    final segs = (segundos % 60).toString().padLeft(2, '0');
    return "$horas:$mins:$segs";
  }
  Color _getColorActividad() {
    switch (actividadActual) {
      case "CONDUCIR":
        return Colors.blue;
      case "PAUSA / DESCANSO":
        return Colors.orange;
      case "OTROS TRABAJOS":
        return Colors.grey;
      default:
        return Theme.of(context).colorScheme.primary;
    }
  }
  Color _getColorConduccionActiva() {
    if (_segundosConduccionActiva >= 16200) return Colors.red;
    if (_segundosConduccionActiva >= 12600) return Colors.orange;
    if (_segundosConduccionActiva >= 10800) return Colors.amber;
    if (actividadActual == "PAUSA / DESCANSO") return Colors.grey;
    return Colors.blue;
  }
  Color _getColorDescanso() {
    if (_segundosDescanso >= 2670) return Colors.green;
    if (_segundosDescanso >= 870) return Colors.orange;
    return Colors.amber;
  }
  String _getMensajeDescanso() {
    if (_segundosDescanso >= 2670) {
      return "✅ ¡Descanso completado!\nPuedes conducir 4h30min más";
    } else if (_segundosDescanso >= 870) {
      final faltan = 2670 - _segundosDescanso;
      final mins = faltan ~/ 60;
      return "✅ Primera fracción: 15min ✅\n⚠️ Faltan ${mins}min para descanso válido";
    } else {
      final mins = _segundosDescanso ~/ 60;
      final segs = _segundosDescanso % 60;
      return "⚠️ Descanso: ${mins}min ${segs}seg\n⚠️ Mínimo 15min para que cuente";
    }
  }
  void _iniciarJornada() async {
    setState(() => cargando = true);
    int userId = int.parse(widget.userData['id_usuario'].toString());
    var res = await _api.abrirJornada(userId);
    if (!mounted) return;
    final data = res['data'] as Map<String, dynamic>?;

    if (res['status'] == 'success' && data != null) {
      setState(() {
        idJornada = data['id_jornada'];
        actividadActual = "Jornada Iniciada";
        _inicioJornada = DateTime.now();
        _inicioActividad = DateTime.now();
        _reiniciarContadores();
        // Guardar info del descanso previo
        final descanso = data['descanso'] as Map<String, dynamic>?;
        _tipoDescanso = descanso?['tipo'];
        _descansosReducidos =
            int.tryParse(descanso?['reducidos_semana'].toString() ?? '0') ?? 0;
        _descansosRestantes =
            int.tryParse(descanso?['reducidos_restantes'].toString() ?? '3') ??
                3;
      });
      // Mostrar alertas generadas al abrir
      final alertas = data['alertas_generadas'] as List<dynamic>? ?? [];
      if (alertas.isNotEmpty) {
        _mostrarAlertasDescanso(alertas, data['descanso']);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Jornada iniciada. ID: $idJornada"),
            backgroundColor: Colors.green,
          ),
        );
      }
      setState(() => cargando = false);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error: ${res['message']}"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
  // Diálogo con las alertas de descanso al abrir jornada
  void _mostrarAlertasDescanso(
      List<dynamic> alertas,
      Map<String, dynamic>? descanso,
      ) {
    final tipo = descanso?['tipo'] ?? '';
    Color color;
    IconData icono;
    String titulo;
    if (tipo == 'insuficiente') {
      color = Colors.red;
      icono = Icons.warning_rounded;
      titulo = '¡Descanso insuficiente!';
    } else if (tipo == 'reducido') {
      color = Colors.orange;
      icono = Icons.info_rounded;
      titulo = 'Descanso reducido usado';
    } else {
      color = Colors.orange;
      icono = Icons.info_rounded;
      titulo = 'Aviso de descanso';
    }
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        icon: Icon(icono, color: color, size: 48),
        title: Text(titulo, style: TextStyle(color: color)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Mensaje según tipo
            if (tipo == 'insuficiente')
              const Text(
                'El descanso antes de esta jornada fue inferior a 9 horas. '
                    'Esto incumple el Reglamento CE 561/2006.',
              ),
            if (tipo == 'reducido') ...[
              Text(
                'Has utilizado ${descanso?['reducidos_semana']} de 3 descansos '
                    'reducidos permitidos esta semana.',
              ),
              const SizedBox(height: 8),
              // Indicador visual de descansos reducidos usados
              Row(
                children: List.generate(3, (i) {
                  final usado = i < _descansosReducidos;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Icon(
                      usado ? Icons.circle : Icons.circle_outlined,
                      color: usado ? Colors.orange : Colors.grey,
                      size: 20,
                    ),
                  );
                }),
              ),
              const SizedBox(height: 8),
              Text(
                'Te quedan $_descansosRestantes descansos reducidos esta semana.',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: _descansosRestantes == 0 ? Colors.red : Colors.orange,
                ),
              ),
            ],
            if (tipo == 'fraccionado')
              const Text(
                'Tu descanso fue fraccionado (3h + 9h). '
                    'Recuerda completar siempre ambos bloques.',
              ),
            if (_descansosRestantes == 0) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: const Text(
                  '⚠️ Has agotado los 3 descansos reducidos. '
                      'Todos los descansos hasta el próximo descanso semanal '
                      'deben ser de mínimo 11 horas.',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("ENTENDIDO"),
          ),
        ],
      ),
    );
  }
  void _reiniciarContadores() {
    _segundosJornada = 0;
    _segundosConduccionTotal = 0;
    _segundosConduccionActiva = 0;
    _segundosDescanso = 0;
    _acumuladoConduccionActiva = 0;
    _acumuladoConduccionTotal = 0;
    _inicioConduccionActiva = null;
    _tiempoJornada = "00:00:00";
    _tiempoConduccionTotal = "00:00:00";
    _tiempoConduccionActiva = "00:00:00";
    _tiempoDescanso = "00:00:00";
    _huboPausaReciente = false;
    _resetAlertasConduccion();
  }
  void _registrarActividad(String texto, String tipo, Color color) async {
    final antiguaActividad = actividadActual;
    final antiguoInicio = _inicioActividad;
    final antiguoInicioConduccion = _inicioConduccionActiva;

    setState(() {
      actividadActual = texto;
      _inicioActividad = DateTime.now();
      if (tipo == "conduccion") {
        _inicioConduccionActiva = DateTime.now();
      }
      cargando = true;
    });

    var res = await _api.registrarActividad(idJornada!, tipo);

    if (!mounted) return;
    setState(() => cargando = false);

    if (res['status'] == 'success') {
      final resResumen = await _api.getMinutosConduccion(idJornada!);
      if (resResumen['status'] == 'success' && resResumen['data'] != null) {
        final data = resResumen['data'];
        setState(() {
          _segundosConduccionActiva = (data['conduccion_activa'] ?? 0);
          _segundosConduccionTotal = (data['conduccion_total'] ?? 0);
          _huboPausaReciente = data['pausa_parte1_cumplida'] ?? false;
          
          _acumuladoConduccionActiva = _segundosConduccionActiva;
          _acumuladoConduccionTotal = _segundosConduccionTotal;
          
          _tiempoConduccionActiva = _formatearSegundos(_segundosConduccionActiva);
          _tiempoConduccionTotal = _formatearSegundos(_segundosConduccionTotal);
        });
      }

      setState(() {
        if (tipo == 'pausa' || tipo == 'descanso') {
          _resetAlertasConduccion();
          _segundosDescanso = 0;
        }

        if (tipo == "conduccion") {
          _inicioConduccionActiva = DateTime.now();
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Iniciando: $texto"), backgroundColor: color),
      );
    } else {
      setState(() {
        actividadActual = antiguaActividad;
        _inicioActividad = antiguoInicio;
        _inicioConduccionActiva = antiguoInicioConduccion;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error: ${res['message']}"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
  void _confirmarCierreJornada() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("¿Terminar jornada?"),
        content: const Text(
          "Se registrará la duración total y la hora de fin.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("CANCELAR"),
          ),
          TextButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              Navigator.pop(context);
              setState(() => cargando = true);
              var res = await _api.cerrarJornada(idJornada!);
              if (!mounted) return;
              setState(() => cargando = false);

              if (res['status'] == 'success') {
                setState(() {
                  idJornada = null;
                  actividadActual = "Ninguna";
                  _inicioJornada = null;
                  _inicioActividad = null;
                  _inicioConduccionActiva = null;
                  _tipoDescanso = null;
                  _descansosReducidos = 0;
                  _descansosRestantes = 3;
                  _reiniciarContadores();
                });
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text("¡Jornada finalizada!"),
                    backgroundColor: Colors.green,
                  ),
                );
              } else {
                messenger.showSnackBar(
                  SnackBar(
                    content: Text("Error: ${res['message']}"),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text(
              "SÍ, FINALIZAR",
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }
  void _confirmarLogout() {
    if (idJornada != null) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("¡Jornada activa!"),
          content: const Text("Cierra la jornada antes de salir."),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("ENTENDIDO"),
            ),
          ],
        ),
      );
      return;
    }
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("¿Cerrar sesión?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("CANCELAR"),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              SessionService.cerrarSesion();
              widget.onLogout();
            },
            child: const Text("SÍ, CERRAR"),
          ),
        ],
      ),
    );
  }
  void _mostrarAlertas() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const NotificacionesScreen()),
    );
    _actualizarContadorNotificaciones();
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("¡Hola, ${widget.userData['nombre']}!"),
        actions: [
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_outlined),
                onPressed: () => _mostrarAlertas(),
              ),
              if (_alertasNoLeidas > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 18,
                      minHeight: 18,
                    ),
                    child: Text(
                      '$_alertasNoLeidas',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          IconButton(
            icon: Icon(
              Theme.of(context).brightness == Brightness.dark
                  ? Icons.light_mode
                  : Icons.dark_mode,
            ),
            onPressed: widget.onThemeToggle,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _confirmarLogout,
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              if (idJornada != null) ...[
                _buildActividadCard(),
                const SizedBox(height: 15),
                if (actividadActual == "PAUSA / DESCANSO") ...[
                  _buildDescansoCard(),
                  const SizedBox(height: 15),
                ],
                _buildConduccionActivaCard(),
                const SizedBox(height: 15),
                _buildTiemposCard(),
                const SizedBox(height: 25),
                _buildBotones(),
                const Spacer(),
                _buildFinalizarButton(),
              ] else ...[
                _buildSinJornadaCard(),
              ],
              if (cargando)
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: LinearProgressIndicator(),
                ),
            ],
          ),
        ),
      ),
    );
  }
  Widget _buildActividadCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
      decoration: BoxDecoration(
        color: _getColorActividad().withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _getColorActividad(), width: 2),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(_getIconoActividad(), color: _getColorActividad(), size: 28),
              const SizedBox(width: 10),
              Text(
                actividadActual.toUpperCase(),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: _getColorActividad(),
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _tiempoActividad,
            style: TextStyle(
              fontSize: 56,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
              color: _getColorActividad(),
            ),
          ),
        ],
      ),
    );
  }
  Widget _buildDescansoCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: _getColorDescanso().withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: _getColorDescanso(), width: 2),
      ),
      child: Column(
        children: [
          Icon(Icons.timer, color: _getColorDescanso(), size: 24),
          const SizedBox(height: 8),
          Text(
            "Descanso: $_tiempoDescanso",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
              color: _getColorDescanso(),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _getMensajeDescanso(),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: _getColorDescanso()),
          ),
        ],
      ),
    );
  }
  Widget _buildConduccionActivaCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Conducción activa",
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              Text(
                _tiempoConduccionActiva,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                  color: _getColorConduccionActiva(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(
              value: (_segundosConduccionActiva / 16200).clamp(0.0, 1.0),
              backgroundColor: Colors.grey.shade300,
              valueColor: AlwaysStoppedAnimation<Color>(
                _getColorConduccionActiva(),
              ),
              minHeight: 12,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            actividadActual == "PAUSA / DESCANSO"
                ? "Pausada"
                : "Límite: 04:30:00",
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
  Widget _buildTiemposCard() {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _tiempoItem(Icons.schedule, "Jornada", _tiempoJornada, Colors.grey),
          Container(width: 1, height: 40, color: Colors.grey.shade300),
          _tiempoItem(
            Icons.timer,
            "Conducción total",
            _tiempoConduccionTotal,
            Colors.blue,
          ),
        ],
      ),
    );
  }
  Widget _buildBotones() {
    return Row(
      children: [
        Expanded(
          child: _botonActividad(
            "CONDUCIR",
            Colors.blue,
            Icons.local_shipping,
            "conduccion",
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _botonActividad("PAUSA", Colors.orange, Icons.coffee, "pausa"),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _botonActividad(
            "OTROS",
            Colors.grey,
            Icons.build,
            "otros_trabajos",
          ),
        ),
      ],
    );
  }
  Widget _buildFinalizarButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: cargando ? null : _confirmarCierreJornada,
        icon: const Icon(Icons.stop_circle),
        label: const Text("FINALIZAR JORNADA"),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.red.shade100,
          foregroundColor: Colors.red,
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    );
  }
  Widget _buildSinJornadaCard() {
    return Expanded(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 20),

            const SizedBox(height: 40),
            Icon(
              Icons.play_circle_outline,
              size: 80,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 10),
            Text(
              "Sin jornada activa",
              style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 30),
            // Botón Iniciar
            ElevatedButton.icon(
              onPressed: cargando ? null : _iniciarJornada,
              icon: const Icon(Icons.play_arrow),
              label: const Text("INICIAR JORNADA"),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 60), // Botón más ancho
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              ),
            ),
            const SizedBox(height: 15),
            // Botón Historial
            ElevatedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => HistorialScreen(
                    idUsuario: int.parse(widget.userData['id_usuario'].toString()),
                  ),
                ),
              ),
              icon: const Icon(Icons.history),
              label: const Text("VER HISTORIAL"),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 60),
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
  IconData _getIconoActividad() {
    switch (actividadActual) {
      case "CONDUCIR":
        return Icons.local_shipping;
      case "PAUSA / DESCANSO":
        return Icons.coffee;
      case "OTROS TRABAJOS":
        return Icons.build;
      default:
        return Icons.play_arrow;
    }
  }
  Widget _tiempoItem(IconData icono, String label, String tiempo, Color color) {
    return Column(
      children: [
        Icon(icono, size: 20, color: color),
        const SizedBox(height: 5),
        Text(
          tiempo,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
      ],
    );
  }
  Widget _botonActividad(
      String texto,
      Color color,
      IconData icono,
      String tipo,
      ) {
    bool esActivo = actividadActual == texto;
    return SizedBox(
      height: 70,
      child: ElevatedButton(
        onPressed: (esActivo || cargando || idJornada == null)
            ? null
            : () => _registrarActividad(texto, tipo, color),
        style: ElevatedButton.styleFrom(
          backgroundColor: esActivo ? color : color.withValues(alpha: 0.8),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          elevation: esActivo ? 0 : 4,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icono, size: 24),
            const SizedBox(height: 4),
            Text(
              texto,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
  // --- INDICADOR DE DESCANSOS REDUCIDOS ---
  Widget _indicadorDescansos() {
    if (_tipoDescanso == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: _descansosRestantes == 0
            ? Colors.red.shade50
            : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _descansosRestantes == 0
              ? Colors.red.shade200
              : Colors.orange.shade200,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.hotel,
            size: 16,
            color: _descansosRestantes == 0 ? Colors.red : Colors.orange,
          ),
          const SizedBox(width: 8),
          Text(
            'Descansos reducidos: $_descansosReducidos/3',
            style: TextStyle(
              fontSize: 13,
              color: _descansosRestantes == 0 ? Colors.red : Colors.orange,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 8),
          Row(
            children: List.generate(3, (i) {
              return Icon(
                i < _descansosReducidos ? Icons.circle : Icons.circle_outlined,
                size: 10,
                color: _descansosRestantes == 0 ? Colors.red : Colors.orange,
              );
            }),
          ),
        ],
      ),
    );
  }
}
