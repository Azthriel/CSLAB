// auto.dart

import 'dart:convert';
import 'dart:io';
import 'package:cslab/secret.dart';
import 'package:cslab/tools.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:cslab/master.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Representa un dispositivo a crear:
class _DeviceInfo {
  final String productCode;
  final String serial;
  final String port;
  bool hasError = false;
  String errorMessage = '';
  int retryCount = 0;

  _DeviceInfo(this.productCode, this.serial, this.port);
}

class AutoPage extends StatefulWidget {
  const AutoPage({super.key});

  @override
  AutoPageState createState() => AutoPageState();
}

class AutoPageState extends State<AutoPage> {
  final service = SerialService();
  final settings = AppSettings(); // Usar configuraciones dinámicas

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

      versionToUpload = folderName;

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

      // 6) Capturar y cerrar puertos con delay
      printLog('Closing all ports before flashing...', 'azul');
      for (final port in ports) {
        try {
          await service.disconnectPort(port);
          printLog('Port closed: $port', 'verde');
        } catch (e) {
          printLog('Error closing port $port: $e', 'rojo');
        }
      }

      // Dar tiempo al OS para liberar los puertos
      await Future.delayed(const Duration(milliseconds: 2000));

      // 7) Flashear dispositivos con procesamiento paralelo controlado
      printLog(
        'Starting parallel flash process (max ${settings.maxConcurrentFlash} concurrent)',
        'amarillo',
      );

      // Dividir en batches para no sobrecargar
      for (int i = 0; i < devices.length; i += settings.maxConcurrentFlash) {
        final batch =
            devices.skip(i).take(settings.maxConcurrentFlash).toList();
        printLog(
          'Flashing batch ${i ~/ settings.maxConcurrentFlash + 1}: ${batch.length} devices',
          'cyan',
        );

        // Flashear batch en paralelo
        await Future.wait(
          batch.map((device) => _flashDevice(device, localPaths, pythonExe)),
        );

        // Delay entre batches
        if (i + settings.maxConcurrentFlash < devices.length) {
          await Future.delayed(const Duration(seconds: 1));
        }
      }

      await Future.delayed(const Duration(seconds: 2));

      // 8) Cambiar Número de Serie con reintentos
      printLog('Starting serial number programming...', 'amarillo');
      for (final device in devices) {
        if (device.hasError) continue;

        // Re-conectar puerto con retry
        final connected = await service.connectPort(device.port);
        if (!connected) {
          printLog('Cannot reconnect to ${device.port}', 'rojo');
          _reportLines.add(
            '${device.productCode}:${device.serial}@${device.port} ---> ERROR (reconnect)',
          );
          device.hasError = true;
          continue;
        }

        // Esperar estabilización
        await Future.delayed(const Duration(milliseconds: 500));

        try {
          String msg = jsonEncode({"cmd": 4, "content": device.serial});
          final sent = await service.sendToPort(device.port, msg);

          if (sent) {
            registerActivity(
              device.productCode,
              device.serial,
              "Se le envió número de serie",
            );
            printLog('Sent SN ${device.serial} to ${device.port}', 'verde');
            showToast('SN ${device.serial} enviado a ${device.port}');
            _reportLines.add(
              '${device.productCode}:${device.serial}@${device.port} ---> COMPLETADO (SerialNumber)',
            );
          } else {
            throw Exception('Failed to send serial number');
          }
        } catch (e) {
          printLog('Error sending SN to ${device.port}: $e', 'rojo');
          registerActivity(
            device.productCode,
            device.serial,
            "Error enviando número de serie: $e",
          );
          _reportLines.add(
            '${device.productCode}:${device.serial}@${device.port} ---> ERROR (SerialNumber): $e',
          );
          device.hasError = true;
        }

        // Delay entre dispositivos
        await Future.delayed(settings.deviceDelay);
      }

      // 9) Crear Things y cargar certificados con mejoras
      final uri = Uri.parse(createThingURL);

