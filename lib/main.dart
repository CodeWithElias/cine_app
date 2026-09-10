import 'package:flutter/material.dart';

import 'screens/login_screen.dart';
import 'screens/voice_screen.dart';
import 'services/auth_service.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const CineApp());
}

class CineApp extends StatelessWidget {
  const CineApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lumen Cinema',
      debugShowCheckedModeBanner: false,
      theme: lumenTheme,
      home: const _StartupGate(),
    );
  }
}

/// Inicializa el login con Google y revisa si ya hay una sesion guardada
/// antes de decidir si mostrar el login o ir directo a la pantalla de voz.
class _StartupGate extends StatefulWidget {
  const _StartupGate();

  @override
  State<_StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<_StartupGate> {
  late final Future<void> _init;

  @override
  void initState() {
    super.initState();
    _init = AuthService.instance.init();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _init,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            backgroundColor: LumenColors.surfaceContainerLowest,
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return AuthService.instance.estaLogueado
            ? const VoiceScreen()
            : const LoginScreen();
      },
    );
  }
}
