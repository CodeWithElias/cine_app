import 'dart:io';

import 'package:cine_app/screens/voice_screen.dart';
import 'package:cine_app/theme/app_theme.dart';
import 'package:cine_app/utils/responsivo.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// La pantalla completa (cabecera + contenido + boton del asistente + subtitulos) en los tamaños de telefono y tablet, con los
/// plugins nativos simulados (microfono, reproductor, carpetas): solo importa que el diseño no se desborde ni se tape.
Future<void> _cargarRoboto() async {
  final raiz = Platform.environment['FLUTTER_ROOT'] ?? 'C:/dev/flutter';
  final cargador = FontLoader('Roboto');
  for (final peso in ['regular', 'medium', 'bold', 'light', 'black', 'thin']) {
    final archivo = File(
      '$raiz/bin/cache/artifacts/material_fonts/roboto-$peso.ttf',
    );
    if (await archivo.exists()) {
      cargador.addFont(
        archivo.readAsBytes().then((b) => ByteData.sublistView(b)),
      );
    }
  }
  await cargador.load();
}

void _simularPlugins(Directory carpeta) {
  final mensajero =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  for (final canal in [
    'xyz.luan/audioplayers',
    'xyz.luan/audioplayers.global',
    'com.llfbandit.record/messages',
    'dev.fluttercommunity.plus/connectivity',
  ]) {
    mensajero.setMockMethodCallHandler(MethodChannel(canal), (call) async {
      if (call.method == 'check') return ['wifi'];
      return null;
    });
  }
  mensajero.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async => carpeta.path,
  );
}

const _pantallas = <String, Size>{
  'telefono chico 320x568': Size(320, 568),
  'telefono 360x640': Size(360, 640),
  'telefono 393x852': Size(393, 852),
  'telefono grande 430x932': Size(430, 932),
  'tablet vertical 800x1280': Size(800, 1280),
  'tablet horizontal 1280x800': Size(1280, 800),
};

void main() {
  late Directory carpeta;

  setUpAll(_cargarRoboto);

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'sinconexion_ofrecido': true,
    }); // que no aparezca el ofrecimiento del modo sin conexion
    carpeta = await Directory.systemTemp.createTemp('voz_test');
    _simularPlugins(carpeta);
  });

  tearDown(() async {
    if (await carpeta.exists()) await carpeta.delete(recursive: true);
  });

  for (final entrada in _pantallas.entries) {
    for (final letra in [1.0, 2.0]) {
      testWidgets(
        'pantalla de voz · ${entrada.key} · letra ${letra == 1.0 ? 'normal' : 'al maximo'}',
        (tester) async {
          tester.view.devicePixelRatio = 2;
          tester.view.physicalSize = entrada.value * 2;
          addTearDown(tester.view.reset);

          await tester.pumpWidget(
            MaterialApp(
              theme: lumenTheme,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(letra)),
                child: Builder(builder: (c) => adaptarATamano(c, child)),
              ),
              home: const VoiceScreen(),
            ),
          );
          await tester.pump(const Duration(milliseconds: 400));

          // Inicio: cabecera con los tres botones, tarjeta de modo sin conexion y el boton del asistente.
          expect(find.text('Inicio'), findsOneWidget);
          expect(find.text('Cartelera'), findsWidgets);
          expect(find.byIcon(Icons.mic), findsOneWidget);
          expect(tester.takeException(), isNull);

          // El boton del asistente no se sale de la pantalla ni se mete debajo de la barra de navegacion.
          final boton = tester.getRect(find.byIcon(Icons.mic));
          expect(boton.bottom, lessThanOrEqualTo(entrada.value.height));
          expect(boton.left, greaterThanOrEqualTo(0));
          expect(boton.right, lessThanOrEqualTo(entrada.value.width));

          // Las otras pantallas dentro del mismo armazon.
          for (final destino in ['Cartelera', 'Mis compras']) {
            await tester.tap(find.text(destino).first);
            await tester.pump(const Duration(milliseconds: 400));
            await tester.pump(const Duration(milliseconds: 400));
            expect(tester.takeException(), isNull, reason: destino);
          }

          await tester.pumpWidget(
            const SizedBox(),
          ); // se desmonta: cancela temporizadores y sesiones
          await tester.pump(const Duration(seconds: 13));
        },
      );
    }
  }
}
