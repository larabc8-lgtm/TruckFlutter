import 'package:flutter/material.dart';
import '../services/notificacion_storage_service.dart';

class NotificacionesScreen extends StatefulWidget {
  const NotificacionesScreen({super.key});

  @override
  State<NotificacionesScreen> createState() => _NotificacionesScreenState();
}

class _NotificacionesScreenState extends State<NotificacionesScreen> {
  final _storage = NotificacionStorageService();
  List<NotificacionLocal> _notificaciones = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargarNotificaciones();
  }

  Future<void> _cargarNotificaciones() async {
    setState(() => _cargando = true);
    final todas = await _storage.obtenerTodas();
    if (mounted) {
      setState(() {
        _notificaciones = todas;
        _cargando = false;
      });
    }
  }

  Future<void> _marcarTodasLeidas() async {
    await _storage.marcarTodasLeidas();
    _cargarNotificaciones();
  }

  Future<void> _eliminarTodas() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar notificaciones'),
        content: const Text('¿Estás seguro de que quieres eliminar todas las notificaciones?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCELAR'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ELIMINAR', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      await _storage.eliminarTodas();
      _cargarNotificaciones();
    }
  }

  Future<void> _manejarToque(NotificacionLocal notif) async {
    if (!notif.leida) {
      await _storage.marcarLeida(notif.id);
      _cargarNotificaciones();
    }
  }

  IconData _getIcono(String tipo) {
    switch (tipo) {
      case 'conduccion': return Icons.local_shipping;
      case 'descanso': return Icons.bedtime;
      case 'jornada': return Icons.timer;
      case 'semanal': return Icons.calendar_today;
      default: return Icons.info;
    }
  }

  Color _getColor(String tipo) {
    switch (tipo) {
      case 'conduccion': return Colors.blue;
      case 'descanso': return Colors.orange;
      case 'jornada': return Colors.green;
      case 'semanal': return Colors.purple;
      default: return Colors.grey;
    }
  }

  String _formatearFecha(DateTime fecha) {
    final ahora = DateTime.now();
    final diferencia = ahora.difference(fecha);
    
    String formatTime(DateTime d) {
      return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    }
    
    String formatDate(DateTime d) {
      return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    }

    if (diferencia.inDays == 0 && fecha.day == ahora.day) {
      return 'Hoy ${formatTime(fecha)}';
    } else if (diferencia.inDays == 1 || (diferencia.inDays == 0 && fecha.day != ahora.day)) {
      return 'Ayer ${formatTime(fecha)}';
    } else {
      return '${formatDate(fecha)} ${formatTime(fecha)}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notificaciones'),
        actions: [
          if (_notificaciones.any((n) => !n.leida))
            IconButton(
              icon: const Icon(Icons.done_all),
              tooltip: 'Marcar todas como leídas',
              onPressed: _marcarTodasLeidas,
            ),
          if (_notificaciones.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Eliminar todas',
              onPressed: _eliminarTodas,
            ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _notificaciones.isEmpty
              ? _buildEstadoVacio()
              : _buildListaNotificaciones(),
    );
  }

  Widget _buildEstadoVacio() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.notifications_off_outlined, size: 80, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            'No tienes notificaciones',
            style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _buildListaNotificaciones() {
    return ListView.builder(
      itemCount: _notificaciones.length,
      itemBuilder: (context, index) {
        final notif = _notificaciones[index];
        final isDarkMode = Theme.of(context).brightness == Brightness.dark;
        
        return Dismissible(
          key: Key(notif.id),
          direction: DismissDirection.endToStart,
          background: Container(
            color: Colors.red,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            child: const Icon(Icons.delete, color: Colors.white),
          ),
          onDismissed: (direction) async {
            await _storage.eliminar(notif.id);
            _cargarNotificaciones();
          },
          child: Container(
            color: notif.leida 
                ? null 
                : (isDarkMode ? Colors.blue.withValues(alpha: 0.1) : Colors.blue.shade50),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: _getColor(notif.tipo).withValues(alpha: 0.2),
                child: Icon(_getIcono(notif.tipo), color: _getColor(notif.tipo)),
              ),
              title: Text(
                notif.titulo,
                style: TextStyle(
                  fontWeight: notif.leida ? FontWeight.normal : FontWeight.bold,
                ),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Text(notif.cuerpo),
                  const SizedBox(height: 4),
                  Text(
                    _formatearFecha(notif.fecha),
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
                ],
              ),
              isThreeLine: true,
              onTap: () => _manejarToque(notif),
            ),
          ),
        );
      },
    );
  }
}
