// ignore_for_file: prefer_interpolation_to_compose_strings

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:cs_laboratorio/master.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ToolsPage extends StatefulWidget {
  const ToolsPage({super.key});

  @override
  ToolsPageState createState() => ToolsPageState();
}

class ToolsPageState extends State<ToolsPage> {
  final service = SerialService();
  final TextEditingController _productCodeController = TextEditingController();
  final TextEditingController _hwVersionController = TextEditingController();
  final TextEditingController _startNumberController = TextEditingController();

  bool _isProgramming = false;
  bool _isChangingSN = false;

  // GitHub repo configuration
  static const _owner = 'barberop';
  static const _repo = 'sime-domotica';
  static const _branch = 'main';
  static const _baseRawUrl = 'https://raw.githubusercontent.com';

  @override
  void initState() {
    super.initState();
    service.addListener(_onServiceChanged);
    // printLog('ToolsPage initialized');
  }

  void _onServiceChanged() {
    printLog(
      'SerialService state changed: ports=${service.selectedPortNames}, baud=${service.baudRate}',
    );
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _productCodeController.dispose();
    _hwVersionController.dispose();
    _startNumberController.dispose();
    service.removeListener(_onServiceChanged);
    // printLog('ToolsPage disposed');
    super.dispose();
  }

  void programSerials() {
    printLog('Starting programSerials', 'amarillo');
    int startNum = int.tryParse(_startNumberController.text) ?? 0;
    printLog('Parsed startNum: $startNum');
    final now = DateTime.now();
    final yy = now.year.toString().substring(2).padLeft(2, '0');
    final mm = now.month.toString().padLeft(2, '0');
    final dd = now.day.toString().padLeft(2, '0');
    final datePart = '$yy$mm$dd';
    printLog('Date part for SN: $datePart');

    setState(() => _isChangingSN = true);
    int counter = startNum;
    for (final portName in service.selectedPortNames) {
      final nn = counter.toString().padLeft(2, '0');
      final serialNum = '$datePart$nn';
      String msg = jsonEncode({"cmd": 4, "content": serialNum});
      printLog('Sending SN to $portName: $serialNum');
      showToast('Cargando SN $serialNum a $portName');
      service.sendToPort(portName, msg);
      counter++;
    }

    setState(() => _isChangingSN = false);
    // showToast('Cargamos SN a ${service.selectedPortNames.length} puertos');
    printLog('Finished programSerials');
  }

  /// Lista el directorio LAB_FILES en GitHub y devuelve el directorio con la última versión de software (termina con "_F")
  Future<String> fetchLatestSoftwareFolder(
    String productCode,
    String hwVersion,
  ) async {
    final path = '$productCode/LAB_FILES';
    final uri = Uri.https(
      'api.github.com',
      '/repos/$_owner/$_repo/contents/$path',
      {'ref': _branch},
    );
    printLog('Fetching LAB_FILES from: $uri', 'azul');
    final response = await http.get(
      uri,
      headers: {'Accept': 'application/vnd.github.v3+json'},
    );
    printLog('GitHub API status: ${response.statusCode}');
    if (response.statusCode != 200) {
      printLog('Error listing LAB_FILES: ${response.body}', 'rojo');
      throw Exception('Error al listar LAB_FILES: ${response.statusCode}');
    }
    final List<dynamic> items = jsonDecode(response.body);
    final prefix = 'hv${hwVersion}sv';
    final folders = <String>[];
    for (final item in items) {
      if (item['type'] == 'dir') {
        final name = item['name'] as String;
        printLog('Found item: $name', 'verde');
        final expectedLength = prefix.length + 9;
        if (name.startsWith(prefix) &&
            name.endsWith('_F') &&
            name.length == expectedLength) {
          folders.add(name);
          printLog('Accepted folder: $name', 'verde');
        }
      }
    }
    if (folders.isEmpty) {
      printLog('No matching folders found for HW $hwVersion', 'rojo');
      throw Exception(
        'No se encontró ninguna versión de software para HW $hwVersion',
      );
    }
    folders.sort();
    final latestFolder = folders.last;
    printLog('Latest software folder: $latestFolder', 'magenta');
    return latestFolder;
  }

  /// Descarga un archivo desde GitHub raw y lo guarda localmente
  Future<File> downloadFile(Uri url, String outPath) async {
    printLog('Downloading file: $url to $outPath', 'cyan');
    final response = await http.get(url);
    printLog('Download status for $url: ${response.statusCode}');
    if (response.statusCode == 200) {
      final file = File(outPath);
      await file.writeAsBytes(response.bodyBytes);
      printLog('Saved file to $outPath');
      return file;
    } else {
      printLog('Failed download: ${response.statusCode}', 'rojo');
      throw Exception('Error al descargar $outPath: ${response.statusCode}');
    }
  }

