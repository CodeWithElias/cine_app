import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Copia local de los datos del cine (cartelera, funciones, dulceria, compras) para poder consultarlos sin internet.
/// Se guarda en la carpeta privada de la app y se refresca cada vez que la app llega al servidor.
///
/// Nunca lanza: si no se puede leer o escribir, simplemente no hay copia (la app sigue funcionando en linea).
class CacheLocal {
  CacheLocal._();
  static final CacheLocal instance = CacheLocal._();

  /// Carpeta donde se guardan los archivos (se puede cambiar en pruebas).
  @visibleForTesting
  Directory? carpetaDePrueba;

  Future<File> _archivo(String clave) async {
    final base =
        carpetaDePrueba ??
        Directory('${(await getApplicationSupportDirectory()).path}/cache');
    if (!await base.exists()) await base.create(recursive: true);
    return File('${base.path}/$clave.json');
  }

  Future<void> guardar(String clave, Object datos) async {
    try {
      final archivo = await _archivo(clave);
      await archivo.writeAsString(
        jsonEncode({
          'guardado': DateTime.now().toIso8601String(),
          'datos': datos,
        }),
      );
    } catch (e) {
      debugPrint('No se pudo guardar la copia local "$clave": $e');
    }
  }

  /// La copia guardada de `clave` y cuando se guardo; null si no hay.
  Future<({DateTime guardado, dynamic datos})?> leer(String clave) async {
    try {
      final archivo = await _archivo(clave);
      if (!await archivo.exists()) return null;
      final json =
          jsonDecode(await archivo.readAsString()) as Map<String, dynamic>;
      final cuando = DateTime.tryParse('${json['guardado']}');
      if (cuando == null) return null;
      return (guardado: cuando, datos: json['datos']);
    } catch (e) {
      debugPrint('No se pudo leer la copia local "$clave": $e');
      return null;
    }
  }

  /// Cuando se guardo por ultima vez la cartelera (el dato que se le muestra al cliente); null si nunca.
  Future<DateTime?> fechaDeCartelera() async =>
      (await leer('peliculas'))?.guardado;

  Future<void> borrarTodo() async {
    try {
      final base =
          carpetaDePrueba ??
          Directory('${(await getApplicationSupportDirectory()).path}/cache');
      if (await base.exists()) await base.delete(recursive: true);
    } catch (_) {}
  }
}