      for (final device in devices) {
        if (device.hasError) continue;
        final thingName = '${device.productCode}:${device.serial}';
        printLog('Creating Thing $thingName', 'amarillo');

        // Crear Thing con retry
        Map<String, dynamic>? payload;
        for (int retry = 0; retry < settings.maxRetriesFlash; retry++) {
          try {
            final body = jsonEncode({'thingName': thingName});
            final response = await http
                .post(uri, body: body)
                .timeout(const Duration(seconds: 10));

            if (response.statusCode == 200) {
              final jsonResponse =
                  jsonDecode(response.body) as Map<String, dynamic>;
              payload =
                  jsonDecode(jsonResponse['body'] as String)
                      as Map<String, dynamic>;
              break;
            } else {
              printLog(
                'HTTP ${response.statusCode} for $thingName (attempt ${retry + 1})',
                'rojo',
              );
              if (retry < settings.maxRetriesFlash - 1) {
                await Future.delayed(Duration(seconds: retry + 1));
              }
            }
          } catch (e) {
            printLog(
              'Exception creating thing (attempt ${retry + 1}): $e',
              'rojo',
            );
            if (retry < settings.maxRetries - 1) {
              await Future.delayed(Duration(seconds: retry + 1));
            }
          }
        }

        if (payload == null) {
          registerActivity(
            device.productCode,
            device.serial,
            "Error al crear Thing: falló después de ${settings.maxRetriesFlash} intentos",
          );
          _reportLines.add(
            '${device.productCode}:${device.serial}@${device.port} ---> ERROR (Thing creation failed)',
          );
          device.hasError = true;
          continue;
        }

        final amazonCA = payload['amazonCA'] as String;
        final deviceCert = payload['deviceCert'] as String;
        final privateKey = payload['privateKey'] as String;

        printLog('Sending certificates to ${device.port}...', 'cyan');

        // Enviar certificados con mejor manejo
        try {
          await _sendCertificateLines(device, amazonCA, '0', 'AmazonCA');
          await _sendCertificateLines(device, deviceCert, '1', 'DeviceCert');
          await _sendCertificateLines(device, privateKey, '2', 'PrivateKey');

          printLog('Thing $thingName loaded successfully', 'verde');
          registerActivity(
            device.productCode,
            device.serial,
            "Se le cargo Thing desde CSLAB",
          );
          _reportLines.add(
            '${device.productCode}:${device.serial}@${device.port} ---> COMPLETADO (Thing)',
          );
        } catch (e) {
          printLog('Error sending certificates to ${device.port}: $e', 'rojo');
          registerActivity(
            device.productCode,
            device.serial,
            "Error cargando Thing: $e",
          );
          _reportLines.add(
            '${device.productCode}:${device.serial}@${device.port} ---> ERROR (Certificates): $e',
          );
          device.hasError = true;
        }

        // Delay entre dispositivos
        await Future.delayed(settings.deviceDelay);
      }

      // 10) Generar archivo de reporte con resumen
      final successCount = devices.where((d) => !d.hasError).length;
      final failCount = devices.where((d) => d.hasError).length;

      final reportHeader = [
        '=' * 60,
        'Reporte de Programación - ${DateTime.now()}',
        'Total dispositivos: ${devices.length}',
        'Exitosos: $successCount',
        'Fallidos: $failCount',
        '=' * 60,
        '',
      ];

      final reportFile = File(
        p.join(File(Platform.resolvedExecutable).parent.path, 'report.txt'),
      );
      await reportFile.writeAsString(
        [...reportHeader, ..._reportLines].join('\r\n'),
      );

      final reportPath = reportFile.path;
      printLog('Reporte guardado en: $reportPath', 'verde');

