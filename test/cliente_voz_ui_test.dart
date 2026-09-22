import 'package:cine_app/models/cine_models.dart';
import 'apoyo_api_falsa.dart';
import 'package:cine_app/services/pagos_stripe.dart';
import 'package:cine_app/state/cine_state.dart';
import 'package:cine_app/state/ui_action_handler.dart';
import 'package:cine_app/state/ui_control.dart';
import 'package:cine_app/theme/app_theme.dart';
import 'package:cine_app/views/cartelera_view.dart';
import 'package:cine_app/models/estrenos.dart';
import 'package:cine_app/views/compra_view.dart';
import 'package:cine_app/widgets/estrenos_carousel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _peliculaJson() => {
  'idPelicula': 1,
  'titulo': 'Oppenheimer',
  'duracionMin': 180,
  'estado': 'activa',
};
Map<String, dynamic> _funcionJson() => {
  'idFuncion': 10,
  'idPelicula': 1,
  'idSala': 7,
  'idPrecio': 3,
  'fecha': ApiFalsa.fecha,
  'horaInicio': '20:00:00',
  'horaFin': '23:00:00',
  'estado': 'programada',
};

void main() {
  group('UiActionHandler (las ui_action del agente mueven la app)', () {
    late CineState cine;
    late UiControl ui;
    late UiActionHandler handler;
    final versiones = <int>[];

    setUp(() {
      cine = CineState(ApiFalsa());
      ui = UiControl();
      versiones.clear();
      handler = UiActionHandler(cine: cine, ui: ui, alAplicar: versiones.add);
    });

    Future<void> aplicar(List<Map<String, dynamic>> acciones, [int? v]) async {
      handler.aplicar(acciones, v);
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }

    test(
      'elegir funcion arranca la compra y trae asientos, precio y sala',
      () async {
        await aplicar([
          {
            'tipo': 'compra.seleccionar_funcion',
            'pelicula': _peliculaJson(),
            'funcion': _funcionJson(),
            'horario': '20:00:00',
          },
          {'tipo': 'navegar', 'destino': 'asientos'},
        ], 1);
        expect(cine.peliculaSeleccionada?.titulo, 'Oppenheimer');
        expect(cine.funcionSeleccionada?.idFuncion, 10);
        expect(cine.pantalla, Pantalla.compra);
        expect(cine.estadoCompra, EstadoCompra.seleccionandoAsientos);
        expect(cine.disponibilidad.length, 8);
        expect(cine.precioUnitario, 35);
        expect(cine.salaSeleccionada?.nombre, 'Sala 1');
        expect(versiones, [1]); // la pantalla avisa que ya aplico la tanda
      },
    );

    test('butacas y dulceria del agente se suman al total', () async {
      await aplicar([
        {
          'tipo': 'compra.seleccionar_funcion',
          'pelicula': _peliculaJson(),
          'funcion': _funcionJson(),
          'horario': '20:00:00',
        },
        {
          'tipo': 'compra.seleccionar_butacas',
          'butacas': [
            {
              'id': 'B1',
              'idAsiento': 11,
              'fila': 'B',
              'columna': 1,
              'estado': 'disponible',
              'precio': 35,
            },
            {
              'id': 'B2',
              'idAsiento': 12,
              'fila': 'B',
              'columna': 2,
              'estado': 'disponible',
              'precio': 35,
            },
          ],
        },
        {
          'tipo': 'compra.candybar',
          'items': [
            {
              'id': '4',
              'nombre': 'Pochoclo',
              'descripcion': '',
              'precio': 20,
              'imagenUrl': '',
              'cantidad': 2,
            },
          ],
        },
      ]);
      expect(cine.butacas.map((b) => b.id), ['B1', 'B2']);
      expect(cine.total, 110);
      expect(cine.contexto(), {
        'idPelicula': 1,
        'idFuncion': 10,
        'asientos': [
          {'id': 'B1', 'idAsiento': 11},
          {'id': 'B2', 'idAsiento': 12},
        ],
        'dulceria': [
          {'idProducto': 4, 'cantidad': 2},
        ],
      });
    });

    test('navegar cambia de pantalla y de paso de la compra', () async {
      await aplicar([
        {'tipo': 'navegar', 'destino': 'cartelera'},
      ]);
      expect(cine.pantalla, Pantalla.cartelera);
      await aplicar([
        {'tipo': 'navegar', 'destino': 'candybar'},
      ]);
      expect(cine.pantalla, Pantalla.compra);
      expect(cine.estadoCompra, EstadoCompra.seleccionandoCandybar);
      await aplicar([
        {'tipo': 'navegar', 'destino': 'mis_compras'},
      ]);
      expect(cine.pantalla, Pantalla.misCompras);
    });

    test('filtrar y mostrar la cartelera', () async {
      await aplicar([
        {'tipo': 'cartelera.filtrar', 'busqueda': 'barbie'},
      ]);
      expect(ui.filtro?.busqueda, 'barbie');
      await aplicar([
        {
          'tipo': 'cartelera.mostrar',
          'ids': [1],
          'idFuncion': 10,
          'pausa_ms': 5,
        },
      ]);
      expect(ui.filtro?.busqueda, isNull); // mostrar limpia el filtro anterior
      expect(ui.resaltado?.ids, [1]);
      expect(ui.resaltado?.idFuncion, 10);
      expect(cine.pantalla, Pantalla.cartelera);
    });

    test(
      'mostrar se omite si ya esta en la compra y solo cambia la funcion',
      () async {
        cine.irA(Pantalla.compra);
        await aplicar([
          {
            'tipo': 'cartelera.mostrar',
            'ids': [1],
            'omitir_en_compra': true,
          },
        ]);
        expect(cine.pantalla, Pantalla.compra);
        expect(ui.resaltado, isNull);
      },
    );

    test(
      'ventanas: confirmacion y ticket se abren y se cierran; la compra completada cierra la confirmacion',
      () async {
        await aplicar([
          {
            'tipo': 'ventana.abrir',
            'ventana': 'confirmacion',
            'datos': {'titulo': 'Confirma tu compra', 'total': 70},
          },
          {
            'tipo': 'ventana.abrir',
            'ventana': 'reporte',
            'datos': {},
          }, // de administrador: se ignora
        ]);
        expect(
          ui.ventana(TipoVentana.confirmacion)?['titulo'],
          'Confirma tu compra',
        );
        await aplicar([
          {
            'tipo': 'compra.completada',
            'venta': {
              'idVenta': 99,
              'idFuncion': 10,
              'total': '70.00',
              'estado': 'pagada',
            },
          },
        ]);
        expect(ui.ventana(TipoVentana.confirmacion), isNull);
        expect(cine.estadoCompra, EstadoCompra.completado);
        expect(cine.ventaCreada?.idVenta, 99);
        expect(
          cine.contexto()['idPelicula'],
          isNull,
        ); // una compra pagada no cuenta como compra en curso
      },
    );

    test('quitar pelicula suelta la funcion y los asientos', () async {
      await aplicar([
        {
          'tipo': 'compra.seleccionar_funcion',
          'pelicula': _peliculaJson(),
          'funcion': _funcionJson(),
          'horario': '20:00:00',
        },
        {'tipo': 'compra.quitar_pelicula'},
      ]);
      expect(cine.peliculaSeleccionada, isNull);
      expect(cine.funcionSeleccionada, isNull);
      expect(cine.butacas, isEmpty);
    });

    test('una accion desconocida no rompe la tanda ni la version', () async {
      await aplicar([
        {'tipo': 'pago.abrir', 'venta': {}},
        {'tipo': 'admin.abrir_tab', 'tab': 'x'},
      ], 7);
      expect(versiones, [7]);
    });

    test('las tandas se aplican en orden aunque una espere', () async {
      handler.aplicar([
        {
          'tipo': 'cartelera.mostrar',
          'ids': [1],
          'pausa_ms': 60,
        },
      ], 1);
      handler.aplicar([
        {'tipo': 'navegar', 'destino': 'asientos'},
      ], 2);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(
        cine.pantalla,
        Pantalla.cartelera,
      ); // la segunda espera a que termine la pausa de la primera
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(cine.pantalla, Pantalla.compra);
      expect(versiones, [1, 2]);
    });
  });

  group('vistas', () {
    Widget envolver(Widget hijo) => MaterialApp(
      theme: lumenTheme,
      home: Scaffold(body: hijo),
    );

    /// Una pantalla alta: la cartelera es una lista y el carrusel de estrenos ocupa lo primero.
    void pantallaAlta(WidgetTester tester) {
      tester.view.physicalSize = const Size(800, 3200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    testWidgets(
      'la cartelera lista peliculas con sus horarios y filtra por lo que pide el agente',
      (tester) async {
        pantallaAlta(tester);
        final cine = CineState(ApiFalsa());
        final ui = UiControl();
        await tester.pumpWidget(envolver(CarteleraView(cine: cine, ui: ui)));
        await tester.pumpAndSettle();
        expect(
          find.text('HORARIOS'),
          findsNWidgets(2),
        ); // una tarjeta por pelicula
        expect(find.textContaining('20:00'), findsOneWidget);

        ui.filtrarCartelera(busqueda: 'barbie');
        await tester.pumpAndSettle();
        expect(find.text('HORARIOS'), findsOneWidget); // solo queda Barbie
        expect(find.textContaining('18:30'), findsOneWidget);

        ui.resaltarCartelera([2]);
        await tester.pump();
        expect(find.text('SEÑALADA POR LUMEN'), findsOneWidget);
        await tester.pump(
          const Duration(seconds: 13),
        ); // el resaltado se apaga solo (el carrusel rota siempre: no se espera a que "asiente")
        await tester.pump();
        expect(find.text('SEÑALADA POR LUMEN'), findsNothing);
      },
    );

    double desplazamiento(WidgetTester tester) => tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byType(SingleChildScrollView).first,
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position
        .pixels;

    testWidgets(
      'cuando el agente señala una pelicula, la lista se desplaza hasta su tarjeta',
      (tester) async {
        final cine = CineState(ApiFalsa());
        final ui = UiControl();
        await tester.pumpWidget(envolver(CarteleraView(cine: cine, ui: ui)));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
        expect(desplazamiento(tester), 0);

        ui.resaltarCartelera([
          2,
        ]); // Barbie: esta debajo del carrusel, fuera de la pantalla
        for (var i = 0; i < 12; i++) {
          await tester.pump(
            const Duration(milliseconds: 100),
          ); // cuadro a cuadro: la animacion del desplazamiento avanza con los cuadros
        }
        expect(desplazamiento(tester), greaterThan(100));
        await tester.pumpWidget(const SizedBox());
        await tester.pump(
          const Duration(seconds: 13),
        ); // vence el temporizador del resaltado
      },
    );

    testWidgets(
      'si el agente señala la pelicula al abrir la cartelera (aun cargando), igual se desplaza cuando aparece',
      (tester) async {
        final cine = CineState(ApiFalsa());
        final ui = UiControl()
          ..resaltarCartelera([
            2,
          ]); // el pedido llega ANTES de que exista la pantalla
        await tester.pumpWidget(envolver(CarteleraView(cine: cine, ui: ui)));
        for (var i = 0; i < 12; i++) {
          await tester.pump(const Duration(milliseconds: 150));
        }
        expect(desplazamiento(tester), greaterThan(100));
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 13));
      },
    );

    testWidgets(
      'el carrusel de estrenos muestra la ficha, el trailer y compra lo que esta en cartelera',
      (tester) async {
        Pelicula? comprada;
        const duna = Pelicula(
          idPelicula: 5,
          titulo: 'Duna: Parte Dos',
          duracionMin: 166,
          estado: 'activa',
        );
        await tester.pumpWidget(
          envolver(
            SingleChildScrollView(
              child: EstrenosCarousel(
                cartelera: const [duna],
                onComprar: (p) => comprada = p,
              ),
            ),
          ),
        );
        await tester.pump();
        expect(find.text('ESTRENOS Y TRÁILERS'), findsOneWidget);
        expect(
          find.text('Dune: Part Two'),
          findsOneWidget,
        ); // el primero de la lista fija
        expect(find.text('Ver tráiler'), findsOneWidget);
        expect(find.text('EN CARTELERA'), findsOneWidget);
        await tester.tap(find.text('Comprar'));
        expect(comprada?.idPelicula, 5);
        await tester.pumpWidget(
          const SizedBox(),
        ); // se desmonta: cancela su temporizador de rotacion
      },
    );

    test(
      'los estrenos se enlazan con la cartelera real y suman las peliculas que no estaban',
      () {
        final api = ApiFalsa();
        final lista = estrenosConCartelera([api.pelicula, api.barbie]);
        expect(
          lista
              .firstWhere((e) => e.titulo == 'Oppenheimer')
              .peliculaReal
              ?.idPelicula,
          1,
        );
        expect(
          lista.firstWhere((e) => e.titulo == 'Dune: Part Two').peliculaReal,
          isNull,
        );
        expect(
          lista.last.titulo,
          'Barbie',
        ); // no estaba en la lista fija: se agrega con su ficha
        expect(lista.length, estrenosBase.length + 1);
        expect(
          estrenosBase.first.urlTrailer.toString(),
          'https://www.youtube.com/watch?v=Way9Dexny3w',
        );
      },
    );

    testWidgets(
      'tocar un horario lleva a la compra y se eligen asientos tocando',
      (tester) async {
        pantallaAlta(tester);
        final cine = CineState(ApiFalsa());
        final ui = UiControl();
        await tester.pumpWidget(envolver(CarteleraView(cine: cine, ui: ui)));
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining('20:00'));
        await tester.pumpAndSettle();
        expect(cine.pantalla, Pantalla.compra);
        expect(cine.funcionSeleccionada?.idFuncion, 10);

        await tester.pumpWidget(
          envolver(CompraView(cine: cine, ui: ui, pagos: PagosStripe())),
        );
        await tester.pumpAndSettle();
        expect(find.text('PANTALLA'), findsOneWidget);
        await tester.tap(find.text('2').first); // A2
        await tester.pump();
        expect(cine.butacas.map((b) => b.id), ['A2']);
        expect(cine.total, 35);
        expect(find.text('35.00 Bs'), findsWidgets);
      },
    );

    testWidgets('sin asientos no se puede continuar', (tester) async {
      final cine = CineState(ApiFalsa());
      final api = ApiFalsa();
      cine.seleccionarFuncion(api.pelicula, api.funcion(10, 1, '20:00:00'));
      await tester.pumpWidget(
        envolver(CompraView(cine: cine, ui: UiControl(), pagos: PagosStripe())),
      );
      await tester.pumpAndSettle();
      final boton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Continuar'),
      );
      expect(boton.onPressed, isNull);
    });
  });
}