  /// Programa el ESP32-C3 flasheando los binarios descargados de la carpeta más reciente
  Future<void> programFirmware() async {
    if ((_productCodeController.text.isEmpty &&
            !_productCodeController.text.endsWith('_IOT')) ||
        _hwVersionController.text.isEmpty) {
      showToast(
        'Error: Debe ingresar el código de producto y la versión de hardware',
      );
      return;
    }
    printLog('Starting firmware program sequence', 'amarillo');
    setState(() => _isProgramming = true);

    try {
      final productCode = _productCodeController.text.trim();
      final hwVersion = _hwVersionController.text.trim();
      printLog('Inputs: productCode=$productCode, hwVersion=$hwVersion');

      // 1) Descargar bins
      final folderName = await fetchLatestSoftwareFolder(
        productCode,
        hwVersion,
      );
      printLog('Using software folder: $folderName');
      final fileNames = [
        'bootloader.bin',
        'partitions.bin',
        'boot_app0.bin',
        'firmware.bin',
      ];
      final tempDir = await getTemporaryDirectory();
      final localPaths = <String>[];
      for (final file in fileNames) {
        if (file == 'boot_app0.bin') {
          // Cargar boot_app0.bin desde assets
          final data = await rootBundle.load('assets/boot_app0.bin');
          final outPath = p.join(tempDir.path, file);
          final outFile = File(outPath);
          await outFile.writeAsBytes(data.buffer.asUint8List());
          localPaths.add(outPath);
          printLog('Saved asset $file to $outPath', 'verde');
        } else {
          final url = Uri.parse(
            '$_baseRawUrl/$_owner/$_repo/$_branch/$productCode/LAB_FILES/$folderName/$file',
          );
          final localPath = p.join(tempDir.path, file);
          final downloaded = await downloadFile(url, localPath);
          localPaths.add(downloaded.path);
        }
      }
      printLog('Downloaded paths: $localPaths');

      // 2) Determinar python embebido
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final pythonExe = p.join(exeDir, 'python-embed', 'python.exe');
      printLog(
        'Checking python executable: $pythonExe exists=${File(pythonExe).existsSync()}',
      );

      // 3) Cerrar puertos antes de flashear
      for (final port in service.selectedPortNames) {
        printLog('Closing serial port: $port', 'amarillo');
        try {
          service.disconnectPort(port);
          printLog('Port closed: $port', 'verde');
        } catch (e) {
          printLog('Error closing port $port: $e', 'rojo');
        }
      }

      // 4) Flashear con esptool
      for (final rawPort in service.selectedPortNames) {
        // Si el nombre es COM con número >=10, usa el prefijo \\.\COMxx
        final port =
            (rawPort.startsWith('COM') && rawPort.length > 4)
                ? r'\\.\' + rawPort
                : rawPort;

        printLog('Flashing port: $port at baud 576000');
        final args = [
          '-m',
          'esptool',
          '--chip',
          'esp32c3',
          '--port',
          port,
          '--baud',
          '576000',
          '--before',
          'default_reset',
          '--after',
          'hard_reset',
          'write_flash',
          '-z',
          '0x0000',
          localPaths[0],
          '0x8000',
          localPaths[1],
          '0xE000',
          localPaths[2],
          '0x10000',
          localPaths[3],
        ];
        printLog('esptool args: $args');

        printLog('Running esptool...');
        final result = await Process.run(pythonExe, args);
        printLog('esptool result.exitCode=${result.exitCode}');
        if (result.stdout.isNotEmpty) printLog('stdout: ${result.stdout}');
        if (result.stderr.isNotEmpty) {
          printLog('stderr: ${result.stderr}', 'rojo');
        }

        if (result.exitCode != 0) {
          showToast('Error flasheando $rawPort: ${result.stderr}');
        } else {
          showToast('Flasheo exitoso en $rawPort');
        }
      }
    } catch (e, st) {
      printLog('Exception in programFirmware: $e\n$st', 'rojo');
      showToast('Error: $e');
    } finally {
      setState(() => _isProgramming = false);
      printLog('Finished programFirmware', 'verde');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: color4,
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          scrollDirection: Axis.vertical,
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
              buildButton(
                text: _isProgramming ? 'Programando...' : 'Programar',
                onPressed:
                    service.selectedPortNames.isEmpty || _isProgramming
                        ? null
                        : programFirmware,
              ),
              const SizedBox(height: 16),
              buildText(
                text: 'Números de serie a cargar',
                fontWeight: FontWeight.bold,
              ),
              const SizedBox(height: 16),
              buildTextField(
                label: 'Número inicial',
                controller: _startNumberController,
                keyboard: TextInputType.number,
              ),
              const SizedBox(height: 16),
              buildButton(
                onPressed:
                    service.selectedPortNames.isEmpty || _isChangingSN
                        ? null
                        : programSerials,
                text:
                    _isChangingSN
                        ? 'Cargando números de serie...'
                        : 'Cargar números de serie',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
