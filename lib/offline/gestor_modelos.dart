import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'modelos_manifiesto.dart';

/// Un archivo de un modelo: de donde se baja, donde queda (relativo a la carpeta del modelo), cuanto pesa y su sha256.
class ArchivoDescarga {
  final String url;
  final String ruta;
  final int bytes;
  final String? sha256;
  const ArchivoDescarga({
    required this.url,
    required this.ruta,
    required this.bytes,
    this.sha256,
  });
}

/// Un modelo descargable (o un grupo de archivos que van juntos).
class PaqueteModelo {
  final String id;
  final String nombre;
  final String descripcion;
  final List<ArchivoDescarga> archivos;
  const PaqueteModelo({
    required this.id,
    required this.nombre,
    required this.descripcion,
    required this.archivos,
  });

  int get bytesTotal => archivos.fold(0, (a, f) => a + f.bytes);
}

List<ArchivoDescarga> _delHub(
  String repo,
  List<ArchivoManifiesto> lista, {
  String prefijoLocal = '',
}) => [
  for (final (ruta, bytes, sha) in lista)
    ArchivoDescarga(
      url: 'https://huggingface.co/$repo/resolve/main/$ruta',
      ruta: '$prefijoLocal$ruta',
      bytes: bytes,
      sha256: sha,
    ),
];

const _archivoVad = ArchivoDescarga(
  url: urlSileroVad,
  ruta: 'silero_vad.onnx',
  bytes: bytesSileroVad,
);

/// Los modelos que se pueden llevar al telefono. `stt_*` = entender la voz (Whisper + detector de voz), `tts` = hablar (Piper).
final List<PaqueteModelo> paquetesDisponibles = [
  PaqueteModelo(
    id: 'stt_tiny',
    nombre: 'Reconocimiento de voz · estándar',
    descripcion: 'Whisper tiny. Rápido y liviano; entiende bien frases cortas.',
    archivos: [..._delHub(repoWhisperTiny, archivosWhisperTiny), _archivoVad],
  ),
  PaqueteModelo(
    id: 'stt_base',
    nombre: 'Reconocimiento de voz · preciso',
    descripcion:
        'Whisper base. Entiende mejor (nombres de películas), pesa más y es más lento.',
    archivos: [..._delHub(repoWhisperBase, archivosWhisperBase), _archivoVad],
  ),
  PaqueteModelo(
    id: 'tts',
    nombre: 'Voz del asistente',
    descripcion:
        'La misma voz en español que usa el asistente en línea (Piper).',
    archivos: [
      ..._delHub(repoVozPiper, archivosVozPiper),
      ..._delHub(repoVozPiper, archivosEspeak),
    ],
  ),
];

PaqueteModelo paquete(String id) =>
    paquetesDisponibles.firstWhere((p) => p.id == id);

enum EstadoPaquete { noDescargado, descargando, pausado, listo, error }

/// Rutas de los archivos que necesita el motor de voz local.
class RutasVoz {
  final String encoder;
  final String decoder;
  final String tokens;
  final String vad;
  final String ttsModelo;
  final String ttsTokens;
  final String espeakDatos;
  const RutasVoz({
    required this.encoder,
    required this.decoder,
    required this.tokens,
    required this.vad,
    required this.ttsModelo,
    required this.ttsTokens,
    required this.espeakDatos,
  });
}

class _Pausa implements Exception {}

class DescargaException implements Exception {
  final String mensaje;
  DescargaException(this.mensaje);
  @override
  String toString() => mensaje;
}

/// Descarga, verifica, guarda y borra los modelos del modo sin conexion.
///
///  - Se guardan en la carpeta PRIVADA de la app (`<soporte>/modelos/<id>/`): ninguna otra app los ve y se borran con la app.
///  - Se puede PAUSAR y REANUDAR: lo bajado queda en archivos `.part` y se retoma con un pedido `Range`.
///  - Cada archivo se VERIFICA (tamaño y, para los grandes, sha256 publicado por el Hub) antes de darlo por bueno.
///  - "Solo por Wi‑Fi" (activado por defecto) evita gastar datos moviles sin querer.
class GestorModelos extends ChangeNotifier {
  GestorModelos({
    Directory? raiz,
    List<PaqueteModelo>? paquetes,
    Future<List<ConnectivityResult>> Function()? conectividad,
    http.Client Function()? clienteHttp,
  }) : _raizFija = raiz,
       _paquetes = paquetes ?? paquetesDisponibles,
       _conectividad =
           conectividad ?? (() => Connectivity().checkConnectivity()),
       _nuevoCliente = clienteHttp ?? http.Client.new;

