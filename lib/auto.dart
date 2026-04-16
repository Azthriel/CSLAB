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
  double flashProgress = 0.0;
  String flashStatus = 'Pendiente';
  bool isFlashing = false;
  // Paso general del proceso
  String currentStep = 'Pendiente'; // 'Flash', 'Nº de Serie', 'Creando Thing', 'Certificados', 'Completado', 'Error'
  // Progreso de certificados
  String certCurrentName = '';
  int certLinesSent = 0;
  int certLinesTotal = 0;

  String resultSummary = '';

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
  List<_DeviceInfo> _devices = [];
  final List<String> _autoLog = [];
  final ScrollController _logScrollController = ScrollController();

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
    if (!mounted) return;
    // Diferir para no llamar setState durante un build en curso
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    service.removeListener(_onServiceChanged);
    _productCodeController.dispose();
    _hwVersionController.dispose();
    _startNumberController.dispose();
    _logScrollController.dispose();
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
      _autoLog.clear();
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

      // Guardar devices en estado para mostrar progreso en UI
      if (mounted) {
        setState(() {
          _devices = devices;
        });
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
        if (mounted) setState(() => device.currentStep = 'Nº de Serie');
        _addAutoLog('[${_nowTs()}] ${device.port} → Enviando Nº de Serie: ${device.serial}');

        // Re-conectar puerto con retry
        final connected = await service.connectPort(device.port);
        if (!connected) {
          printLog('Cannot reconnect to ${device.port}', 'rojo');
          _reportLines.add(
            '${device.productCode}:${device.serial}@${device.port} ---> ERROR (reconnect)',
          );
          device.resultSummary = 'No se pudo reconectar al puerto';
          if (mounted) setState(() => device.currentStep = 'Error');
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
            _addAutoLog('[${_nowTs()}] ${device.port} ✓ Nº de Serie enviado: ${device.serial}');
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
          device.resultSummary = 'Error N° de Serie: $e';
          if (mounted) setState(() => device.currentStep = 'Error');
          device.hasError = true;
        }

        // Delay entre dispositivos
        await Future.delayed(settings.deviceDelay);
      }

      // 9) Crear Things y cargar certificados con mejoras
      final uri = Uri.parse(createThingURL);

      for (final device in devices) {
        if (device.hasError) continue;
        if (mounted) setState(() => device.currentStep = 'Creando Thing');
        final thingName = '${device.productCode}:${device.serial}';
        printLog('Creating Thing $thingName', 'amarillo');
        _addAutoLog('[${_nowTs()}] ${device.port} → Creando Thing: $thingName');

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
          if (mounted) setState(() => device.currentStep = 'Error');
          _addAutoLog('[${_nowTs()}] ${device.port} ✗ Error creando Thing: agotados ${settings.maxRetriesFlash} intentos');
          _reportLines.add(
            '${device.productCode}:${device.serial}@${device.port} ---> ERROR (Thing creation failed)',
          );
          device.resultSummary = 'Error al crear Thing (${settings.maxRetriesFlash} intentos)';
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
          device.resultSummary = 'v$versionToUpload · SN: ${device.serial} · Thing OK';
          if (mounted) setState(() => device.currentStep = 'Completado');
          _addAutoLog('[${_nowTs()}] ${device.port} ✓ Thing $thingName COMPLETADO');
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
          device.resultSummary = 'Error cargando certificados: $e';
          if (mounted) setState(() => device.currentStep = 'Error');
          _addAutoLog('[${_nowTs()}] ${device.port} ✗ Error certificados: $e');
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

  /// Parsea el progreso desde la salida de esptool
  double _parseEsptoolProgress(String line) {
    // esptool muestra progreso como: "Writing at 0x00010000... (1 %)" o similar
    final percentMatch = RegExp(r'\((\d+)\s*%\)').firstMatch(line);
    if (percentMatch != null) {
      final percent = int.tryParse(percentMatch.group(1) ?? '0') ?? 0;
      return percent / 100.0;
    }
    return -1; // No se encontró progreso
  }

  /// Flashea un dispositivo individual con reintentos y streaming de output
  Future<void> _flashDevice(
    _DeviceInfo device,
    Map<String, String> localPaths,
    String pythonExe,
  ) async {
    if (device.hasError) return;

    if (mounted) {
      setState(() {
        device.isFlashing = true;
        device.flashStatus = 'Iniciando...';
        device.flashProgress = 0.0;
        device.currentStep = 'Flash';
      });
    }

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
      '-u', // Unbuffered output para ver progreso en tiempo real
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
        if (mounted) {
          setState(() {
            device.flashStatus =
                retry > 0
                    ? 'Reintento ${retry + 1}/${settings.maxRetriesFlash}'
                    : 'Conectando...';
            device.flashProgress = 0.0;
          });
        }

        // Usar Process.start para streaming de output
        final process = await Process.start(pythonExe, args, runInShell: false);

        final stdoutBuffer = StringBuffer();
        final stderrBuffer = StringBuffer();

        // Escuchar stdout en tiempo real
        final stdoutSubscription = process.stdout
            .transform(const SystemEncoding().decoder)
            .transform(const LineSplitter())
            .listen((line) {
              stdoutBuffer.writeln(line);
              printLog('[${device.port}] stdout: $line', 'cyan');

              // Parsear progreso
              final progress = _parseEsptoolProgress(line);
              if (progress >= 0 && mounted) {
                setState(() {
                  device.flashProgress = progress;
                  device.flashStatus =
                      'Escribiendo... ${(progress * 100).toInt()}%';
                });
              }

              // Detectar etapas del proceso
              if (line.contains('Connecting')) {
                if (mounted) {
                  setState(() {
                    device.flashStatus = 'Conectando al ESP32...';
                  });
                }
              } else if (line.contains('Chip is')) {
                if (mounted) {
                  setState(() {
                    device.flashStatus = 'Chip detectado';
                  });
                }
              } else if (line.contains('Erasing flash')) {
                if (mounted) {
                  setState(() {
                    device.flashStatus = 'Borrando flash...';
                  });
                }
              } else if (line.contains('Hard resetting')) {
                if (mounted) {
                  setState(() {
                    device.flashProgress = 1.0;
                    device.flashStatus = 'Reiniciando...';
                  });
                }
              }

              // Detectar errores en tiempo real
              final lineLower = line.toLowerCase();
              if (lineLower.contains('serial exception') ||
                  lineLower.contains('write timeout') ||
                  lineLower.contains('failed to connect') ||
                  lineLower.contains('could not open port')) {
                if (mounted) {
                  setState(() {
                    device.flashStatus = '⚠ $line';
                  });
                }
              }
            });

        // Escuchar stderr en tiempo real
        final stderrSubscription = process.stderr
            .transform(const SystemEncoding().decoder)
            .transform(const LineSplitter())
            .listen((line) {
              stderrBuffer.writeln(line);
              printLog('[${device.port}] stderr: $line', 'rojo');
            });

        // Esperar a que termine el proceso con timeout
        final exitCode = await process.exitCode.timeout(
          const Duration(seconds: 120),
          onTimeout: () {
            process.kill();
            return -1;
          },
        );

        // Cancelar subscripciones
        await stdoutSubscription.cancel();
        await stderrSubscription.cancel();

        printLog('esptool exitCode=$exitCode for ${device.port}');

        if (exitCode == 0) {
          if (mounted) {
            setState(() {
              device.flashProgress = 1.0;
              device.flashStatus = '✓ Completado';
              device.isFlashing = false;
            });
          }
          showToast('Flasheo exitoso en ${device.port}');
          registerActivity(
            device.productCode,
            device.serial,
            "Flasheo exitoso con versión $versionToUpload",
          );
          device.resultSummary = 'Flash OK · v$versionToUpload';
          if (mounted) {
            setState(() {
              _reportLines.add(
                '${device.productCode}:${device.serial}@${device.port} ---> COMPLETADO (Flash)',
              );
            });
          }
          return;
        } else {
          // Construir mensaje de error detallado
          final stderrOutput = stderrBuffer.toString().trim();
          final stdoutOutput = stdoutBuffer.toString().trim();

          String reason;

          // Primero buscar en stdout ya que esptool escribe errores ahí
          final allOutput = '$stdoutOutput\n$stderrOutput';
          final allLines =
              allOutput.split('\n').where((l) => l.trim().isNotEmpty).toList();

          // Patrones de error conocidos de esptool (case insensitive)
          final errorPatterns = [
            'serial exception',
            'write timeout',
            'read timeout',
            'could not open port',
            'permission denied',
            'failed to connect',
            'no serial data',
            'invalid head of packet',
            'wrong boot mode',
            'chip sync error',
            'a]fatal error',
          ];

          // Buscar línea con patrón de error conocido
          String? foundError;
          for (final line in allLines) {
            final lineLower = line.toLowerCase();
            for (final pattern in errorPatterns) {
              if (lineLower.contains(pattern)) {
                foundError = line.trim();
                break;
              }
            }
            if (foundError != null) break;
          }

          if (foundError != null) {
            reason = foundError;
          } else {
            // Buscar cualquier línea que contenga "error" o "failed"
            final errorLine = allLines.firstWhere((line) {
              final lower = line.toLowerCase();
              return lower.contains('error') ||
                  lower.contains('failed') ||
                  lower.contains('exception');
            }, orElse: () => '');

            if (errorLine.isNotEmpty) {
              reason = errorLine.trim();
            } else {
              reason = 'Exit code $exitCode';
            }
          }

          printLog('Flash failed for ${device.port}: $reason', 'rojo');
          printLog('Full stderr: $stderrOutput', 'rojo');
          printLog('Full stdout: $stdoutOutput', 'amarillo');

          if (mounted) {
            setState(() {
              device.flashStatus = '✗ Error: $reason';
            });
          }

          if (retry < settings.maxRetriesFlash - 1) {
            printLog(
              'Retrying flash for ${device.port} (${retry + 1}/${settings.maxRetriesFlash})',
              'amarillo',
            );
            await Future.delayed(Duration(seconds: retry + 2));
          } else {
            device.hasError = true;
            device.errorMessage = reason;
            device.resultSummary = reason;
            if (mounted) {
              setState(() {
                device.isFlashing = false;
                device.currentStep = 'Error';
                device.flashStatus = '✗ $reason';
              });
            }
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
        if (mounted) {
          setState(() {
            device.flashStatus = '✗ Excepción: $e';
          });
        }
        if (retry < settings.maxRetriesFlash - 1) {
          await Future.delayed(Duration(seconds: retry + 2));
        } else {
          device.hasError = true;
          device.errorMessage = e.toString();
          device.resultSummary = e.toString();
          if (mounted) {
            setState(() {
              device.isFlashing = false;
              device.currentStep = 'Error';
              device.flashStatus = '✗ Excepción: $e';
              _reportLines.add(
                '${device.productCode}:${device.serial}@${device.port} ---> ERROR (Flash): $e',
              );
            });
          }
        }
      }
    }
  }

  /// Descarga un TXT con el log completo del proceso
  Future<void> _downloadLog() async {
    try {
      final now = DateTime.now();
      final ts =
          '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}'
          '_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final filePath = p.join(exeDir, 'log_$ts.txt');

      final lines = <String>[];
      lines.add('=' * 60);
      lines.add('Log de proceso CSLAB - $now');
      lines.add('=' * 60);
      lines.add('');
      lines.add('--- Resumen de dispositivos ---');
      for (final d in _devices) {
        lines.add('${d.port} | SN: ${d.serial} | ${d.currentStep} | ${d.resultSummary}');
      }
      lines.add('');
      lines.add('--- Log detallado ---');
      lines.addAll(_autoLog);

      await File(filePath).writeAsString(lines.join('\r\n'));
      showToast('Log guardado:\n$filePath');
      printLog('Log descargado en: $filePath', 'verde');
    } catch (e) {
      showToast('Error al guardar log: $e');
      printLog('Error descargando log: $e', 'rojo');
    }
  }

  /// Retorna timestamp HH:MM:SS actual
  String _nowTs() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
  }

  /// Agrega una línea al log detallado y hace scroll hasta el final
  void _addAutoLog(String line) {
    if (!mounted) return;
    setState(() => _autoLog.add(line));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScrollController.hasClients) {
        _logScrollController.jumpTo(_logScrollController.position.maxScrollExtent);
      }
    });
  }

  /// Envía líneas de certificado con validación y progreso visual
  /// Envía cada línea CON su salto de línea para que el dispositivo
  /// pueda reconstruir el certificado correctamente
  Future<void> _sendCertificateLines(
    _DeviceInfo device,
    String certificate,
    String certType,
    String certName,
  ) async {
    // Normalizar saltos de línea a \n y dividir
    final normalizedCert = certificate.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final lines = normalizedCert.split('\n');

    // Filtrar líneas completamente vacías
    final nonEmptyLines = lines.where((line) => line.trim().isNotEmpty).toList();

    if (mounted) {
      setState(() {
        device.currentStep = 'Certificados';
        device.certCurrentName = certName;
        device.certLinesSent = 0;
        device.certLinesTotal = nonEmptyLines.length;
      });
    }

    printLog(
      'Sending $certName to ${device.port}: ${nonEmptyLines.length} lines',
      'cyan',
    );
    _addAutoLog('[${_nowTs()}] ${device.port} → Iniciando $certName (${nonEmptyLines.length} líneas)');

    for (int i = 0; i < nonEmptyLines.length; i++) {
      final line = nonEmptyLines[i];

      // Enviar la línea CON el salto de línea al final
      // El dispositivo necesita esto para reconstruir el certificado
      final lineWithNewline = '$line\n';

      final msg = jsonEncode({"cmd": 6, "content": "$certType#$lineWithNewline"});
      final sent = await service.sendToPort(device.port, msg);

      if (!sent) {
        throw Exception(
          'Failed to send $certName line ${i + 1}/${nonEmptyLines.length}',
        );
      }

      final preview = line.length > 40 ? '${line.substring(0, 40)}...' : line;
      if (mounted) {
        setState(() {
          device.certLinesSent = i + 1;
          _autoLog.add('[${_nowTs()}] ${device.port} $certName ${i + 1}/${nonEmptyLines.length}: $preview');
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_logScrollController.hasClients) {
            _logScrollController.jumpTo(_logScrollController.position.maxScrollExtent);
          }
        });
      }

      // Delay entre líneas
      await Future.delayed(settings.certLineDelay);
    }

    _addAutoLog('[${_nowTs()}] ${device.port} ✓ $certName completado (${nonEmptyLines.length} líneas)');
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
              // Tarjetas de progreso por dispositivo
              if (_devices.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text(
                  'Progreso:',
                  style: TextStyle(fontWeight: FontWeight.bold, color: color0),
                ),
                const SizedBox(height: 8),
                ..._devices.map(
                  (device) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color:
                            device.hasError
                                ? Colors.red.withValues(alpha: 0.1)
                                : (device.currentStep == 'Completado'
                                    ? Colors.green.withValues(alpha: 0.1)
                                    : Colors.white.withValues(alpha: 0.5)),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color:
                              device.hasError
                                  ? Colors.red
                                  : (device.currentStep == 'Completado'
                                      ? Colors.green
                                      : color2),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              if (device.currentStep != 'Pendiente' &&
                                  device.currentStep != 'Completado' &&
                                  device.currentStep != 'Error')
                                const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: color2,
                                  ),
                                )
                              else if (device.hasError)
                                const Icon(
                                  Icons.error,
                                  color: Colors.red,
                                  size: 18,
                                )
                              else if (device.currentStep == 'Completado')
                                const Icon(
                                  Icons.check_circle,
                                  color: Colors.green,
                                  size: 18,
                                )
                              else
                                const Icon(
                                  Icons.pending,
                                  color: Colors.grey,
                                  size: 18,
                                ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${device.port} - SN: ${device.serial}',
                                      style: const TextStyle(
                                        color: color0,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                      ),
                                    ),
                                    Text(
                                      device.currentStep == 'Flash'
                                          ? 'Flash: ${device.flashStatus}'
                                          : device.currentStep == 'Certificados'
                                              ? '${device.certCurrentName}: ${device.certLinesSent}/${device.certLinesTotal} líneas'
                                              : device.resultSummary.isNotEmpty
                                                  ? device.resultSummary
                                                  : device.currentStep,
                                      style: TextStyle(
                                        color: device.hasError ? Colors.red : color1,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Badge del paso actual
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                decoration: BoxDecoration(
                                  color: device.hasError
                                      ? Colors.red
                                      : (device.currentStep == 'Completado'
                                          ? Colors.green
                                          : color2),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  device.currentStep,
                                  style: const TextStyle(
                                    color: color4,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          // Barra de progreso de Flash
                          if (device.flashProgress > 0) ...[
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                const Text('Flash:', style: TextStyle(color: color1, fontSize: 10)),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: LinearProgressIndicator(
                                      value: device.flashProgress,
                                      minHeight: 6,
                                      backgroundColor: Colors.grey[300],
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        device.hasError ? Colors.red : color2,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${(device.flashProgress * 100).toInt()}%',
                                  style: const TextStyle(color: color0, fontSize: 10),
                                ),
                              ],
                            ),
                          ],
                          // Barra de progreso de Certificados
                          if (device.currentStep == 'Certificados' && device.certLinesTotal > 0) ...[
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Text(
                                  '${device.certCurrentName}:',
                                  style: const TextStyle(color: color1, fontSize: 10),
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: LinearProgressIndicator(
                                      value: device.certLinesSent / device.certLinesTotal,
                                      minHeight: 6,
                                      backgroundColor: Colors.grey[300],
                                      valueColor: const AlwaysStoppedAnimation<Color>(color2),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${device.certLinesSent}/${device.certLinesTotal}',
                                  style: const TextStyle(color: color0, fontSize: 10),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ] else if (_isRunning) ...[
                const SizedBox(height: 24),
                const Center(child: CircularProgressIndicator(color: color2)),
                const SizedBox(height: 8),
                const Center(
                  child: Text('Preparando...', style: TextStyle(color: color1)),
                ),
              ],
              // Log detallado de envíos
              if (_autoLog.isNotEmpty) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text(
                      'Log de envíos:',
                      style: TextStyle(fontWeight: FontWeight.bold, color: color0),
                    ),
                    const Spacer(),
                    if (!_isRunning)
                      TextButton.icon(
                        onPressed: _downloadLog,
                        icon: const Icon(Icons.download, size: 16, color: color2),
                        label: const Text(
                          'Descargar TXT',
                          style: TextStyle(color: color2, fontSize: 12),
                        ),
                      ),
                    TextButton(
                      onPressed: () => setState(() => _autoLog.clear()),
                      child: const Text(
                        'Limpiar',
                        style: TextStyle(color: color2, fontSize: 12),
                      ),
                    ),
                  ],
                ),
                Container(
                  height: 220,
                  decoration: BoxDecoration(
                    color: color0,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ListView.builder(
                    controller: _logScrollController,
                    padding: const EdgeInsets.all(8),
                    itemCount: _autoLog.length,
                    itemBuilder: (context, i) => Text(
                      _autoLog[i],
                      style: const TextStyle(
                        color: color3,
                        fontSize: 10,
                        fontFamily: 'Courier',
                      ),
                    ),
                  ),
                ),
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
