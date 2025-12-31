import 'package:cslab/login.dart';
import 'package:cslab/menu.dart';
import 'package:flutter/material.dart';
import 'package:cslab/master.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  printLog('Inicio de la aplicación');
  printLog('Versión: $appVersionNumber');
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
      initialRoute: '/login',
      routes: {
        '/login': (context) => const LoginPage(),
        '/menu': (context) => const MenuPage(),
      },
      debugShowCheckedModeBanner: false,
    );
  }
}
