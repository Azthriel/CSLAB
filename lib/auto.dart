// auto.dart

import 'dart:convert';
import 'dart:io';
import 'package:cslab/firestore_service.dart';
import 'package:cslab/secret.dart';
import 'package:cslab/tools.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show
        rootBundle,
        FilteringTextInputFormatter,
        LengthLimitingTextInputFormatter;
import 'package:cslab/master.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Representa un dispositivo a crear:

class AutoPage extends StatefulWidget {
  const AutoPage({super.key});

  @override
  AutoPageState createState() => AutoPageState();
}

class AutoPageState extends State<AutoPage> {
  final service = SerialService();
  final settings = AppSettings();

  // ── Producto ──────────────────────────────────────────────────────────────
  List<String> _productCodes = []; // array Productos de Firestore
  Map<String, String> _pcMap = {}; // nombre amigable → code  (campo PC)
  String? _selectedProductCode;
  bool _isLoadingProductCodes = false;
  bool _manualMode = false; // toggle ingreso manual
  final _manualCodeController = TextEditingController();

  // ── Versiones ─────────────────────────────────────────────────────────────
  List<String> _versions = [];
  String? _selectedVersion;
  bool _isLoadingVersions = false;

  // ── Número inicial (digit boxes 0-99) ─────────────────────────────────────
  final _digitTens = TextEditingController(text: '0');
  final _digitUnits = TextEditingController(text: '0');
  final _focusTens = FocusNode();
  final _focusUnits = FocusNode();

  /// Valor combinado de las dos cajas (0-99)
  int get _startNumber =>
      (int.tryParse(_digitTens.text) ?? 0) * 10 +
      (int.tryParse(_digitUnits.text) ?? 0);

