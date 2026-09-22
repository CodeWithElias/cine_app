import 'dart:io';

import 'package:cine_app/models/cine_models.dart';
import 'package:cine_app/offline/gestor_modelos.dart';
import 'package:cine_app/services/pagos_stripe.dart';
import 'package:cine_app/state/cine_state.dart';
import 'package:cine_app/state/ui_control.dart';
import 'package:cine_app/theme/app_theme.dart';
import 'package:cine_app/utils/responsivo.dart';
import 'package:cine_app/views/cartelera_view.dart';
import 'package:cine_app/views/compra_view.dart';
import 'package:cine_app/views/inicio_view.dart';
import 'package:cine_app/views/mis_compras_view.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';

import 'apoyo_api_falsa.dart';

/// Una sala grande: 3 filas de 18 butacas (mas de las que caben en un telefono angosto con el tamaño de toque comodo).
class ApiSalaGrande extends ApiFalsa {
  @override
  Future<List<AsientoDisponibilidad>> obtenerDisponibilidad(
    int idFuncion,
  ) async => [
    for (final fila in ['A', 'B', 'C'])
      for (var n = 1; n <= 18; n++)
        AsientoDisponibilidad(
          idAsiento: fila.codeUnitAt(0) * 100 + n,
          fila: fila,
          numero: n,
          estado: 'disponible',
        ),
  ];

  @override
  Future<List<CategoriaDulceria>> listarCategoriasDulceria() async => const [
    CategoriaDulceria(idCategoria: 1, nombre: 'Pochoclos'),
    CategoriaDulceria(idCategoria: 2, nombre: 'Bebidas y gaseosas'),
    CategoriaDulceria(idCategoria: 3, nombre: 'Combos familiares'),
  ];

  @override
  Future<List<ProductoDulceria>> listarProductosDulceria() async => const [
    ProductoDulceria(
      idProducto: 1,
      idCategoria: 1,
      nombre: 'Pochoclo grande con mantequilla extra y sal',
      descripcion:
          'Un balde enorme para compartir durante toda la función sin que se acabe.',
      precioBase: 25,
      disponible: true,
    ),
    ProductoDulceria(
      idProducto: 2,
      idCategoria: 2,
      nombre: 'Gaseosa',
      precioBase: 12,
      disponible: true,
    ),
  ];

  @override
  Future<List<CompraHistorial>> listarMisCompras() async => const [
    CompraHistorial(
      venta: Venta(
        idVenta: 12345,
        idFuncion: 10,
        total: 1234.5,
        estado: 'pendiente_pago',
      ),
      pelicula:
          'El increíble viaje de Chihiro: edición conmemorativa en cuatro K',
      sala: 'Sala Premium IMAX Láser',
      fecha: '2026-09-25',
      horaInicio: '20:30:00',
    ),
  ];
}

/// Los tamaños de pantalla mas comunes (ancho x alto en puntos logicos) y el ajuste de letra mas alto que puede elegir el usuario.
const _pantallas = <String, Size>{
  'telefono chico 320x568': Size(320, 568),
  'telefono 360x640': Size(360, 640),
  'telefono 393x852': Size(393, 852),
  'telefono grande 430x932': Size(430, 932),
  'tablet vertical 800x1280': Size(800, 1280),
  'tablet horizontal 1280x800': Size(1280, 800),
};

void _tamano(WidgetTester tester, Size s) {
  tester.view.devicePixelRatio = 2;
  tester.view.physicalSize = s * 2;
  addTearDown(tester.view.reset);
}

Widget _app(Widget hijo, {double letra = 1.0}) => MaterialApp(
  theme: lumenTheme,
  // Igual que en el telefono: el usuario eligio una letra (por fuera) y la app la acota (adaptarATamano).
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(letra)),
    child: Builder(builder: (c) => adaptarATamano(c, child)),
  ),
  home: Scaffold(body: SafeArea(child: hijo)),
);

/// En las pruebas la letra por defecto (Ahem) hace que cada caracter mida lo mismo que su altura: los textos salen el doble de anchos
/// que en un telefono y aparecerian desbordes que no existen. Se carga Roboto (la que usa la app), que viene con el SDK de Flutter.
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

