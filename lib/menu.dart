import 'dart:convert';

import 'package:cs_laboratorio/auto.dart';
import 'package:cs_laboratorio/master.dart';
import 'package:cs_laboratorio/serial.dart';
import 'package:cs_laboratorio/serial_log.dart';
import 'package:cs_laboratorio/tools.dart';
import 'package:flutter/material.dart';
import 'thingmaker.dart';

class MenuPage extends StatefulWidget {
  const MenuPage({super.key});

  @override
  State<MenuPage> createState() => MenuPageState();
}

class MenuPageState extends State<MenuPage> {
  final service = SerialService();
  @override
  void initState() {
    super.initState();
    service.refreshPorts();

    if (mounted) {
      fToast.init(navigatorKey.currentState!.context);
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
            IconButton(
              icon: const Icon(Icons.list_alt, color: color4),
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
                            return InkWell(
                              onTap: () async {
                                final button =
                                    context.findRenderObject() as RenderBox;
                                final overlay =
                                    Overlay.of(
                                          context,
                                        ).context.findRenderObject()
                                        as RenderBox;
                                final rect = RelativeRect.fromRect(
                                  Rect.fromPoints(
                                    button.localToGlobal(
                                      Offset.zero,
                                      ancestor: overlay,
                                    ),
                                    button.localToGlobal(
                                      button.size.bottomRight(Offset.zero),
                                      ancestor: overlay,
                                    ),
                                  ),
                                  Offset.zero & overlay.size,
                                );

                                final seleccionado = await showMenu<String>(
                                  context: context,
                                  position: rect,
                                  constraints: BoxConstraints.tightFor(
                                    width: menuWidth,
                                  ),
                                  color: color2,
                                  items:
                                      service.ports.map((port) {
                                        final isSel = service.selectedPortNames
                                            .contains(port.name);
                                        return PopupMenuItem<String>(
                                          value: port.name,
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.check,
                                                color:
                                                    isSel
                                                        ? color5
                                                        : Colors.transparent,
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  port.description ??
                                                      port.name ??
                                                      '',
                                                  style: const TextStyle(
                                                    color: color4,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      }).toList(),
                                );

                                if (seleccionado != null) {
                                  setState(() {
                                    if (service.selectedPortNames.contains(
                                      seleccionado,
                                    )) {
                                      // Estaba marcado: lo desmarcamos y desconectamos solo ese
                                      service.selectedPortNames.remove(
                                        seleccionado,
                                      );
                                      service.disconnectPort(seleccionado);
                                    } else {
                                      // Lo marcamos
                                      service.selectedPortNames.add(
                                        seleccionado,
                                      );
                                      // Si ya había conexión activa, conectamos inmediatamente este puerto
                                      if (service.isConnected) {
                                        service.connectPort(seleccionado);
                                      }
                                    }
                                  });
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                  horizontal: 8,
                                ),
                                decoration: BoxDecoration(
                                  border: Border.all(color: color4),
                                  borderRadius: BorderRadius.circular(4),
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
                                        style: const TextStyle(color: color4),
                                      ),
                                    ),
                                    const Icon(
                                      Icons.arrow_drop_down,
                                      color: color4,
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
                                : () {
                                  if (service.isConnected) {
                                    service.disconnectAll();
                                  } else {
                                    service.connectMultiple();
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
