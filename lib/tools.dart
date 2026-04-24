// ignore_for_file: prefer_interpolation_to_compose_strings

import 'dart:convert';
import 'dart:io';
import 'package:cslab/firestore_service.dart';
import 'package:cslab/secret.dart';
import 'package:flutter/material.dart';
import 'package:cslab/master.dart';
import 'package:flutter/services.dart'
    show
        rootBundle,
        FilteringTextInputFormatter,
        LengthLimitingTextInputFormatter;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Modelo de dispositivo (público — también referenciado desde auto.dart)
// ─────────────────────────────────────────────────────────────────────────────

class DeviceInfo {
  final String productCode;
  final String serial;
  final String port;
  bool hasError = false;
  String errorMessage = '';
  double flashProgress = 0.0;
  String flashStatus = 'Pendiente';
  bool isFlashing = false;
  String currentStep = 'Pendiente';
  // Campos usados solo en auto.dart, pero _DeviceCard los referencia:
  String certCurrentName = '';
  int certLinesSent = 0;
  int certLinesTotal = 0;
  String resultSummary = '';

  DeviceInfo(this.productCode, this.serial, this.port);
}

// ─────────────────────────────────────────────────────────────────────────────
// ToolsPage
// ─────────────────────────────────────────────────────────────────────────────

class ToolsPage extends StatefulWidget {
  const ToolsPage({super.key});

  @override
  ToolsPageState createState() => ToolsPageState();
}

class ToolsPageState extends State<ToolsPage> {
  final service = SerialService();
  final settings = AppSettings();

  // ── Producto ───────────────────────────────────────────────────────────────
  List<String> _productCodes = [];
  Map<String, String> _pcMap = {};
  String? _selectedProductCode;
  bool _isLoadingProductCodes = false;
  bool _manualMode = false;
  final _manualCodeController = TextEditingController();

  // ── Versiones ──────────────────────────────────────────────────────────────
  List<String> _versions = [];
  String? _selectedVersion;
  bool _isLoadingVersions = false;

  // ── Flash ──────────────────────────────────────────────────────────────────
  bool _isFlashing = false;
  List<DeviceInfo> _flashDevices = [];

  // ── Números de serie ───────────────────────────────────────────────────────
  bool _isChangingSN = false;
  final _digitTens = TextEditingController(text: '0');
  final _digitUnits = TextEditingController(text: '0');
  final _focusTens = FocusNode();
  final _focusUnits = FocusNode();

  int get _startNumber =>
      (int.tryParse(_digitTens.text) ?? 0) * 10 +
      (int.tryParse(_digitUnits.text) ?? 0);

  // ── GitHub ─────────────────────────────────────────────────────────────────
  static const _owner = 'barberop';
  static const _repo = 'sime-domotica';
  static const _branch = 'main';
  static const _baseRawUrl = 'https://raw.githubusercontent.com';

