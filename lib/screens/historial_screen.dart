import 'package:flutter/material.dart';
import '../services/api_service.dart';

class HistorialScreen extends StatefulWidget {
  final int idUsuario;
  const HistorialScreen({required this.idUsuario, super.key});

  @override
  State<HistorialScreen> createState() => _HistorialScreenState();
}

class _HistorialScreenState extends State<HistorialScreen>
    with SingleTickerProviderStateMixin {
  final ApiService _api = ApiService();
  late TabController _tabController;

  List<dynamic> _jornadas = [];
  final Map<int, List<dynamic>> _registrosPorJornada = {};
  bool _cargando = true;
  final Map<int, bool> _cargandoRegistrosJornada = {}; // NUEVO: para trackear carga individual
  final Map<String, bool> _expandido = {};

  int _mesSeleccionado = DateTime.now().month;
  int _anioSeleccionado = DateTime.now().year;

  // Semana seleccionada (offset desde la semana actual)
  int _semanaOffset = 0;

  Map<String, dynamic>? _ultimoDescansoSemanal;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _cargarJornadas();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _cargarJornadas() async {
    if (!mounted) return;
    setState(() => _cargando = true);

    try {
      var res = await _api.getJornadasUsuario(widget.idUsuario);
      if (!mounted) return;

      if (res['status'] == 'success') {
        List<dynamic> jornadas = res['data'] as List<dynamic>;

        // SINCRONIZACIÓN JORNADA ACTIVA:
        // Si la más reciente está abierta, obtenemos datos reales
        if (jornadas.isNotEmpty && jornadas.first['estado'] == 'activa') {
          final idJornada = jornadas.first['id_jornada'] as int;
          final resResumen = await _api.getMinutosConduccion(idJornada);
          if (resResumen['status'] == 'success' && resResumen['data'] != null) {
            final data = resResumen['data'];
            // Sobreescribimos los campos del historial con el cálculo real
            jornadas.first['duracion_conduccion_total'] = data['conduccion_total'];
            jornadas.first['duracion_descanso_total']   = 0; // Se calcula al cerrar
            // La duración de la jornada ya se calcula con COALESCE(NOW()) en el backend
          }
        }

        var dsRes = await _api.getUltimoDescansoSemanal(widget.idUsuario);
        Map<String, dynamic>? ultimoDS;
        if (dsRes['status'] == 'success' && dsRes['data'] != null) {
          ultimoDS = dsRes['data'] as Map<String, dynamic>;
        }

        setState(() {
          _jornadas = jornadas;
          _ultimoDescansoSemanal = ultimoDS;
          _cargando = false;
        });
      } else {
        setState(() => _cargando = false);
      }
    } catch (e) {
      debugPrint("Error cargando historial: $e");
      if (mounted) setState(() => _cargando = false);
    }
  }

  // NUEVO MÉTODO: Carga los registros de una jornada solo cuando se necesita
  Future<void> _cargarDetalleJornada(int idJornada) async {
    // Si ya los tenemos o se están cargando, no hacemos nada
    if (_registrosPorJornada.containsKey(idJornada) || 
        (_cargandoRegistrosJornada[idJornada] ?? false)) {
      return;
    }

    setState(() => _cargandoRegistrosJornada[idJornada] = true);

    try {
      var res = await _api.getRegistrosJornada(idJornada);
      if (mounted && res['status'] == 'success') {
        setState(() {
          _registrosPorJornada[idJornada] = res['data'] as List<dynamic>;
          _cargandoRegistrosJornada[idJornada] = false;
        });
      } else if (mounted) {
        setState(() => _cargandoRegistrosJornada[idJornada] = false);
      }
    } catch (e) {
      if (mounted) setState(() => _cargandoRegistrosJornada[idJornada] = false);
    }
  }

  String _formatear(int minutos) {
    final h = minutos ~/ 60;
    final m = minutos % 60;
    return '${h}h ${m}min';
  }

  String _formatearCorto(int minutos) {
    final h = minutos ~/ 60;
    final m = minutos % 60;
    if (h > 0) {
      return '${h}h ${m}m';
    }
    return '${m}min';
  }

  String _horaTexto(DateTime? dt) {
    if (dt == null) return '--:--';
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _nombreDia(int weekday) {
    if (weekday < 1 || weekday > 7) return '';
    const dias = [
      'Lunes',
      'Martes',
      'Miércoles',
      'Jueves',
      'Viernes',
      'Sábado',
      'Domingo',
    ];
    return dias[weekday - 1];
  }

  String _nombreMes(int month) {
    if (month < 1 || month > 12) return '';
    const meses = [
      'Enero',
      'Febrero',
      'Marzo',
      'Abril',
      'Mayo',
      'Junio',
      'Julio',
      'Agosto',
      'Septiembre',
      'Octubre',
      'Noviembre',
      'Diciembre',
    ];
    return meses[month - 1];
  }

  String _tipoDescansoTexto(String tipo) {
    switch (tipo) {
      case 'normal':
        return '11h (normal)';
      case 'reducido':
        return '9h (reducido)';
      case 'fraccionado':
        return '3+9h';
      case 'insuficiente':
        return '<9h';
      default:
        return '-';
    }
  }

  Color _tipoDescansoColor(String tipo) {
    switch (tipo) {
      case 'normal':
        return Colors.green;
      case 'reducido':
        return Colors.orange;
      case 'fraccionado':
        return Colors.blue;
      case 'insuficiente':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData _iconoActividad(String tipo) {
    switch (tipo) {
      case 'conduccion':
        return Icons.directions_car;
      case 'pausa':
        return Icons.coffee;
      case 'descanso':
        return Icons.hotel;
      case 'disponibilidad':
        return Icons.accessibility;
      case 'otros_trabajos':
        return Icons.build;
      default:
        return Icons.timer;
    }
  }

  List<dynamic> _jornadasHoy() {
    final hoy = DateTime.now();
    return _jornadas.where((j) {
      final f = DateTime.tryParse(j['fecha_inicio'] ?? '');
      return f != null &&
          f.year == hoy.year &&
          f.month == hoy.month &&
          f.day == hoy.day;
    }).toList();
  }

  List<dynamic> _jornadasSemana() {
    final now = DateTime.now();
    final diaSemana = now.weekday;
    final inicioSemana = now.subtract(Duration(days: diaSemana - 1));
    final finSemana = inicioSemana.add(const Duration(days: 6));
    return _jornadas.where((j) {
      final f = DateTime.tryParse(j['fecha_inicio'] ?? '');
      return f != null && !f.isBefore(inicioSemana) && !f.isAfter(finSemana);
    }).toList();
  }

  List<dynamic> _jornadasMes(int mes, int anio) {
    return _jornadas.where((j) {
      final f = DateTime.tryParse(j['fecha_inicio'] ?? '');
      return f != null && f.year == anio && f.month == mes;
    }).toList();
  }

  Map<int, List<dynamic>> _jornadasPorDia(List<dynamic> jornadas) {
    final Map<int, List<dynamic>> dias = {};
    for (var j in jornadas) {
      final f = DateTime.tryParse(j['fecha_inicio'] ?? '');
      if (f == null) continue;
      dias.putIfAbsent(f.day, () => []);
      dias[f.day]!.add(j);
    }
    return Map.fromEntries(
      dias.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
  }

  List<MapEntry<int, List<dynamic>>> _diasSemanaActual() {
    final now = DateTime.now();
    final diaSemana = now.weekday;
    final inicioSemana = now.subtract(Duration(days: diaSemana - 1));
    final List<MapEntry<int, List<dynamic>>> dias = [];

    for (int i = 0; i < 7; i++) {
      final dia = inicioSemana.add(Duration(days: i));
      final jornadasDia = _jornadas.where((j) {
        final f = DateTime.tryParse(j['fecha_inicio'] ?? '');
        return f != null &&
            f.year == dia.year &&
            f.month == dia.month &&
            f.day == dia.day;
      }).toList();
      dias.add(MapEntry(dia.day, jornadasDia));
    }
    return dias;
  }

  Widget _diaExpandible(
    int dia,
    List<dynamic> jornadas,
    DateTime fecha, {
    String? descansoDelSiguiente,
  }) {
    final key = '${fecha.year}-${fecha.month}-$dia';
    final estaExpandido = _expandido[key] ?? false;
    final tieneDatos = jornadas.isNotEmpty;

    final totalConduccion = jornadas.fold<int>(
      0,
      (sum, j) =>
          sum + (int.tryParse(j['duracion_conduccion_total'].toString()) ?? 0),
    );
    final totalJornada = jornadas.fold<int>(
      0,
      (sum, j) =>
          sum +
          (int.tryParse(j['duracion_jornada_total']?.toString() ?? '0') ?? 0),
    );

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: tieneDatos ? 2 : 1,
      child: Column(
        children: [
          InkWell(
            onTap: tieneDatos
                ? () {
                    setState(() => _expandido[key] = !estaExpandido);
                    if (!estaExpandido) {
                      // Al expandir, cargamos el detalle de todas las jornadas de ese día
                      for (var j in jornadas) {
                        _cargarDetalleJornada(j['id_jornada'] as int);
                      }
                    }
                  }
                : null,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      if (!tieneDatos)
                        Icon(
                          Icons.circle_outlined,
                          size: 10,
                          color: Colors.grey.shade400,
                        )
                      else
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                          ),
                        ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _nombreDia(fecha.weekday),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: tieneDatos
                                    ? Colors.black87
                                    : Colors.grey,
                              ),
                            ),
                            if (!tieneDatos)
                              Text(
                                'Sin actividad',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (tieneDatos) ...[
                        _miniDato(
                          Icons.directions_car,
                          _formatearCorto(totalConduccion),
                          Colors.blue,
                        ),
                        const SizedBox(width: 12),
                        _miniDato(
                          Icons.timer,
                          _formatearCorto(totalJornada),
                          Colors.teal,
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          estaExpandido ? Icons.expand_less : Icons.expand_more,
                          color: Colors.grey.shade400,
                        ),
                      ],
                    ],
                  ),
                  // Mostrar descanso del día siguiente (que pertenece a este día)
                  if (descansoDelSiguiente != null &&
                      descansoDelSiguiente.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _tipoDescansoColor(
                          descansoDelSiguiente,
                        ).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.bedtime,
                            size: 14,
                            color: _tipoDescansoColor(descansoDelSiguiente),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Descanso: ${_tipoDescansoTexto(descansoDelSiguiente)}',
                            style: TextStyle(
                              fontSize: 11,
                              color: _tipoDescansoColor(descansoDelSiguiente),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (estaExpandido && tieneDatos)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                children: [
                  const Divider(),
                  for (var j in jornadas) _detalleJornada(j),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _detalleJornada(Map<String, dynamic> jornada) {
    final idJornada = jornada['id_jornada'] as int;
    final esActiva = jornada['estado'] == 'activa';
    
    // Si se está cargando el detalle
    if (_cargandoRegistrosJornada[idJornada] ?? false) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(
          child: Column(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(height: 8),
              Text('Cargando registros...', style: TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    final inicio = DateTime.tryParse(jornada['fecha_inicio'] ?? '');
    final fin = jornada['fecha_fin'] != null
        ? DateTime.tryParse(jornada['fecha_fin'])
        : null;
    final registros = _registrosPorJornada[jornada['id_jornada']] ?? [];

    final totalConduccion =
        int.tryParse(jornada['duracion_conduccion_total'].toString()) ?? 0;
    final totalPausas =
        int.tryParse(jornada['duracion_descanso_total'].toString()) ?? 0;
    final totalJornada =
        int.tryParse(jornada['duracion_jornada_total']?.toString() ?? '0') ?? 0;

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.play_arrow, size: 16, color: Colors.green),
              const SizedBox(width: 4),
              Text(
                'INICIO: ${_horaTexto(inicio)}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...registros.map((r) {
            final ini = DateTime.tryParse(r['hora_inicio'] ?? '');
            final finR = r['hora_fin'] != null
                ? DateTime.tryParse(r['hora_fin'])
                : null;
            final tipo = r['tipo_actividad']?.toString() ?? '';
            final duracion =
                int.tryParse(r['duracion_minutos'].toString()) ?? 0;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Icon(
                    _iconoActividad(tipo),
                    size: 16,
                    color: _colorActividad(tipo),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${_horaTexto(ini)} → ${finR != null ? _horaTexto(finR) : 'ahora'}',
                    style: const TextStyle(fontSize: 11),
                  ),
                  const Spacer(),
                  Text(
                    _formatearCorto(duracion),
                    style: TextStyle(
                      fontSize: 11,
                      color: _colorActividad(tipo),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            );
          }),
          if (fin != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.stop, size: 16, color: Colors.red),
                const SizedBox(width: 4),
                Text(
                  'FIN: ${_horaTexto(fin)}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
          const Divider(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _datoDetalle(
                Icons.directions_car,
                'Conducción',
                _formatear(totalConduccion),
                Colors.blue,
              ),
              _datoDetalle(
                Icons.coffee,
                'Pausas',
                _formatear(totalPausas),
                Colors.orange,
              ),
              _datoDetalle(
                Icons.timer,
                'Jornada',
                _formatear(totalJornada),
                Colors.teal,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _colorActividad(String tipo) {
    switch (tipo) {
      case 'conduccion':
        return Colors.blue;
      case 'pausa':
        return Colors.orange;
      case 'descanso':
        return Colors.purple;
      case 'disponibilidad':
        return Colors.teal;
      case 'otros_trabajos':
        return Colors.grey;
      default:
        return Colors.black54;
    }
  }

  Widget _miniDato(IconData icono, String valor, Color color) {
    return Row(
      children: [
        Icon(icono, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          valor,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _datoDetalle(IconData icono, String label, String valor, Color color) {
    return Column(
      children: [
        Icon(icono, size: 18, color: color),
        const SizedBox(height: 2),
        Text(
          valor,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
        ),
      ],
    );
  }

  Widget _listaHoy() {
    final jornadas = _jornadasHoy();
    final hoy = DateTime.now();
    final key = 'hoy-${hoy.year}-${hoy.month}-${hoy.day}';
    final estaExpandido = _expandido[key] ?? false;

    return ListView(
      children: [
        Card(
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 4,
          child: Column(
            children: [
              InkWell(
                onTap: jornadas.isNotEmpty
                    ? () {
                        setState(() => _expandido[key] = !estaExpandido);
                        if (!estaExpandido) {
                          for (var j in jornadas) {
                            _cargarDetalleJornada(j['id_jornada'] as int);
                          }
                        }
                      }
                    : null,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_nombreDia(hoy.weekday)}, ${hoy.day} de ${_nombreMes(hoy.month)} de ${hoy.year}',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (jornadas.isEmpty)
                              Text(
                                'Sin actividad',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (jornadas.isNotEmpty) ...[
                        _miniDato(
                          Icons.directions_car,
                          _formatearCorto(
                            jornadas.fold<int>(
                              0,
                              (sum, j) =>
                                  sum +
                                  (int.tryParse(
                                        j['duracion_conduccion_total']
                                            .toString(),
                                      ) ??
                                      0),
                            ),
                          ),
                          Colors.blue,
                        ),
                        const SizedBox(width: 12),
                        _miniDato(
                          Icons.timer,
                          _formatearCorto(
                            jornadas.fold<int>(
                              0,
                              (sum, j) =>
                                  sum +
                                  (int.tryParse(
                                        j['duracion_jornada_total']
                                                ?.toString() ??
                                            '0',
                                      ) ??
                                      0),
                            ),
                          ),
                          Colors.teal,
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          estaExpandido ? Icons.expand_less : Icons.expand_more,
                          color: Colors.grey.shade400,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (estaExpandido && jornadas.isNotEmpty)
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: Column(
                    children: [
                      const Divider(),
                      for (var j in jornadas) _detalleJornada(j),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _listaSemana() {
    final now = DateTime.now();
    final inicioSemanaActual = now.subtract(Duration(days: now.weekday - 1));
    final inicioSemana = inicioSemanaActual.add(
      Duration(days: _semanaOffset * 7),
    );
    final finSemana = inicioSemana.add(const Duration(days: 6));

    final dias = _diasSemana(inicioSemana);

    final totalConduccionSemana = dias.fold<int>(0, (sum, entry) {
      return sum +
          entry.value.fold<int>(
            0,
            (s, j) =>
                s +
                (int.tryParse(j['duracion_conduccion_total'].toString()) ?? 0),
          );
    });
    final diasTrabajados = dias.where((d) => d.value.isNotEmpty).length;

    return ListView(
      children: [
        _resumenSemana(totalConduccionSemana, diasTrabajados, inicioSemana),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () => setState(() => _semanaOffset--),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Semana del ${inicioSemana.day} al ${finSemana.day} de ${_nombreMes(inicioSemana.month)}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: _semanaOffset < 0
                    ? () => setState(() => _semanaOffset++)
                    : null,
              ),
            ],
          ),
        ),
        for (int i = 0; i < dias.length; i++)
          _diaExpandible(
            dias[i].key,
            dias[i].value,
            inicioSemana.add(Duration(days: i)),
            descansoDelSiguiente: i < dias.length - 1
                ? _getDescansoDelDia(inicioSemana.add(Duration(days: i + 1)))
                : null,
          ),
        const SizedBox(height: 20),
      ],
    );
  }

  String? _getDescansoDelDia(DateTime dia) {
    final jornadasDia = _jornadas.where((j) {
      final f = DateTime.tryParse(j['fecha_inicio'] ?? '');
      return f != null &&
          f.year == dia.year &&
          f.month == dia.month &&
          f.day == dia.day;
    }).toList();
    if (jornadasDia.isNotEmpty) {
      return jornadasDia.first['tipo_descanso']?.toString();
    }
    return null;
  }

  List<MapEntry<int, List<dynamic>>> _diasSemana(DateTime inicioSemana) {
    final List<MapEntry<int, List<dynamic>>> dias = [];
    for (int i = 0; i < 7; i++) {
      final dia = inicioSemana.add(Duration(days: i));
      final jornadasDia = _jornadas.where((j) {
        final f = DateTime.tryParse(j['fecha_inicio'] ?? '');
        return f != null &&
            f.year == dia.year &&
            f.month == dia.month &&
            f.day == dia.day;
      }).toList();
      dias.add(MapEntry(dia.day, jornadasDia));
    }
    return dias;
  }

  Widget _resumenSemana(
    int conduccionTotal,
    int diasTrabajados,
    DateTime inicioSemana,
  ) {
    final duracion = _ultimoDescansoSemanal != null
        ? int.tryParse(
                _ultimoDescansoSemanal!['duracion_minutos'].toString(),
              ) ??
              0
        : 0;
    final inicioDS = _ultimoDescansoSemanal != null
        ? DateTime.tryParse(_ultimoDescansoSemanal!['hora_inicio'] ?? '')
        : null;
    final finDS = _ultimoDescansoSemanal != null
        ? DateTime.tryParse(_ultimoDescansoSemanal!['hora_fin'] ?? '')
        : null;

    String estadoDescanso;
    Color colorEstado;
    IconData iconoEstado;

    if (duracion >= 2700) {
      estadoDescanso = '✓ Descanso completado (${_formatear(duracion)})';
      colorEstado = Colors.green;
      iconoEstado = Icons.check_circle;
    } else if (duracion > 0) {
      estadoDescanso = '⚠️ Descanso incompleto (${_formatear(duracion)})';
      colorEstado = Colors.orange;
      iconoEstado = Icons.warning;
    } else {
      estadoDescanso = '⏳ Pendiente: Debe descansar 45h';
      colorEstado = Colors.grey;
      iconoEstado = Icons.schedule;
    }

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _datoDetalle(
                Icons.directions_car,
                'Conducción',
                _formatear(conduccionTotal),
                Colors.blue,
              ),
              _datoDetalle(
                Icons.calendar_today,
                'Días trabajados',
                '$diasTrabajados',
                Colors.teal,
              ),
            ],
          ),
          const Divider(height: 24),
          Text(
            '🛌 DESCANSO SEMANAL',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(iconoEstado, color: colorEstado, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        estadoDescanso,
                        style: TextStyle(
                          color: colorEstado,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (inicioDS != null && finDS != null)
                        Text(
                          '${_nombreDia(inicioDS.weekday)} ${inicioDS.day} → ${_nombreDia(finDS.weekday)} ${finDS.day}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _listaMes() {
    final jornadas = _jornadasMes(_mesSeleccionado, _anioSeleccionado);
    final dias = _jornadasPorDia(jornadas);

    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () {
                  if (_mesSeleccionado == 1) {
                    setState(() {
                      _mesSeleccionado = 12;
                      _anioSeleccionado--;
                    });
                  } else {
                    setState(() => _mesSeleccionado--);
                  }
                },
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${_nombreMes(_mesSeleccionado)} $_anioSeleccionado',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () {
                  if (_mesSeleccionado == 12) {
                    setState(() {
                      _mesSeleccionado = 1;
                      _anioSeleccionado++;
                    });
                  } else {
                    setState(() => _mesSeleccionado++);
                  }
                },
              ),
            ],
          ),
        ),
        if (dias.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: Column(
                children: [
                  Icon(Icons.event_busy, size: 60, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  Text(
                    'No hay jornadas en ${_nombreMes(_mesSeleccionado)}',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          )
        else
          for (var entry in dias.entries)
            _diaExpandible(
              entry.key,
              entry.value,
              DateTime(_anioSeleccionado, _mesSeleccionado, entry.key),
              descansoDelSiguiente: _getDescansoDelDia(
                DateTime(_anioSeleccionado, _mesSeleccionado, entry.key + 1),
              ),
            ),
        const SizedBox(height: 20),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final hoy = DateTime.now();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Historial',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold),
          tabs: [
            Tab(text: '${_nombreDia(hoy.weekday).toUpperCase()}, ${hoy.day}'),
            const Tab(text: 'SEMANA'),
            Tab(text: _nombreMes(hoy.month).toUpperCase()),
          ],
        ),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [_listaHoy(), _listaSemana(), _listaMes()],
            ),
    );
  }
}
