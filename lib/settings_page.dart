import 'package:cslab/master.dart';
import 'package:flutter/material.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final settings = AppSettings();

  @override
  void initState() {
    super.initState();
    settings.addListener(_onSettingsChanged);
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    settings.removeListener(_onSettingsChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuraciones'),
        backgroundColor: color1,
        foregroundColor: color4,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: color4),
            tooltip: 'Restaurar valores por defecto',
            onPressed: () {
              showAlertDialog(
                context,
                true,
                const Text('Confirmar'),
                const Text(
                  '¿Deseas restaurar todas las configuraciones a sus valores por defecto?',
                ),
                [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancelar'),
                  ),
                  TextButton(
                    onPressed: () {
                      settings.resetToDefaults();
                      Navigator.pop(context);
                      showToast('Configuraciones restauradas');
                    },
                    child: const Text('Restaurar'),
                  ),
                ],
              );
            },
          ),
        ],
      ),
      body: Container(
        color: color0,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Sección: Comunicación Serial
            _buildSectionHeader('Comunicación Serial'),
            _buildSliderSetting(
              title: 'Máximo de mensajes en log',
              value: settings.maxLogMessages.toDouble(),
              min: 100,
              max: 5000,
              divisions: 49,
              onChanged: (val) => settings.maxLogMessages = val.toInt(),
              displayValue: settings.maxLogMessages.toString(),
            ),
            _buildSliderSetting(
              title: 'Timeout de comando (segundos)',
              value: settings.commandTimeout.inSeconds.toDouble(),
              min: 1,
              max: 30,
              divisions: 29,
              onChanged:
                  (val) =>
                      settings.commandTimeout = Duration(seconds: val.toInt()),
              displayValue: '${settings.commandTimeout.inSeconds}s',
            ),
            _buildSliderSetting(
              title: 'Delay de reconexión (ms)',
              value: settings.reconnectDelay.inMilliseconds.toDouble(),
              min: 100,
              max: 2000,
              divisions: 19,
              onChanged:
                  (val) =>
                      settings.reconnectDelay = Duration(
                        milliseconds: val.toInt(),
                      ),
              displayValue: '${settings.reconnectDelay.inMilliseconds}ms',
            ),
            _buildSliderSetting(
              title: 'Máximo de reintentos',
              value: settings.maxRetries.toDouble(),
              min: 1,
              max: 10,
              divisions: 9,
              onChanged: (val) => settings.maxRetries = val.toInt(),
              displayValue: settings.maxRetries.toString(),
            ),

            const SizedBox(height: 24),

            // Sección: Programación de Dispositivos
            _buildSectionHeader('Programación de Dispositivos'),
            _buildSliderSetting(
              title: 'Flasheos simultáneos',
              value: settings.maxConcurrentFlash.toDouble(),
              min: 1,
              max: 40,
              divisions: 39,
              onChanged: (val) => settings.maxConcurrentFlash = val.toInt(),
              displayValue: settings.maxConcurrentFlash.toString(),
            ),
            _buildSliderSetting(
              title: 'Reintentos en flasheo',
              value: settings.maxRetriesFlash.toDouble(),
              min: 1,
              max: 5,
              divisions: 4,
              onChanged: (val) => settings.maxRetriesFlash = val.toInt(),
              displayValue: settings.maxRetriesFlash.toString(),
            ),
            _buildSliderSetting(
              title: 'Delay entre líneas de certificado (ms)',
              value: settings.certLineDelay.inMilliseconds.toDouble(),
              min: 100,
              max: 1000,
              divisions: 18,
              onChanged:
                  (val) =>
                      settings.certLineDelay = Duration(
                        milliseconds: val.toInt(),
                      ),
              displayValue: '${settings.certLineDelay.inMilliseconds}ms',
            ),
            _buildSliderSetting(
              title: 'Delay entre dispositivos (ms)',
              value: settings.deviceDelay.inMilliseconds.toDouble(),
              min: 200,
              max: 2000,
              divisions: 18,
              onChanged:
                  (val) =>
                      settings.deviceDelay = Duration(
                        milliseconds: val.toInt(),
                      ),
              displayValue: '${settings.deviceDelay.inMilliseconds}ms',
            ),

            const SizedBox(height: 32),

            // Información adicional
            Card(
              color: color1,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.info_outline, color: color4),
                        const SizedBox(width: 8),
                        Text(
                          'Información',
                          style: TextStyle(
                            color: color4,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '• Los cambios se aplican inmediatamente\n'
                      '• Valores más altos = mayor estabilidad pero más lento\n'
                      '• Valores más bajos = más rápido pero menos tolerante a errores\n'
                      '• Recomendado: mantener valores por defecto',
                      style: TextStyle(color: color4, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 16),
      child: Text(
        title,
        style: const TextStyle(
          color: color4,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildSliderSetting({
    required String title,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
    required String displayValue,
  }) {
    return Card(
      color: color1,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: color4,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: color2,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    displayValue,
                    style: const TextStyle(
                      color: color4,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              activeColor: color2,
              inactiveColor: color3,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}
