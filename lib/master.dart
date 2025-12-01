import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:path/path.dart' as p;

//! VARIABLES !\\

//!-------------------------VERSION NUMBER-------------------------!\\
const String appVersionNumber = '1.0.10';
//!-------------------------VERSION NUMBER-------------------------!\\

//*-Colores-*\\
const Color color0 = Color(0xFF0F2A1D);
const Color color1 = Color(0xFF375534);
const Color color2 = Color(0xFF6B9071);
const Color color3 = Color(0xFFAEC3B0);
const Color color4 = Color(0xFFE3EED4);
const Color color5 = Color(0xFF000000);
//*-Colores-*\\

//*- Toast -*\\
late FToast fToast;
//*- Toast -*\\

//*-Key de la app (uso de navegación y contextos)-*\\
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
//*-Key de la app (uso de navegación y contextos)-*\\

//*-Estado de app-*\\
const bool xProfileMode = bool.fromEnvironment('dart.vm.profile');
const bool xReleaseMode = bool.fromEnvironment('dart.vm.product');
const bool xDebugMode = !xProfileMode && !xReleaseMode;
// const bool xDebugMode = true;
//*-Estado de app-*\\

//! FUNCIONES !\\

///*-Permite hacer prints seguros, solo en modo debug-*\\\
///Colores permitidos para [color] son:
///rojo, verde, amarillo, azul, magenta y cyan.
///
///Si no colocas ningún color se pondra por defecto...
void printLog(var text, [String? color]) {
  if (color != null) {
    switch (color.toLowerCase()) {
      case 'rojo':
        color = '\x1B[31m';
        break;
      case 'verde':
        color = '\x1B[32m';
        break;
      case 'amarillo':
        color = '\x1B[33m';
        break;
      case 'azul':
        color = '\x1B[34m';
        break;
      case 'magenta':
        color = '\x1B[35m';
        break;
      case 'cyan':
        color = '\x1B[36m';
        break;
      case 'reset':
        color = '\x1B[0m';
        break;
      default:
        color = '\x1B[0m';
        break;
    }
  } else {
    color = '\x1B[0m';
  }
  if (xDebugMode) {
    if (Platform.isWindows) {
      // ignore: avoid_print
      print('${color}PrintData: $text\x1B[0m');
      // Platform.isWindows ? stdout.write('${color}PrintData: $text\x1B[0m') : null;
    } else {
      // ignore: avoid_print
      print("PrintData: $text");
    }
  }
}
//*-Permite hacer prints seguros, solo en modo debug-*\\

//*-Elementos genericos-*\\
///Genera un toast con el mensaje que le pases
void showToast(String message) {
  printLog('Toast: $message');
  fToast.removeCustomToast();
  Widget toast = Container(
    padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(25.0),
      color: color3,
      border: Border.all(color: color0, width: 1.0),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset('assets/misc/Dragon.png', width: 24, height: 24),
        const SizedBox(width: 12.0),
        Flexible(
          child: Text(
            message,
            style: TextStyle(fontSize: 16, color: color0),
            softWrap: true,
            maxLines: 10,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ),
      ],
    ),
  );

  fToast.showToast(
    child: toast,
    gravity: ToastGravity.BOTTOM,
    toastDuration: const Duration(seconds: 2),
  );
}

