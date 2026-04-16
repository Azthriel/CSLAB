import 'package:cslab/master.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
  
  // Controladores para los 4 dígitos del legajo
  final List<TextEditingController> legajoControllers = List.generate(4, (_) => TextEditingController());
  final List<FocusNode> legajoFocusNodes = List.generate(4, (_) => FocusNode());
  
  // Controladores para los 4 dígitos de la contraseña
  final List<TextEditingController> passControllers = List.generate(4, (_) => TextEditingController());
  final List<FocusNode> passFocusNodes = List.generate(4, (_) => FocusNode());

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Inicializar fToast con el context de esta ruta, que ya está dentro
    // de MaterialApp y tiene el overlay disponible.
    fToast.init(context);
  }

  Future<void> verificarCredenciales() async {
    printLog('Verificando credenciales...');
    
    // Obtener valores de los 4 cuadros
    final legajo = legajoControllers.map((c) => c.text).join();
    final pass = passControllers.map((c) => c.text).join();
    
    // Validar que legajo y contraseña tengan exactamente 4 dígitos
    if (legajo.length != 4 || !RegExp(r'^[0-9]{4}$').hasMatch(legajo)) {
      showToast('El legajo debe tener exactamente 4 dígitos');
      return;
    }
    
    if (pass.length != 4 || !RegExp(r'^[0-9]{4}$').hasMatch(pass)) {
      showToast('La contraseña debe tener exactamente 4 dígitos');
      return;
    }
    
    try {
      DocumentSnapshot documentSnapshot =
          await FirebaseFirestore.instance
              .collection('Legajos')
              .doc(legajo)
              .get();

      if (documentSnapshot.exists) {
        Map<String, dynamic> data =
            documentSnapshot.data() as Map<String, dynamic>;
        if (data['pass'] == pass) {
          showToast('Inicio de sesión exitoso');
          legajoConectado = legajo;
          printLog("Legajo conectado: $legajoConectado", "cyan");
          accessLevel = data['Acceso'] ?? 0;
          printLog("Nivel de acceso: $accessLevel", "cyan");
          completeName = data['Nombre'] ?? '';
          navigatorKey.currentState?.pushReplacementNamed('/menu');
          printLog('Inicio de sesión exitoso');
        } else {
          showToast('Contraseña incorrecta');
          printLog('Credenciales incorrectas');
        }
      } else {
        showToast('Legajo inexistente');
      }
    } catch (error, st) {
      printLog('Error al realizar la consulta: $error\n$st', 'rojo');
      showToast('Error de conexión: verificá tu red e internet');
    }
  }

  @override
  void dispose() {
    super.dispose();
    legajoController.dispose();
    passController.dispose();
    passNode.dispose();
    // Limpiar controladores y focus nodes de los cuadros
    for (var controller in legajoControllers) {
      controller.dispose();
    }
    for (var node in legajoFocusNodes) {
      node.dispose();
    }
    for (var controller in passControllers) {
      controller.dispose();
    }
    for (var node in passFocusNodes) {
      node.dispose();
    }
  }
  
  // Widget para crear los 4 cuadros de entrada
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
              style: const TextStyle(color: color4, fontSize: 16, fontWeight: FontWeight.w500),
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
                    // Mover al siguiente campo
                    if (index < 3) {
                      focusNodes[index + 1].requestFocus();
                    } else {
                      // Si es el último cuadro del legajo, ir a contraseña
                      if (!isLast) {
                        passFocusNodes[0].requestFocus();
                      } else {
                        // Si es el último de contraseña, iniciar sesión
                        verificarCredenciales();
                      }
                    }
                  }
                },
                onSubmitted: (value) {
                  if (index == 3 && isLast) {
                    verificarCredenciales();
                  }
                },
              ),
            );
          }),
        ),
      ],
    );
  }

  //!Visual
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