  // ──────────────────────────────────────────────────────────────────────────
  // Ciclo de vida
  // ──────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    service.addListener(_onServiceChanged);
    _loadProductCodes();
  }

  @override
  void dispose() {
    _manualCodeController.dispose();
    _digitTens.dispose();
    _digitUnits.dispose();
    _focusTens.dispose();
    _focusUnits.dispose();
    service.removeListener(_onServiceChanged);
    super.dispose();
  }

  void _onServiceChanged() {
    if (mounted) setState(() {});
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Carga desde Firestore / GitHub
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> _loadProductCodes() async {
    if (mounted) setState(() => _isLoadingProductCodes = true);
    try {
      final data = await FirestoreService.getDocument('CSFABRICA', 'Data');
      if (data == null) {
        throw Exception('Documento CSFABRICA/Data no encontrado');
      }

      final rawProducts = data['Productos'];
      final codes =
          (rawProducts is List)
              ? rawProducts.map((e) => e.toString()).toList()
              : <String>[];
      codes.sort();

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
      printLog('Cargados ${codes.length} códigos de producto', 'verde');
    } catch (e) {
      printLog('Error cargando productos: $e', 'rojo');
      if (mounted) setState(() => _isLoadingProductCodes = false);
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
      final versions = await fetchAllSoftwareFolders(code);
      if (mounted) {
        setState(() {
          _versions = versions;
          _selectedVersion = versions.last;
          _isLoadingVersions = false;
        });
      }
    } catch (e) {
      printLog('Sin versiones para $code: $e', 'rojo');
      if (mounted) setState(() => _isLoadingVersions = false);
      showToast('No se encontraron versiones para "$code"');
    }
  }

  String? get _effectiveProductCode {
    if (_manualMode) {
      final t = _manualCodeController.text.trim();
      return t.isEmpty ? null : t;
    }
    return _selectedProductCode;
  }

  String _friendlyName(String code) {
    final entry = _pcMap.entries.where((e) => e.value == code).firstOrNull;
    return entry != null ? '${entry.key}  ($code)' : code;
  }

  /// Público: también lo usa AutoPage vía `ToolsPageState()`.
  Future<List<String>> fetchAllSoftwareFolders(String productCode) async {
    final uri = Uri.https(
      'api.github.com',
      '/repos/$_owner/$_repo/contents/$productCode/LAB_FILES',
      {'ref': _branch},
    );
    for (int retry = 0; retry < settings.maxRetriesFlash; retry++) {
      try {
        final response = await http
            .get(
              uri,
              headers: {
                'Authorization': 'Bearer $githubToken',
                'Accept': 'application/vnd.github.v3+json',
              },
            )
            .timeout(const Duration(seconds: 10));
        if (response.statusCode == 200) {
          final items = jsonDecode(response.body) as List<dynamic>;
          final folders =
              items
                  .where(
                    (i) =>
                        i['type'] == 'dir' &&
                        (i['name'] as String).endsWith('_F'),
                  )
                  .map<String>((i) => i['name'] as String)
                  .toList()
                ..sort();
          if (folders.isEmpty) {
            throw Exception('Sin versiones para $productCode');
          }
          return folders;
        } else if (retry < settings.maxRetriesFlash - 1) {
          await Future.delayed(Duration(seconds: retry + 1));
        }
      } catch (e) {
        if (retry < settings.maxRetriesFlash - 1) {
          await Future.delayed(Duration(seconds: retry + 1));
        } else {
          rethrow;
        }
      }
    }
    throw Exception('No se pudieron obtener versiones de $productCode');
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Flash (solo firmware, sin SN ni Thing)
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> _flashOnly() async {
    final productCode = _effectiveProductCode;
    if (productCode == null ||
        _selectedVersion == null ||
        service.selectedPortNames.isEmpty) {
      showToast('Seleccioná producto, versión y al menos un puerto');
      return;
    }

    final ports = List<String>.from(service.selectedPortNames);
    final devices =
        ports.map((port) => DeviceInfo(productCode, '', port)).toList();

    if (mounted) {
      setState(() {
        _isFlashing = true;
        _flashDevices = devices;
      });
    }

    try {
      final folderName = _selectedVersion!;
      versionToUpload = folderName;
      printLog(
        'FlashOnly: product=$productCode version=$folderName',
        'amarillo',
      );

      // Descargar bins desde GitHub
      final tempDir = await getTemporaryDirectory();
      final Map<String, String> localPaths = {};

      for (final file in ['bootloader.bin', 'partitions.bin', 'firmware.bin']) {
        final url = Uri.parse(
          '$_baseRawUrl/$_owner/$_repo/$_branch/$productCode/LAB_FILES/$folderName/$file',
        );
        printLog('Descargando $file', 'cyan');
        final response = await http.get(url);
        if (response.statusCode != 200) {
          throw Exception('Error descargando $file: ${response.statusCode}');
        }
        final outPath = p.join(tempDir.path, file);
        await File(outPath).writeAsBytes(response.bodyBytes);
        localPaths[file] = outPath;
      }

      // boot_app0.bin desde assets
      final bootData = await rootBundle.load('assets/boot_app0.bin');
      final bootPath = p.join(tempDir.path, 'boot_app0.bin');
      await File(bootPath).writeAsBytes(bootData.buffer.asUint8List());
      localPaths['boot_app0.bin'] = bootPath;
      printLog('boot_app0.bin cargado desde assets', 'verde');

      final pythonExe = p.join(
        File(Platform.resolvedExecutable).parent.path,
        'python-embed',
        'python.exe',
      );
      printLog(
        'Python: $pythonExe exists=${File(pythonExe).existsSync()}',
        'magenta',
      );

      // Cerrar puertos
      for (final port in ports) {
        try {
          await service.disconnectPort(port);
          printLog('Puerto cerrado: $port', 'verde');
        } catch (e) {
          printLog('Error cerrando $port: $e', 'rojo');
        }
      }
      await Future.delayed(const Duration(milliseconds: 2000));

      // Flash en paralelo (batches según setting)
      for (int i = 0; i < devices.length; i += settings.maxConcurrentFlash) {
        final batch =
            devices.skip(i).take(settings.maxConcurrentFlash).toList();
        printLog(
          'Batch ${i ~/ settings.maxConcurrentFlash + 1}: ${batch.length} dispositivos',
          'cyan',
        );
        await Future.wait(
          batch.map((d) => _flashDevice(d, localPaths, pythonExe)),
        );
        if (i + settings.maxConcurrentFlash < devices.length) {
          await Future.delayed(const Duration(seconds: 1));
        }
      }

      final ok = devices.where((d) => !d.hasError).length;
      final fail = devices.where((d) => d.hasError).length;
      showToast('Flash completo: $ok OK, $fail errores');
    } catch (e, st) {
      printLog('Error en flashOnly: $e\n$st', 'rojo');
      showToast('Error crítico: $e');
    } finally {
      if (mounted) setState(() => _isFlashing = false);
    }
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

    final rawPort = device.port;
    final portArg =
        (rawPort.startsWith('COM') && rawPort.length > 4)
            ? r'\\.\' + rawPort
            : rawPort;
    printLog('Flasheando $portArg', 'amarillo');

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
              final prog = _parseProgress(line);
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
              device.currentStep = 'Completado';
            });
          }
          showToast('Flash OK en ${device.port}');
          return;
        }

        // Extraer motivo de error
        final all = '${stdoutBuf.toString()}\n${stderrBuf.toString()}';
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
        ];
        String reason = 'Exit code $exitCode';
        for (final line in all.split('\n')) {
          final ll = line.toLowerCase();
          if (errorPatterns.any((p) => ll.contains(p))) {
            reason = line.trim();
            break;
          }
          if (ll.contains('error') ||
              ll.contains('failed') ||
              ll.contains('exception')) {
            reason = line.trim();
          }
        }
        if (mounted) setState(() => device.flashStatus = '✗ $reason');

        if (retry < settings.maxRetriesFlash - 1) {
          await Future.delayed(Duration(seconds: retry + 2));
        } else {
          device.hasError = true;
          device.errorMessage = reason;
          device.resultSummary = reason;
          if (mounted) {
            setState(() {
              device.isFlashing = false;
              device.currentStep = 'Error';
            });
          }
        }
      } catch (e) {
        if (mounted) setState(() => device.flashStatus = '✗ $e');
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
            });
          }
        }
      }
    }
  }

  double _parseProgress(String line) {
    final m = RegExp(r'\((\d+)\s*%\)').firstMatch(line);
    return m != null ? (int.tryParse(m.group(1) ?? '0') ?? 0) / 100.0 : -1;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Números de serie (independiente del flash)
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> _loadSerials() async {
    if (service.selectedPortNames.isEmpty) {
      showToast('No hay puertos seleccionados');
      return;
    }

    final now = DateTime.now();
    final datePart =
        '${now.year.toString().substring(2).padLeft(2, '0')}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}';

    setState(() => _isChangingSN = true);

    int counter = _startNumber;
    int ok = 0;
    int fail = 0;

    for (final portName in service.selectedPortNames) {
      final nn = counter.toString().padLeft(2, '0');
      final serialNum = '$datePart$nn';
      final msg = jsonEncode({'cmd': 4, 'content': serialNum});

      printLog('Enviando SN $serialNum → $portName');
      final sent = await service.sendToPort(portName, msg);

      if (sent) {
        showToast('SN $serialNum → $portName');
        ok++;
      } else {
        showToast('Error enviando SN a $portName');
        fail++;
      }

      counter++;
      await Future.delayed(const Duration(milliseconds: 300));
    }

    setState(() => _isChangingSN = false);
    showToast('Números de serie: $ok OK, $fail errores');
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Build
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
              // ══════════════════════════════════════════════════════════════
              // SECCIÓN: PROGRAMAR FIRMWARE
              // ══════════════════════════════════════════════════════════════
              _sectionHeader(Icons.flash_on, 'Programar Firmware'),
              const SizedBox(height: 12),

              const _Label('Código de producto'),
              const SizedBox(height: 6),
              _buildProductSelector(),
              const SizedBox(height: 16),

              const _Label('Versión de firmware'),
              const SizedBox(height: 6),
              _isLoadingVersions
                  ? const _LoadingField(label: 'Buscando versiones...')
                  : _buildDropdown(
                    value: _selectedVersion,
                    items: _versions.reversed.toList(),
                    enabled: !_isFlashing && _versions.isNotEmpty,
                    onChanged: (v) => setState(() => _selectedVersion = v),
                    hint:
                        _versions.isEmpty
                            ? 'Seleccioná un producto y buscá versiones'
                            : null,
                  ),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed:
                    (!_isFlashing &&
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
              buildButton(
                onPressed:
                    (!_isFlashing &&
                            _effectiveProductCode != null &&
                            _selectedVersion != null &&
                            service.selectedPortNames.isNotEmpty)
                        ? _flashOnly
                        : null,
                text: _isFlashing ? 'Flasheando...' : 'Flashear',
                icon: Icons.bolt,
              ),

              // Tarjetas de progreso
              if (_flashDevices.isNotEmpty) ...[
                const SizedBox(height: 16),
                const _Label('Progreso:'),
                const SizedBox(height: 8),
                ..._flashDevices.map(
                  (d) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: _DeviceCard(device: d),
                  ),
                ),
              ] else if (_isFlashing) ...[
                const SizedBox(height: 24),
                const Center(child: CircularProgressIndicator(color: color2)),
                const SizedBox(height: 8),
                const Center(
                  child: Text('Preparando...', style: TextStyle(color: color1)),
                ),
              ],

              // ══════════════════════════════════════════════════════════════
              // SECCIÓN: NÚMEROS DE SERIE
              // ══════════════════════════════════════════════════════════════
              const SizedBox(height: 32),
              _sectionHeader(Icons.tag, 'Números de Serie'),
              const SizedBox(height: 12),

              const _Label('Número inicial'),
              const SizedBox(height: 6),
              _buildDigitBoxes(),
              const SizedBox(height: 16),

              buildButton(
                onPressed:
                    (!_isChangingSN && service.selectedPortNames.isNotEmpty)
                        ? _loadSerials
                        : null,
                text: _isChangingSN ? 'Cargando...' : 'Cargar números de serie',
                icon: Icons.send,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Widget helpers
  // ──────────────────────────────────────────────────────────────────────────

  Widget _sectionHeader(IconData icon, String title) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color1,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, color: color4, size: 20),
          const SizedBox(width: 10),
          Text(
            title,
            style: const TextStyle(
              color: color4,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductSelector() {
    if (_manualMode) {
      return Row(
        children: [
          Expanded(
            child: TextField(
              controller: _manualCodeController,
              enabled: !_isFlashing,
              style: const TextStyle(color: color4),
              decoration: InputDecoration(
                hintText: 'Ingresá el código manualmente',
                hintStyle: const TextStyle(color: color3),
                filled: true,
                fillColor: color1,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 14,
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 8),
          _CircleIconButton(
            icon: Icons.list,
            tooltip: 'Usar dropdown',
            enabled: !_isFlashing,
            onPressed:
                () => setState(() {
                  _manualMode = false;
                  _manualCodeController.clear();
                }),
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          child:
              _isLoadingProductCodes
                  ? const _LoadingField(label: 'Cargando productos...')
                  : _buildDropdown(
                    value: _selectedProductCode,
                    items: _productCodes,
                    enabled: !_isFlashing && _productCodes.isNotEmpty,
                    displayBuilder: _friendlyName,
                    onChanged: (v) => setState(() => _selectedProductCode = v),
                    hint:
                        _productCodes.isEmpty
                            ? 'Sin productos en Firestore'
                            : null,
                  ),
        ),
        const SizedBox(width: 8),
        _CircleIconButton(
          icon: Icons.refresh,
          tooltip: 'Recargar productos',
          enabled: !_isFlashing && !_isLoadingProductCodes,
          onPressed: _loadProductCodes,
        ),
        const SizedBox(width: 4),
        _CircleIconButton(
          icon: Icons.edit,
          tooltip: 'Ingresar código manual',
          enabled: !_isFlashing,
          onPressed: () => setState(() => _manualMode = true),
        ),
      ],
    );
  }

  Widget _buildDigitBoxes() {
    Widget box(TextEditingController ctrl, FocusNode focus, FocusNode? next) {
      return SizedBox(
        width: 56,
        height: 56,
        child: TextField(
          controller: ctrl,
          focusNode: focus,
          enabled: !_isChangingSN,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 1,
          style: const TextStyle(
            color: color4,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(1),
          ],
          decoration: InputDecoration(
            filled: true,
            fillColor: color1,
            counterText: '',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            contentPadding: EdgeInsets.zero,
          ),
          onChanged: (v) {
            if (v.isNotEmpty && next != null) next.requestFocus();
            setState(() {});
          },
        ),
      );
    }

    return Row(
      children: [
        box(_digitTens, _focusTens, _focusUnits),
        const SizedBox(width: 8),
        box(_digitUnits, _focusUnits, null),
        const SizedBox(width: 12),
        Text(
          '→ SN empezará en $_startNumber',
          style: const TextStyle(color: color1, fontSize: 13),
        ),
      ],
    );
  }

  Widget _buildDropdown({
    required String? value,
    required List<String> items,
    required bool enabled,
    required ValueChanged<String?> onChanged,
    String? hint,
    String Function(String)? displayBuilder,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: (value != null && items.contains(value)) ? value : null,
      isExpanded: true,
      dropdownColor: color1,
      style: const TextStyle(color: color4, fontSize: 14),
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
      hint:
          hint != null
              ? Text(hint, style: const TextStyle(color: color3, fontSize: 13))
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

// ─────────────────────────────────────────────────────────────────────────────
// Widgets auxiliares
// ─────────────────────────────────────────────────────────────────────────────

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      color: color0,
      fontSize: 13,
      fontWeight: FontWeight.w600,
    ),
  );
}

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
                      device.port,
                      style: const TextStyle(
                        color: color0,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      device.flashStatus,
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
        ],
      ),
    );
  }
}
