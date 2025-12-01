// auto.dart

import 'dart:convert';
import 'dart:io';

import 'package:cs_laboratorio/tools.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:cs_laboratorio/master.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Representa un dispositivo a crear:
class _DeviceInfo {
  final String productCode;
  final String serial;
  final String port;
  bool hasError = false;
  _DeviceInfo(this.productCode, this.serial, this.port);
}

class AutoPage extends StatefulWidget {
  const AutoPage({super.key});

  @override
  AutoPageState createState() => AutoPageState();
}

class AutoPageState extends State<AutoPage> {
  final service = SerialService();

  final _productCodeController = TextEditingController();
  final _hwVersionController = TextEditingController();
  final _startNumberController = TextEditingController();

  bool _isRunning = false;
  // ignore: prefer_final_fields
  List<String> _reportLines = [];

  static const _owner = 'barberop';
  static const _repo = 'sime-domotica';
  static const _branch = 'main';
  static const _baseRawUrl = 'https://raw.githubusercontent.com';

  @override
  void initState() {
    super.initState();
    service.addListener(_onServiceChanged);
  }

  void _onServiceChanged() {
    setState(() {});
  }

  @override
  void dispose() {
    service.removeListener(_onServiceChanged);
    _productCodeController.dispose();
    _hwVersionController.dispose();
    _startNumberController.dispose();
    super.dispose();
  }

