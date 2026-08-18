import 'package:flutter/material.dart';
import '../services/api_service.dart';

// Widget que muestra el estado del descanso semanal
class DescansoSemanalWidget extends StatefulWidget {
  final int idUsuario;
  final int? idUltimoRegistro;
  const DescansoSemanalWidget({
    required this.idUsuario,
    this.idUltimoRegistro,
    super.key,
  });

  @override
  State<DescansoSemanalWidget> createState() => _DescansoSemanalWidgetState();
}

class _DescansoSemanalWidgetState extends State<DescansoSemanalWidget> {
  final ApiService _api = ApiService();

  bool _cargando        = true;
  int _diasConsecutivos = 0;
  int _diasHastaLimite  = 6;
  String _nivelAlerta   = 'ok';
  List<dynamic> _compensaciones = [];
  int _totalHorasDeuda  = 0;

  @override
  void initState() {
    super.initState();
    _cargarEstado();
  }

  void _cargarEstado() async {
    setState(() => _cargando = true);
    var res = await _api.getEstadoDescansoSemanal(widget.idUsuario);
    if (!mounted) return;
    if (res['status'] == 'success') {
      final data = res['data'];
      setState(() {
        _diasConsecutivos = data['dias_consecutivos'] ?? 0;
        _diasHastaLimite  = data['dias_hasta_limite']  ?? 6;
        _nivelAlerta      = data['nivel_alerta']        ?? 'ok';
        _compensaciones   = data['compensaciones_pendientes'] ?? [];
        _totalHorasDeuda  = data['total_horas_deuda']   ?? 0;
        _cargando = false;
      });
    } else {
      setState(() => _cargando = false);
    }
  }

  void _confirmarDescansoSemanal() async {
    if (widget.idUltimoRegistro == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("No hay ningún registro de descanso activo para marcar."),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Diálogo de confirmación
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("¿Marcar como descanso semanal?"),
        content: const Text(
          "Confirma que el descanso actual es tu descanso semanal.\n\n"
              "• Si dura 45h o más → descanso normal ✅\n"
              "• Si dura entre 24h y 45h → descanso reducido ⚠️\n"
              "  (deberás compensar las horas restantes en 3 semanas)",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("CANCELAR"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("CONFIRMAR"),
          ),
        ],
      ),
    );

    if (confirmar != true || !mounted) return;

    final res = await _api.marcarDescansoSemanal(
      widget.idUltimoRegistro!,
      widget.idUsuario,
    );

    if (!mounted) return;

    if (res['status'] == 'success') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res['message']),
          backgroundColor: Colors.green,
        ),
      );
      _cargarEstado();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error: ${res['message']}"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Color get _colorAlerta {
    switch (_nivelAlerta) {
      case 'critico': return Colors.red;
      case 'aviso':   return Colors.orange;
      default:        return Colors.green;
    }
  }

  IconData get _iconoAlerta {
    switch (_nivelAlerta) {
      case 'critico': return Icons.warning_rounded;
      case 'aviso':   return Icons.info_rounded;
      default:        return Icons.check_circle;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) return const LinearProgressIndicator();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _colorAlerta.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _colorAlerta.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_iconoAlerta, color: _colorAlerta, size: 22),
              const SizedBox(width: 8),
              Text(
                "Descanso semanal",
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: _colorAlerta,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Barra de días trabajados
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "$_diasConsecutivos días trabajados",
                style: const TextStyle(fontSize: 13),
              ),
              Text(
                _diasHastaLimite > 0
                    ? "Límite en $_diasHastaLimite días"
                    : "¡Límite alcanzado!",
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: _colorAlerta,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (_diasConsecutivos / 6).clamp(0.0, 1.0),
              backgroundColor: Colors.grey.shade300,
              valueColor: AlwaysStoppedAnimation<Color>(_colorAlerta),
              minHeight: 10,
            ),
          ),
          // Etiquetas de días
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(7, (i) => Text(
              i == 0 ? '' : '$i',
              style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
            )),
          ),

          // Compensaciones pendientes
          if (_compensaciones.isNotEmpty) ...[
            const Divider(height: 20),
            Row(
              children: [
                const Icon(Icons.access_time, size: 16, color: Colors.orange),
                const SizedBox(width: 6),
                Text(
                  "Deuda pendiente: $_totalHorasDeuda horas",
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ..._compensaciones.map((c) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                "• ${c['horas_deuda']}h → antes del "
                    "${c['fecha_limite'].toString().substring(0, 10)} "
                    "(${c['dias_restantes']} días)",
                style: TextStyle(
                  fontSize: 12,
                  color: (c['dias_restantes'] as int) <= 3
                      ? Colors.red
                      : Colors.orange,
                ),
              ),
            )),
          ],

          // Botón marcar descanso semanal
          if (widget.idUltimoRegistro != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.hotel),
                label: const Text("Marcar como descanso semanal"),
                onPressed: _confirmarDescansoSemanal,
                style: OutlinedButton.styleFrom(
                  foregroundColor: _colorAlerta,
                  side: BorderSide(color: _colorAlerta),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}