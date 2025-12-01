import 'package:cs_laboratorio/menu.dart';
import 'package:flutter/material.dart';
import 'package:cs_laboratorio/master.dart';
import 'package:fluttertoast/fluttertoast.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  printLog('Inicio de la aplicación');
  printLog('Versión: $appVersionNumber');
  await ensurePythonEmbed();

  printLog('Python embebido inicializado');

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
    fToast.init(context);

    printLog('FToast inicializado');
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
      home: const MenuPage(),
      debugShowCheckedModeBanner: false,
    );
  }
}
