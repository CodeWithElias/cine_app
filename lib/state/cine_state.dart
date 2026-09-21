import 'package:flutter/foundation.dart';

import '../models/cine_models.dart';
import '../services/cine_api.dart';

/// Pantallas de la app (el equivalente de las rutas del frontend web).
enum Pantalla { inicio, cartelera, compra, misCompras }

/// Estado de la compra en curso y de la pantalla visible. Es el espejo de
/// `cine.reducer.ts` + `CineContext` del frontend: lo mueve tanto el toque del
/// cliente como las `ui_action` que manda el agente de voz.
class CineState extends ChangeNotifier {
  CineState(this.api);

  final CineApi api;

  Pantalla pantalla = Pantalla.inicio;

  List<Pelicula> peliculas = const [];
  Pelicula? peliculaSeleccionada;
  String? horarioSeleccionado;
  Funcion? funcionSeleccionada;
  Sala? salaSeleccionada;
  List<AsientoDisponibilidad> disponibilidad = const [];
  bool cargandoDisponibilidad = false;

  /// Por que no se pudo traer la disponibilidad (null si se trajo bien): se muestra en pantalla en vez de un vacio mudo.
  String? errorDisponibilidad;
  double? precioUnitario;
  List<Butaca> butacas = const [];
  List<ItemDulceria> dulceria = const [];
  EstadoCompra estadoCompra = EstadoCompra.seleccionandoAsientos;
  Venta? ventaCreada;

  /// Venta ya creada (asientos reservados) que falta cobrar, con la huella de
  /// lo elegido: si el cliente cambia algo, esa venta ya no corresponde.
  Venta? ventaPendiente;
  String? _firmaPendiente;

  int _cargaFuncion = 0;

  // ---------------------------------------------------------------- derivados

  double get totalEntradas => butacas.fold(0, (a, b) => a + b.precio);
  double get totalDulceria => dulceria.fold(0, (a, i) => a + i.precio * i.cantidad);
  double get total => totalEntradas + totalDulceria;
  double get totalReal => ventaCreada?.total ?? total;

  /// Huella de lo elegido (funcion + asientos + dulceria).
  String get firma {
    final asientos = (butacas.map((b) => b.idAsiento).toList()..sort()).join(',');
    final dulces = (dulceria.map((i) => '${i.id}x${i.cantidad}').toList()..sort()).join(',');
    return '${funcionSeleccionada?.idFuncion}|$asientos|$dulces';
  }

  /// Lo que el cliente tiene marcado, solo con ids: se le cuenta al agente
  /// (ver `contextoDeCine` en la web y estado_compra.py en el agente).
  /// Una compra ya pagada no cuenta: seguiria "resucitandola".
  Map<String, dynamic> contexto() {
    if (estadoCompra == EstadoCompra.completado || ventaCreada != null) {
      return {'idPelicula': null, 'idFuncion': null, 'asientos': [], 'dulceria': []};
    }
    return {
      'idPelicula': peliculaSeleccionada?.idPelicula,
      'idFuncion': funcionSeleccionada?.idFuncion,
      'asientos': butacas.map((b) => {'id': b.id, 'idAsiento': b.idAsiento}).toList(),
      'dulceria': [
        for (final i in dulceria)
          if (int.tryParse(i.id) != null) {'idProducto': int.parse(i.id), 'cantidad': i.cantidad},
      ],
    };
  }

  // ---------------------------------------------------------------- navegacion

  void irA(Pantalla p) {
    if (pantalla == p) return;
    pantalla = p;
    notifyListeners();
  }

  // ---------------------------------------------------------------- catalogo

  void setPeliculas(List<Pelicula> lista) {
    peliculas = lista;
    notifyListeners();
  }

  // ---------------------------------------------------------------- compra

  /// El cliente (o el agente) elige una funcion: arranca una compra nueva.
  void seleccionarFuncion(Pelicula pelicula, Funcion funcion) {
    peliculaSeleccionada = pelicula;
    horarioSeleccionado = funcion.horaInicio;
    funcionSeleccionada = funcion;
    salaSeleccionada = null;
    disponibilidad = const [];
    precioUnitario = null;
    butacas = const [];
    dulceria = const [];
    estadoCompra = EstadoCompra.seleccionandoAsientos;
    ventaCreada = null;
    _soltarPendiente();
    notifyListeners();
    _cargarDatosDeFuncion(funcion);
  }

