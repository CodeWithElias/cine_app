import '../models/cine_models.dart';

/// Datos que el interprete local usa para contestar sin internet: la copia guardada de la cartelera, las funciones y las compras.
class DatosLocales {
  final List<Pelicula> peliculas;
  final List<Funcion> funciones;
  final List<CompraHistorial> compras;
  final DateTime? guardado;

  const DatosLocales({this.peliculas = const [], this.funciones = const [], this.compras = const [], this.guardado});

  bool get vacio => peliculas.isEmpty;
}

/// Lo que responde el interprete: el texto que se dice en voz alta y las acciones de pantalla (las mismas `ui_action`
/// que manda el agente en linea, asi las ejecuta el mismo `UiActionHandler`).
class RespuestaLocal {
  final String texto;
  final List<Map<String, dynamic>> acciones;
  final bool necesitaConexion;
  const RespuestaLocal(this.texto, {this.acciones = const [], this.necesitaConexion = false});
}

// ---------------------------------------------------------------------------- texto

/// Minusculas, sin acentos ni signos, con espacios simples: para comparar lo que dijo el cliente con los titulos.
String normalizar(String texto) {
  const de = 'áàäâéèëêíìïîóòöôúùüûñ';
  const a = 'aaaaeeeeiiiioooouuuun';
  final b = StringBuffer();
  for (final c in texto.toLowerCase().split('')) {
    final i = de.indexOf(c);
    b.write(i >= 0 ? a[i] : c);
  }
  return b.toString().replaceAll(RegExp(r'[^a-z0-9 ]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Con ruido, eco o un trozo de voz muy corto, Whisper inventa frases o entra en bucle ("la tinta de la tinta de la tinta...").
/// Es el mismo filtro que usa el servidor (`es_alucinacion` en back_agent/app/services/stt.py).
bool esAlucinacion(String texto) {
  final limpio = normalizar(texto);
  if (limpio.isEmpty) return true;
  const inventadas = [
    'subtitulos realizados por la comunidad de amara',
    'subtitulos por la comunidad de amara',
    'amara org',
    'gracias por ver el video',
    'gracias por ver',
    'suscribete',
    'no olvides suscribirte',
    'hasta la proxima',
    'subtitulado por',
  ];
  if (inventadas.any(limpio.contains)) return true;
  final palabras = limpio.split(' ');
  for (final largo in [1, 2, 3]) {
    var seguidas = 1;
    for (var i = largo; i <= palabras.length - largo; i += largo) {
      final igual = List.generate(largo, (k) => palabras[i + k] == palabras[i - largo + k]).every((x) => x);
      seguidas = igual ? seguidas + 1 : 1;
      if (seguidas >= 4) return true;
    }
  }
  return false;
}

int _distancia(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  var anterior = List<int>.generate(b.length + 1, (j) => j);
  for (var i = 1; i <= a.length; i++) {
    final actual = List<int>.filled(b.length + 1, 0)..[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final costo = a[i - 1] == b[j - 1] ? 0 : 1;
      actual[j] = [actual[j - 1] + 1, anterior[j] + 1, anterior[j - 1] + costo].reduce((x, y) => x < y ? x : y);
    }
    anterior = actual;
  }
  return anterior[b.length];
}

/// Dos palabras "iguales" para el reconocedor: mismas o casi (un error de letra en palabras largas: Whisper escribe mal los titulos).
bool _parecidas(String a, String b) {
  if (a == b) return true;
  if (a.length < 5 || b.length < 5) return false;
  return _distancia(a, b) <= (a.length >= 8 ? 2 : 1);
}

// ---------------------------------------------------------------------------- fechas y horas habladas

const _numeros = ['doce', 'una', 'dos', 'tres', 'cuatro', 'cinco', 'seis', 'siete', 'ocho', 'nueve', 'diez', 'once'];
const _diasSemana = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];
const _meses = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];

/// "20:30:00" -> "las ocho y media de la noche" (para que la voz lo lea como se dice, no como "veinte dos puntos treinta").
String horaHablada(String horaInicio) {
  final partes = horaInicio.split(':');
  final h24 = int.tryParse(partes.first) ?? 0;
  final m = partes.length > 1 ? int.tryParse(partes[1]) ?? 0 : 0;
  // "menos cuarto" se dice sobre la hora que viene: 7:45 es "ocho menos cuarto".
  final hora = (m == 45 ? h24 + 1 : h24) % 24;
  final h12 = hora % 12;
  final articulo = h12 == 1 ? 'la' : 'las';
  final periodo = hora < 6 ? 'de la madrugada' : hora < 12 ? 'de la mañana' : hora < 19 ? 'de la tarde' : 'de la noche';
  final minutos = switch (m) {
    0 => '',
    15 => ' y cuarto',
    30 => ' y media',
    45 => ' menos cuarto',
    _ => ' y $m',
  };
  return '$articulo ${_numeros[h12]}$minutos $periodo';
}

/// "hoy", "mañana" o "el viernes 25 de septiembre".
String diaHablado(String fecha, DateTime ahora) {
  final d = DateTime.tryParse(fecha);
  if (d == null) return fecha;
  final hoy = DateTime(ahora.year, ahora.month, ahora.day);
  final dif = DateTime(d.year, d.month, d.day).difference(hoy).inDays;
  if (dif == 0) return 'hoy';
  if (dif == 1) return 'mañana';
  return 'el ${_diasSemana[d.weekday - 1]} ${d.day} de ${_meses[d.month - 1]}';
}

String _unir(List<String> l) => l.length <= 1 ? l.join() : '${l.sublist(0, l.length - 1).join(', ')} y ${l.last}';

// ---------------------------------------------------------------------------- interprete

/// Entiende lo simple sin internet: cartelera, horarios de una pelicula, mis compras y moverse por la app. Para comprar,
/// pagar o pedir dulceria avisa que hace falta conexion. Trabaja con la copia guardada de los datos.
class InterpreteLocal {
  InterpreteLocal(this.datos, {DateTime Function()? ahora}) : _ahora = ahora ?? DateTime.now;

  final DatosLocales datos;
  final DateTime Function() _ahora;

  static const _palabrasVacias = {'de', 'la', 'el', 'los', 'las', 'del', 'y', 'en', 'un', 'una', 'the', 'part', 'parte', 'a', 'al'};

  static const _avisoCompra = 'Para comprar necesito conexión a internet. Cuando vuelvas a tenerla, con gusto te ayudo con la compra.';

  bool _dice(String t, List<String> frases) => frases.any((f) => t.contains(f));

  RespuestaLocal interpretar(String original) {
    final t = normalizar(original);
    final palabras = t.split(' ').where((p) => p.isNotEmpty).toSet();

    // Lo del historial primero: "mis compras" no es comprar.
    if (_dice(t, ['mis compras', 'mis entradas', 'mis boletos', 'mis reservas', 'que compre', 'compras hice', 'compras que hice', 'historial'])) {
      return _misCompras();
    }

    // Comprar, pagar, elegir asientos, dulceria, confirmar o cancelar: todo eso necesita el servidor.
    const verbosDeCompra = ['comprar', 'compra', 'entrada', 'entradas', 'boleto', 'boletos', 'ticket', 'asiento', 'asientos', 'butaca', 'butacas', 'pagar', 'pago', 'reservar', 'reserva', 'dulceria', 'pochoclo', 'pochoclos', 'palomitas', 'gaseosa', 'combo', 'nachos', 'confirmo', 'confirmar', 'cancelar'];
    if (palabras.any(verbosDeCompra.contains) || _dice(t, ['quiero ver', 'quiero una funcion', 'quiero dos', 'quiero tres'])) {
      return const RespuestaLocal(_avisoCompra, necesitaConexion: true);
    }

    if (_dice(t, ['menu principal', 'pantalla principal', 'ir al inicio', 'volver al inicio']) || t == 'inicio') {
      return const RespuestaLocal('Listo, vamos al inicio.', acciones: [
        {'tipo': 'navegar', 'destino': 'inicio'},
      ]);
    }

    final pelicula = _buscarPelicula(t);
    if (pelicula != null) return _funcionesDe(pelicula);

    if (_dice(t, ['cartelera', 'peliculas', 'pelicula', 'que hay', 'que pasan', 'que dan', 'estrenos', 'que ver'])) return _cartelera();

    if (_dice(t, ['hoy', 'manana', 'funciones', 'horarios', 'a que hora'])) return _funcionesDelDia(t);

    if (palabras.any(const {'hola', 'buenas', 'buenos', 'buen'}.contains) && palabras.length <= 4) {
      return const RespuestaLocal('¡Hola! Estoy sin conexión, pero puedo decirte la cartelera, los horarios de una película y tus compras.');
    }
    if (palabras.contains('gracias')) return const RespuestaLocal('¡De nada! Aquí estoy para lo que necesites.');
    if (palabras.any(const {'adios', 'chao', 'chau'}.contains) || _dice(t, ['hasta luego', 'nos vemos'])) {
      return const RespuestaLocal('¡Hasta luego! Que disfrutes la función.');
    }

    return const RespuestaLocal('Sin conexión solo puedo ayudarte con la cartelera, los horarios de una película y tus compras. ¿Qué te gustaría saber?');
  }

  // ---- peliculas

  /// La pelicula de la que habla el cliente, o null. Cuenta que parte de las palabras del titulo dijo (con tolerancia a
  /// errores de escritura del reconocedor) y exige que sea al menos la mitad.
  Pelicula? _buscarPelicula(String t) {
    final dichas = t.split(' ').where((p) => p.length >= 2).toList();
    Pelicula? mejor;
    var mejorPuntaje = 0.0;
    for (final p in datos.peliculas) {
      final claves = normalizar(p.titulo).split(' ').where((w) => w.isNotEmpty && !_palabrasVacias.contains(w)).toList();
      if (claves.isEmpty) continue;
      final acertadas = claves.where((c) => dichas.any((d) => _parecidas(c, d))).length;
      final puntaje = acertadas / claves.length;
      if (acertadas >= 1 && puntaje >= 0.5 && puntaje > mejorPuntaje) {
        mejor = p;
        mejorPuntaje = puntaje;
      }
    }
    return mejor;
  }

  List<Funcion> _proximas(Iterable<Funcion> lista) {
    final ahora = _ahora();
    final futuras = lista.where((f) {
      final inicio = f.inicio;
      return f.estado == 'programada' && inicio != null && !inicio.isBefore(ahora);
    }).toList()
      ..sort((a, b) => '${a.fecha}${a.horaInicio}'.compareTo('${b.fecha}${b.horaInicio}'));
    return futuras;
  }

  RespuestaLocal _funcionesDe(Pelicula p) {
    final proximas = _proximas(datos.funciones.where((f) => f.idPelicula == p.idPelicula));
    final accion = [
      {'tipo': 'cartelera.mostrar', 'ids': [p.idPelicula], 'pausa_ms': 0},
    ];
    if (proximas.isEmpty) {
      return RespuestaLocal('«${p.titulo}» está en cartelera, pero no tengo funciones próximas guardadas.', acciones: accion);
    }
    final ahora = _ahora();
    final dichas = proximas.take(4).map((f) => '${diaHablado(f.fecha, ahora)} a ${horaHablada(f.horaInicio)}').toList();
    final resto = proximas.length - dichas.length;
    return RespuestaLocal(
      '«${p.titulo}» tiene funciones ${_unir(dichas)}${resto > 0 ? ' y $resto más' : ''}.',
      acciones: accion,
    );
  }

  RespuestaLocal _cartelera() {
    final activas = datos.peliculas.where((p) => p.estado == 'activa').map((p) => p.titulo).toSet().toList();
    const navegar = [
      {'tipo': 'navegar', 'destino': 'cartelera'},
      {'tipo': 'cartelera.filtrar', 'busqueda': null},
    ];
    if (activas.isEmpty) {
      return const RespuestaLocal('No tengo guardada la cartelera. Cuando tengas internet la descargo para poder consultarla sin conexión.', acciones: navegar);
    }
    if (activas.length == 1) return RespuestaLocal('Hoy tenemos una sola película: ${activas.first}.', acciones: navegar);
    final dichas = activas.take(4).toList();
    final resto = activas.length - dichas.length;
    final lista = resto > 0 ? '${dichas.join(', ')} y $resto más' : _unir(dichas);
    return RespuestaLocal('Tenemos ${activas.length} películas en cartelera: $lista. Dime el nombre de una y te digo sus horarios.', acciones: navegar);
  }

  RespuestaLocal _funcionesDelDia(String t) {
    final ahora = _ahora();
    final manana = t.contains('manana');
    final dia = manana ? ahora.add(const Duration(days: 1)) : ahora;
    final fecha = '${dia.year.toString().padLeft(4, '0')}-${dia.month.toString().padLeft(2, '0')}-${dia.day.toString().padLeft(2, '0')}';
    final delDia = _proximas(datos.funciones.where((f) => f.fecha == fecha));
    final palabraDia = manana ? 'mañana' : 'hoy';
    if (delDia.isEmpty) {
      return RespuestaLocal('No tengo funciones guardadas para $palabraDia. Dime el nombre de una película y te digo sus próximas funciones.');
    }
    final titulos = <int, String>{for (final p in datos.peliculas) p.idPelicula: p.titulo};
    final dichas = delDia.take(4).map((f) => '${titulos[f.idPelicula] ?? 'una película'} a ${horaHablada(f.horaInicio)}').toList();
    final resto = delDia.length - dichas.length;
    return RespuestaLocal('$palabraDia hay ${delDia.length} funciones: ${_unir(dichas)}${resto > 0 ? ' y $resto más' : ''}.', acciones: const [
      {'tipo': 'navegar', 'destino': 'cartelera'},
    ]);
  }

  // ---- compras

  RespuestaLocal _misCompras() {
    const navegar = [
      {'tipo': 'navegar', 'destino': 'mis_compras'},
    ];
    if (datos.compras.isEmpty) {
      return const RespuestaLocal('No tengo guardadas tus compras. Cuando tengas internet las descargo para verlas sin conexión.', acciones: navegar);
    }
    final ahora = _ahora();
    final ultima = datos.compras.first;
    final n = datos.compras.length;
    return RespuestaLocal(
      'Tienes $n ${n == 1 ? 'compra' : 'compras'} guardadas. La última es para «${ultima.pelicula}», ${diaHablado(ultima.fecha, ahora)} a ${horaHablada(ultima.horaInicio)}.',
      acciones: navegar,
    );
  }
}
