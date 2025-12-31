import 'package:cslab/master.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => LoginPageState();
}

class LoginPageState extends State<LoginPage> {
  final TextEditingController legajoController = TextEditingController();
  final TextEditingController passController = TextEditingController();
  final FocusNode passNode = FocusNode();

  @override
  void initState() {
    super.initState();
    fToast.init(navigatorKey.currentState!.context);
  }

  Future<void> verificarCredenciales() async {
    printLog('Verificando credenciales...');
    try {
      DocumentSnapshot documentSnapshot =
          await FirebaseFirestore.instance
              .collection('Legajos')
              .doc(legajoController.text.trim())
              .get();

      if (documentSnapshot.exists) {
        Map<String, dynamic> data =
            documentSnapshot.data() as Map<String, dynamic>;
        if (data['pass'] == passController.text.trim()) {
          showToast('Inicio de sesión exitoso');
          legajoConectado = legajoController.text.trim();
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
    } catch (error) {
      printLog('Error al realizar la consulta: $error');
    }
  }

  @override
  void dispose() {
    super.dispose();
    legajoController.dispose();
    passController.dispose();
    passNode.dispose();
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
                  SizedBox(
                    width: 300,
                    child: TextField(
                      style: const TextStyle(color: color4),
                      controller: legajoController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: color2,
                        labelText: 'Ingrese su legajo',
                        labelStyle: const TextStyle(color: color4),
                        prefixIcon: const Icon(Icons.badge, color: color4),
                        floatingLabelBehavior: FloatingLabelBehavior.never,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15.0),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onSubmitted: (value) {
                        passNode.requestFocus();
                      },
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: 300,
                    child: TextField(
                      style: const TextStyle(color: color4),
                      focusNode: passNode,
                      controller: passController,
                      keyboardType: TextInputType.number,
                      obscureText: true,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: color2,
                        labelText: 'Ingrese su contraseña',
                        labelStyle: const TextStyle(color: color4),
                        prefixIcon: const Icon(Icons.lock, color: color4),
                        floatingLabelBehavior: FloatingLabelBehavior.never,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15.0),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onSubmitted: (value) {
                        verificarCredenciales();
                      },
                    ),
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