      showToast(
        'Proceso completo. $successCount OK, $failCount errores. Ver report.txt',
      );
    } catch (e, st) {
      printLog('Error en runAll: $e\n$st', 'rojo');
      showToast('Error crítico en proceso: $e');
      _reportLines.add('ERROR CRÍTICO: $e');
    } finally {
      // Actualizar UI
      if (mounted) {
        setState(() {
          _isRunning = false;
        });
      }
      printLog('runAll finished', 'verde');
    }
  }

  /// Flashea un dispositivo individual con reintentos
  Future<void> _flashDevice(
    _DeviceInfo device,
    Map<String, String> localPaths,
    String pythonExe,
  ) async {
    if (device.hasError) return;

    registerActivity(
      device.productCode,
      device.serial,
      "Se comenzo el flasheo con versión $versionToUpload",
    );

    final rawPort = device.port;
    final portArg =
        (rawPort.startsWith('COM') && rawPort.length > 4)
            ? r'\\.\' + rawPort
            : rawPort;

    printLog(
      'Flashing ${device.productCode}:${device.serial} on $portArg',
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
      '${service.baudRate}',
      '--before',
      'default_reset',
      '--after',
      'hard_reset',
      '--connect-attempts',
      '5',
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

    for (int retry = 0; retry < settings.maxRetriesFlash; retry++) {
      try {
        final result = await Process.run(
          pythonExe,
          args,
        ).timeout(const Duration(seconds: 60));

        printLog('esptool exitCode=${result.exitCode} for ${device.port}');

        if (result.exitCode == 0) {
          showToast('Flasheo exitoso en ${device.port}');
          registerActivity(
            device.productCode,
            device.serial,
            "Flasheo exitoso con versión $versionToUpload",
          );
          if (mounted) {
            setState(() {
              _reportLines.add(
                '${device.productCode}:${device.serial}@${device.port} ---> COMPLETADO (Flash)',
              );
            });
          }
          return;
        } else {
          final reason =
              result.stderr?.toString().trim().replaceAll('\n', ' ') ??
              'Exit code ${result.exitCode}';
          printLog('Flash failed for ${device.port}: $reason', 'rojo');

          if (retry < settings.maxRetriesFlash - 1) {
            printLog(
              'Retrying flash for ${device.port} (${retry + 1}/${settings.maxRetriesFlash})',
              'amarillo',
            );
            await Future.delayed(Duration(seconds: retry + 2));
          } else {
            device.hasError = true;
            device.errorMessage = reason;
            registerActivity(
              device.productCode,
              device.serial,
              "Error en flasheo: $reason",
            );
            if (mounted) {
              setState(() {
                _reportLines.add(
                  '${device.productCode}:${device.serial}@${device.port} ---> ERROR (Flash): $reason',
                );
              });
            }
          }
        }
      } catch (e) {
        printLog('Exception flashing ${device.port}: $e', 'rojo');
        if (retry < settings.maxRetriesFlash - 1) {
          await Future.delayed(Duration(seconds: retry + 2));
        } else {
          device.hasError = true;
          device.errorMessage = e.toString();
          if (mounted) {
            setState(() {
              _reportLines.add(
                '${device.productCode}:${device.serial}@${device.port} ---> ERROR (Flash): $e',
              );
            });
          }
        }
      }
    }
  }

  /// Envía líneas de certificado con validación
  Future<void> _sendCertificateLines(
    _DeviceInfo device,
    String certificate,
    String certType,
    String certName,
  ) async {
    final lines =
        certificate
            .split('\n')
            .where((line) => line.trim().isNotEmpty)
            .toList();

    printLog(
      'Sending $certName to ${device.port}: ${lines.length} lines',
      'cyan',
    );

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      final msg = jsonEncode({"cmd": 6, "content": "$certType#$line"});
      final sent = await service.sendToPort(device.port, msg);

      if (!sent) {
        throw Exception(
          'Failed to send $certName line ${i + 1}/${lines.length}',
        );
      }

      // Delay entre líneas (más largo que antes)
      await Future.delayed(settings.certLineDelay);

      // Log cada 10 líneas
      if ((i + 1) % 10 == 0) {
        printLog('  Progress: ${i + 1}/${lines.length} lines sent', 'verde');
      }
    }

    printLog('$certName sent successfully to ${device.port}', 'verde');
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