  bool _isRunning = false;
  // ignore: prefer_final_fields
  List<String> _reportLines = [];
  List<DeviceInfo> _devices = [];
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
    _loadProductCodes();
  }

  void _onServiceChanged() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    service.removeListener(_onServiceChanged);
    _manualCodeController.dispose();
    _digitTens.dispose();
    _digitUnits.dispose();
    _focusTens.dispose();
    _focusUnits.dispose();
    _logScrollController.dispose();
    super.dispose();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Carga de datos
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> _loadProductCodes() async {
    if (mounted) setState(() => _isLoadingProductCodes = true);
    try {
      final data = await FirestoreService.getDocument('CSFABRICA', 'Data');
      if (data == null) {
        throw Exception('Documento CSFABRICA/Data no encontrado');
      }

      // Productos: array de strings
      final rawProducts = data['Productos'];
      final codes =
          (rawProducts is List)
              ? rawProducts.map((e) => e.toString()).toList()
              : <String>[];
      codes.sort();

      // PC: mapa nombre amigable → code
      final rawPc = data['PC'];
      final pcMap =
          (rawPc is Map)
              ? rawPc.map((k, v) => MapEntry(k.toString(), v.toString()))
              : <String, String>{};

      if (mounted) {
        setState(() {
          _productCodes = codes;
          _pcMap = pcMap;
          _isLoadingProductCodes = false;
        });
      }
      printLog('Loaded ${codes.length} product codes from Firestore', 'verde');
    } catch (e) {
      printLog('Error loading product codes: $e', 'rojo');
      if (mounted) setState(() => _isLoadingProductCodes = false);
      showToast('Error al cargar productos: $e');
    }
  }

  Future<void> _loadVersions() async {
    final code = _effectiveProductCode;
    if (code == null || code.isEmpty) {
      showToast('Seleccioná o ingresá un código de producto primero');
      return;
    }
    if (mounted) {
      setState(() {
        _versions = [];
        _selectedVersion = null;
        _isLoadingVersions = true;
      });
    }
    try {
      final versions = await ToolsPageState().fetchAllSoftwareFolders(code);
      if (mounted) {
        setState(() {
          _versions = versions;
          _selectedVersion = versions.last;
          _isLoadingVersions = false;
        });
      }
      printLog('Loaded ${versions.length} version(s) for $code', 'verde');
    } catch (e) {
      printLog('No versions found for $code: $e', 'rojo');
      if (mounted) setState(() => _isLoadingVersions = false);
      showToast('No se encontraron versiones de firmware para "$code"');
    }
  }

  /// Código de producto activo (dropdown o campo manual)
  String? get _effectiveProductCode {
    if (_manualMode) {
      final t = _manualCodeController.text.trim();
      return t.isEmpty ? null : t;
    }
    return _selectedProductCode;
  }

  /// Texto que muestra el dropdown: "Nombre (CODE)" si existe en el mapa PC
  String _friendlyName(String code) {
    final entry = _pcMap.entries.where((e) => e.value == code).firstOrNull;
    return entry != null ? '${entry.key}  ($code)' : code;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Proceso principal
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> _runAll() async {
    final productCode = _effectiveProductCode;
    if (productCode == null ||
        _selectedVersion == null ||
        service.selectedPortNames.isEmpty) {
      showToast('Seleccioná producto, versión y al menos un puerto');
      return;
    }

    setState(() {
      _isRunning = true;
      _reportLines.clear();
      _autoLog.clear();
    });

    try {
      final folderName = _selectedVersion!;
      int serialCounter = _startNumber;
      printLog(
        'RunAll: productCode=$productCode, version=$folderName, startNum=$serialCounter',
        'amarillo',
      );

      final ports = List<String>.from(service.selectedPortNames);
      final devices = <DeviceInfo>[];
      final now = DateTime.now();
      final yy = now.year.toString().substring(2).padLeft(2, '0');
      final mm = now.month.toString().padLeft(2, '0');
      final dd = now.day.toString().padLeft(2, '0');

      for (final port in ports) {
        final nn = serialCounter.toString().padLeft(2, '0');
        devices.add(DeviceInfo(productCode, '$yy$mm$dd$nn', port));
        serialCounter++;
      }
      if (mounted) setState(() => _devices = devices);

      versionToUpload = folderName;
      printLog('Using SW folder: $folderName', 'verde');

      // Descargar firmware
      final tempDir = await getTemporaryDirectory();
      final Map<String, String> localPaths = {};
      for (final file in ['bootloader.bin', 'partitions.bin', 'firmware.bin']) {
        final url = Uri.parse(
          '$_baseRawUrl/$_owner/$_repo/$_branch/$productCode/LAB_FILES/$folderName/$file',
        );
        final outPath = p.join(tempDir.path, file);
        printLog('Downloading $file', 'cyan');
        final response = await http.get(url);
        if (response.statusCode != 200) {
          throw Exception('Error descargando $file: ${response.statusCode}');
        }
        await File(outPath).writeAsBytes(response.bodyBytes);
        localPaths[file] = outPath;
      }
      // boot_app0.bin desde assets
      {
        final data = await rootBundle.load('assets/boot_app0.bin');
        final outPath = p.join(tempDir.path, 'boot_app0.bin');
        await File(outPath).writeAsBytes(data.buffer.asUint8List());
        localPaths['boot_app0.bin'] = outPath;
        printLog('Loaded boot_app0.bin from assets', 'verde');
      }

      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final pythonExe = p.join(exeDir, 'python-embed', 'python.exe');
      printLog(
        'Python: $pythonExe exists=${File(pythonExe).existsSync()}',
        'magenta',
      );

      // Cerrar puertos
      for (final port in ports) {
        try {
          await service.disconnectPort(port);
          printLog('Port closed: $port', 'verde');
        } catch (e) {
          printLog('Error closing port $port: $e', 'rojo');
        }
      }
      await Future.delayed(const Duration(milliseconds: 2000));

      // Flash paralelo
      for (int i = 0; i < devices.length; i += settings.maxConcurrentFlash) {
        final batch =
            devices.skip(i).take(settings.maxConcurrentFlash).toList();
        printLog(
          'Flashing batch ${i ~/ settings.maxConcurrentFlash + 1}: ${batch.length} devices',
          'cyan',
        );
        await Future.wait(
          batch.map((d) => _flashDevice(d, localPaths, pythonExe)),
        );
        if (i + settings.maxConcurrentFlash < devices.length) {
          await Future.delayed(const Duration(seconds: 1));
        }
      }
      await Future.delayed(const Duration(seconds: 2));

      // Número de serie
      for (final device in devices) {
        if (device.hasError) continue;
        if (mounted) setState(() => device.currentStep = 'Nº de Serie');
        _addAutoLog(
          '[${_nowTs()}] ${device.port} → Enviando Nº de Serie: ${device.serial}',
        );

        final connected = await service.connectPort(device.port);
        if (!connected) {
          _setDeviceError(device, 'No se pudo reconectar al puerto');
          _reportLines.add(
            '${device.productCode}:${device.serial}@${device.port} ---> ERROR (reconnect)',
          );
          continue;
        }
        await Future.delayed(const Duration(milliseconds: 500));

        try {
          final sent = await service.sendToPort(
            device.port,
            jsonEncode({"cmd": 4, "content": device.serial}),
          );
          if (sent) {
            registerActivity(
              device.productCode,
              device.serial,
              "Se le envió número de serie",
            );
            showToast('SN ${device.serial} enviado a ${device.port}');
            _addAutoLog(
              '[${_nowTs()}] ${device.port} ✓ Nº de Serie: ${device.serial}',
            );
            _reportLines.add(
              '${device.productCode}:${device.serial}@${device.port} ---> COMPLETADO (SerialNumber)',
            );
          } else {
            throw Exception('Failed to send serial number');
          }
        } catch (e) {
          registerActivity(
            device.productCode,
            device.serial,
            "Error enviando número de serie: $e",
          );
          _reportLines.add(
            '${device.productCode}:${device.serial}@${device.port} ---> ERROR (SerialNumber): $e',
          );
          _setDeviceError(device, 'Error N° de Serie: $e');
        }
        await Future.delayed(settings.deviceDelay);
      }

      // Things y certificados
      final uri = Uri.parse(createThingURL);
      for (final device in devices) {
        if (device.hasError) continue;
        if (mounted) setState(() => device.currentStep = 'Creando Thing');
        final thingName = '${device.productCode}:${device.serial}';
        _addAutoLog('[${_nowTs()}] ${device.port} → Creando Thing: $thingName');

        Map<String, dynamic>? payload;
        for (int retry = 0; retry < settings.maxRetriesFlash; retry++) {
          try {
            final response = await http
                .post(uri, body: jsonEncode({'thingName': thingName}))
                .timeout(const Duration(seconds: 10));
            if (response.statusCode == 200) {
              final jr = jsonDecode(response.body) as Map<String, dynamic>;
              payload =
                  jsonDecode(jr['body'] as String) as Map<String, dynamic>;
              break;
            } else if (retry < settings.maxRetriesFlash - 1) {
              await Future.delayed(Duration(seconds: retry + 1));
            }
          } catch (e) {
            if (retry < settings.maxRetries - 1) {
              await Future.delayed(Duration(seconds: retry + 1));
            }
          }
        }

        if (payload == null) {
          registerActivity(
            device.productCode,
            device.serial,
            "Error al crear Thing: agotados ${settings.maxRetriesFlash} intentos",
          );
          _addAutoLog('[${_nowTs()}] ${device.port} ✗ Error creando Thing');
          _reportLines.add(
            '${device.productCode}:${device.serial}@${device.port} ---> ERROR (Thing creation failed)',
          );
          _setDeviceError(
            device,
            'Error al crear Thing (${settings.maxRetriesFlash} intentos)',
          );
          continue;
        }

        try {
          await _sendCertificateLines(
            device,
            payload['amazonCA'] as String,
            '0',
            'AmazonCA',
          );
          await _sendCertificateLines(
            device,
            payload['deviceCert'] as String,
            '1',
            'DeviceCert',
          );
          await _sendCertificateLines(
            device,
            payload['privateKey'] as String,
            '2',
            'PrivateKey',
          );
          registerActivity(
            device.productCode,
            device.serial,
            "Se le cargo Thing desde CSLAB",
          );
          device.resultSummary =
              'v$versionToUpload · SN: ${device.serial} · Thing OK';
          if (mounted) setState(() => device.currentStep = 'Completado');
          _addAutoLog(
            '[${_nowTs()}] ${device.port} ✓ Thing $thingName COMPLETADO',
          );
          _reportLines.add(
            '${device.productCode}:${device.serial}@${device.port} ---> COMPLETADO (Thing)',
          );
        } catch (e) {
          registerActivity(
            device.productCode,
            device.serial,
            "Error cargando Thing: $e",
          );
          _addAutoLog('[${_nowTs()}] ${device.port} ✗ Error certificados: $e');
          _reportLines.add(
            '${device.productCode}:${device.serial}@${device.port} ---> ERROR (Certificates): $e',
          );
          _setDeviceError(device, 'Error cargando certificados: $e');
        }
        await Future.delayed(settings.deviceDelay);
      }

      // Reporte
      final ok = devices.where((d) => !d.hasError).length;
      final fail = devices.where((d) => d.hasError).length;
      final reportFile = File(
        p.join(File(Platform.resolvedExecutable).parent.path, 'report.txt'),
      );
      await reportFile.writeAsString(
        [
          '=' * 60,
          'Reporte de Programación - ${DateTime.now()}',
          'Total: ${devices.length} | OK: $ok | Errores: $fail',
          '=' * 60,
          '',
          ..._reportLines,
        ].join('\r\n'),
      );
      showToast('Proceso completo. $ok OK, $fail errores. Ver report.txt');
    } catch (e, st) {
      printLog('Error en runAll: $e\n$st', 'rojo');
      showToast('Error crítico en proceso: $e');
      _reportLines.add('ERROR CRÍTICO: $e');
    } finally {
      if (mounted) setState(() => _isRunning = false);
      printLog('runAll finished', 'verde');
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Helpers
  // ──────────────────────────────────────────────────────────────────────────

  void _setDeviceError(DeviceInfo device, String message) {
    device.hasError = true;
    device.resultSummary = message;
    if (mounted) setState(() => device.currentStep = 'Error');
  }

  double _parseEsptoolProgress(String line) {
    final m = RegExp(r'\((\d+)\s*%\)').firstMatch(line);
    return m != null ? (int.tryParse(m.group(1) ?? '0') ?? 0) / 100.0 : -1;
  }

  Future<void> _flashDevice(
    DeviceInfo device,
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
      '-u',
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

        final process = await Process.start(pythonExe, args, runInShell: false);
        final stdoutBuf = StringBuffer();
        final stderrBuf = StringBuffer();

        final outSub = process.stdout
            .transform(const SystemEncoding().decoder)
            .transform(const LineSplitter())
            .listen((line) {
              stdoutBuf.writeln(line);
              printLog('[${device.port}] $line', 'cyan');
              final prog = _parseEsptoolProgress(line);
              if (prog >= 0 && mounted) {
                setState(() {
                  device.flashProgress = prog;
                  device.flashStatus =
                      'Escribiendo... ${(prog * 100).toInt()}%';
                });
              }
              if (line.contains('Connecting') && mounted) {
                setState(() => device.flashStatus = 'Conectando al ESP32...');
              } else if (line.contains('Chip is') && mounted) {
                setState(() => device.flashStatus = 'Chip detectado');
              } else if (line.contains('Erasing flash') && mounted) {
                setState(() => device.flashStatus = 'Borrando flash...');
              } else if (line.contains('Hard resetting') && mounted) {
                setState(() {
                  device.flashProgress = 1.0;
                  device.flashStatus = 'Reiniciando...';
                });
              }
              final ll = line.toLowerCase();
              if ((ll.contains('serial exception') ||
                      ll.contains('write timeout') ||
                      ll.contains('failed to connect') ||
                      ll.contains('could not open port')) &&
                  mounted) {
                setState(() => device.flashStatus = '⚠ $line');
              }
            });
        final errSub = process.stderr
            .transform(const SystemEncoding().decoder)
            .transform(const LineSplitter())
            .listen((line) {
              stderrBuf.writeln(line);
              printLog('[${device.port}] stderr: $line', 'rojo');
            });

        final exitCode = await process.exitCode.timeout(
          const Duration(seconds: 120),
          onTimeout: () {
            process.kill();
            return -1;
          },
        );
        await outSub.cancel();
        await errSub.cancel();

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
            setState(
              () => _reportLines.add(
                '${device.productCode}:${device.serial}@${device.port} ---> COMPLETADO (Flash)',
              ),
            );
          }
          return;
        }

        final allOutput =
            '${stdoutBuf.toString().trim()}\n${stderrBuf.toString().trim()}';
        final allLines =
            allOutput.split('\n').where((l) => l.trim().isNotEmpty).toList();
        const errorPatterns = [
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
        ];
        String? foundError;
        for (final line in allLines) {
          final ll = line.toLowerCase();
          for (final pat in errorPatterns) {
            if (ll.contains(pat)) {
              foundError = line.trim();
              break;
            }
          }
          if (foundError != null) break;
        }
        final reason =
            foundError ??
            allLines.firstWhere((l) {
              final ll = l.toLowerCase();
              return ll.contains('error') ||
                  ll.contains('failed') ||
                  ll.contains('exception');
            }, orElse: () => 'Exit code $exitCode').trim();

        if (mounted) setState(() => device.flashStatus = '✗ Error: $reason');

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
              _reportLines.add(
                '${device.productCode}:${device.serial}@${device.port} ---> ERROR (Flash): $reason',
              );
            });
          }
          registerActivity(
            device.productCode,
            device.serial,
            "Error en flasheo: $reason",
          );
        }
      } catch (e) {
        printLog('Exception flashing ${device.port}: $e', 'rojo');
        if (mounted) setState(() => device.flashStatus = '✗ Excepción: $e');
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

  Future<void> _downloadLog() async {
    try {
      final now = DateTime.now();
      final ts =
          '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
      final filePath = p.join(
        File(Platform.resolvedExecutable).parent.path,
        'log_$ts.txt',
      );
      await File(filePath).writeAsString(
        [
          '=' * 60,
          'Log CSLAB - $now',
          '=' * 60,
          '',
          '--- Dispositivos ---',
          ..._devices.map(
            (d) =>
                '${d.port} | SN: ${d.serial} | ${d.currentStep} | ${d.resultSummary}',
          ),
          '',
          '--- Log ---',
          ..._autoLog,
        ].join('\r\n'),
      );
      showToast('Log guardado:\n$filePath');
    } catch (e) {
      showToast('Error al guardar log: $e');
    }
  }

  String _nowTs() {
    final n = DateTime.now();
    return '${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}:${n.second.toString().padLeft(2, '0')}';
  }

  void _addAutoLog(String line) {
    if (!mounted) return;
    setState(() => _autoLog.add(line));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScrollController.hasClients) {
        _logScrollController.jumpTo(
          _logScrollController.position.maxScrollExtent,
        );
      }
    });
  }

  Future<void> _sendCertificateLines(
    DeviceInfo device,
    String certificate,
    String certType,
    String certName,
  ) async {
    final lines =
        certificate
            .replaceAll('\r\n', '\n')
            .replaceAll('\r', '\n')
            .split('\n')
            .where((l) => l.trim().isNotEmpty)
            .toList();
    if (mounted) {
      setState(() {
        device.currentStep = 'Certificados';
        device.certCurrentName = certName;
        device.certLinesSent = 0;
        device.certLinesTotal = lines.length;
      });
    }
    printLog(
      'Sending $certName to ${device.port}: ${lines.length} lines',
      'cyan',
    );
    _addAutoLog(
      '[${_nowTs()}] ${device.port} → Iniciando $certName (${lines.length} líneas)',
    );
    for (int i = 0; i < lines.length; i++) {
      final sent = await service.sendToPort(
        device.port,
        jsonEncode({"cmd": 6, "content": "$certType#${lines[i]}\n"}),
      );
      if (!sent) {
        throw Exception(
          'Failed to send $certName line ${i + 1}/${lines.length}',
        );
      }
      final preview =
          lines[i].length > 40 ? '${lines[i].substring(0, 40)}...' : lines[i];
      if (mounted) {
        setState(() {
          device.certLinesSent = i + 1;
          _autoLog.add(
            '[${_nowTs()}] ${device.port} $certName ${i + 1}/${lines.length}: $preview',
          );
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_logScrollController.hasClients) {
            _logScrollController.jumpTo(
              _logScrollController.position.maxScrollExtent,
            );
          }
        });
      }
      await Future.delayed(settings.certLineDelay);
    }
    _addAutoLog(
      '[${_nowTs()}] ${device.port} ✓ $certName completado (${lines.length} líneas)',
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // UI
  // ──────────────────────────────────────────────────────────────────────────

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
              // ── Producto ──────────────────────────────────────────────────
              const Text(
                'Código de producto',
                style: TextStyle(
                  color: color0,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              _buildProductSelector(),
              const SizedBox(height: 16),

              // ── Versión ───────────────────────────────────────────────────
              const Text(
                'Versión de firmware',
                style: TextStyle(
                  color: color0,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              _isLoadingVersions
                  ? const _LoadingField(label: 'Buscando versiones...')
                  : _buildDropdown(
                    value: _selectedVersion,
                    items: _versions.reversed.toList(),
                    enabled: !_isRunning && _versions.isNotEmpty,
                    onChanged: (v) => setState(() => _selectedVersion = v),
                    hint:
                        _versions.isEmpty
                            ? 'Seleccioná un producto y buscá versiones'
                            : null,
                  ),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed:
                    (!_isRunning &&
                            !_isLoadingVersions &&
                            _effectiveProductCode != null)
                        ? _loadVersions
                        : null,
                icon: const Icon(Icons.search, size: 18),
                label: const Text('Buscar versiones'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: color1,
                  foregroundColor: color4,
                  disabledBackgroundColor: color1.withValues(alpha: 0.4),
                  disabledForegroundColor: color3.withValues(alpha: 0.5),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  elevation: 0,
                ),
              ),
              const SizedBox(height: 16),

              // ── Número inicial ────────────────────────────────────────────
              const Text(
                'Número inicial',
                style: TextStyle(
                  color: color0,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              _buildDigitBoxes(),
              const SizedBox(height: 24),

              buildButton(
                onPressed: _isRunning ? null : _runAll,
                text: _isRunning ? 'Procesando...' : 'Iniciar',
              ),
              const SizedBox(height: 24),

              // ── Progreso por dispositivo ──────────────────────────────────
              if (_devices.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text(
                  'Progreso:',
                  style: TextStyle(fontWeight: FontWeight.bold, color: color0),
                ),
                const SizedBox(height: 8),
                ..._devices.map(
                  (d) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: _DeviceCard(device: d),
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

              // ── Log ───────────────────────────────────────────────────────
              if (_autoLog.isNotEmpty) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text(
                      'Log de envíos:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: color0,
                      ),
                    ),
                    const Spacer(),
                    if (!_isRunning)
                      TextButton.icon(
                        onPressed: _downloadLog,
                        icon: const Icon(
                          Icons.download,
                          size: 16,
                          color: color2,
                        ),
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
                    itemBuilder:
                        (_, i) => Text(
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

  // ── Digit boxes para número inicial ──────────────────────────────────────
  Widget _buildDigitBoxes() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        _buildSingleDigit(_digitTens, _focusTens, nextFocus: _focusUnits),
        const SizedBox(width: 12),
        _buildSingleDigit(_digitUnits, _focusUnits),
      ],
    );
  }

  Widget _buildSingleDigit(
    TextEditingController controller,
    FocusNode focusNode, {
    FocusNode? nextFocus,
  }) {
    return SizedBox(
      width: 64,
      height: 64,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        enabled: !_isRunning,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        maxLength: 1,
        style: const TextStyle(
          color: color4,
          fontSize: 28,
          fontWeight: FontWeight.bold,
        ),
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(1),
        ],
        decoration: InputDecoration(
          filled: true,
          fillColor: color2,
          counterText: '',
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: EdgeInsets.zero,
        ),
        onChanged: (value) {
          if (value.isNotEmpty && nextFocus != null) {
            nextFocus.requestFocus();
          }
          setState(() {}); // refresca _startNumber
        },
      ),
    );
  }

  // ── Selector de producto (dropdown + botones / campo manual) ──────────────
  Widget _buildProductSelector() {
    if (_isLoadingProductCodes) {
      return const _LoadingField(label: 'Cargando productos...');
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child:
              _manualMode
                  ? buildTextField(
                    label: 'Código de producto (manual)',
                    controller: _manualCodeController,
                  )
                  : _buildDropdown(
                    value: _selectedProductCode,
                    items: _productCodes,
                    enabled: !_isRunning,
                    displayBuilder: _friendlyName,
                    onChanged:
                        (v) => setState(() {
                          _selectedProductCode = v;
                          _versions = [];
                          _selectedVersion = null;
                        }),
                  ),
        ),
        const SizedBox(width: 8),
        if (!_manualMode) ...[
          _CircleIconButton(
            icon: Icons.refresh,
            tooltip: 'Recargar productos',
            enabled: !_isRunning,
            onPressed: _loadProductCodes,
          ),
          const SizedBox(width: 4),
          _CircleIconButton(
            icon: Icons.edit,
            tooltip: 'Ingresar código manual',
            enabled: !_isRunning,
            onPressed:
                () => setState(() {
                  _manualCodeController.text = _selectedProductCode ?? '';
                  _manualMode = true;
                }),
          ),
        ] else ...[
          _CircleIconButton(
            icon: Icons.check,
            tooltip: 'Confirmar',
            enabled: true,
            onPressed:
                () => setState(() {
                  _manualMode = false;
                  _versions = [];
                  _selectedVersion = null;
                }),
          ),
          const SizedBox(width: 4),
          _CircleIconButton(
            icon: Icons.close,
            tooltip: 'Cancelar',
            enabled: true,
            onPressed:
                () => setState(() {
                  _manualMode = false;
                  _manualCodeController.clear();
                }),
          ),
        ],
      ],
    );
  }

  Widget _buildDropdown({
    required String? value,
    required List<String> items,
    required bool enabled,
    required ValueChanged<String?> onChanged,
    String Function(String)? displayBuilder,
    String? hint,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        filled: true,
        fillColor: color1,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
      ),
      dropdownColor: color0,
      iconEnabledColor: color4,
      iconDisabledColor: color3.withValues(alpha: 0.4),
      style: TextStyle(
        color: enabled ? color4 : color3.withValues(alpha: 0.5),
        fontSize: 15,
      ),
      hint:
          hint != null
              ? Text(
                hint,
                style: TextStyle(
                  color: color3.withValues(alpha: 0.8),
                  fontSize: 14,
                ),
              )
              : null,
      items:
          items
              .map(
                (item) => DropdownMenuItem(
                  value: item,
                  child: Text(
                    displayBuilder != null ? displayBuilder(item) : item,
                    style: const TextStyle(color: color4),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
      onChanged: enabled ? onChanged : null,
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Widgets auxiliares
// ────────────────────────────────────────────────────────────────────────────

class _LoadingField extends StatelessWidget {
  final String label;
  const _LoadingField({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: color1,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: color2),
          ),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(color: color3, fontSize: 14)),
        ],
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback onPressed;

  const _CircleIconButton({
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: enabled ? color2 : color1,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: enabled ? onPressed : null,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(
              icon,
              size: 20,
              color: enabled ? color4 : color3.withValues(alpha: 0.4),
            ),
          ),
        ),
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  final DeviceInfo device;
  const _DeviceCard({required this.device});

  @override
  Widget build(BuildContext context) {
    final isActive =
        device.currentStep != 'Pendiente' &&
        device.currentStep != 'Completado' &&
        device.currentStep != 'Error';
    Color borderColor = color2;
    Color bgColor = Colors.white.withValues(alpha: 0.5);
    if (device.hasError) {
      borderColor = Colors.red;
      bgColor = Colors.red.withValues(alpha: 0.1);
    } else if (device.currentStep == 'Completado') {
      borderColor = Colors.green;
      bgColor = Colors.green.withValues(alpha: 0.1);
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (isActive)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: color2,
                  ),
                )
              else if (device.hasError)
                const Icon(Icons.error, color: Colors.red, size: 18)
              else if (device.currentStep == 'Completado')
                const Icon(Icons.check_circle, color: Colors.green, size: 18)
              else
                const Icon(Icons.pending, color: Colors.grey, size: 18),
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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color:
                      device.hasError
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
          if (device.flashProgress > 0) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Text(
                  'Flash:',
                  style: TextStyle(color: color1, fontSize: 10),
                ),
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
          if (device.currentStep == 'Certificados' &&
              device.certLinesTotal > 0) ...[
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
    );
  }
}
