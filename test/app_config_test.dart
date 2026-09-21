import 'package:cine_app/config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A que servidor se conecta la app y como arma las URLs: por defecto la nube (AWS) con HTTPS,
/// y una IP de red local sigue funcionando con los puertos de siempre.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => AppConfig.setHostIp(AppConfig.hostNube));

  test('por defecto se conecta al servidor en la nube, todo por HTTPS', () {
    expect(AppConfig.hostIp, 'https://54-224-233-99.sslip.io');
    expect(AppConfig.backendApiUrl, 'https://54-224-233-99.sslip.io/api');
    expect(AppConfig.voiceAgentUrl, 'https://54-224-233-99.sslip.io');
    expect(AppConfig.voiceWsUrl, 'wss://54-224-233-99.sslip.io/ws/voz');
  });

  test('una IP de red local vuelve a http con el backend en el 3333 y el agente en el 8000', () async {
    await AppConfig.setHostIp('192.168.1.6');

    expect(AppConfig.backendApiUrl, 'http://192.168.1.6:3333/api');
    expect(AppConfig.voiceAgentUrl, 'http://192.168.1.6:8000');
    expect(AppConfig.voiceWsUrl, 'ws://192.168.1.6:8000/ws/voz');
  });

  test('el atajo «Nube (AWS)» del selector devuelve al valor por defecto', () async {
    await AppConfig.setHostIp('10.0.2.2');
    expect(AppConfig.backendApiUrl, 'http://10.0.2.2:3333/api');

    await AppConfig.setHostIp(AppConfig.hostNube);

    expect(AppConfig.hostIp, 'https://54-224-233-99.sslip.io');
    expect(AppConfig.voiceWsUrl, 'wss://54-224-233-99.sslip.io/ws/voz');
  });

  test('lo elegido en el selector se recuerda al volver a abrir la app', () async {
    await AppConfig.setHostIp('192.168.1.6');

    await AppConfig.init();

    expect(AppConfig.hostIp, '192.168.1.6');
  });
}
