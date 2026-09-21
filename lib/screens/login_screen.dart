import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import 'voice_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  String? _error;
  bool _cargando = false;

  Future<void> _abrirConfiguracionIp() async {
    final controller = TextEditingController(text: AppConfig.hostIp);
    final nueva = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: LumenColors.surfaceContainer,
        title: const Row(
          children: [
            Icon(Icons.dns_outlined, color: LumenColors.primary, size: 22),
            SizedBox(width: 10),
            Text(
              'IP del Servidor',
              style: TextStyle(color: LumenColors.onSurface, fontSize: 18),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Por defecto la app se conecta al servidor en la nube (AWS). Si trabajas en una red local, indica la IP de tu PC o la URL del backend:',
                style: TextStyle(
                  color: LumenColors.onSurfaceVariant,
                  fontSize: 13,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                autofocus: true,
                style: const TextStyle(color: LumenColors.onSurface),
                decoration: const InputDecoration(
                  labelText: 'IP o Host',
                  hintText: 'Ej: 192.168.1.6 o ${AppConfig.hostNube}',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.wifi, size: 18),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Atajos rápidos:',
                style: TextStyle(
                  color: LumenColors.onSurfaceVariant,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                children: [
                  ActionChip(
                    label: const Text(
                      'Nube (AWS)',
                      style: TextStyle(fontSize: 11),
                    ),
                    onPressed: () => controller.text = AppConfig.hostNube,
                  ),
                  ActionChip(
                    label: const Text(
                      '192.168.1.6 (Casa)',
                      style: TextStyle(fontSize: 11),
                    ),
                    onPressed: () => controller.text = '192.168.1.6',
                  ),
                  ActionChip(
                    label: const Text(
                      '10.0.2.2 (Emulador)',
                      style: TextStyle(fontSize: 11),
                    ),
                    onPressed: () => controller.text = '10.0.2.2',
                  ),
                  ActionChip(
                    label: const Text(
                      '100.114.60.117 (Tailscale)',
                      style: TextStyle(fontSize: 11),
                    ),
                    onPressed: () => controller.text = '100.114.60.117',
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, controller.text.trim()),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (nueva != null && nueva.isNotEmpty) {
      await AppConfig.setHostIp(nueva);
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Servidor actualizado a: ${AppConfig.hostIp}')),
      );
    }
  }

  Future<void> _iniciarSesion() async {
    setState(() {
      _error = null;
      _cargando = true;
    });
    try {
      await AuthService.instance.loginConGoogle();
      if (!mounted) return;
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const VoiceScreen()));
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'No se pudo iniciar sesión. Intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LumenColors.surfaceContainerLowest,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: LumenColors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: LumenColors.surfaceContainer,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: LumenColors.primary.withValues(alpha: 0.25),
                            blurRadius: 24,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.theaters,
                        color: LumenColors.primary,
                        size: 32,
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Inicia sesión para continuar',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: LumenColors.onSurface,
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Necesitas una cuenta de Google para hablar con el agente de voz de Lumen Cinema.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: LumenColors.onSurfaceVariant,
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: _cargando
                          ? const Center(
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                ),
                              ),
                            )
                          : ElevatedButton.icon(
                              onPressed: _iniciarSesion,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: Colors.black87,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(24),
                                ),
                              ),
                              icon: const Icon(Icons.g_mobiledata, size: 28),
                              label: const Text(
                                'Continuar con Google',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: LumenColors.error,
                          fontSize: 13,
                        ),
                      ),
                    ],
                    // TODO: quitar este acceso directo cuando el login con
                    // Google esté configurado (cliente OAuth Android creado).
                    // Sirve solo para probar la pantalla de voz mientras tanto.
                    const SizedBox(height: 20),
                    const Divider(color: LumenColors.outlineVariant, height: 1),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: () {
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                            builder: (_) => const VoiceScreen(),
                          ),
                        );
                      },
                      icon: const Icon(
                        Icons.bug_report,
                        size: 18,
                        color: LumenColors.onSurfaceVariant,
                      ),
                      label: const Text(
                        'Probar sin iniciar sesión (temporal)',
                        style: TextStyle(
                          color: LumenColors.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    ValueListenableBuilder<String>(
                      valueListenable: AppConfig.hostNotifier,
                      builder: (context, host, _) => TextButton.icon(
                        onPressed: _abrirConfiguracionIp,
                        icon: const Icon(
                          Icons.wifi_tethering,
                          size: 16,
                          color: LumenColors.secondary,
                        ),
                        label: Text(
                          'Servidor: $host',
                          style: const TextStyle(
                            color: LumenColors.onSurfaceVariant,
                            fontSize: 11,
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
      ),
    );
  }
}
