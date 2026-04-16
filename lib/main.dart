import 'package:cslab/login.dart';
import 'package:cslab/menu.dart';
import 'package:flutter/material.dart';
import 'package:cslab/master.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  printLog('Inicio de la aplicación');
  appVersionNumber = await _getAppVersion();
  printLog('Versión: $appVersionNumber');

  await ensureWindowsDeps();
  printLog('Dependencias de Windows OK');

  await ensurePythonEmbed();
  printLog('Python embebido inicializado');

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  printLog('Firebase inicializado');

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  MyAppState createState() => MyAppState();
}

class MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();

    printLog('Iniciando FToast');
    fToast = FToast();

    printLog('FToast instanciado');
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      builder: FToastBuilder(),
      title: 'CS Laboratorio',
      navigatorKey: navigatorKey,
      theme: ThemeData(
        scaffoldBackgroundColor: color0,
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: color1,
          hintStyle: TextStyle(color: color3),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
        ),
        textTheme: TextTheme(
          bodyLarge: TextStyle(color: color4),
          bodyMedium: TextStyle(color: color4),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: color2,
            foregroundColor: color4,
          ),
        ),
      ),
      initialRoute: '/login',
      routes: {
        '/login': (context) => const LoginPage(),
        '/menu': (context) => const MenuPage(),
      },
      debugShowCheckedModeBanner: false,
    );
  }
}

Future<String> _getAppVersion() async {
  try {
    final pubspecText = await rootBundle.loadString('pubspec.yaml');
    for (var line in pubspecText.split('\n')) {
      if (line.trim().startsWith('version:')) {
        final fullVersion = line.split(':')[1].trim();
        final cleanVersion = fullVersion.split('+')[0];
        return cleanVersion;
      }
    }
    return '1.0.0';
  } catch (e) {
    return '1.0.0';
  }
}
