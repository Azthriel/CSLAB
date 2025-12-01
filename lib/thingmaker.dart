import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cs_laboratorio/master.dart';
import 'package:http/http.dart' as http;

class ThingMaker extends StatefulWidget {
  const ThingMaker({super.key});
  @override
  State<ThingMaker> createState() => _ThingMakerState();
}

class _ThingMakerState extends State<ThingMaker> {
  final service = SerialService();
  final TextEditingController pcController = TextEditingController();
  final TextEditingController snController = TextEditingController();
  final List<String> items = [];
  final FocusNode pcNode = FocusNode();

  void _addItem() {
    final pc = pcController.text.trim();
    final sn = snController.text.trim();
    if (pc.isNotEmpty && sn.isNotEmpty && pc != '_IOT') {
      setState(() {
        items.add('$pc/$sn');
      });
      pcController.clear();
      snController.clear();

      pcNode.requestFocus();
    } else {
      showToast(
        "El código de producto y el número de serie no pueden estar vacíos",
      );
      return;
    }
  }

  Future<void> createThings() async {
    Uri uri = Uri.parse(
      'https://7afkb3q46b.execute-api.sa-east-1.amazonaws.com/v1/THINGS',
    );

    // Obtiene la lista de puertos seleccionados para enviar cada Thing
    final ports = service.selectedPortNames;
    if (ports.length != items.length) {
      showToast('La cantidad de puertos no coincide con la de Things');
      return;
    }

    for (int i = 0; i < items.length; i++) {
      String equipo = items[i];
      String portName = ports[i];

      // Conecta el puerto específico para este Thing
      if (!service.connectPort(portName)) {
        showToast('Error al conectar al puerto \$portName');
        continue;
      }

      String pc = equipo.split('/')[0];
      String sn = equipo.split('/')[1];
      String thingName = '$pc:$sn';
      String bd = jsonEncode({'thingName': thingName});

      printLog('Body: $bd');
      var response = await http.post(uri, body: bd);

      if (response.statusCode == 200) {
        printLog('Respuesta: ${response.body}');
        showToast('Thing creado: $thingName');

        Map<String, dynamic> jsonResponse = jsonDecode(response.body);
        Map<String, dynamic> body = jsonDecode(jsonResponse['body']);

        String amazonCA = body['amazonCA'];
        String deviceCert = body['deviceCert'];
        String privateKey = body['privateKey'];

        printLog('Certificado: $deviceCert', "Cyan");
        printLog('Llave privada: $privateKey', "Cyan");
        printLog('Amazon CA: $amazonCA', "Cyan");

        // Envía cada certificado al puerto asignado
        for (String line in amazonCA.split('\n')) {
          if (line.isEmpty || line == ' ') break;
          printLog(line, "Cyan");
          String msg = jsonEncode({'cmd': 6, 'content': '0#$line'});
          service.sendToPort(portName, msg);
          await Future.delayed(const Duration(milliseconds: 200));
        }
        for (String line in deviceCert.split('\n')) {
          if (line.isEmpty || line == ' ') break;
          printLog(line, "Cyan");
          String msg = jsonEncode({'cmd': 6, 'content': '1#$line'});
          service.sendToPort(portName, msg);
          await Future.delayed(const Duration(milliseconds: 200));
        }
        for (String line in privateKey.split('\n')) {
          if (line.isEmpty || line == ' ') break;
          printLog(line, "Cyan");
          String msg = jsonEncode({'cmd': 6, 'content': '2#$line'});
          service.sendToPort(portName, msg);
          await Future.delayed(const Duration(milliseconds: 200));
        }
      } else {
        printLog('Error: ${response.statusCode}');
        showToast('Error al crear el Thing: $thingName');
      }
    }

    showToast("Todas las things creadas");
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
              Focus(
                onFocusChange: (hasFocus) {
                  if (!hasFocus) {
                    final text = pcController.text;
                    if (!text.endsWith('_IOT')) {
                      pcController.text = '${text}_IOT';
                      // opcional: mover el cursor al final
                      pcController.selection = TextSelection.collapsed(
                        offset: pcController.text.length,
                      );
                    }
                  }
                },
                child: buildTextField(
                  label: 'Código de producto',
                  hint: 'Código de producto',
                  controller: pcController,
                  focusNode: pcNode,
                ),
              ),
              const SizedBox(height: 12),
              buildTextField(
                label: 'Número de serie',
                hint: 'Número de serie',
                controller: snController,
              ),
              const SizedBox(height: 12),
              buildButton(text: 'Agregar', onPressed: _addItem),
              const SizedBox(height: 20),
              SizedBox(
                height: 200,
                child:
                    items.isEmpty
                        ? Center(
                          child: Text(
                            'Aquí se mostrarán las entradas',
                            style: TextStyle(color: color1),
                          ),
                        )
                        : ListView.builder(
                          itemCount: items.length,
                          itemBuilder:
                              (context, index) => Card(
                                color: color1,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                margin: const EdgeInsets.symmetric(vertical: 6),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Text(
                                    items[index],
                                    style: TextStyle(color: color4),
                                  ),
                                ),
                              ),
                        ),
              ),
              buildButton(
                text: 'Crear Things',
                onPressed: () async {
                  await createThings();

                  setState(() {
                    items.clear();
                    pcController.clear();
                    snController.clear();
                  });
                },
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          setState(() {
            items.clear();
            pcController.clear();
            snController.clear();
          });
          showToast("Lista borrada");
        },
        backgroundColor: color2,
        child: const Icon(Icons.delete, color: color4),
      ),
    );
  }
}