///Genera un cuadro de dialogo con los parametros que le pases
void showAlertDialog(
  BuildContext context,
  bool dismissible,
  Widget? title,
  Widget? content,
  List<Widget>? actions,
) {
  showGeneralDialog(
    context: context,
    barrierDismissible: dismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    transitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (
      BuildContext context,
      Animation<double> animation,
      Animation<double> secondaryAnimation,
    ) {
      double screenWidth = MediaQuery.of(context).size.width;
      return StatefulBuilder(
        builder: (BuildContext context, StateSetter changeState) {
          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: 300.0,
                maxWidth: screenWidth - 20,
              ),
              child: IntrinsicWidth(
                child: Container(
                  decoration: BoxDecoration(
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        spreadRadius: 1,
                        blurRadius: 20,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Card(
                    color: color3,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30.0),
                    ),
                    elevation: 24,
                    child: Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.topCenter,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 70, 20, 20),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Center(
                                child: DefaultTextStyle(
                                  style: const TextStyle(
                                    color: color0,
                                    fontSize: 24,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  child: title ?? const SizedBox.shrink(),
                                ),
                              ),
                              const SizedBox(height: 20),
                              Center(
                                child: DefaultTextStyle(
                                  style: const TextStyle(
                                    color: color0,
                                    fontSize: 16,
                                  ),
                                  child: content ?? const SizedBox.shrink(),
                                ),
                              ),
                              const SizedBox(height: 30),
                              if (actions != null)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children:
                                      actions.map((widget) {
                                        if (widget is TextButton) {
                                          return Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 5.0,
                                            ),
                                            child: TextButton(
                                              style: TextButton.styleFrom(
                                                foregroundColor: color0,
                                                backgroundColor: color3,
                                              ),
                                              onPressed: widget.onPressed,
                                              child: widget.child!,
                                            ),
                                          );
                                        } else {
                                          return widget;
                                        }
                                      }).toList(),
                                ),
                            ],
                          ),
                        ),
                        Positioned(
                          top: -50,
                          child: Material(
                            elevation: 10,
                            shape: const CircleBorder(),
                            shadowColor: Colors.black.withValues(alpha: 0.4),
                            child: CircleAvatar(
                              radius: 50,
                              backgroundColor: color3,
                              child: Image.asset(
                                'assets/misc/Dragon.png',
                                width: 60,
                                height: 60,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeInOut),
        child: ScaleTransition(
          scale: CurvedAnimation(parent: animation, curve: Curves.easeInOut),
          child: child,
        ),
      );
    },
  );
}

///Genera un botón generico con los parametros que le pases
Widget buildButton({
  required String text,
  required VoidCallback? onPressed,
  IconData? icon,
}) {
  return ElevatedButton.icon(
    style: ElevatedButton.styleFrom(
      backgroundColor: color1,
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 6,
      shadowColor: color3.withValues(alpha: 0.4),
    ),
    onPressed: onPressed,
    icon: icon != null ? Icon(icon, color: color4) : const SizedBox.shrink(),
    label: Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: color4,
      ),
    ),
  );
}

///Genera un cuadro de texto generico con los parametros que le pases
Widget buildTextField({
  TextEditingController? controller,
  required String label,
  String? hint,
  void Function(String)? onSubmitted,
  double widthFactor = 0.8,
  TextInputType? keyboard,
  void Function(String)? onChanged,
  void Function(String)? validator,
  int? maxLines,
  FocusNode? focusNode,
}) {
  return FractionallySizedBox(
    alignment: Alignment.center,
    widthFactor: widthFactor,
    child: Container(
      margin: const EdgeInsets.only(bottom: 20.0),
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      decoration: BoxDecoration(
        color: color1,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: color3.withValues(alpha: 0.3),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        focusNode: focusNode,
        controller: controller,
        onSubmitted: onSubmitted,
        onChanged: onChanged,
        maxLines: maxLines,
        style: const TextStyle(color: color4),
        keyboardType: keyboard,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(
            color: color4,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
          hintText: hint,
          hintStyle: const TextStyle(color: color4),
          border: InputBorder.none,
          enabledBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: color4, width: 1.0),
          ),
          focusedBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: color4, width: 2.0),
          ),
        ),
      ),
    ),
  );
}

