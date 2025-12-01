import 'package:cs_laboratorio/master.dart';
import 'package:flutter/material.dart';

class SerialLogPage extends StatefulWidget {
  const SerialLogPage({super.key});

  @override
  State<SerialLogPage> createState() => _SerialLogPageState();
}

class _SerialLogPageState extends State<SerialLogPage> {
  final service = SerialService();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // Nos suscribimos para recibir notificaciones de nuevos mensajes
    service.addListener(_onServiceChanged);
    // Si aún no conectas desde otro sitio, podrías lanzar la conexión aquí
    // service.connectMultiple();
  }

  void _onServiceChanged() {
    // Disparamos rebuild
    setState(() {});
    // Tras el rebuild, desplazamos al último mensaje
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  @override
  void dispose() {
    // Desuscribimos el listener y eliminamos el controller
    service.removeListener(_onServiceChanged);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Logs del puerto serie'),
        backgroundColor: color2,
        foregroundColor: color4,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete, color: color4),
            tooltip: 'Borrar logs',
            onPressed: () {
              service.clearLogs();
            },
          ),
        ],
      ),
      body: Container(
        color: color0,
        child:
            service.messageLog.isEmpty
                ? const Center(
                  child: Text(
                    'No hay mensajes aún.',
                    style: TextStyle(color: color4),
                  ),
                )
                : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(8),
                  itemCount: service.messageLog.length,
                  itemBuilder: (context, index) {
                    final msg = service.messageLog[index];

                    return Card(
                      color: color1,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        dense: true,
                        leading: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              msg.timestamp
                                  .toLocal()
                                  .toIso8601String()
                                  .substring(11, 19),
                              style: const TextStyle(
                                color: color4,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              msg.portName,
                              style: const TextStyle(
                                color: color4,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        title: Text(
                          msg.data.trim(),
                          style: const TextStyle(
                            color: color4,
                            fontFamily: 'Courier',
                          ),
                        ),
                      ),
                    );
                  },
                ),
      ),
    );
  }
}
