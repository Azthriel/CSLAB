import 'package:cslab/firestore_service.dart';
import 'package:cslab/master.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => LoginPageState();
}

class LoginPageState extends State<LoginPage> {
  final TextEditingController legajoController = TextEditingController();
  final TextEditingController passController = TextEditingController();
  final FocusNode passNode = FocusNode();

  final List<TextEditingController> legajoControllers = List.generate(
    4,
    (_) => TextEditingController(),
  );
  final List<FocusNode> legajoFocusNodes = List.generate(4, (_) => FocusNode());

  final List<TextEditingController> passControllers = List.generate(
    4,
    (_) => TextEditingController(),
  );
  final List<FocusNode> passFocusNodes = List.generate(4, (_) => FocusNode());

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    fToast.init(context);
  }

  Future<void> verificarCredenciales() async {
    printLog('verificarCredenciales() llamado');

    final legajo = legajoControllers.map((c) => c.text).join();
    final pass = passControllers.map((c) => c.text).join();

    if (legajo.length != 4 || !RegExp(r'^[0-9]{4}$').hasMatch(legajo)) {
      showToast('El legajo debe tener exactamente 4 dígitos');
      return;
    }
    if (pass.length != 4 || !RegExp(r'^[0-9]{4}$').hasMatch(pass)) {
      showToast('La contraseña debe tener exactamente 4 dígitos');
      return;
    }

    try {
      printLog('Llamando Firestore REST...');
      final data = await FirestoreService.getDocument('Legajos', legajo);
      printLog('REST OK. exists=${data != null}');

      if (data == null) {
        showToast('Legajo inexistente');
        return;
      }

      if (data['pass'] == pass) {
        legajoConectado = legajo;
        accessLevel = data['Acceso'] ?? 0;
        completeName = data['Nombre'] ?? '';
        showToast('Inicio de sesión exitoso');
        navigatorKey.currentState?.pushReplacementNamed('/menu');
      } else {
        showToast('Contraseña incorrecta');
      }
    } catch (e, s) {
      printLog('ERROR: $e\n$s', 'rojo');
      showToast('Error de conexión: verificá tu red e internet');
    }

    printLog('verificarCredenciales() finalizado');
  }

  @override
  void dispose() {
    super.dispose();
    legajoController.dispose();
    passController.dispose();
    passNode.dispose();
    for (var c in legajoControllers) {
      c.dispose();
    }
    for (var n in legajoFocusNodes) {
      n.dispose();
    }
    for (var c in passControllers) {
      c.dispose();
    }
    for (var n in passFocusNodes) {
      n.dispose();
    }
  }

  Widget buildPinBoxes({
    required List<TextEditingController> controllers,
    required List<FocusNode> focusNodes,
    required String label,
    required IconData icon,
    bool obscureText = false,
    bool isLast = false,
  }) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color4, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: color4,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(4, (index) {
            return Container(
              width: 60,
              height: 60,
              margin: const EdgeInsets.symmetric(horizontal: 5),
              child: TextField(
                controller: controllers[index],
                focusNode: focusNodes[index],
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                obscureText: obscureText,
                maxLength: 1,
                style: const TextStyle(
                  color: color4,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(1),
                ],
                decoration: InputDecoration(
                  filled: true,
                  fillColor: color2,
                  counterText: '',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12.0),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.all(0),
                ),
                onChanged: (value) {
                  if (value.isNotEmpty) {
                    if (index < 3) {
                      focusNodes[index + 1].requestFocus();
                    } else {
                      if (!isLast) {
                        passFocusNodes[0].requestFocus();
                      } else {
                        verificarCredenciales();
                      }
                    }
                  }
                },
                onSubmitted: (value) {
                  if (index == 3 && isLast) verificarCredenciales();
                },
              ),
            );
          }),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: color1,
      body: Center(
        child: Column(
          children: [
            SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 50),
                  SizedBox(
                    height: 200,
                    child: Image.asset('assets/LogoApp.png'),
                  ),
                  const SizedBox(height: 20),
                  buildPinBoxes(
                    controllers: legajoControllers,
                    focusNodes: legajoFocusNodes,
                    label: 'Ingrese su legajo',
                    icon: Icons.badge,
                    obscureText: false,
                    isLast: false,
                  ),
                  const SizedBox(height: 20),
                  buildPinBoxes(
                    controllers: passControllers,
                    focusNodes: passFocusNodes,
                    label: 'Ingrese su contraseña',
                    icon: Icons.lock,
                    obscureText: true,
                    isLast: true,
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: 300,
                    child: ElevatedButton(
                      onPressed: () => verificarCredenciales(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: color3,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                      child: const Text(
                        'Ingresar',
                        style: TextStyle(fontSize: 16, color: color4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 15),
                ],
              ),
            ),
            const Spacer(),
            Text(
              'Versión $appVersionNumber',
              style: const TextStyle(color: color4, fontSize: 12),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}
