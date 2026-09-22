import 'package:flutter/foundation.dart';

import '../models/cine_models.dart';
import 'cine_state.dart';
import 'ui_control.dart';

/// Traduce las acciones de interfaz que manda el agente (`ui_action`, ver
/// back_agent/app/ui_actions.py) a lo que la app sabe hacer: cambiar de
/// pantalla, mover el estado de la compra, filtrar/resaltar la cartelera y
/// abrir/cerrar ventanas. Es el espejo de `useUiActionHandler.ts`.
///
/// Es DETERMINISTA (el modelo no decide la interfaz) y en SERIE: las acciones de
/// un turno se ejecutan en orden y algunas esperan (dejar ver la pelicula
/// resaltada antes de pasar a los asientos); un turno nuevo no pisa a uno que
/// todavia se esta mostrando.
class UiActionHandler {
  UiActionHandler({required this.cine, required this.ui, this.alAplicar});

  final CineState cine;
  final UiControl ui;

  /// Se llama al terminar una tanda que traia numero de version (ver `contexto`).
  final void Function(int version)? alAplicar;

  Future<void> _cola = Future.value();

  void aplicar(List<dynamic> acciones, int? version) {
    _cola = _cola
        .then((_) => _ejecutar(acciones))
        .catchError((Object e) {
          debugPrint('[ui_action] $e');
        })
        .then((_) {
          // Aunque una accion falle, la tanda ya "paso": el servidor tiene que saber que la pantalla llego a esta version.
          if (version != null) alAplicar?.call(version);
        });
  }

  Future<void> _ejecutar(List<dynamic> acciones) async {
    for (final cruda in acciones) {
      if (cruda is! Map) continue;
      final a = cruda.cast<String, dynamic>();
      switch (a['tipo']) {
        // ---- estado de la compra
        case 'compra.seleccionar_funcion':
          ui.cerrar(
            TipoVentana.ticket,
          ); // arranca otra compra: el comprobante anterior ya no corresponde
          final pelicula = Pelicula.fromJson(
            (a['pelicula'] as Map).cast<String, dynamic>(),
          );
          final funcion = Funcion.fromJson(
            (a['funcion'] as Map).cast<String, dynamic>(),
          );
          cine.seleccionarFuncion(pelicula, funcion);
        case 'compra.seleccionar_butacas':
          cine.setButacas([
            for (final b in (a['butacas'] as List? ?? const []))
              Butaca.fromJson((b as Map).cast<String, dynamic>()),
          ]);
        case 'compra.candybar':
          cine.setDulceria([
            for (final i in (a['items'] as List? ?? const []))
              ItemDulceria.fromJson((i as Map).cast<String, dynamic>()),
          ]);
        case 'pago.abrir':
          // Ya se dijo "confirmo": la venta esta creada (con sus asientos reservados) y falta cobrarla con tarjeta.
          // La pantalla de pago muestra el formulario de Stripe para ESTA venta.
          ui.cerrar(TipoVentana.confirmacion);
          final venta = a['venta'];
          if (venta is Map) {
            cine.setVentaPendiente(
              Venta.fromJson(venta.cast<String, dynamic>()),
            );
          }
          cine.setEstadoCompra(EstadoCompra.pago);
          cine.irA(Pantalla.compra);
        case 'pago.enviar':
          ui.pedirPago('enviar');
        case 'pago.cancelar':
          ui.pedirPago('cancelar');
        case 'compra.completada':
          ui.cerrar(TipoVentana.confirmacion);
          final v = a['venta'];
          cine.completarCompra(
            v is Map ? Venta.fromJson(v.cast<String, dynamic>()) : null,
          );
          cine.irA(Pantalla.compra);
        case 'compra.reiniciar':
          ui.cerrar(TipoVentana.confirmacion);
          ui.cerrar(TipoVentana.ticket);
          cine.resetearCompra();
        case 'compra.quitar_pelicula':
          ui.cerrar(TipoVentana.confirmacion);
          ui.cerrar(TipoVentana.ticket);
          cine.quitarPelicula();
        case 'compra.quitar_funcion':
          ui.cerrar(TipoVentana.confirmacion);
          cine.quitarFuncion();

        // ---- pantalla
        case 'navegar':
          final destino = a['destino'] as String? ?? '';
          switch (destino) {
            case 'asientos' || 'candybar' || 'pago':
              cine.setEstadoCompra(estadoCompraDeDestino(destino));
              cine.irA(Pantalla.compra);
            case 'inicio':
              ui.cerrar(TipoVentana.ticket);
              cine.irA(Pantalla.inicio);
            case 'cartelera':
              ui.cerrar(TipoVentana.ticket);
              cine.irA(Pantalla.cartelera);
            case 'mis_compras':
              ui.cerrar(TipoVentana.ticket);
              cine.irA(Pantalla.misCompras);
          }
        case 'cartelera.filtrar':
          ui.filtrarCartelera(
            busqueda: a['busqueda'] as String?,
            dia: a['dia'] as String?,
          );
        case 'cartelera.mostrar':
          // Si ya esta en los asientos y solo cambia la funcion, no se lo saca de ahi.
          if (a['omitir_en_compra'] == true &&
              cine.pantalla == Pantalla.compra) {
            break;
          }
          ui.cerrar(TipoVentana.ticket);
          ui.filtrarCartelera(); // que ningun filtro anterior oculte lo que se va a mostrar
          ui.resaltarCartelera([
            for (final id in (a['ids'] as List? ?? const []))
              (id as num).toInt(),
          ], (a['idFuncion'] as num?)?.toInt());
          cine.irA(Pantalla.cartelera);
          final pausa = (a['pausa_ms'] as num?)?.toInt() ?? 0;
          if (pausa > 0) {
            await Future<void>.delayed(
              Duration(milliseconds: pausa),
            ); // se ve la eleccion un momento
          }
        case 'ventana.abrir':
          final tipo = _tipoVentana(a['ventana']);
          if (tipo != null) {
            ui.abrir(
              tipo,
              ((a['datos'] as Map?) ?? const {}).cast<String, dynamic>(),
            );
          }
        case 'ventana.cerrar':
          final tipo = _tipoVentana(a['ventana']);
          if (tipo != null) ui.cerrar(tipo);

        // admin.*: la app movil es solo del cliente.
        default:
          break;
      }
    }
  }

  TipoVentana? _tipoVentana(dynamic v) => switch (v) {
    'confirmacion' => TipoVentana.confirmacion,
    'ticket' => TipoVentana.ticket,
    _ => null,
  };
}
