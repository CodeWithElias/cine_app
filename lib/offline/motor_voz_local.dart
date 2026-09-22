import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'gestor_modelos.dart';

/// Motor de voz que corre EN EL TELEFONO, sin internet (sherpa-onnx):
///   microfono (PCM16 16 kHz) -> detector de voz (Silero) -> reconocimiento (Whisper) -> texto
///   texto -> voz (Piper) -> PCM16
///
/// Todo el trabajo pesado vive en un isolate aparte: reconocer una frase o generar una voz tarda de cientos de ms a unos
/// segundos y en el hilo de la interfaz congelaria la pantalla.
class MotorVozLocal {
  MotorVozLocal._(this._aIsolate, this._isolate, this._recibir);

  final SendPort _aIsolate;
  final Isolate _isolate;
  final ReceivePort _recibir;
  var _cerrado = false;
  var _ultimoIdVoz = 0;

  /// El detector de voz noto que el cliente empezo (true) o dejo de hablar (false).
  void Function(bool hablando)? onVoz;

  /// Frase reconocida (ya terminada).
  void Function(String texto)? onTexto;

  /// Audio de una frase que se pidio decir: PCM16 mono y su tasa de muestreo.
  void Function(int id, int tasa, Uint8List pcm)? onAudioHablado;

  void Function(String mensaje)? onError;

  /// Carga los modelos en un isolate y espera a que esten listos (unos segundos la primera vez).
  static Future<MotorVozLocal> crear(
    RutasVoz rutas, {
    Duration espera = const Duration(seconds: 90),
  }) async {
    final recibir = ReceivePort();
    final conexion = Completer<SendPort>();
    final listo = Completer<void>();
    MotorVozLocal? motor;
    final isolate = await Isolate.spawn(
      _entrada,
      _Arranque(recibir.sendPort, rutas),
    );
    recibir.listen((dynamic m) {
      if (m is SendPort) {
        conexion.complete(m);
        return;
      }
      if (m is! Map) return;
      switch (m['t']) {
        case 'listo':
          if (!listo.isCompleted) listo.complete();
        case 'error':
          final texto = '${m['m']}';
          if (!listo.isCompleted) {
            listo.completeError(texto);
          } else {
            motor?.onError?.call(texto);
          }
        case 'vad':
          motor?.onVoz?.call(m['hablando'] == true);
        case 'texto':
          motor?.onTexto?.call('${m['texto']}');
        case 'voz':
          final datos = (m['pcm'] as TransferableTypedData)
              .materialize()
              .asUint8List();
          motor?.onAudioHablado?.call(m['id'] as int, m['tasa'] as int, datos);
      }
    });
    motor = MotorVozLocal._(
      await conexion.future.timeout(espera),
      isolate,
      recibir,
    );
    try {
      await listo.future.timeout(espera);
    } catch (e) {
      await motor.cerrar();
      rethrow;
    }
    return motor;
  }

  /// Le pasa un trozo del microfono (PCM16 little-endian, 16 kHz, mono).
  void enviarAudio(Uint8List pcm) {
    if (_cerrado) return;
    _aIsolate.send({
      't': 'audio',
      'pcm': TransferableTypedData.fromList([pcm]),
    });
  }

  /// Pide decir un texto; el audio llega por [onAudioHablado] con el id que devuelve esto.
  int hablar(String texto) {
    final id = ++_ultimoIdVoz;
    if (!_cerrado) _aIsolate.send({'t': 'hablar', 'id': id, 'texto': texto});
    return id;
  }

  /// El ultimo id de voz pedido: lo que llegue con un id menor ya no interesa (se interrumpio).
  int get ultimoIdVoz => _ultimoIdVoz;

  /// Descarta lo que el detector de voz tiene a medias (ej. al terminar de hablar el asistente).
  void reiniciarDeteccion() {
    if (!_cerrado) _aIsolate.send({'t': 'reiniciar'});
  }

  Future<void> cerrar() async {
    if (_cerrado) return;
    _cerrado = true;
    _aIsolate.send({'t': 'cerrar'});
    await Future<void>.delayed(const Duration(milliseconds: 150));
    _isolate.kill(priority: Isolate.beforeNextEvent);
    _recibir.close();
  }

  // ------------------------------------------------------------------ isolate

