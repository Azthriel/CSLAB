import 'dart:convert';
import 'package:cslab/firestore_service.dart';
import 'package:cslab/secret.dart';
import 'package:flutter/material.dart';
import 'package:cslab/master.dart';
import 'package:http/http.dart' as http;

class ThingMaker extends StatefulWidget {
  const ThingMaker({super.key});
  @override
  State<ThingMaker> createState() => _ThingMakerState();
}

class _ThingMakerState extends State<ThingMaker> {
  final service = SerialService();
  final TextEditingController snController = TextEditingController();
  final List<String> items = [];

  // ── Dropdown de producto (igual que en auto.dart / tools.dart) ────────────
  List<String> _productCodes = [];
  Map<String, String> _pcMap = {};
  String? _selectedProductCode;
  bool _isLoadingProductCodes = false;
  bool _manualMode = false;
  final _manualCodeController = TextEditingController();

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

  @override
  void initState() {
    super.initState();
    _loadProductCodes();
  }

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
    } catch (e) {
      printLog('Error cargando productos en ThingMaker: $e', 'rojo');
      if (mounted) setState(() => _isLoadingProductCodes = false);
    }
  }

  void _addItem() {
    final pc = _effectiveProductCode ?? '';
    final sn = snController.text.trim();
    if (pc.isNotEmpty && sn.isNotEmpty && pc != '_IOT') {
      setState(() {
        items.add('$pc/$sn');
      });
      snController.clear();
    } else {
      showToast(
        "El código de producto y el número de serie no pueden estar vacíos",
      );
      return;
    }
  }

  Future<void> createThings() async {
    Uri uri = Uri.parse(createThingURL);

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
      final connected = await service.connectPort(portName);
      if (!connected) {
        showToast('Error al conectar al puerto $portName');
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

        registerActivity(pc, sn, "Thing creado desde CSLAB");

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
        registerActivity(
          pc,
          sn,
          "Error al crear Thing: ${response.statusCode}",
        );
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
              // ── Selector de producto ──────────────────────────────────────
              _buildProductSelector(),
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
            snController.clear();
          });
          showToast("Lista borrada");
        },
        backgroundColor: color2,
        child: const Icon(Icons.delete, color: color4),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Selector de producto (igual que en tools/auto)
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildProductSelector() {
    if (_manualMode) {
      return Row(
        children: [
          Expanded(
            child: TextField(
              controller: _manualCodeController,
              style: const TextStyle(color: color4),
              decoration: InputDecoration(
                labelText: 'Código de producto',
                labelStyle: const TextStyle(color: color3),
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
          _circleBtn(
            icon: Icons.list,
            tooltip: 'Usar dropdown',
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
                  ? _loadingField('Cargando productos...')
                  : DropdownButtonFormField<String>(
                    initialValue:
                        (_selectedProductCode != null &&
                                _productCodes.contains(_selectedProductCode))
                            ? _selectedProductCode
                            : null,
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
                    hint: Text(
                      _productCodes.isEmpty
                          ? 'Sin productos en Firestore'
                          : 'Código de producto',
                      style: const TextStyle(color: color3, fontSize: 13),
                    ),
                    items:
                        _productCodes
                            .map(
                              (code) => DropdownMenuItem(
                                value: code,
                                child: Text(
                                  _friendlyName(code),
                                  style: const TextStyle(color: color4),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                    onChanged: (v) => setState(() => _selectedProductCode = v),
                  ),
        ),
        const SizedBox(width: 8),
        _circleBtn(
          icon: Icons.refresh,
          tooltip: 'Recargar productos',
          onPressed: _loadProductCodes,
        ),
        const SizedBox(width: 4),
        _circleBtn(
          icon: Icons.edit,
          tooltip: 'Ingresar código manual',
          onPressed: () => setState(() => _manualMode = true),
        ),
      ],
    );
  }

  Widget _circleBtn({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: color2,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(icon, size: 20, color: color4),
          ),
        ),
      ),
    );
  }

  Widget _loadingField(String label) {
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