///Genera un texto generico con los parametros que le pases
Widget buildText({
  required String text,
  double fontSize = 16,
  FontWeight fontWeight = FontWeight.normal,
  Color color = color4,
  TextAlign textAlign = TextAlign.center,
  double widthFactor = 0.9,
  List<TextSpan>? textSpans,
}) {
  return FractionallySizedBox(
    alignment: Alignment.center,
    widthFactor: widthFactor,
    child: Container(
      margin: const EdgeInsets.only(bottom: 20.0),
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      decoration: BoxDecoration(
        color: color0,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(color: color4, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Text.rich(
        TextSpan(
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: fontWeight,
            color: color,
          ),
          children: textSpans ?? [TextSpan(text: text)],
        ),
        textAlign: textAlign,
      ),
    ),
  );
}
//*-Elementos genericos-*\\

Future<void> ensurePythonEmbed() async {
  final exeDir = File(Platform.resolvedExecutable).parent.path;
  final targetDir = Directory(p.join(exeDir, 'python-embed'));
  if (await targetDir.exists()) return;

  // 1) lee el zip de assets
  final bytes = await rootBundle.load('assets/python-embed.zip');
  final archive = ZipDecoder().decodeBytes(bytes.buffer.asUint8List());

  // 2) extrae cada archivo
  for (final file in archive) {
    final outPath = p.join(exeDir, file.name);
    if (file.isFile) {
      final outFile = File(outPath);
      await outFile.create(recursive: true);
      await outFile.writeAsBytes(file.content as List<int>);
    } else {
      await Directory(outPath).create(recursive: true);
    }
  }
}

//! Clases !\\
/// Servicio singleton para manejar un único puerto serie
class SerialService extends ChangeNotifier {
  static final SerialService _instance = SerialService._internal();
  factory SerialService() => _instance;
  SerialService._internal();

  /// Puertos disponibles como objetos SerialPort (para acceder a .description)
  List<SerialPort> ports = [];
  List<String> selectedPortNames = [];
  int baudRate = 115200;

  /// Historial completo de mensajes
  final List<SerialMessage> messageLog = [];

  final List<SerialPortReader> _readers = [];
  final StreamController<SerialMessage> _inController =
      StreamController.broadcast();

  /// Stream público con todo lo que llega del puerto
  Stream<SerialMessage> get incomingData => _inController.stream;

  /// Determina si el puerto está abierto y conectado
  bool get isConnected => _readers.any((r) => r.port.isOpen);

  /// Recarga la lista de puertos
  void refreshPorts() {
    final names = SerialPort.availablePorts;
    ports = names.map((n) => SerialPort(n)).toList();
    selectedPortNames.clear();
    notifyListeners();
  }

  /// Desconecta un solo puerto
  void disconnectPort(String name) {
    final idx = _readers.indexWhere((r) => r.port.name == name);
    if (idx != -1) {
      _readers[idx].port.close();
      _readers.removeAt(idx);
      notifyListeners();
    }
  }

  /// Desconecta todos los puertos
  void disconnectAll() {
    for (final r in _readers) {
      r.port.close();
    }
    _readers.clear();
    notifyListeners();
  }

  /// Conecta a todos los puertos marcados
  bool connectMultiple() {
    disconnectAll();
    bool anyOk = false;
    for (final name in selectedPortNames) {
      final port = SerialPort(name);
      if (!port.openReadWrite()) continue;
      port.config =
          SerialPortConfig()
            ..baudRate = baudRate
            ..bits = 8
            ..stopBits = 1
            ..parity = 0;
      final reader = SerialPortReader(port);
      reader.stream.listen((chunk) {
        try {
          final text = utf8.decode(chunk);
          final msg = SerialMessage(name, text);
          _inController.add(msg);
          messageLog.add(msg);
          notifyListeners();
        } catch (e) {
          printLog('Error al decodificar el chunk: $e');
        }
      });
      _readers.add(reader);
      anyOk = true;
    }
    notifyListeners();
    return anyOk;
  }

  /// Envía mensaje a todos los puertos abiertos
  void sendMessage(String message) {
    printLog('Mando anashee $message');
    final bytes = utf8.encode(message);
    for (final reader in _readers) {
      if (reader.port.isOpen) {
        reader.port.write(Uint8List.fromList(bytes));
      }
    }
  }

  /// Borra el historial de mensajes
  void clearLogs() {
    messageLog.clear();
    notifyListeners();
  }

  /// Envia mensaje a un puerto específico
  void sendToPort(String name, String message) {
    try {
      final bytes = utf8.encode(message);
      for (final reader in _readers) {
        if (reader.port.name == name && reader.port.isOpen) {
          reader.port.write(Uint8List.fromList(bytes));
          break;
        }
      }
    } catch (e) {
      printLog('Error al enviar mensaje: $e');
      showToast('Error al enviar mensaje: $e');
    }
  }

  /// Conecta un solo puerto cuyo nombre recibes
  bool connectPort(String name) {
    // Evita reconectar si ya está abierto
    if (_readers.any((r) => r.port.name == name && r.port.isOpen)) {
      return true;
    }
    final port = SerialPort(name);
    if (!port.openReadWrite()) {
      return false;
    }
    port.config =
        SerialPortConfig()
          ..baudRate = baudRate
          ..bits = 8
          ..stopBits = 1
          ..parity = 0;

    final reader = SerialPortReader(port)
      ..stream.listen((chunk) {
        final text = utf8.decode(chunk);
        final msg = SerialMessage(name, text);
        _inController.add(msg);
        messageLog.add(msg);
        notifyListeners();
      });

    _readers.add(reader);
    notifyListeners();
    return true;
  }
}

/// Representa un trozo de datos recibidos por un puerto, con timestamp
class SerialMessage {
  final String portName;
  final String data;
  final DateTime timestamp;

  SerialMessage(this.portName, this.data) : timestamp = DateTime.now();
}