  /// Trae disponibilidad, precio y sala de la funcion elegida (en paralelo).
  Future<void> _cargarDatosDeFuncion(Funcion f) async {
    final carga = ++_cargaFuncion;
    cargandoDisponibilidad = true;
    errorDisponibilidad = null;
    notifyListeners();

    // Los tres datos se piden en paralelo pero cada uno por su cuenta: si falla el precio o la sala, las butacas
    // se muestran igual (antes un solo fallo dejaba la pantalla en "no hay butacas").
    Future<T?> aparte<T>(Future<T> pedido, String que) async {
      try {
        return await pedido;
      } catch (e) {
        debugPrint('No se pudo cargar $que de la funcion ${f.idFuncion}: $e');
        if (que == 'la disponibilidad') errorDisponibilidad = e.toString();
        return null;
      }
    }

    final resultados = await Future.wait<Object?>([
      aparte(api.obtenerDisponibilidad(f.idFuncion), 'la disponibilidad'),
      f.idPrecio == null ? Future<double?>.value(null) : aparte(api.obtenerPrecio(f.idPrecio!), 'el precio'),
      aparte(api.obtenerSala(f.idSala), 'la sala'),
    ]);
    if (carga != _cargaFuncion) return;
    disponibilidad = (resultados[0] as List<AsientoDisponibilidad>?) ?? const [];
    precioUnitario = resultados[1] as double?;
    salaSeleccionada = resultados[2] as Sala?;
    // Las butacas que se eligieron antes de saber el precio (ej. las eligio el agente) toman el precio real.
    if (precioUnitario != null && butacas.any((b) => b.precio == 0)) {
      butacas = [for (final b in butacas) b.precio == 0 ? Butaca(id: b.id, idAsiento: b.idAsiento, fila: b.fila, columna: b.columna, precio: precioUnitario!) : b];
    }
    cargandoDisponibilidad = false;
    notifyListeners();
  }

  /// Recarga la disponibilidad (ej. tras un error al reservar).
  Future<void> recargarDisponibilidad() async {
    final f = funcionSeleccionada;
    if (f != null) await _cargarDatosDeFuncion(f);
  }

  void toggleButaca(AsientoDisponibilidad a) {
    final id = '${a.fila}${a.numero}';
    if (butacas.any((b) => b.id == id)) {
      butacas = butacas.where((b) => b.id != id).toList();
    } else {
      butacas = [
        ...butacas,
        Butaca(id: id, idAsiento: a.idAsiento, fila: a.fila, columna: a.numero, precio: precioUnitario ?? 0),
      ];
    }
    notifyListeners();
  }

  void setButacas(List<Butaca> lista) {
    butacas = lista;
    notifyListeners();
  }

  void setDulceria(List<ItemDulceria> items) {
    dulceria = items;
    notifyListeners();
  }

  void actualizarDulceria(ItemDulceria item) {
    final lista = [...dulceria];
    final i = lista.indexWhere((x) => x.id == item.id);
    if (i >= 0) {
      if (item.cantidad == 0) {
        lista.removeAt(i);
      } else {
        lista[i] = item;
      }
    } else if (item.cantidad > 0) {
      lista.add(item);
    }
    dulceria = lista;
    notifyListeners();
  }

  void setEstadoCompra(EstadoCompra e) {
    if (estadoCompra == e) return;
    estadoCompra = e;
    notifyListeners();
  }

  void completarCompra(Venta? venta) {
    if (venta != null) ventaCreada = venta;
    _soltarPendiente();
    estadoCompra = EstadoCompra.completado;
    notifyListeners();
  }

  void setVentaPendiente(Venta venta) {
    ventaPendiente = venta;
    _firmaPendiente = firma;
    notifyListeners();
  }

  /// La venta pendiente sigue valiendo si no cambio lo elegido desde que se reservo.
  bool get pendienteVigente => ventaPendiente != null && _firmaPendiente == firma;

  void _soltarPendiente() {
    ventaPendiente = null;
    _firmaPendiente = null;
  }

  void limpiarPendiente() {
    _soltarPendiente();
    notifyListeners();
  }

  void quitarPelicula() {
    peliculaSeleccionada = null;
    horarioSeleccionado = null;
    funcionSeleccionada = null;
    salaSeleccionada = null;
    disponibilidad = const [];
    precioUnitario = null;
    butacas = const [];
    estadoCompra = EstadoCompra.seleccionandoAsientos;
    ventaCreada = null;
    _soltarPendiente();
    _cargaFuncion++;
    notifyListeners();
  }

  void quitarFuncion() {
    horarioSeleccionado = null;
    funcionSeleccionada = null;
    salaSeleccionada = null;
    disponibilidad = const [];
    precioUnitario = null;
    butacas = const [];
    estadoCompra = EstadoCompra.seleccionandoAsientos;
    _soltarPendiente();
    _cargaFuncion++;
    notifyListeners();
  }

  void resetearCompra() {
    peliculaSeleccionada = null;
    horarioSeleccionado = null;
    funcionSeleccionada = null;
    salaSeleccionada = null;
    disponibilidad = const [];
    precioUnitario = null;
    butacas = const [];
    dulceria = const [];
    estadoCompra = EstadoCompra.seleccionandoAsientos;
    ventaCreada = null;
    _soltarPendiente();
    _cargaFuncion++;
    notifyListeners();
  }
}
