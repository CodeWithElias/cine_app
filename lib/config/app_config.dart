import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Servidor en la nube (AWS) con HTTPS: es al que se conecta la app por defecto,
/// asi quien la instala no tiene que escribir nada.
const String _kHostNube = 'https://54-224-233-99.sslip.io';

/// IP o Host por defecto. Se puede sobreescribir al compilar con:
/// `flutter run --dart-define=HOST_IP=192.168.1.6`
const String _kDefaultHost =
    String.fromEnvironment('HOST_IP', defaultValue: _kHostNube);

/// Configuracion dinamica del entorno.
///
/// Permite cambiar la IP libremente (WiFi de casa, WiFi de la universidad,
/// zona portatil del celular, emulador o Tailscale) sin tener que recompilar
/// la aplicacion. La IP seleccionada se persiste en SharedPreferences.
class AppConfig {
  AppConfig._();

  /// El servidor en la nube: el atajo del selector para volver al valor por defecto.
  static const String hostNube = _kHostNube;

  static const _hostKey = 'lumen_host_ip';
  static String _host = _kDefaultHost;
  static final ValueNotifier<String> hostNotifier =
      ValueNotifier<String>(_host);

  /// Carga la IP guardada previamente en el dispositivo.
  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final guardada = prefs.getString(_hostKey);
      if (guardada != null && guardada.trim().isNotEmpty) {
        _host = guardada.trim();
        hostNotifier.value = _host;
      }
    } catch (_) {}
  }

  static String get hostIp => _host;

  /// Cambia la IP o URL del host y la guarda para proximos inicios.
  static Future<void> setHostIp(String nuevoHost) async {
    _host = nuevoHost.trim();
    hostNotifier.value = _host;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_hostKey, _host);
    } catch (_) {}
  }

  /// Backend NestJS (BackendParcial1/Backend) - login y datos de negocio.
  static String get backendApiUrl {
    if (_host.startsWith('http://') || _host.startsWith('https://')) {
      return '$_host/api';
    }
    return 'http://$_host:3333/api';
  }

  /// Agente de voz (back_agent) - FastAPI, transcribe/responde/sintetiza audio.
  static String get voiceAgentUrl {
    if (_host.startsWith('http://') || _host.startsWith('https://')) {
      return _host;
    }
    return 'http://$_host:8000';
  }

  /// Conversacion continua con el agente (WebSocket `/ws/voz`): mismo servicio
  /// y mismo protocolo que usa el frontend web (src/core/voice).
  static String get voiceWsUrl {
    if (_host.startsWith('https://')) {
      final sinProto = _host.substring(8);
      return 'wss://$sinProto/ws/voz';
    }
    if (_host.startsWith('http://')) {
      final sinProto = _host.substring(7);
      return 'ws://$sinProto/ws/voz';
    }
    return 'ws://$_host:8000/ws/voz';
  }
}

/// Getters globales para mantener compatibilidad total con el codigo existente.
String get kHostIp => AppConfig.hostIp;
String get kBackendApiUrl => AppConfig.backendApiUrl;
String get kVoiceAgentUrl => AppConfig.voiceAgentUrl;
String get kVoiceWsUrl => AppConfig.voiceWsUrl;

/// Mismo Client ID de Google (tipo Web) que usan el frontend y el backend.
/// En Android, Google Play Services valida la app internamente con el cliente
/// OAuth Android (paquete + SHA-1); en el codigo SIEMPRE se pasa el Web Client ID.
const String kGoogleServerClientId =
    '12414827958-jim0qgmma2n35cu2jouo165k9aahfk7n.apps.googleusercontent.com';
