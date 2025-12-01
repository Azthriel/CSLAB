// lib/serial_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cs_laboratorio/master.dart';

class SerialPage extends StatefulWidget {
  const SerialPage({super.key});
  @override
  SerialPageState createState() => SerialPageState();
}

class SerialPageState extends State<SerialPage> {
  final service = SerialService();
  final TextEditingController _textController = TextEditingController();

  StreamSubscription<SerialMessage>? _inSub;
  String _receivedText = '';

  @override
  void initState() {
    super.initState();
    service.addListener(_onServiceChanged);
    // Escucha todo lo que llegue por el serial
    _inSub = service.incomingData.listen((msg) {
      setState(() {
        // prefix + color por puerto, o simplemente texto
        _receivedText += '[${msg.portName}] ${msg.data} \n';
      });
    });
  }

  @override
  void dispose() {
    _inSub?.cancel();
    _textController.dispose();
    service.removeListener(_onServiceChanged);
    super.dispose();
  }

  void _onServiceChanged() {
    // Cuando service notifica, reconstruimos
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: color4,
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            children: [
              // ─── Envío de mensajes ────────────────────────────────────
              Card(
                color: color4,
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      buildTextField(
                        label: 'Mensaje a enviar',
                        controller: _textController,
                      ),
                      const SizedBox(height: 12),
                      buildButton(
                        text: 'Enviar',
                        icon: Icons.send,
                        onPressed:
                            service.isConnected
                                ? () {
                                  service.sendMessage(_textController.text);
                                  _textController.clear();
                                }
                                : null,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // ─── Área de datos recibidos ─────────────────────────────
              SizedBox(
                height: 300,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: FractionallySizedBox(
                    widthFactor: 0.8, // 80% del ancho
                    child: Card(
                      color: color1,
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: SingleChildScrollView(
                          child: Text(
                            _receivedText.isEmpty
                                ? 'Esperando datos...'
                                : _receivedText,
                            style: const TextStyle(
                              fontFamily: 'Courier',
                              color: color4,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          setState(() {
            _receivedText = '';
            _textController.clear();
          });
          showToast("Datos borrados");
        },
        backgroundColor: color2,
        child: const Icon(Icons.delete, color: color4),
      ),
    );
  }
}