void main() {
  setUpAll(_cargarRoboto);

  group('Responsivo (las medidas)', () {
    test('la escala sigue al ancho pero con tope', () {
      expect(Responsivo.medidas(390, 800).escala, closeTo(1.0, 0.01));
      expect(
        Responsivo.medidas(320, 568).escala,
        closeTo(0.82, 0.01),
      ); // no baja de 0.82
      expect(
        Responsivo.medidas(1280, 800).escala,
        closeTo(1.2, 0.01),
      ); // en tablet no se estira
      expect(Responsivo.medidas(1280, 800).anchoContenido, 640);
      expect(Responsivo.medidas(360, 640).anchoContenido, 360);
    });

    test('pantalla corta y tablet', () {
      expect(Responsivo.medidas(320, 568).esPantallaCorta, isTrue);
      expect(Responsivo.medidas(393, 852).esPantallaCorta, isFalse);
      expect(Responsivo.medidas(800, 1280).esTablet, isTrue);
      expect(Responsivo.medidas(393, 852).esTablet, isFalse);
    });

    test(
      'el boton del asistente y los subtitulos se achican en pantallas cortas',
      () {
        final corta = Responsivo.medidas(320, 568);
        final normal = Responsivo.medidas(393, 852);
        expect(corta.tamanoBoton, lessThan(normal.tamanoBoton));
        expect(corta.altoSubtitulos, lessThan(normal.altoSubtitulos));
        expect(normal.tamanoBoton, inInclusiveRange(78, 98));
      },
    );
  });

  group(
    'las pantallas no se desbordan en ningun tamaño ni con la letra mas grande',
    () {
      for (final entrada in _pantallas.entries) {
        for (final letra in [1.0, 2.0]) {
          // Una letra de 2.0 es mas de lo que se permite: la app la acota a 1.25; lo que se prueba es justamente eso.
          final nombre =
              '${entrada.key} · letra ${letra == 1.0 ? 'normal' : 'al maximo'}';

          testWidgets('inicio · $nombre', (tester) async {
            _tamano(tester, entrada.value);
            final cine = CineState(ApiSalaGrande());
            await tester.pumpWidget(
              _app(
                InicioView(
                  cine: cine,
                  nombre: 'María Fernanda de los Ángeles',
                  conversando: false,
                  gestor: GestorModelos(),
                  onSinConexion: () {},
                ),
                letra: letra,
              ),
            );
            await tester.pump();
            expect(tester.takeException(), isNull);
          });

          testWidgets('cartelera · $nombre', (tester) async {
            _tamano(tester, entrada.value);
            final cine = CineState(ApiSalaGrande());
            await tester.pumpWidget(
              _app(
                CarteleraView(cine: cine, ui: UiControl()),
                letra: letra,
              ),
            );
            await tester.pump(const Duration(milliseconds: 300));
            await tester.pump(const Duration(milliseconds: 300));
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(
              const SizedBox(),
            ); // se desmontan los temporizadores del carrusel
          });

          testWidgets('asientos, dulceria y pago · $nombre', (tester) async {
            _tamano(tester, entrada.value);
            final api = ApiSalaGrande();
            final cine = CineState(
              api,
            )..seleccionarFuncion(api.pelicula, api.funcion(10, 1, '20:00:00'));
            final pagos =
                PagosStripe(); // sin Stripe: solo efectivo (el campo de tarjeta es un componente nativo)
            await tester.pumpWidget(
              _app(
                CompraView(cine: cine, ui: UiControl(), pagos: pagos),
                letra: letra,
              ),
            );
            await tester.pump(const Duration(milliseconds: 200));
            await tester.pump(const Duration(milliseconds: 200));
            expect(find.text('PANTALLA'), findsOneWidget);
            expect(tester.takeException(), isNull);

            cine.setButacas(const [
              Butaca(
                id: 'A1',
                idAsiento: 6501,
                fila: 'A',
                columna: 1,
                precio: 35,
              ),
              Butaca(
                id: 'A2',
                idAsiento: 6502,
                fila: 'A',
                columna: 2,
                precio: 35,
              ),
            ]);
            cine.setEstadoCompra(EstadoCompra.seleccionandoCandybar);
            await tester.pump(const Duration(milliseconds: 200));
            await tester.pump(const Duration(milliseconds: 200));
            expect(tester.takeException(), isNull);

            cine.setEstadoCompra(EstadoCompra.pago);
            await tester.pump(const Duration(milliseconds: 200));
            expect(tester.takeException(), isNull);

            cine.completarCompra(
              const Venta(
                idVenta: 777,
                idFuncion: 10,
                total: 70,
                estado: 'pagada',
              ),
            );
            await tester.pump(const Duration(milliseconds: 200));
            expect(tester.takeException(), isNull);
          });

          testWidgets('mis compras · $nombre', (tester) async {
            _tamano(tester, entrada.value);
            final cine = CineState(ApiSalaGrande());
            await tester.pumpWidget(
              _app(MisComprasView(cine: cine), letra: letra),
            );
            await tester.pump(const Duration(milliseconds: 200));
            await tester.tap(find.textContaining('Chihiro'));
            await tester.pump(const Duration(milliseconds: 300));
            expect(tester.takeException(), isNull);
          });
        }
      }
    },
  );

  testWidgets(
    'en un telefono angosto el mapa de butacas se achica en vez de desbordarse',
    (tester) async {
      _tamano(tester, const Size(320, 568));
      final api = ApiSalaGrande();
      final cine = CineState(api)
        ..seleccionarFuncion(api.pelicula, api.funcion(10, 1, '20:00:00'));
      await tester.pumpWidget(
        _app(CompraView(cine: cine, ui: UiControl(), pagos: PagosStripe())),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      // 18 butacas por fila: todas siguen ahi y se pueden tocar.
      expect(find.text('18'), findsNWidgets(3));
      final ultima = tester.getTopRight(find.text('18').first);
      expect(ultima.dx, lessThanOrEqualTo(320)); // no se sale de la pantalla
      await tester.tap(find.text('18').first);
      await tester.pump();
      expect(cine.butacas.map((b) => b.id), ['A18']);
    },
  );

  testWidgets(
    'en una tablet el contenido de la cartelera no se estira de borde a borde',
    (tester) async {
      _tamano(tester, const Size(1280, 800));
      final cine = CineState(ApiSalaGrande());
      await tester.pumpWidget(
        _app(
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: Responsivo.anchoMaximo,
              ),
              child: CarteleraView(cine: cine, ui: UiControl()),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      final ancho = tester.getSize(find.byType(CarteleraView)).width;
      expect(ancho, lessThanOrEqualTo(Responsivo.anchoMaximo));
      await tester.pumpWidget(const SizedBox());
    },
  );
}
