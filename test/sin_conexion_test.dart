import 'dart:convert';
import 'dart:io';

import 'package:cine_app/models/cine_models.dart';
import 'package:cine_app/offline/cache_local.dart';
import 'package:cine_app/offline/gestor_modelos.dart';
import 'package:cine_app/offline/interprete_local.dart';
import 'package:cine_app/offline/modelos_manifiesto.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------- interprete

final _ahora = DateTime(
  2026,
  9,
  21,
  12,
  0,
); // lunes 21 de septiembre de 2026, mediodia

Funcion _f(int id, int idPelicula, String fecha, String hora) => Funcion(
  idFuncion: id,
  idPelicula: idPelicula,
  idSala: 1,
  fecha: fecha,
  horaInicio: hora,
  horaFin: '23:00:00',
  estado: 'programada',
);

Pelicula _p(int id, String titulo) => Pelicula(
  idPelicula: id,
  titulo: titulo,
  duracionMin: 120,
  estado: 'activa',
);

DatosLocales _datos({List<CompraHistorial> compras = const []}) => DatosLocales(
  peliculas: [
    _p(1, 'Oppenheimer'),
    _p(2, 'Barbie'),
    _p(3, 'Spider-Man: Beyond'),
    _p(4, 'El Viaje de Chihiro'),
    _p(5, 'Blade Runner 2049'),
  ],
  funciones: [
    _f(10, 2, '2026-09-21', '20:30:00'), // Barbie hoy 20:30
    _f(11, 2, '2026-09-22', '18:00:00'), // Barbie mañana
    _f(12, 1, '2026-09-21', '11:00:00'), // Oppenheimer hoy 11:00: YA paso
    _f(13, 1, '2026-09-23', '16:15:00'),
    _f(14, 4, '2026-09-21', '19:45:00'),
  ],
  compras: compras,
);

InterpreteLocal _interprete({List<CompraHistorial> compras = const []}) =>
    InterpreteLocal(_datos(compras: compras), ahora: () => _ahora);

