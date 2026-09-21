import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/cine_models.dart';
import '../offline/cache_local.dart';
import 'auth_service.dart';

class ApiException implements Exception {
  final String message;
  final int? status;
  ApiException(this.message, {this.status});

  @override
  String toString() => message;
}

/// Cliente REST del backend NestJS para lo que usa el cliente en la app:
/// espejo de Parcial1_Sw2_Frontend/src/api/*.api.ts (mismos endpoints).
class CineApi {
  static const _timeout = Duration(seconds: 15);

  /// Si lo ultimo que se mostro salio de la copia guardada (no habia red), cuando se guardo esa copia; si no, null.
  static final ValueNotifier<DateTime?> datosGuardadosDesde = ValueNotifier<DateTime?>(null);

  /// Pide una lista al servidor y guarda una copia; si no hay conexion (no si el servidor respondio con un error) devuelve la
  /// copia guardada. Asi la cartelera, las funciones, la dulceria y las compras se pueden ver sin internet.
  Future<List<T>> _listaConCopia<T>(String clave, String ruta, T Function(Map<String, dynamic>) desde) async {
    try {
      final cruda = _lista(await _get(ruta));
      datosGuardadosDesde.value = null;
      // Sin esperar: guardar la copia no debe demorar la pantalla.
      CacheLocal.instance.guardar(clave, cruda);
      return cruda.map(desde).toList();
    } on ApiException catch (e) {
      if (e.status != null) rethrow; // el servidor contesto (401, 500...): no es falta de conexion
      final copia = await CacheLocal.instance.leer(clave);
      if (copia == null) rethrow;
      datosGuardadosDesde.value = copia.guardado;
      return _lista(copia.datos).map(desde).toList();
    }
  }

  /// Se llama cuando el backend rechaza el token (la sesion vencio): la pantalla vuelve al login.
  static void Function()? onSesionVencida;

  Map<String, String> _headers({bool json = false}) {
    final token = AuthService.instance.token;
    return {
      if (json) 'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  dynamic _leer(http.Response r) {
    dynamic cuerpo;
    try {
      cuerpo = r.body.isEmpty ? null : jsonDecode(utf8.decode(r.bodyBytes));
    } catch (_) {
      cuerpo = null;
    }
    if (r.statusCode == 401 && AuthService.instance.token != null) onSesionVencida?.call();
    if (r.statusCode < 200 || r.statusCode >= 300) {
      var mensaje = 'Error ${r.statusCode} del servidor.';
      if (cuerpo is Map && cuerpo['message'] != null) {
        final m = cuerpo['message'];
        mensaje = m is List ? m.join(' ') : m.toString();
      }
      throw ApiException(mensaje, status: r.statusCode);
    }
    return cuerpo;
  }

  Future<dynamic> _get(String ruta) async {
    try {
      return _leer(await http.get(Uri.parse('$kBackendApiUrl$ruta'), headers: _headers()).timeout(_timeout));
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('No se pudo conectar con el servidor.');
    }
  }

  Future<dynamic> _post(String ruta, [Map<String, dynamic>? cuerpo]) async {
    try {
      final r = await http
          .post(Uri.parse('$kBackendApiUrl$ruta'), headers: _headers(json: true), body: jsonEncode(cuerpo ?? const {}))
          .timeout(_timeout);
      return _leer(r);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('No se pudo conectar con el servidor.');
    }
  }

  List<Map<String, dynamic>> _lista(dynamic d) => (d as List).map((e) => (e as Map).cast<String, dynamic>()).toList();

  // ---- catalogo

  Future<List<Pelicula>> listarPeliculas() => _listaConCopia('peliculas', '/peliculas', Pelicula.fromJson);

  Future<List<Funcion>> listarFunciones() => _listaConCopia('funciones', '/funciones', Funcion.fromJson);

  Future<List<AsientoDisponibilidad>> obtenerDisponibilidad(int idFuncion) async =>
      _lista(await _get('/funciones/$idFuncion/disponibilidad')).map(AsientoDisponibilidad.fromJson).toList();

  /// Valor unitario de la entrada (`GET /precios/:id`).
  Future<double> obtenerPrecio(int idPrecio) async {
    final d = (await _get('/precios/$idPrecio') as Map).cast<String, dynamic>();
    final v = d['valor'];
    return v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
  }

  Future<Sala> obtenerSala(int idSala) async => Sala.fromJson(((await _get('/salas/$idSala')) as Map).cast<String, dynamic>());

  // ---- dulceria

  Future<List<CategoriaDulceria>> listarCategoriasDulceria() => _listaConCopia('dulceria_categorias', '/dulceria/categorias', CategoriaDulceria.fromJson);

  Future<List<ProductoDulceria>> listarProductosDulceria() => _listaConCopia('dulceria_productos', '/dulceria/productos', ProductoDulceria.fromJson);

  // ---- ventas y pagos

  Future<List<CompraHistorial>> listarMisCompras() =>
      _listaConCopia('compras_${AuthService.instance.usuario?.idUsuario ?? 0}', '/ventas', CompraHistorial.fromJson);

  Future<DetalleCompra> obtenerDetalleCompra(int idVenta) async =>
      DetalleCompra.fromJson(((await _get('/ventas/$idVenta')) as Map).cast<String, dynamic>());

  Future<Venta> crearVenta({
    required int idFuncion,
    required List<int> idAsientos,
    required List<ItemDulceria> dulceria,
  }) async {
    final d = await _post('/ventas', {
      'idFuncion': idFuncion,
      'idAsientos': idAsientos,
      'tipoRegistro': 'manual',
      'confirmacionNoReembolso': true,
      'confirmacionVerbalCheck': false,
      'dulceria': dulceria.map((i) => {'idProducto': int.parse(i.id), 'cantidad': i.cantidad}).toList(),
    });
    return Venta.fromJson((d as Map).cast<String, dynamic>());
  }

  /// Pago en efectivo: el sistema lo confirma al instante y devuelve la venta pagada.
  Future<Venta> pagarEnEfectivo(int idVenta) async {
    final d = await _post('/pagos', {'idVenta': idVenta, 'metodo': 'efectivo'});
    return Venta.fromJson((d as Map).cast<String, dynamic>());
  }

  /// `GET /pagos/config` (publico): si hay pago con tarjeta y con que clave publicable.
  Future<ConfigPagos> obtenerConfiguracionPagos() async =>
      ConfigPagos.fromJson(((await _get('/pagos/config')) as Map).cast<String, dynamic>());

  /// Abre (o retoma) el cobro con tarjeta de una venta pendiente y devuelve el `clientSecret`.
  Future<InicioPagoStripe> iniciarPagoStripe(int idVenta) async =>
      InicioPagoStripe.fromJson(((await _post('/pagos/stripe/iniciar', {'idVenta': idVenta})) as Map).cast<String, dynamic>());

  /// Despues de confirmar la tarjeta: el servidor consulta a Stripe y devuelve la venta como quedo.
  Future<VerificacionPago> verificarPagoStripe(int idPago) async =>
      VerificacionPago.fromJson(((await _post('/pagos/$idPago/verificar')) as Map).cast<String, dynamic>());

  /// Cancela una venta que todavia no se pago y libera sus asientos.
  Future<void> cancelarVentaPendiente(int idVenta) async {
    await _post('/pagos/venta/$idVenta/cancelar');
  }
}
