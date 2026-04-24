import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cslab/firestore_service.dart';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:path/path.dart' as p;

//! VARIABLES !\\

String appVersionNumber = '1.0.0';

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

//*-Usuario conectado-*\\
String legajoConectado = '';
int accessLevel = 0;
String completeName = '';
//*-Usuario conectado-*\\

//*-Estado de app-*\\
const bool xProfileMode = bool.fromEnvironment('dart.vm.profile');
const bool xReleaseMode = bool.fromEnvironment('dart.vm.product');
const bool xDebugMode = !xProfileMode && !xReleaseMode;
// const bool xDebugMode = true;
//*-Estado de app-*\\

//*- Versión a flashear en equipos -*\\
String versionToUpload = '';
//*- Versión a flashear en equipos -*\\

//! FUNCIONES !\\

///*-Permite hacer prints seguros, solo en modo debug-*\\\
///Colores permitidos para [color] son:
///rojo, verde, amarillo, azul, magenta y cyan.
///
///Si no colocas ningún color se pondra por defecto...
void printLog(var text, [String? color]) {
  // Escribir siempre al archivo (funciona en release)
  logToFile(text.toString());

  // Console solo en debug con colores
  if (xDebugMode) {
    String ansi = '\x1B[0m';
    if (color != null) {
      switch (color.toLowerCase()) {
        case 'rojo':
          ansi = '\x1B[31m';
          break;
        case 'verde':
          ansi = '\x1B[32m';
          break;
        case 'amarillo':
          ansi = '\x1B[33m';
          break;
        case 'azul':
          ansi = '\x1B[34m';
          break;
        case 'magenta':
          ansi = '\x1B[35m';
          break;
        case 'cyan':
          ansi = '\x1B[36m';
          break;
        default:
          ansi = '\x1B[0m';
          break;
      }
    }
    // ignore: avoid_print
    print('${ansi}PrintData: $text\x1B[0m');
  } else {
    // ignore: avoid_print
    print(text);
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
  Color? color,
}) {
  return ElevatedButton.icon(
    style: ElevatedButton.styleFrom(
      backgroundColor: color ?? color1,
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
  Alignment? alignment,
}) {
  return FractionallySizedBox(
    alignment: alignment ?? Alignment.center,
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

//*-Registro de actividad-*\\
void registerActivity(
  String productCode,
  String serialNumber,
  String accion,
) async {
  try {
    final String diaDeLaFecha = DateTime.now()
        .toString()
        .split(' ')[0]
        .replaceAll('-', '');

    final String documentPath = '$productCode:$serialNumber';
    final String fieldName = '$diaDeLaFecha:$legajoConectado';

    printLog('Registrando actividad: $documentPath → $fieldName: $accion');

    await FirestoreService.arrayUnion('Registro', documentPath, fieldName, [
      accion,
    ]);

    printLog('Actividad registrada correctamente.', 'verde');
  } catch (e, s) {
    printLog('Error al registrar actividad: $e', 'rojo');
    printLog(s);
  }
}
//*-Registro de actividad-*\\

Future<void> ensureWindowsDeps() async {
  if (!Platform.isWindows) return;

  final exeDir = File(Platform.resolvedExecutable).parent.path;

  final doneMarker = File(p.join(exeDir, '.deps_ready'));
  if (await doneMarker.exists()) {
    printLog('Dependencias de Windows ya verificadas, skip.', 'verde');
    return;
  }

  printLog('Verificando dependencias de Windows...', 'amarillo');

  // Extraer archivos desde assets
  final batPath = p.join(exeDir, 'setup_deps.bat');
  final redistPath = p.join(exeDir, 'vc_redist.x64.exe');

  final batBytes = await rootBundle.load('assets/setup_deps.bat');
  await File(batPath).writeAsBytes(batBytes.buffer.asUint8List());

  final redistBytes = await rootBundle.load('assets/vc_redist.x64.exe');
  await File(redistPath).writeAsBytes(redistBytes.buffer.asUint8List());

  // Ejecutar y esperar que termine
  final result = await Process.run('cmd', ['/c', batPath], runInShell: true);

  printLog('setup_deps exit code: ${result.exitCode}');
  if (result.stdout.toString().trim().isNotEmpty) {
    printLog('setup_deps stdout: ${result.stdout}');
  }
  if (result.stderr.toString().trim().isNotEmpty) {
    printLog('setup_deps stderr: ${result.stderr}', 'rojo');
  }

  try {
    await File(batPath).delete();
  } catch (_) {}
  try {
    await File(redistPath).delete();
  } catch (_) {}

  // Marcar como hecho
  await doneMarker.writeAsString('ok');
  printLog('Dependencias verificadas correctamente.', 'verde');
}

// *- Logger a archivo (funciona en release) -*\\
String get logFilePath =>
    p.join(File(Platform.resolvedExecutable).parent.path, 'cslab_log.txt');

Future<void> initFileLogger() async {
  final file = File(logFilePath);
  await file.writeAsString(
    '=== CS LAB ${DateTime.now()} ===\n',
    mode: FileMode.write,
  );
}

void logToFile(String text) {
  try {
    final file = File(logFilePath);
    file.writeAsStringSync(
      '[${DateTime.now().toIso8601String()}] $text\n',
      mode: FileMode.append,
    );
  } catch (_) {}
}
// *- Logger a archivo -*\\

//! Clases !\\

/// Configuraciones globales de la aplicación
class AppSettings extends ChangeNotifier {
  static final AppSettings _instance = AppSettings._internal();
  factory AppSettings() => _instance;
  AppSettings._internal();

  // Configuraciones de SerialService
  int _maxLogMessages = 1000;
  Duration _commandTimeout = const Duration(seconds: 5);
  Duration _reconnectDelay = const Duration(milliseconds: 500);
  int _maxRetries = 3;

  // Configuraciones de AutoPage
  int _maxConcurrentFlash = 4;
  int _maxRetriesFlash = 2;
  Duration _certLineDelay = const Duration(milliseconds: 300);
  Duration _deviceDelay = const Duration(milliseconds: 500);

  // Getters
  int get maxLogMessages => _maxLogMessages;
  Duration get commandTimeout => _commandTimeout;
  Duration get reconnectDelay => _reconnectDelay;
  int get maxRetries => _maxRetries;
  int get maxConcurrentFlash => _maxConcurrentFlash;
  int get maxRetriesFlash => _maxRetriesFlash;
  Duration get certLineDelay => _certLineDelay;
  Duration get deviceDelay => _deviceDelay;

  // Setters con notificación
  set maxLogMessages(int value) {
    if (value >= 100 && value <= 10000) {
      _maxLogMessages = value;
      notifyListeners();
    }
  }

  set commandTimeout(Duration value) {
    _commandTimeout = value;
    notifyListeners();
  }

  set reconnectDelay(Duration value) {
    _reconnectDelay = value;
    notifyListeners();
  }

  set maxRetries(int value) {
    if (value >= 1 && value <= 10) {
      _maxRetries = value;
      notifyListeners();
    }
  }

  set maxConcurrentFlash(int value) {
    if (value >= 1 && value <= 40) {
      _maxConcurrentFlash = value;
      notifyListeners();
    }
  }

  set maxRetriesFlash(int value) {
    if (value >= 1 && value <= 10) {
      _maxRetriesFlash = value;
      notifyListeners();
    }
  }

  set certLineDelay(Duration value) {
    _certLineDelay = value;
    notifyListeners();
  }

  set deviceDelay(Duration value) {
    _deviceDelay = value;
    notifyListeners();
  }

  // Resetear a valores por defecto
  void resetToDefaults() {
    _maxLogMessages = 1000;
    _commandTimeout = const Duration(seconds: 5);
    _reconnectDelay = const Duration(milliseconds: 500);
    _maxRetries = 3;
    _maxConcurrentFlash = 4;
    _maxRetriesFlash = 2;
    _certLineDelay = const Duration(milliseconds: 300);
    _deviceDelay = const Duration(milliseconds: 500);
    notifyListeners();
  }
}

/// Servicio singleton para manejar un único puerto serie
class SerialService extends ChangeNotifier {
  static final SerialService _instance = SerialService._internal();
  factory SerialService() => _instance;
  SerialService._internal();

  // Usar configuraciones dinámicas
  final settings = AppSettings();

  /// Puertos disponibles como objetos SerialPort (para acceder a .description)
  List<SerialPort> ports = [];
  List<String> selectedPortNames = [];
  int baudRate = 115200;

  /// Historial completo de mensajes (con límite automático)
  final List<SerialMessage> messageLog = [];

  final List<SerialPortReader> _readers = [];
  final StreamController<SerialMessage> _inController =
      StreamController.broadcast();

  // Control de listening on-demand
  bool isListening = false;
  final Map<String, StreamSubscription> _streamSubscriptions = {};

  // Debouncing para notifyListeners()
  Timer? _notifyTimer;
  bool _hasPendingNotification = false;

  /// Notifica listeners con debouncing para evitar saturar UI
  void _notifyWithDebounce() {
    _hasPendingNotification = true;
    _notifyTimer?.cancel();
    _notifyTimer = Timer(const Duration(milliseconds: 100), () {
      if (_hasPendingNotification) {
        _hasPendingNotification = false;
        notifyListeners();
      }
    });
  }

  /// Limpia logs si exceden el máximo
  void _trimLogs() {
    if (messageLog.length > settings.maxLogMessages) {
      messageLog.removeRange(0, messageLog.length - settings.maxLogMessages);
      // printLog(
      //   'Logs trimmed to ${settings.maxLogMessages} messages',
      //   'amarillo',
      // );
    }
  }

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

  /// Desconecta un solo puerto con limpieza adecuada
  Future<void> disconnectPort(String name) async {
    // Primero cancelar el listener si existe
    _stopListening(name);

    final idx = _readers.indexWhere((r) => r.port.name == name);
    if (idx != -1) {
      try {
        final reader = _readers[idx];
        if (reader.port.isOpen) {
          try {
            // Limpiar buffers antes de cerrar (3 = both)
            reader.port.flush(3);
          } catch (e) {
            // Ignorar errores de flush
          }
          await Future.delayed(const Duration(milliseconds: 100));
          try {
            reader.port.close();
            printLog('Port $name closed successfully', 'verde');
          } catch (e) {
            // Ignorar SerialPortError al cerrar (común en Windows)
            if (!e.toString().contains('completó correctamente')) {
              printLog('Error closing port $name: $e', 'rojo');
            }
          }
        }
        _readers.removeAt(idx);
        notifyListeners();
      } catch (e) {
        printLog('Exception in disconnectPort $name: $e', 'rojo');
      }
    }
  }

  /// Desconecta todos los puertos con limpieza adecuada
  Future<void> disconnectAll() async {
    printLog('Disconnecting all ports...', 'amarillo');
    for (final r in _readers) {
      try {
        if (r.port.isOpen) {
          try {
            r.port.flush(3); // 3 = both input/output
          } catch (e) {
            // Ignorar errores de flush
          }
          await Future.delayed(const Duration(milliseconds: 50));
          try {
            r.port.close();
          } catch (e) {
            // Silenciar SerialPortError común en Windows
            if (!e.toString().contains('completó correctamente')) {
              printLog('Error closing port ${r.port.name}: $e', 'rojo');
            }
          }
        }
      } catch (e) {
        printLog('Exception closing port ${r.port.name}: $e', 'rojo');
      }
    }
    _readers.clear();
    printLog('All ports disconnected', 'verde');
    notifyListeners();
  }

  /// Conecta a todos los puertos marcados (sin iniciar listening automático)
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

      // Limpiar buffer
      port.flush(3);

      final reader = SerialPortReader(port);
      _readers.add(reader);

      // Si isListening está activo, iniciar el listener
      if (isListening) {
        _startListening(name, reader);
      }

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

  /// Envia mensaje a un puerto específico con validación
  Future<bool> sendToPort(String name, String message) async {
    try {
      final bytes = utf8.encode(message);
      for (final reader in _readers) {
        if (reader.port.name == name) {
          if (!reader.port.isOpen) {
            printLog('Port $name is not open', 'rojo');
            return false;
          }

          final written = reader.port.write(Uint8List.fromList(bytes));
          if (written != bytes.length) {
            printLog(
              'Incomplete write to $name: $written/${bytes.length}',
              'amarillo',
            );
          }

          // Pequeño delay para permitir procesamiento
          await Future.delayed(const Duration(milliseconds: 50));
          printLog('Sent ${bytes.length} bytes to $name', 'verde');
          return true;
        }
      }
      printLog('Port $name not found in active readers', 'rojo');
      return false;
    } catch (e) {
      printLog('Error al enviar mensaje a $name: $e', 'rojo');
      showToast('Error al enviar mensaje: $e');
      return false;
    }
  }

  /// Conecta un solo puerto cuyo nombre recibes (con retry)
  Future<bool> connectPort(String name, {int? retries}) async {
    retries ??= settings.maxRetries;
    // Evita reconectar si ya está abierto
    if (_readers.any((r) => r.port.name == name && r.port.isOpen)) {
      printLog('Port $name already connected', 'verde');
      return true;
    }

    for (int attempt = 1; attempt <= retries; attempt++) {
      try {
        printLog('Connecting to $name (attempt $attempt/$retries)', 'cyan');
        final port = SerialPort(name);

        if (!port.openReadWrite()) {
          printLog('Failed to open port $name on attempt $attempt', 'rojo');
          if (attempt < retries) {
            await Future.delayed(settings.reconnectDelay * attempt);
            continue;
          }
          return false;
        }

        port.config =
            SerialPortConfig()
              ..baudRate = baudRate
              ..bits = 8
              ..stopBits = 1
              ..parity = 0;

        // Limpiar buffer antes de leer (3 = both input/output)
        port.flush(3);

        final reader = SerialPortReader(port);
        _readers.add(reader);

        // Si isListening está activo, iniciar el listener inmediatamente
        if (isListening) {
          _startListening(name, reader);
        }
        printLog('Successfully connected to $name', 'verde');
        _notifyWithDebounce(); // Debounced para evitar saturar UI
        return true;
      } catch (e) {
        printLog('Exception connecting to $name: $e', 'rojo');
        if (attempt < retries) {
          await Future.delayed(settings.reconnectDelay * attempt);
        }
      }
    }

    printLog('Failed to connect to $name after $retries attempts', 'rojo');
    return false;
  }

  /// Inicia el listening de datos para un puerto específico
  void _startListening(String portName, SerialPortReader reader) {
    // Si ya existe una suscripción, solo reanudarla
    if (_streamSubscriptions.containsKey(portName)) {
      _streamSubscriptions[portName]!.resume();
      printLog('Resumed listening on $portName', 'cyan');
      return;
    }

    final sub = reader.stream.listen(
      (chunk) {
        try {
          final text = utf8.decode(chunk, allowMalformed: true);
          if (text.trim().isNotEmpty) {
            final msg = SerialMessage(portName, text);
            _inController.add(msg);
            messageLog.add(msg);
            _trimLogs();
            _notifyWithDebounce();
          }
        } catch (e) {
          // Silenciar errores de decodificación
        }
      },
      onError: (error) {
        if (!error.toString().contains('completó correctamente')) {
          printLog('Stream error on $portName: $error', 'rojo');
        }
      },
      cancelOnError: false,
    );

    _streamSubscriptions[portName] = sub;
    printLog('Started listening on $portName', 'cyan');
  }

  /// Cancela completamente la suscripción de un puerto (para desconexión)
  void _stopListening(String portName) {
    final sub = _streamSubscriptions.remove(portName);
    sub?.cancel();
    printLog('Stopped listening on $portName', 'cyan');
  }

  /// Pausa el listening de un puerto específico (no cancela la suscripción)
  void _pauseListening(String portName) {
    final sub = _streamSubscriptions[portName];
    if (sub != null && !sub.isPaused) {
      sub.pause();
      printLog('Paused listening on $portName', 'cyan');
    }
  }

  /// Activa el listening en todos los puertos conectados
  void startListeningAll() {
    isListening = true;
    for (var reader in _readers) {
      if (reader.port.isOpen) {
        final portName = reader.port.name;
        if (portName != null) {
          _startListening(portName, reader);
        }
      }
    }
    printLog('Started listening on all ${_readers.length} ports', 'verde');
    _notifyWithDebounce(); // Usar debounce para evitar setState durante build
  }

  /// Pausa el listening en todos los puertos (pero mantiene suscripciones)
  void stopListeningAll() {
    isListening = false;
    for (var portName in _streamSubscriptions.keys) {
      _pauseListening(portName);
    }
    printLog('Paused listening on all ports', 'amarillo');
    _notifyWithDebounce(); // Usar debounce para evitar setState durante build
  }

  /// Limpieza completa del servicio
  Future<void> disposeService() async {
    _notifyTimer?.cancel();
    stopListeningAll(); // Cancelar todos los listeners
    await disconnectAll();
    await _inController.close();
    messageLog.clear();
    printLog('SerialService disposed', 'verde');
  }
}

/// Representa un trozo de datos recibidos por un puerto, con timestamp
class SerialMessage {
  final String portName;
  final String data;
  final DateTime timestamp;

  SerialMessage(this.portName, this.data) : timestamp = DateTime.now();
}