  static final GestorModelos instance = GestorModelos();

  final Directory? _raizFija;
  final List<PaqueteModelo> _paquetes;
  final Future<List<ConnectivityResult>> Function() _conectividad;
  final http.Client Function() _nuevoCliente;

  static const _claveSoloWifi = 'sinconexion_solo_wifi';
  static const _clavePreferirLocal = 'sinconexion_preferir_local';
  static const _claveStt = 'sinconexion_stt';
  static const _marcaListo = '.listo';
  static const _paralelos = 8;

  bool iniciado = false;
  bool soloWifi = true;
  bool preferirLocal = false;
  String sttElegido = 'stt_tiny';

  late final Map<String, EstadoPaquete> _estado = {
    for (final p in _paquetes) p.id: EstadoPaquete.noDescargado,
  };
  late final Map<String, int> _descargados = {
    for (final p in _paquetes) p.id: 0,
  };
  final Map<String, String?> _error = {};

  bool _pausaPedida = false;
  http.Client? _cliente;
  DateTime _ultimoAviso = DateTime.fromMillisecondsSinceEpoch(0);

  EstadoPaquete estado(String id) => _estado[id] ?? EstadoPaquete.noDescargado;
  int bytesDescargados(String id) => _descargados[id] ?? 0;
  String? error(String id) => _error[id];
  PaqueteModelo _paq(String id) => _paquetes.firstWhere((p) => p.id == id);

  double progreso(String id) {
    final total = _paq(id).bytesTotal;
    return total == 0 ? 0 : (_descargados[id]! / total).clamp(0.0, 1.0);
  }

  bool get descargando =>
      _estado.values.any((e) => e == EstadoPaquete.descargando);

  /// Hay reconocimiento de voz y voz del asistente: el modo sin conexion se puede usar.
  bool get listoParaVoz =>
      sttActivo != null && estado('tts') == EstadoPaquete.listo;

  /// El reconocimiento de voz que se usaria: el elegido si esta listo, si no el otro.
  String? get sttActivo {
    if (estado(sttElegido) == EstadoPaquete.listo) return sttElegido;
    for (final id in const ['stt_tiny', 'stt_base']) {
      if (estado(id) == EstadoPaquete.listo) return id;
    }
    return null;
  }

  // ------------------------------------------------------------------ inicio y ajustes

  Future<Directory> _carpeta(String id) async {
    final raiz =
        _raizFija ??
        Directory('${(await getApplicationSupportDirectory()).path}/modelos');
    return Directory('${raiz.path}/$id');
  }

