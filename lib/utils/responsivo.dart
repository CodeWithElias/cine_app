import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Medidas que se adaptan al tamaño de la pantalla: un telefono chico (320 dp de ancho), uno grande (430 dp) o una tablet.
///
/// Criterio: todo lo que en un diseño fijo mediria N pixeles se calcula a partir del ANCHO real disponible, con un minimo
/// y un maximo para que ni se vea diminuto ni se estire de mas; y en pantallas anchas el contenido no pasa de un ancho comodo
/// de lectura, centrado.
class Responsivo {
  Responsivo._(this.ancho, this.alto);

  factory Responsivo.de(BuildContext context) {
    final t = MediaQuery.sizeOf(context);
    return Responsivo._(t.width, t.height);
  }

  /// Para pruebas o para calcular con medidas conocidas.
  factory Responsivo.medidas(double ancho, double alto) =>
      Responsivo._(ancho, alto);

  final double ancho;
  final double alto;

  /// Ancho de referencia del diseno original (un telefono comun).
  static const double anchoBase = 390;

  /// Desde este ancho se considera tablet (o telefono plegable abierto).
  static const double anchoTablet = 600;

  /// El contenido no se estira mas que esto: en una tablet queda centrado, como una columna de lectura.
  static const double anchoMaximo = 640;

  bool get esTablet => ancho >= anchoTablet;

  /// Telefonos de poca altura (pantallas de 5" o con la barra de navegacion ocupando mucho): hay que ahorrar espacio vertical.
  bool get esPantallaCorta => alto < 640;

  /// Que tanto se agranda o achica lo que se mide en pixeles fijos.
  double get escala =>
      (math.min(ancho, anchoMaximo) / anchoBase).clamp(0.82, 1.2);

  /// Ancho del contenido (lo que queda dentro de la columna centrada).
  double get anchoContenido => math.min(ancho, anchoMaximo);

  /// Diametro del boton del asistente.
  double get tamanoBoton =>
      (esPantallaCorta ? 72 : 88) * escala.clamp(0.9, 1.1);

  /// Alto del cuadro de subtitulos (lo entendido + la respuesta).
  double get altoSubtitulos => esPantallaCorta ? 86 : 104;

  /// Margen lateral de la pantalla: en tablet la columna centrada ya lo da.
  double get margenLateral => ancho < 360 ? 12 : 16;
}

/// Envuelve la app para que la letra del sistema (el "tamano de fuente" que el usuario eligio en Ajustes) no rompa las
/// pantallas: se respeta hasta cierto punto (accesibilidad) y de ahi no pasa.
Widget adaptarATamano(BuildContext context, Widget? hijo) {
  final mq = MediaQuery.of(context);
  return MediaQuery(
    data: mq.copyWith(
      textScaler: mq.textScaler.clamp(
        minScaleFactor: 0.85,
        maxScaleFactor: 1.25,
      ),
    ),
    child: hijo ?? const SizedBox.shrink(),
  );
}

/// En telefonos la app se usa en vertical (el boton del asistente y la barra de compra van abajo); las tablets giran libres.
Future<void> fijarOrientacion() async {
  final vista = WidgetsBinding.instance.platformDispatcher.views.firstOrNull;
  if (vista == null) return;
  final ladoCorto =
      math.min(vista.physicalSize.width, vista.physicalSize.height) /
      vista.devicePixelRatio;
  await SystemChrome.setPreferredOrientations(
    ladoCorto < Responsivo.anchoTablet
        ? const [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]
        : DeviceOrientation.values,
  );
}