  Future<void> _runAll() async {
    if (_productCodeController.text.isEmpty ||
        _hwVersionController.text.isEmpty ||
        _startNumberController.text.isEmpty ||
        service.selectedPortNames.isEmpty) {
      showToast('Complete todos los campos y seleccione al menos un puerto');
      return;
    }

    setState(() {
      _isRunning = true;
      _reportLines.clear();
    });

    try {
      // 1) Preparar inputs
      final productCode = _productCodeController.text.trim();
      final hwVersion = _hwVersionController.text.trim();
      int serialCounter = int.parse(_startNumberController.text.trim());
      printLog(
        'RunAll start: productCode=$productCode, hwVersion=$hwVersion, startNum=$serialCounter',
        'amarillo',
      );

      final ports = List<String>.from(service.selectedPortNames);

      final devices = <_DeviceInfo>[];
      final now = DateTime.now();
      final yy = now.year.toString().substring(2).padLeft(2, '0');
      final mm = now.month.toString().padLeft(2, '0');
      final dd = now.day.toString().padLeft(2, '0');

      for (final port in ports) {
        final nn = serialCounter.toString().padLeft(2, '0');
        final serial = '$yy$mm$dd$nn';
        devices.add(_DeviceInfo(productCode, serial, port));
        serialCounter++;
      }

      // 2) Obtener carpeta de firmware en GitHub
      final folderName = await _fetchLatestSoftwareFolder(
        productCode,
        hwVersion,
      );
      printLog('Using software folder: $folderName', 'verde');

      // 3) Descargar firmware (excepto boot_app0.bin)
      final tempDir = await getTemporaryDirectory();
      final Map<String, String> localPaths = {};
      for (final file in ['bootloader.bin', 'partitions.bin', 'firmware.bin']) {
        final url = Uri.parse(
          '$_baseRawUrl/$_owner/$_repo/$_branch/$productCode/LAB_FILES/$folderName/$file',
        );
        final outPath = p.join(tempDir.path, file);
        printLog('Downloading $file to $outPath', 'cyan');
        final response = await http.get(url);
        if (response.statusCode != 200) {
          throw Exception('Error descargando $file: ${response.statusCode}');
        }
        await File(outPath).writeAsBytes(response.bodyBytes);
        localPaths[file] = outPath;
      }
      // 4) Cargar boot_app0.bin desde assets
      {
        const assetPath = 'assets/boot_app0.bin';
        final data = await rootBundle.load(assetPath);
        final outPath = p.join(tempDir.path, 'boot_app0.bin');
        await File(outPath).writeAsBytes(data.buffer.asUint8List());
        localPaths['boot_app0.bin'] = outPath;
        printLog('Loaded boot_app0.bin from assets to $outPath', 'verde');
      }

      // 5) Preparar ruta a python embebido
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final pythonExe = p.join(exeDir, 'python-embed', 'python.exe');
      printLog(
        'Python executable: $pythonExe exists=${File(pythonExe).existsSync()}',
        'magenta',
      );

      // 6) Capturar y cerrar puertos

      printLog('Ports to process: $ports', 'azul');
      for (final port in ports) {
        try {
          service.disconnectPort(port);
          printLog('Port closed: $port', 'verde');
        } catch (e) {
          printLog('Error closing port $port: $e', 'rojo');
        }
      }

      // 7) Flashear todos los puertos
      // 7) Flashear todos los dispositivos, usando la lista de devices
      for (final device in devices) {
        if (device.hasError) continue;
        final rawPort = device.port;
        final portArg =
            (rawPort.startsWith('COM') && rawPort.length > 4)
                ? r'\\.\' + rawPort
                : rawPort;

        printLog(
          'Flashing ${device.productCode}:${device.serial} on $portArg at 576000 baud',
          'amarillo',
        );

        final args = [
          '-m',
          'esptool',
          '--chip',
          'esp32c3',
          '--port',
          portArg,
          '--baud',
          '576000',
          '--before',
          'default_reset',
          '--after',
          'hard_reset',
          'write_flash',
          '-z',
          '0x0000',
          localPaths['bootloader.bin']!,
          '0x8000',
          localPaths['partitions.bin']!,
          '0xE000',
          localPaths['boot_app0.bin']!,
          '0x10000',
          localPaths['firmware.bin']!,
        ];
        printLog('esptool args: $args');

        final result = await Process.run(pythonExe, args);
        printLog('esptool exitCode=${result.exitCode}');
        if (result.stdout.isNotEmpty) printLog('stdout: ${result.stdout}');
        if (result.stderr.isNotEmpty) {
          printLog('stderr: ${result.stderr}', 'rojo');
        }

        if (result.exitCode != 0) {
          showToast('Error flasheando ${device.port}');
          // Aquí incluimos el serial correcto en el reporte
          final reason =
              result.stderr?.toString().trim().replaceAll('\n', ' ') ??
              'Exit code ${result.exitCode}';
          _reportLines.add(
            '${device.productCode}:${device.serial}@${device.port} ---> ERROR (Flash): $reason',
          );
          device.hasError = true;
          continue;
        } else {
          showToast('Flasheo exitoso en ${device.port}');
          _reportLines.add(
            '${device.productCode}:${device.serial}@${device.port} ---> COMPLETADO (Flash)',
          );
        }
      }

      await Future.delayed(const Duration(seconds: 1));

      // 9) Cambiar Número de Serie a todos
      for (final device in devices) {
        // Re-conectar puerto
        service.connectPort(device.port);
        if (!service.isConnected) {
          printLog('Cannot reconnect to ${device.port}', 'rojo');
          _reportLines.add(
            '${device.productCode}:${device.serial}@${device.port} ---> ERROR (connect)',
          );
          device.hasError = true;
          continue;
        }
        if (device.hasError) continue;
        try {
          String msg = jsonEncode({"cmd": 4, "content": device.serial});
          service.sendToPort(device.port, msg);
          printLog('Sent SN ${device.serial} to ${device.port}', 'azul');
          showToast('Enviando SN ${device.serial} a ${device.port}');
          _reportLines.add(
            '${device.productCode}:${device.serial}@${device.port} ---> COMPLETADO (SerialNumber)',
          );
        } catch (e) {
          printLog('Error sending SN to ${device.port}: $e', 'rojo');
          _reportLines.add(
            '${device.productCode}:${device.serial}@${device.port} ---> ERROR (SerialNumber)',
          );
          device.hasError = true;
          continue;
        }
      }

      // 10) Crear Things y cargar certificados
      final uri = Uri.parse(
        'https://7afkb3q46b.execute-api.sa-east-1.amazonaws.com/v1/THINGS',
      );
      for (final device in devices) {
        if (device.hasError) continue;
        final thingName = '${device.productCode}:${device.serial}';
        printLog('Creating Thing $thingName', 'amarillo');

        final body = jsonEncode({'thingName': thingName});
        final response = await http.post(uri, body: body);
        if (response.statusCode != 200) {
          printLog('HTTP ${response.statusCode} for $thingName', 'rojo');
          _reportLines.add(
            '${device.productCode}:${device.serial}@${device.port} ---> ERROR (HTTP ${response.statusCode})',
          );
          device.hasError = true;
          continue;
        }

        final jsonResponse = jsonDecode(response.body) as Map<String, dynamic>;
        final payload =
            jsonDecode(jsonResponse['body'] as String) as Map<String, dynamic>;
        final amazonCA = payload['amazonCA'] as String;
        final deviceCert = payload['deviceCert'] as String;
        final privateKey = payload['privateKey'] as String;

        printLog('DeviceCert: $deviceCert', 'verde');
        printLog('PrivateKey: $privateKey', 'verde');
        printLog('AmazonCA: $amazonCA', 'verde');

        // Enviar certificados
        for (final line in amazonCA.split('\n')) {
          if (line.isEmpty || line == ' ') break;
          printLog('Sending AmazonCA line: $line', 'verde');
          service.sendToPort(
            device.port,
            jsonEncode({"cmd": 6, "content": "0#$line"}),
          );
          await Future.delayed(const Duration(milliseconds: 200));
        }
        for (final line in deviceCert.split('\n')) {
          if (line.isEmpty || line == ' ') break;
          printLog('Sending DeviceCert line: $line', 'verde');
          service.sendToPort(
            device.port,
            jsonEncode({"cmd": 6, "content": "1#$line"}),
          );
          await Future.delayed(const Duration(milliseconds: 200));
        }
        for (final line in privateKey.split('\n')) {
          if (line.isEmpty || line == ' ') break;
          printLog('Sending PrivateKey line: $line', 'verde');
          service.sendToPort(
            device.port,
            jsonEncode({"cmd": 6, "content": "2#$line"}),
          );
          await Future.delayed(const Duration(milliseconds: 200));
        }

        printLog('Thing $thingName loaded', 'verde');
        _reportLines.add(
          '${device.productCode}:${device.serial}@${device.port} ---> COMPLETADO (Thing)',
        );
      }

      // 11) Generar archivo de reporte
      final reportFile = File(
        p.join(File(Platform.resolvedExecutable).parent.path, 'report.txt'),
      );
      await reportFile.writeAsString(_reportLines.join('\r\n'));

      showToast('Proceso completo. Revisa report.txt');
    } catch (e, st) {
      printLog('Error en runAll: $e\n$st', 'rojo');
      showToast('Error en proceso: $e');
    } finally {
      setState(() {
        _isRunning = false;
      });
      printLog('runAll finished', 'verde');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: color4,
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Focus(
                onFocusChange: (hasFocus) {
                  if (!hasFocus) {
                    final text = _productCodeController.text;
                    if (!text.endsWith('_IOT')) {
                      _productCodeController.text = '${text}_IOT';
                      _productCodeController
                          .selection = TextSelection.collapsed(
                        offset: _productCodeController.text.length,
                      );
                      printLog('Appended _IOT to productCode', 'magenta');
                    }
                  }
                },
                child: buildTextField(
                  label: 'Código de producto',
                  controller: _productCodeController,
                ),
              ),
              buildTextField(
                label: 'Versión de hardware',
                controller: _hwVersionController,
              ),
              buildTextField(
                label: 'Número inicial',
                controller: _startNumberController,
                keyboard: TextInputType.number,
              ),
              const SizedBox(height: 24),
              buildButton(
                onPressed: _isRunning ? null : _runAll,
                text: _isRunning ? 'Procesando...' : 'Iniciar',
              ),
              const SizedBox(height: 24),
              if (_reportLines.isNotEmpty) ...[
                const Text('Reporte de ejecución:'),
                const SizedBox(height: 8),
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _reportLines.length,
                  itemBuilder:
                      (context, i) => Text(
                        _reportLines[i],
                        style: TextStyle(color: color1),
                      ),
                ),
              ],
              if (_isRunning) ...[
                const SizedBox(height: 24),
                const Center(child: CircularProgressIndicator(color: color2)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // Reutiliza tu función existente
  Future<String> _fetchLatestSoftwareFolder(
    String productCode,
    String hwVersion,
  ) => ToolsPageState().fetchLatestSoftwareFolder(productCode, hwVersion);
}
