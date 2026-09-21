import 'dart:async';

import 'package:flutter/foundation.dart';

/// Filtro de la cartelera pedido por el agente ("busca Barbie", "las del viernes").
class FiltroCartelera {
  final String? busqueda;
  final String? dia; // AAAA-MM-DD
  const FiltroCartelera({this.busqueda, this.dia});
}

/// Lo que el agente esta SEÑALANDO en la cartelera: las peliculas y, si ya se
/// eligio, el horario. Se apaga solo pasado un rato.
class ResaltadoCartelera {
  final List<int> ids;
  final int? idFuncion;
  final int n;
  const ResaltadoCartelera(this.ids, this.idFuncion, this.n);
}

enum TipoVentana { confirmacion, ticket }

/// El cliente dijo "pagar" o "cancelar" durante el pago con tarjeta: la pantalla de pago lo atiende.
class SolicitudPago {
  final String accion; // enviar | cancelar
  final int n;
  const SolicitudPago(this.accion, this.n);
}

/// Espejo de `UiControlContext` + `VentanasContext` del frontend: lo que el
/// agente le pide a la pantalla que no es estado de la compra (filtrar y
/// resaltar la cartelera, abrir la confirmacion o el ticket).
class UiControl extends ChangeNotifier {
  static const _duracionResaltado = Duration(seconds: 12);

  FiltroCartelera? filtro;
  int filtroN = 0;

  ResaltadoCartelera? resaltado;
  Timer? _temporizador;

  final Map<TipoVentana, Map<String, dynamic>> _ventanas = {};

  SolicitudPago? solicitudPago;

  void pedirPago(String accion) {
    solicitudPago = SolicitudPago(accion, (solicitudPago?.n ?? 0) + 1);
    notifyListeners();
  }

  Map<String, dynamic>? ventana(TipoVentana t) => _ventanas[t];

  void filtrarCartelera({String? busqueda, String? dia}) {
    final b = busqueda?.trim();
    filtro = FiltroCartelera(busqueda: (b == null || b.isEmpty) ? null : b, dia: dia);
    filtroN++;
    notifyListeners();
  }

  void resaltarCartelera(List<int> ids, [int? idFuncion]) {
    resaltado = ResaltadoCartelera(ids, idFuncion, (resaltado?.n ?? 0) + 1);
    _temporizador?.cancel();
    _temporizador = Timer(_duracionResaltado, () {
      resaltado = null;
      notifyListeners();
    });
    notifyListeners();
  }

  void abrir(TipoVentana t, Map<String, dynamic> datos) {
    _ventanas[t] = datos;
    notifyListeners();
  }

  void cerrar(TipoVentana t) {
    if (_ventanas.remove(t) != null) notifyListeners();
  }

  void cerrarTodas() {
    if (_ventanas.isEmpty) return;
    _ventanas.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _temporizador?.cancel();
    super.dispose();
  }
}