  Future<void> iniciar() async {
    if (iniciado) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      soloWifi = prefs.getBool(_claveSoloWifi) ?? true;
      preferirLocal = prefs.getBool(_clavePreferirLocal) ?? false;
      sttElegido = prefs.getString(_claveStt) ?? 'stt_tiny';
    } catch (_) {}
    for (final p in _paquetes) {
      final dir = await _carpeta(p.id);
      if (await File('${dir.path}/$_marcaListo').exists() &&
          await _completo(p, dir)) {
        _estado[p.id] = EstadoPaquete.listo;
        _descargados[p.id] = p.bytesTotal;
      } else if (await _hayParciales(dir)) {
        _estado[p.id] = EstadoPaquete.pausado;
        _descargados[p.id] = await _bytesEnDisco(p, dir);
      }
    }
    iniciado = true;
    notifyListeners();
  }

  Future<void> _guardarAjuste(void Function(SharedPreferences) f) async {
    try {
      f(await SharedPreferences.getInstance());
    } catch (_) {}
  }

  void setSoloWifi(bool v) {
    soloWifi = v;
    _guardarAjuste((p) => p.setBool(_claveSoloWifi, v));
    notifyListeners();
  }

  void setPreferirLocal(bool v) {
    preferirLocal = v;
    _guardarAjuste((p) => p.setBool(_clavePreferirLocal, v));
    notifyListeners();
  }

  void setSttElegido(String id) {
    sttElegido = id;
    _guardarAjuste((p) => p.setString(_claveStt, id));
    notifyListeners();
  }

  // ------------------------------------------------------------------ estado en disco

  Future<bool> _completo(PaqueteModelo p, Directory dir) async {
    for (final a in p.archivos) {
      final f = File('${dir.path}/${a.ruta}');
      if (!await f.exists() || await f.length() != a.bytes) return false;
    }
    return true;
  }

  Future<bool> _hayParciales(Directory dir) async {
    if (!await dir.exists()) return false;
    await for (final e in dir.list(recursive: true)) {
      if (e is File && e.path.endsWith('.part')) return true;
    }
    return false;
  }

  Future<int> _bytesEnDisco(PaqueteModelo p, Directory dir) async {
    var total = 0;
    for (final a in p.archivos) {
      final f = File('${dir.path}/${a.ruta}');
      if (await f.exists()) {
        total += await f.length();
      } else {
        final parcial = File('${f.path}.part');
        if (await parcial.exists()) total += await parcial.length();
      }
    }
    return total;
  }

  /// Las rutas de los archivos del motor de voz (null si el modo sin conexion no esta listo).
  Future<RutasVoz?> rutasVoz() async {
    final stt = sttActivo;
    if (stt == null || estado('tts') != EstadoPaquete.listo) return null;
    final dirStt = (await _carpeta(stt)).path;
    final dirTts = (await _carpeta('tts')).path;
    final prefijo = stt == 'stt_base' ? 'base' : 'tiny';
    return RutasVoz(
      encoder: '$dirStt/$prefijo-encoder.int8.onnx',
      decoder: '$dirStt/$prefijo-decoder.int8.onnx',
      tokens: '$dirStt/$prefijo-tokens.txt',
      vad: '$dirStt/silero_vad.onnx',
      ttsModelo: '$dirTts/es_ES-sharvard-medium.onnx',
      ttsTokens: '$dirTts/tokens.txt',
      espeakDatos: '$dirTts/espeak-ng-data',
    );
  }

  // ------------------------------------------------------------------ descarga

  /// Baja los modelos recomendados: el reconocimiento de voz elegido y la voz del asistente.
  Future<void> descargarRecomendados() async {
    for (final id in [sttElegido, 'tts']) {
      if (estado(id) == EstadoPaquete.listo) continue;
      await descargar(id);
      if (estado(id) != EstadoPaquete.listo) {
        return; // se pauso o fallo: no se sigue con el otro
      }
    }
  }

  Future<void> _comprobarRed() async {
    final r = await _conectividad();
    final hayRed = r.any((c) => c != ConnectivityResult.none);
    if (!hayRed) {
      throw DescargaException(
        'Sin conexión a internet. Conéctate para descargar.',
      );
    }
    final buena =
        r.contains(ConnectivityResult.wifi) ||
        r.contains(ConnectivityResult.ethernet);
    if (soloWifi && !buena) {
      throw DescargaException(
        'Estás con datos móviles. Conéctate a Wi‑Fi o desactiva «Solo por Wi‑Fi».',
      );
    }
  }

  Future<void> descargar(String id) async {
    if (descargando || estado(id) == EstadoPaquete.listo) return;
    final p = _paq(id);
    _pausaPedida = false;
    _error[id] = null;
    _estado[id] = EstadoPaquete.descargando;
    notifyListeners();
    final dir = await _carpeta(id);
    _cliente = _nuevoCliente();
    try {
      await _comprobarRed();
      await dir.create(recursive: true);
      await File(
        '${dir.path}/$_marcaListo',
      ).delete().catchError((Object _) => File(''));
      _descargados[id] = 0;

      // Los archivos ya completos cuentan de entrada; los que faltan se bajan. Los grandes de a uno; los chicos (los
      // cientos de archivos del pronunciador) de a varios a la vez.
      final pendientes = <ArchivoDescarga>[];
      for (final a in p.archivos) {
        final f = File('${dir.path}/${a.ruta}');
        if (await f.exists() && await f.length() == a.bytes) {
          _descargados[id] = _descargados[id]! + a.bytes;
        } else {
          pendientes.add(a);
        }
      }
      final grandes = pendientes
          .where((a) => a.bytes > 5 * 1024 * 1024)
          .toList();
      final chicos = pendientes
          .where((a) => a.bytes <= 5 * 1024 * 1024)
          .toList();

      void suma(int delta) {
        _descargados[id] = _descargados[id]! + delta;
        _avisarProgreso();
      }

      for (final a in grandes) {
        await _bajarArchivo(a, dir, suma);
      }
      var siguiente = 0;
      Future<void> obrero() async {
        while (true) {
          if (_pausaPedida) throw _Pausa();
          final i = siguiente++;
          if (i >= chicos.length) return;
          await _bajarArchivo(chicos[i], dir, suma);
        }
      }

      await Future.wait([for (var i = 0; i < _paralelos; i++) obrero()]);

      await File(
        '${dir.path}/$_marcaListo',
      ).writeAsString(DateTime.now().toIso8601String());
      _estado[id] = EstadoPaquete.listo;
      _descargados[id] = p.bytesTotal;
    } on _Pausa {
      _estado[id] = EstadoPaquete.pausado;
    } catch (e) {
      if (_pausaPedida) {
        _estado[id] = EstadoPaquete.pausado;
      } else {
        _estado[id] = EstadoPaquete.error;
        _error[id] = _mensajeDe(e);
      }
    } finally {
      _cliente?.close();
      _cliente = null;
      notifyListeners();
    }
  }

  String _mensajeDe(Object e) {
    if (e is DescargaException) return e.mensaje;
    if (e is FileSystemException &&
        (e.osError?.errorCode == 112 || e.osError?.errorCode == 28)) {
      return 'No hay espacio suficiente en el teléfono.';
    }
    if (e is SocketException ||
        e is http.ClientException ||
        e is TimeoutException) {
      return 'Se cortó la conexión. Toca «Reanudar» para seguir donde quedó.';
    }
    return 'No se pudo descargar: $e';
  }

  void _avisarProgreso() {
    final ahora = DateTime.now();
    if (ahora.difference(_ultimoAviso).inMilliseconds < 200) return;
    _ultimoAviso = ahora;
    notifyListeners();
  }

  /// Pausa la descarga en curso: lo bajado queda guardado y "Reanudar" sigue donde quedo.
  void pausar() {
    if (!descargando) return;
    _pausaPedida = true;
    _cliente?.close();
  }

  Future<void> _bajarArchivo(
    ArchivoDescarga a,
    Directory dir,
    void Function(int) suma,
  ) async {
    final destino = File('${dir.path}/${a.ruta}');
    await destino.parent.create(recursive: true);
    final parcial = File('${destino.path}.part');
    var existentes = await parcial.exists() ? await parcial.length() : 0;
    if (existentes > a.bytes) {
      await parcial.delete();
      existentes = 0;
    }
    if (existentes > 0) {
      suma(existentes); // lo que ya estaba bajado cuenta para el progreso
    }

    if (existentes < a.bytes) {
      final pedido = http.Request('GET', Uri.parse(a.url));
      if (existentes > 0) pedido.headers['Range'] = 'bytes=$existentes-';
      final respuesta = await _cliente!
          .send(pedido)
          .timeout(const Duration(seconds: 30));
      if (respuesta.statusCode == 416) {
        // El servidor dice que ya no hay mas que bajar desde ahi: se empieza de cero para no quedar con un archivo raro.
        await parcial.delete();
        suma(-existentes);
        throw DescargaException(
          'El servidor no aceptó reanudar. Vuelve a tocar «Descargar».',
        );
      }
      if (respuesta.statusCode != 200 && respuesta.statusCode != 206) {
        throw DescargaException(
          'El servidor respondió ${respuesta.statusCode} al bajar ${a.ruta}.',
        );
      }
      final retoma = respuesta.statusCode == 206 && existentes > 0;
      if (!retoma && existentes > 0) {
        suma(-existentes); // el servidor ignoro el Range y manda todo otra vez
        existentes = 0;
      }
      final sink = parcial.openWrite(
        mode: retoma ? FileMode.append : FileMode.write,
      );
      try {
        await for (final trozo in respuesta.stream.timeout(
          const Duration(seconds: 30),
        )) {
          if (_pausaPedida) throw _Pausa();
          sink.add(trozo);
          suma(trozo.length);
        }
      } finally {
        await sink.flush();
        await sink.close();
      }
    }

    final tamano = await parcial.length();
    if (tamano != a.bytes) {
      await parcial.delete();
      throw DescargaException(
        '${a.ruta} llegó incompleto ($tamano de ${a.bytes} bytes). Vuelve a intentar.',
      );
    }
    if (a.sha256 != null) {
      final huella = (await sha256.bind(parcial.openRead()).first).toString();
      if (huella != a.sha256) {
        await parcial.delete();
        throw DescargaException(
          '${a.ruta} llegó dañado (no coincide su huella). Vuelve a intentar.',
        );
      }
    }
    await parcial.rename(destino.path);
  }

  // ------------------------------------------------------------------ borrar

  /// Borra un modelo del telefono (libera el espacio).
  Future<void> eliminar(String id) async {
    if (estado(id) == EstadoPaquete.descargando) pausar();
    final dir = await _carpeta(id);
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (e) {
      debugPrint('No se pudo borrar $id: $e');
    }
    _estado[id] = EstadoPaquete.noDescargado;
    _descargados[id] = 0;
    _error[id] = null;
    notifyListeners();
  }

  Future<void> eliminarTodo() async {
    for (final p in _paquetes) {
      await eliminar(p.id);
    }
  }
}
