import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/cine_models.dart';
import '../services/auth_service.dart';
import 'cache_local.dart';
import 'gestor_modelos.dart';
import 'interprete_local.dart';
import 'motor_voz_local.dart';

/// Une las piezas del modo sin conexion para la conversacion de voz: decide cuando usarlo, arma el motor de voz del telefono
/// y contesta con la copia guardada de los datos.
class SinConexion {
  SinConexion(this.gestor);

  final GestorModelos gestor;

  /// ¿Se puede usar el modo sin conexion? (los modelos ya estan descargados)
  bool get disponible => gestor.listoParaVoz;

  /// ¿El servidor del asistente contesta? Un pedido corto: si no llega en 2,5 s se da por caido.
  Future<bool> servidorAlcanzable() async {
    try {
      final redes = await Connectivity().checkConnectivity();
      if (redes.every((r) => r == ConnectivityResult.none)) return false;
      final r = await http
          .get(Uri.parse('$kVoiceAgentUrl/'))
          .timeout(const Duration(milliseconds: 2500));
      return r.statusCode < 500;
    } catch (_) {
      return false;
    }
  }

  /// Usar el asistente del telefono: solo si esta descargado y (el cliente lo prefiere o el servidor no contesta).
  Future<bool> debeUsarLocal() async {
    if (!disponible) return false;
    if (gestor.preferirLocal) return true;
    return !(await servidorAlcanzable());
  }

  Future<MotorVozLocal> crearMotor() async {
    final rutas = await gestor.rutasVoz();
    if (rutas == null) {
      throw StateError('El modo sin conexión no está descargado.');
    }
    return MotorVozLocal.crear(rutas);
  }

  /// Lo que se sabe sin internet: la ultima copia de la cartelera, las funciones y las compras del cliente.
  Future<DatosLocales> cargarDatos() async {
    final cache = CacheLocal.instance;
    final peliculas = await cache.leer('peliculas');
    final funciones = await cache.leer('funciones');
    final idUsuario = AuthService.instance.usuario?.idUsuario;
    final compras = idUsuario == null
        ? null
        : await cache.leer('compras_$idUsuario');

    List<T> lista<T>(
      ({DateTime guardado, dynamic datos})? c,
      T Function(Map<String, dynamic>) desde,
    ) => c == null
        ? <T>[]
        : [
            for (final e in (c.datos as List))
              desde((e as Map).cast<String, dynamic>()),
          ];

    return DatosLocales(
      peliculas: lista(
        peliculas,
        Pelicula.fromJson,
      ).where((p) => p.estado == 'activa').toList(),
      funciones: lista(funciones, Funcion.fromJson),
      compras: lista(compras, CompraHistorial.fromJson)
        ..sort(
          (a, b) =>
              (b.venta.fechaHora ?? '').compareTo(a.venta.fechaHora ?? ''),
        ),
      guardado: peliculas?.guardado,
    );
  }

  Future<RespuestaLocal> interpretar(String texto) async =>
      InterpreteLocal(await cargarDatos()).interpretar(texto);
}
