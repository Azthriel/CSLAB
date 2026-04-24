import 'dart:convert';
import 'dart:io';
import 'package:cslab/auto.dart';
import 'package:cslab/master.dart';
import 'package:cslab/serial.dart';
import 'package:cslab/serial_log.dart';
import 'package:cslab/settings_page.dart';
import 'package:cslab/tools.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'thingmaker.dart';

class MenuPage extends StatefulWidget {
  const MenuPage({super.key});

  @override
  State<MenuPage> createState() => MenuPageState();
}

class MenuPageState extends State<MenuPage> {
  final service = SerialService();
  final settings = AppSettings();

  @override
  void initState() {
    super.initState();
    // Diferir refreshPorts para que no dispare notifyListeners durante el build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      service.refreshPorts();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Usar el context de esta ruta (dentro de MaterialApp, tiene overlay).
    fToast.init(context);
  }

  Future<void> _eraseFlash() async {
    if (service.selectedPortNames.isEmpty) {
      showToast('No hay puertos seleccionados');
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            backgroundColor: color2,
            title: const Text(
              '⚠️ Confirmar Erase Flash',
              style: TextStyle(color: color4),
            ),
            content: Text(
              '¿Borrar TODA la memoria de ${service.selectedPortNames.length} dispositivo(s)?\n\nEsto eliminará firmware, certificados y configuraciones.',
              style: const TextStyle(color: color4),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar', style: TextStyle(color: color4)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text(
                  'Borrar',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
    );

    if (confirm != true) return;

    // Verificar mounted antes de usar context
    if (!mounted) return;

    // Mostrar diálogo de progreso NO DISMISSIBLE
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => PopScope(
            canPop: false,
            child: AlertDialog(
              backgroundColor: color2,
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: color1),
                  const SizedBox(height: 16),
                  Text(
                    'Borrando flash de ${service.selectedPortNames.length} dispositivos...\n\nEsto puede tardar hasta 1 minuto por equipo.',
                    style: const TextStyle(color: color4),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
    );

    try {
      final pythonExe = p.join(
        File(Platform.resolvedExecutable).parent.path,
        'python-embed',
        'python.exe',
      );

      if (!File(pythonExe).existsSync()) {
        if (mounted) Navigator.pop(context); // Cerrar diálogo de progreso
        showToast('Python no encontrado');
        return;
      }

      await service.disconnectAll();
      await Future.delayed(const Duration(milliseconds: 2000));

      int successCount = 0;
      int failCount = 0;
      final List<String> errorDetails = [];

      // ── Erase en PARALELO ────────────────────────────────────────────────
      Future<void> erasePort(String port) async {
        final portArg =
            (port.startsWith('COM') && port.length > 4) ? r'\\.\' + port : port;
        printLog('Erasing flash on $port...', 'amarillo');

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
          '--connect-attempts',
          '5',
          'erase_flash',
        ];

        try {
          final process = await Process.start(
            pythonExe,
            args,
            runInShell: false,
          );
          final stdoutBuffer = StringBuffer();
          final stderrBuffer = StringBuffer();

          final stdoutSubscription = process.stdout
              .transform(const SystemEncoding().decoder)
              .transform(const LineSplitter())
              .listen((line) {
                stdoutBuffer.writeln(line);
                printLog('[$port] $line', 'cyan');
                final percentMatch = RegExp(r'\((\d+)\s*%\)').firstMatch(line);
                if (percentMatch != null) {
                  printLog(
                    '[$port] Erase progress: ${percentMatch.group(1)}%',
                    'verde',
                  );
                }
              });

          final stderrSubscription = process.stderr
              .transform(const SystemEncoding().decoder)
              .transform(const LineSplitter())
              .listen((line) {
                stderrBuffer.writeln(line);
                printLog('[$port] stderr: $line', 'rojo');
              });

          final exitCode = await process.exitCode.timeout(
            const Duration(seconds: 90),
            onTimeout: () {
              process.kill();
              return -1;
            },
          );
          await stdoutSubscription.cancel();
          await stderrSubscription.cancel();

          printLog('Erase exitCode=$exitCode for $port', 'cyan');

          if (exitCode == 0) {
            printLog('Erase successful on $port', 'verde');
            successCount++;
          } else {
            final allOutput =
                '${stdoutBuffer.toString().trim()}\n${stderrBuffer.toString().trim()}';
            final allLines = allOutput.split('\n');

            // Buscar mensaje de error relevante
            String errorMsg = 'Exit code $exitCode';
            for (final line in allLines) {
              final lineLower = line.toLowerCase();
              if (lineLower.contains('error') ||
                  lineLower.contains('failed') ||
                  lineLower.contains('exception') ||
                  lineLower.contains('timeout')) {
                errorMsg = line.trim();
                break;
              }
            }

            printLog('Erase FAILED on $port: $errorMsg', 'rojo');
            errorDetails.add('$port: $errorMsg');
            failCount++;
          }
        } catch (e) {
          printLog('Exception erasing $port: $e', 'rojo');
          errorDetails.add('$port: Exception - $e');
          failCount++;
        }
      }

      // Lanzar todos los erases EN PARALELO
      await Future.wait(
        service.selectedPortNames.map((port) => erasePort(port)),
      );

      // Cerrar diálogo de progreso
      if (mounted) Navigator.pop(context);

      // Mostrar resumen detallado
      if (errorDetails.isNotEmpty) {
        printLog('=== ERRORES DE ERASE ===', 'rojo');
        for (final error in errorDetails) {
          printLog(error, 'rojo');
        }
        printLog('========================', 'rojo');
      }

      showToast('Erase: $successCount OK, $failCount errores');
    } catch (e) {
      if (mounted) Navigator.pop(context); // Cerrar diálogo de progreso
      printLog('Error crítico en _eraseFlash: $e', 'rojo');
      showToast('Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Altura estimada: 100 para la config + 48 del TabBar
    const configHeight = 100.0;
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: color1,
          foregroundColor: color4,
          title: Text('CS Laboratorio $appVersionNumber'),
          actions: [
            // Botón de información del usuario
            IconButton(
              icon: const Icon(Icons.account_circle, color: color4),
              tooltip: 'Información del usuario',
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) {
                    return AlertDialog(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      backgroundColor: color1,
                      titlePadding: const EdgeInsets.all(16),
                      contentPadding: const EdgeInsets.all(16),
                      title: const Text(
                        "Información del Usuario",
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                          color: color4,
                        ),
                      ),
                      content: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Contenedor para Legajo
                            Container(
                              margin: const EdgeInsets.symmetric(vertical: 8.0),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: color2,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  const Text(
                                    "Legajo:",
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                      color: color4,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      legajoConectado,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        color: color4,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Contenedor para Nombre
                            Container(
                              margin: const EdgeInsets.symmetric(vertical: 8.0),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: color2,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  const Text(
                                    "Nombre:",
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                      color: color4,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      completeName,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        color: color4,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Contenedor para Nivel de acceso
                            Container(
                              margin: const EdgeInsets.symmetric(vertical: 8.0),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: color2,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  const Text(
                                    "Nivel de acceso:",
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                      color: color4,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      accessLevel.toString(),
                                      style: const TextStyle(
                                        fontSize: 16,
                                        color: color4,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      actions: [
                        // Botón de cerrar sesión
                        Center(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 5,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 12,
                              ),
                            ),
                            onPressed: () {
                              Navigator.of(context).pop();
                              // Limpiar variables de sesión
                              legajoConectado = '';
                              accessLevel = 0;
                              completeName = '';
                              // Navegar a login
                              Navigator.of(
                                context,
                              ).pushReplacementNamed('/login');
                            },
                            icon: const Icon(
                              Icons.logout,
                              size: 20,
                              color: color4,
                            ),
                            label: const Text(
                              "Cerrar sesión",
                              style: TextStyle(color: color4, fontSize: 16),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
            // Indicador de estado de listening
            IconButton(
              icon: Icon(
                service.isListening ? Icons.pause : Icons.play_arrow,
                color: color4,
                size: 20,
              ),
              tooltip:
                  service.isListening
                      ? 'Escuchando puertos (Click para pausar)'
                      : 'Escucha pausada (Click para iniciar)',
              onPressed: () {
                if (service.isListening) {
                  service.stopListeningAll();
                } else {
                  service.startListeningAll();
                }
                setState(() {}); // Actualizar UI
              },
            ),
            IconButton(
              icon: const Icon(Icons.settings, color: color4),
              tooltip: 'Configuraciones',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const SettingsPage()),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.list_alt, color: color4),
              tooltip: 'Ver logs',
              onPressed: () {
                showModalBottomSheet(
                  context: context,
                  backgroundColor: color0,
                  builder: (_) => const SerialLogPage(),
                );
              },
            ),
          ],
          // -----------------------------
          bottom: PreferredSize(
            preferredSize: Size.fromHeight(configHeight + 48),
            child: Column(
              children: [
                // 1) Configuración de puerto y botón
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.usb, color: color4),
                      const SizedBox(width: 8),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final menuWidth = constraints.maxWidth;
                            return PopupMenuButton<String>(
                              enabled: !service.isConnected,
                              color: color2,
                              offset: const Offset(0, 50),
                              constraints: BoxConstraints(
                                minWidth: menuWidth,
                                maxWidth: menuWidth,
                              ),
                              itemBuilder: (BuildContext context) {
                                if (service.ports.isEmpty) {
                                  return [
                                    const PopupMenuItem<String>(
                                      enabled: false,
                                      child: Text(
                                        'No hay puertos disponibles',
                                        style: TextStyle(color: color4),
                                      ),
                                    ),
                                  ];
                                }

                                return service.ports.map((port) {
                                  return PopupMenuItem<String>(
                                    enabled: false,
                                    padding: EdgeInsets.zero,
                                    child: StatefulBuilder(
                                      builder: (context, innerSetState) {
                                        final isSelected = service
                                            .selectedPortNames
                                            .contains(port.name);
                                        return InkWell(
                                          onTap: () {
                                            if (port.name != null) {
                                              if (isSelected) {
                                                service.selectedPortNames
                                                    .remove(port.name!);
                                              } else {
                                                service.selectedPortNames.add(
                                                  port.name!,
                                                );
                                              }
                                              innerSetState(() {});
                                              setState(() {});
                                            }
                                          },
                                          child: Container(
                                            width: menuWidth,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 16,
                                              vertical: 12,
                                            ),
                                            child: Row(
                                              children: [
                                                Icon(
                                                  isSelected
                                                      ? Icons.check_box
                                                      : Icons
                                                          .check_box_outline_blank,
                                                  color:
                                                      isSelected
                                                          ? color0
                                                          : color1.withValues(
                                                            alpha: 0.6,
                                                          ),
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    port.description ??
                                                        port.name ??
                                                        '',
                                                    style: TextStyle(
                                                      color: color4,
                                                      fontWeight:
                                                          isSelected
                                                              ? FontWeight.w600
                                                              : FontWeight
                                                                  .normal,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  );
                                }).toList();
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                  horizontal: 8,
                                ),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color:
                                        service.isConnected ? color3 : color4,
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                  color:
                                      service.isConnected
                                          ? color1.withValues(alpha: 0.3)
                                          : Colors.transparent,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        service.selectedPortNames.isEmpty
                                            ? 'Selecciona puertos'
                                            : service.selectedPortNames.join(
                                              ', ',
                                            ),
                                        style: TextStyle(
                                          color:
                                              service.isConnected
                                                  ? color3
                                                  : color4,
                                        ),
                                      ),
                                    ),
                                    Icon(
                                      Icons.arrow_drop_down,
                                      color:
                                          service.isConnected ? color3 : color4,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),

                      IconButton(
                        icon: const Icon(Icons.refresh, color: color4),
                        tooltip: 'Refrescar lista',
                        onPressed: () {
                          setState(() => service.refreshPorts());
                        },
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: color2,
                        ),
                        onPressed:
                            service.selectedPortNames.isEmpty
                                ? null
                                : () async {
                                  if (service.isConnected) {
                                    await service.disconnectAll();
                                    showToast(
                                      'Desconectado de todos los puertos',
                                    );
                                  } else {
                                    bool succes = service.connectMultiple();
                                    if (!succes) {
                                      showToast(
                                        'Error al conectar a los puertos seleccionados',
                                      );
                                    } else {
                                      showToast(
                                        'Conectado a los puertos seleccionados',
                                      );
                                    }
                                  }
                                  setState(() {});
                                },

                        child: Text(
                          service.isConnected ? 'Desconectar' : 'Conectar',
                        ),
                      ),
                    ],
                  ),
                ),

                // 2) Selección de Baud Rate
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.speed, color: color4),
                      const SizedBox(width: 8),
                      const Text('Baud Rate:', style: TextStyle(color: color4)),
                      const SizedBox(width: 8),
                      DropdownButton<int>(
                        dropdownColor: color2,
                        value: service.baudRate,
                        items:
                            service.ports.isEmpty
                                ? []
                                : [
                                      9600,
                                      19200,
                                      38400,
                                      57600,
                                      115200,
                                      230400,
                                      460800,
                                      576000,
                                      921600,
                                      1152000,
                                    ]
                                    .map(
                                      (b) => DropdownMenuItem(
                                        value: b,
                                        child: Text(
                                          '$b',
                                          style: const TextStyle(color: color4),
                                        ),
                                      ),
                                    )
                                    .toList(),
                        onChanged: (b) {
                          setState(() => service.baudRate = b!);
                          final message = jsonEncode({
                            'cmd': 5,
                            'content': service.baudRate,
                          });
                          service.sendMessage(message);
                        },
                      ),
                      const Spacer(),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                        onPressed:
                            service.selectedPortNames.isEmpty
                                ? null
                                : _eraseFlash,
                        icon: const Icon(Icons.delete_forever, size: 18),
                        label: const Text(
                          'Erase Flash',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ),
                ),

                // 3) La TabBar
                const TabBar(
                  indicatorColor: color4,
                  unselectedLabelColor: color2,
                  labelColor: color4,
                  tabs: [
                    Tab(text: 'Auto'),
                    Tab(text: 'Tools'),
                    Tab(text: 'Things'),
                    Tab(text: 'Serial'),
                  ],
                ),
              ],
            ),
          ),
        ),
        body: TabBarView(
          children: const [AutoPage(), ToolsPage(), ThingMaker(), SerialPage()],
        ),
      ),
    );
  }
}