  static void _entrada(_Arranque a) async {
    final puerto = ReceivePort();
    a.hacia.send(puerto.sendPort);

    sherpa.VoiceActivityDetector? vad;
    sherpa.OfflineRecognizer? reconocedor;
    sherpa.OfflineTts? tts;
    try {
      sherpa
          .initBindings(); // cada isolate carga las bibliotecas nativas por su cuenta
      vad = sherpa.VoiceActivityDetector(
        config: sherpa.VadModelConfig(
          sileroVad: sherpa.SileroVadModelConfig(
            model: a.rutas.vad,
            threshold: 0.5,
            minSilenceDuration: 0.6,
            minSpeechDuration: 0.25,
            maxSpeechDuration: 12,
          ),
          sampleRate: 16000,
          numThreads: 1,
          debug: false,
        ),
        bufferSizeInSeconds: 30,
      );
      reconocedor = sherpa.OfflineRecognizer(
        sherpa.OfflineRecognizerConfig(
          model: sherpa.OfflineModelConfig(
            whisper: sherpa.OfflineWhisperModelConfig(
              encoder: a.rutas.encoder,
              decoder: a.rutas.decoder,
              language: 'es',
              task: 'transcribe',
            ),
            tokens: a.rutas.tokens,
            modelType: 'whisper',
            numThreads: 2,
            debug: false,
          ),
        ),
      );
      tts = sherpa.OfflineTts(
        sherpa.OfflineTtsConfig(
          model: sherpa.OfflineTtsModelConfig(
            vits: sherpa.OfflineTtsVitsModelConfig(
              model: a.rutas.ttsModelo,
              tokens: a.rutas.ttsTokens,
              dataDir: a.rutas.espeakDatos,
            ),
            numThreads: 2,
            debug: false,
          ),
        ),
      );
      a.hacia.send({'t': 'listo'});
    } catch (e) {
      a.hacia.send({
        't': 'error',
        'm': 'No se pudieron cargar los modelos: $e',
      });
      return;
    }

    var hablando = false;
    await for (final dynamic m in puerto) {
      if (m is! Map) continue;
      try {
        switch (m['t']) {
          case 'audio':
            final bytes = (m['pcm'] as TransferableTypedData)
                .materialize()
                .asUint8List();
            final muestras = Float32List(bytes.length ~/ 2);
            final datos = ByteData.sublistView(bytes);
            for (var i = 0; i < muestras.length; i++) {
              muestras[i] = datos.getInt16(i * 2, Endian.little) / 32768.0;
            }
            vad.acceptWaveform(muestras);
            final ahora = vad.isDetected();
            if (ahora != hablando) {
              hablando = ahora;
              a.hacia.send({'t': 'vad', 'hablando': hablando});
            }
            while (!vad.isEmpty()) {
              final segmento = vad.front();
              vad.pop();
              if (segmento.samples.length < 4800) {
                continue; // menos de 0,3 s: un ruido, no una frase
              }
              final flujo = reconocedor.createStream();
              flujo.acceptWaveform(
                samples: segmento.samples,
                sampleRate: 16000,
              );
              reconocedor.decode(flujo);
              final texto = reconocedor.getResult(flujo).text.trim();
              flujo.free();
              if (texto.isNotEmpty) {
                a.hacia.send({'t': 'texto', 'texto': texto});
              }
            }
          case 'hablar':
            final voz = tts.generate(
              text: m['texto'] as String,
              sid: 0,
              speed: 1.0,
            );
            final pcm = Int16List(voz.samples.length);
            for (var i = 0; i < pcm.length; i++) {
              pcm[i] = (voz.samples[i].clamp(-1.0, 1.0) * 32767).round();
            }
            a.hacia.send({
              't': 'voz',
              'id': m['id'],
              'tasa': voz.sampleRate,
              'pcm': TransferableTypedData.fromList([pcm.buffer.asUint8List()]),
            });
          case 'reiniciar':
            vad.clear();
            vad.reset();
            hablando = false;
          case 'cerrar':
            vad.free();
            reconocedor.free();
            tts.free();
            puerto.close();
            return;
        }
      } catch (e) {
        a.hacia.send({'t': 'error', 'm': '$e'});
      }
    }
  }
}

class _Arranque {
  final SendPort hacia;
  final RutasVoz rutas;
  const _Arranque(this.hacia, this.rutas);
}