void main() {
  group('horaHablada / diaHablado', () {
    test('se dice como una persona', () {
      expect(horaHablada('20:30:00'), 'las ocho y media de la noche');
      expect(horaHablada('13:00:00'), 'la una de la tarde');
      expect(horaHablada('19:45:00'), 'las ocho menos cuarto de la noche');
      expect(horaHablada('00:15:00'), 'las doce y cuarto de la madrugada');
      expect(horaHablada('08:05:00'), 'las ocho y 5 de la mañana');
    });

    test('hoy, mañana y el resto de los dias', () {
      expect(diaHablado('2026-09-21', _ahora), 'hoy');
      expect(diaHablado('2026-09-22', _ahora), 'mañana');
      expect(diaHablado('2026-09-25', _ahora), 'el viernes 25 de septiembre');
    });
  });

  group('esAlucinacion (lo que Whisper inventa con ruido o eco)', () {
    test('detecta frases inventadas y bucles', () {
      expect(
        esAlucinacion('Subtítulos realizados por la comunidad de Amara.org'),
        isTrue,
      );
      expect(
        esAlucinacion(
          'La tinta de la tinta de la tinta de la tinta de la tinta.',
        ),
        isTrue,
      );
      expect(esAlucinacion('sí sí sí sí sí'), isTrue);
      expect(esAlucinacion('  '), isTrue);
    });

    test('no marca frases reales', () {
      for (final t in [
        'Adiós, adiós, adiós.',
        '¿Qué hay en cartelera?',
        'Dos entradas, dos gaseosas y dos nachos',
      ]) {
        expect(esAlucinacion(t), isFalse, reason: t);
      }
    });
  });

  group('InterpreteLocal (sin internet)', () {
    test('cartelera: dice las peliculas y lleva a la pantalla', () {
      final r = _interprete().interpretar('¿Qué hay en cartelera?');
      expect(r.texto, contains('5 películas en cartelera'));
      expect(r.texto, contains('Oppenheimer'));
      expect(r.texto, contains('y 1 más')); // dice 4 y cuenta las que faltan
      expect(r.acciones.first, {'tipo': 'navegar', 'destino': 'cartelera'});
      expect(r.necesitaConexion, isFalse);
    });

    test(
      'horarios de una pelicula: solo las funciones que faltan, con la hora hablada',
      () {
        final r = _interprete().interpretar('¿A qué hora es Barbie?');
        expect(
          r.texto,
          '«Barbie» tiene funciones hoy a las ocho y media de la noche y mañana a las seis de la tarde.',
        );
        expect(r.acciones.single['tipo'], 'cartelera.mostrar');
        expect(r.acciones.single['ids'], [2]);
      },
    );

    test('una funcion que ya paso hoy no se ofrece', () {
      final r = _interprete().interpretar('horarios de Oppenheimer');
      expect(r.texto, isNot(contains('once')));
      expect(r.texto, contains('el miércoles 23 de septiembre'));
    });

    test(
      'entiende titulos mal escritos por el reconocedor y titulos largos',
      () {
        expect(
          _interprete()
              .interpretar('cuando pasan operheimer')
              .acciones
              .single['ids'],
          [1],
        );
        expect(
          _interprete()
              .interpretar('que horarios tiene el viaje de chihiro')
              .acciones
              .single['ids'],
          [4],
        );
        expect(
          _interprete()
              .interpretar('funciones de blade runner')
              .acciones
              .single['ids'],
          [5],
        );
      },
    );

    test('comprar, pagar o pedir dulceria necesita conexion', () {
      for (final frase in [
        'quiero dos entradas para Barbie',
        'quiero comprar',
        'agregame unos pochoclos',
        'quiero el asiento A5',
        'confirmo',
      ]) {
        final r = _interprete().interpretar(frase);
        expect(r.necesitaConexion, isTrue, reason: frase);
        expect(r.texto, contains('conexión'));
        expect(r.acciones, isEmpty);
      }
    });

    test('mis compras no se confunde con comprar', () {
      final vacia = _interprete().interpretar('¿qué compras hice?');
      expect(vacia.necesitaConexion, isFalse);
      expect(vacia.acciones.single['destino'], 'mis_compras');

      final compra = CompraHistorial(
        venta: const Venta(
          idVenta: 9,
          idFuncion: 10,
          total: 70,
          estado: 'pagada',
        ),
        pelicula: 'Barbie',
        sala: 'Sala 1',
        fecha: '2026-09-21',
        horaInicio: '20:30:00',
      );
      final r = _interprete(compras: [compra]).interpretar('mis compras');
      expect(r.texto, contains('1 compra guardadas'));
      expect(r.texto, contains('«Barbie», hoy a las ocho y media de la noche'));
    });

    test('funciones del dia y de mañana', () {
      expect(
        _interprete().interpretar('¿qué funciones hay hoy?').texto,
        startsWith('hoy hay 2 funciones'),
      );
      expect(
        _interprete().interpretar('funciones de mañana').texto,
        contains('Barbie a las seis de la tarde'),
      );
    });

    test('saludo, gracias, adios, inicio y algo que no entiende', () {
      expect(_interprete().interpretar('hola').texto, contains('sin conexión'));
      expect(_interprete().interpretar('gracias').texto, contains('De nada'));
      expect(_interprete().interpretar('adiós').texto, contains('Hasta luego'));
      expect(
        _interprete().interpretar('menú principal').acciones.single['destino'],
        'inicio',
      );
      expect(
        _interprete().interpretar('blablabla').texto,
        contains('Sin conexión solo puedo'),
      );
    });

    test('sin copia de la cartelera lo dice en vez de inventar', () {
      final r = InterpreteLocal(
        const DatosLocales(),
        ahora: () => _ahora,
      ).interpretar('qué hay en cartelera');
      expect(r.texto, contains('No tengo guardada la cartelera'));
    });
  });

  // -------------------------------------------------------------------------- copia local

  group('CacheLocal', () {
    late Directory carpeta;
    setUp(() async {
      carpeta = await Directory.systemTemp.createTemp('cache_test');
      CacheLocal.instance.carpetaDePrueba = carpeta;
    });
    tearDown(() async {
      CacheLocal.instance.carpetaDePrueba = null;
      if (await carpeta.exists()) await carpeta.delete(recursive: true);
    });

    test('guarda y lee la copia con su fecha', () async {
      await CacheLocal.instance.guardar('peliculas', [
        _p(1, 'Barbie').toJson(),
      ]);
      final copia = await CacheLocal.instance.leer('peliculas');
      expect(copia, isNotNull);
      expect(
        Pelicula.fromJson(
          (copia!.datos as List).first as Map<String, dynamic>,
        ).titulo,
        'Barbie',
      );
      expect(DateTime.now().difference(copia.guardado).inSeconds, lessThan(5));
    });

    test(
      'lo que no existe o esta roto no lanza: simplemente no hay copia',
      () async {
        expect(await CacheLocal.instance.leer('nada'), isNull);
        await File(
          '${carpeta.path}/roto.json',
        ).writeAsString('{ esto no es json');
        expect(await CacheLocal.instance.leer('roto'), isNull);
      },
    );

    test('los modelos ida y vuelta por JSON (asi se guardan las copias)', () {
      final f = _f(7, 2, '2026-09-21', '20:30:00');
      expect(Funcion.fromJson(f.toJson()).horaInicio, '20:30:00');
      const v = Venta(idVenta: 3, idFuncion: 7, total: 70.5, estado: 'pagada');
      final c = CompraHistorial(
        venta: v,
        pelicula: 'Barbie',
        sala: 'Sala 2',
        fecha: '2026-09-21',
        horaInicio: '20:30:00',
      );
      final otra = CompraHistorial.fromJson(
        jsonDecode(jsonEncode(c.toJson())) as Map<String, dynamic>,
      );
      expect(otra.pelicula, 'Barbie');
      expect(otra.sala, 'Sala 2');
      expect(otra.venta.total, 70.5);
    });
  });

  // -------------------------------------------------------------------------- catalogo

  group('catalogo de modelos', () {
    test(
      'los tamaños son los de los archivos reales y el total ronda lo anunciado',
      () {
        expect(paquete('stt_tiny').bytesTotal, greaterThan(95 * 1024 * 1024));
        expect(paquete('stt_tiny').bytesTotal, lessThan(110 * 1024 * 1024));
        expect(paquete('tts').archivos.length, 2 + archivosEspeak.length);
        final recomendado =
            paquete('stt_tiny').bytesTotal + paquete('tts').bytesTotal;
        expect(recomendado / 1024 / 1024, inInclusiveRange(180, 215));
      },
    );

    test('los archivos grandes traen su sha256 para verificarlos', () {
      for (final a in paquete(
        'stt_tiny',
      ).archivos.where((a) => a.bytes > 5 * 1024 * 1024)) {
        expect(a.sha256, isNotNull, reason: a.ruta);
        expect(a.sha256!.length, 64);
      }
    });
  });

  // -------------------------------------------------------------------------- descarga

  group('GestorModelos: descarga, verificacion, reanudacion y borrado', () {
    late HttpServer servidor;
    late Directory raiz;
    late Map<String, List<int>> archivos;
    var cortarPrimeraDescargaEn =
        -1; // bytes tras los que el servidor corta la conexion (una sola vez)
    var pedidos = <String>[];
    var rangosRecibidos = <String>[];

    List<int> bytesDe(int n, int semilla) =>
        List<int>.generate(n, (i) => (i * 31 + semilla) & 0xff);

    PaqueteModelo paqueteDePrueba(
      String id,
      Map<String, List<int>> contenido, {
      bool shaMalo = false,
    }) => PaqueteModelo(
      id: id,
      nombre: id,
      descripcion: '',
      archivos: [
        for (final e in contenido.entries)
          ArchivoDescarga(
            url: 'http://127.0.0.1:${servidor.port}/${e.key}',
            ruta: e.key,
            bytes: e.value.length,
            sha256: e.value.length > 1000
                ? (shaMalo ? '0' * 64 : sha256.convert(e.value).toString())
                : null,
          ),
      ],
    );

    GestorModelos gestor(
      List<PaqueteModelo> paquetes, {
      List<ConnectivityResult> red = const [ConnectivityResult.wifi],
    }) => GestorModelos(
      raiz: raiz,
      paquetes: paquetes,
      conectividad: () async => red,
    );

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      raiz = await Directory.systemTemp.createTemp('modelos_test');
      cortarPrimeraDescargaEn = -1;
      pedidos = [];
      rangosRecibidos = [];
      archivos = {
        'stt/encoder.onnx': bytesDe(300000, 1),
        'stt/tokens.txt': bytesDe(500, 2),
        'tts/voz.onnx': bytesDe(200000, 3),
        'tts/espeak/a_dict': bytesDe(300, 4),
        'tts/espeak/b_dict': bytesDe(400, 5),
      };
      servidor = await HttpServer.bind('127.0.0.1', 0);
      servidor.listen((req) async {
        final ruta = req.uri.path.substring(1);
        pedidos.add(ruta);
        final datos = archivos[ruta];
        if (datos == null) {
          req.response.statusCode = 404;
          await req.response.close();
          return;
        }
        var desde = 0;
        final rango = req.headers.value('range');
        if (rango != null) {
          rangosRecibidos.add(rango);
          desde = int.parse(
            RegExp(r'bytes=(\d+)-').firstMatch(rango)!.group(1)!,
          );
          req.response.statusCode = 206;
          req.response.headers.set(
            'content-range',
            'bytes $desde-${datos.length - 1}/${datos.length}',
          );
        }
        final cuerpo = datos.sublist(desde);
        if (cortarPrimeraDescargaEn >= 0 &&
            cuerpo.length > cortarPrimeraDescargaEn &&
            desde == 0) {
          final corte = cortarPrimeraDescargaEn;
          cortarPrimeraDescargaEn = -1;
          // Promete todo el archivo, manda una parte y corta la conexion (como cuando se va la señal).
          final socket = await req.response.detachSocket(writeHeaders: false);
          socket.add(
            utf8.encode(
              'HTTP/1.1 200 OK\r\ncontent-length: ${cuerpo.length}\r\n\r\n',
            ),
          );
          socket.add(cuerpo.sublist(0, corte));
          await socket.flush();
          await Future<void>.delayed(
            const Duration(milliseconds: 50),
          ); // deja que llegue antes de cortar
          socket.destroy();
          return;
        }
        req.response.contentLength = cuerpo.length;
        req.response.add(cuerpo);
        await req.response.close();
      });
    });

    tearDown(() async {
      await servidor.close(force: true);
      if (await raiz.exists()) await raiz.delete(recursive: true);
    });

    PaqueteModelo stt() => paqueteDePrueba('stt_tiny', {
      'stt/encoder.onnx': archivos['stt/encoder.onnx']!,
      'stt/tokens.txt': archivos['stt/tokens.txt']!,
    });
    PaqueteModelo tts() => paqueteDePrueba('tts', {
      'tts/voz.onnx': archivos['tts/voz.onnx']!,
      'tts/espeak/a_dict': archivos['tts/espeak/a_dict']!,
      'tts/espeak/b_dict': archivos['tts/espeak/b_dict']!,
    });

    test(
      'descarga todo, lo verifica y el modo sin conexion queda listo',
      () async {
        final g = gestor([stt(), tts()]);
        await g.iniciar();
        expect(g.listoParaVoz, isFalse);
        await g.descargarRecomendados();
        expect(g.estado('stt_tiny'), EstadoPaquete.listo);
        expect(g.estado('tts'), EstadoPaquete.listo);
        expect(g.listoParaVoz, isTrue);
        expect(g.progreso('tts'), 1.0);
        expect(
          await File('${raiz.path}/stt_tiny/stt/encoder.onnx').readAsBytes(),
          archivos['stt/encoder.onnx'],
        );
        expect(
          await File('${raiz.path}/tts/tts/espeak/b_dict').readAsBytes(),
          archivos['tts/espeak/b_dict'],
        );
        expect(
          Directory(
            raiz.path,
          ).listSync(recursive: true).where((e) => e.path.endsWith('.part')),
          isEmpty,
        );
      },
    );

    test('sin descargar solo uno de los dos, no esta listo', () async {
      final g = gestor([stt(), tts()]);
      await g.iniciar();
      await g.descargar('stt_tiny');
      expect(g.estado('stt_tiny'), EstadoPaquete.listo);
      expect(g.listoParaVoz, isFalse); // falta la voz del asistente
    });

    test('lo descargado sigue ahi al volver a abrir la app', () async {
      final g = gestor([stt(), tts()]);
      await g.iniciar();
      await g.descargarRecomendados();
      final nuevo = gestor([stt(), tts()]);
      await nuevo.iniciar();
      expect(nuevo.listoParaVoz, isTrue);
    });

    test(
      'si se corta la conexion queda pausado y "reanudar" sigue donde quedo (pedido Range)',
      () async {
        cortarPrimeraDescargaEn = 120000;
        final g = gestor([stt(), tts()]);
        await g.iniciar();
        await g.descargar('stt_tiny');
        expect(g.estado('stt_tiny'), EstadoPaquete.error);
        expect(g.error('stt_tiny'), contains('Reanudar'));
        final parcial = File('${raiz.path}/stt_tiny/stt/encoder.onnx.part');
        expect(await parcial.exists(), isTrue);
        final yaBajado = await parcial.length();
        expect(
          yaBajado,
          inInclusiveRange(1, 120000),
        ); // lo que alcanzo a llegar antes del corte

        await g.descargar('stt_tiny'); // reanudar
        expect(g.estado('stt_tiny'), EstadoPaquete.listo);
        expect(
          rangosRecibidos,
          contains('bytes=$yaBajado-'),
        ); // pidio SOLO lo que faltaba
        expect(
          await File('${raiz.path}/stt_tiny/stt/encoder.onnx').readAsBytes(),
          archivos['stt/encoder.onnx'],
        ); // integro
      },
    );

    test('un archivo dañado (huella distinta) se rechaza y se borra', () async {
      final g = gestor([
        paqueteDePrueba('stt_tiny', {
          'stt/encoder.onnx': archivos['stt/encoder.onnx']!,
        }, shaMalo: true),
        tts(),
      ]);
      await g.iniciar();
      await g.descargar('stt_tiny');
      expect(g.estado('stt_tiny'), EstadoPaquete.error);
      expect(g.error('stt_tiny'), contains('dañado'));
      expect(
        await File('${raiz.path}/stt_tiny/stt/encoder.onnx').exists(),
        isFalse,
      );
      expect(
        await File('${raiz.path}/stt_tiny/stt/encoder.onnx.part').exists(),
        isFalse,
      );
    });

    test('un archivo que llega incompleto se rechaza', () async {
      final incompleto = paqueteDePrueba('stt_tiny', {
        'stt/encoder.onnx': archivos['stt/encoder.onnx']!,
      });
      // El catalogo dice que pesa mas de lo que el servidor entrega.
      final mentiroso = PaqueteModelo(
        id: 'stt_tiny',
        nombre: 'x',
        descripcion: '',
        archivos: [
          ArchivoDescarga(
            url: incompleto.archivos.first.url,
            ruta: 'stt/encoder.onnx',
            bytes: 400000,
          ),
        ],
      );
      final g = gestor([mentiroso, tts()]);
      await g.iniciar();
      await g.descargar('stt_tiny');
      expect(g.estado('stt_tiny'), EstadoPaquete.error);
      expect(g.error('stt_tiny'), contains('incompleto'));
    });

    test('con "solo Wi‑Fi" y datos moviles no descarga nada', () async {
      final g = gestor([stt(), tts()], red: const [ConnectivityResult.mobile]);
      await g.iniciar();
      expect(g.soloWifi, isTrue); // por defecto
      await g.descargar('stt_tiny');
      expect(g.estado('stt_tiny'), EstadoPaquete.error);
      expect(g.error('stt_tiny'), contains('Wi‑Fi'));
      expect(pedidos, isEmpty);

      g.setSoloWifi(false); // el cliente acepta gastar datos
      await g.descargar('stt_tiny');
      expect(g.estado('stt_tiny'), EstadoPaquete.listo);
    });

    test('sin red avisa y no intenta', () async {
      final g = gestor([stt(), tts()], red: const [ConnectivityResult.none]);
      await g.iniciar();
      await g.descargar('tts');
      expect(g.error('tts'), contains('Sin conexión'));
      expect(pedidos, isEmpty);
    });

    test(
      'borrar libera el espacio y deja el modelo como no descargado',
      () async {
        final g = gestor([stt(), tts()]);
        await g.iniciar();
        await g.descargarRecomendados();
        await g.eliminar('tts');
        expect(g.estado('tts'), EstadoPaquete.noDescargado);
        expect(g.listoParaVoz, isFalse);
        expect(await Directory('${raiz.path}/tts').exists(), isFalse);
        expect(g.estado('stt_tiny'), EstadoPaquete.listo); // el otro no se toca
      },
    );

    test(
      'los ajustes (solo Wi‑Fi, preferir el telefono, reconocimiento elegido) se recuerdan',
      () async {
        final g = gestor([stt(), tts()]);
        await g.iniciar();
        g.setSoloWifi(false);
        g.setPreferirLocal(true);
        g.setSttElegido('stt_base');
        await Future<void>.delayed(const Duration(milliseconds: 50));
        final otro = gestor([stt(), tts()]);
        await otro.iniciar();
        expect(otro.soloWifi, isFalse);
        expect(otro.preferirLocal, isTrue);
        expect(otro.sttElegido, 'stt_base');
      },
    );
  });
}
