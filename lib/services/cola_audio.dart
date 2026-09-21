import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

/// Cola de reproduccion del audio del agente. Cada frase llega como PCM16 mono
/// suelto; se envuelve en un WAV y se reproduce una tras otra. Si mientras suena
/// una llegan varias mas, se juntan en un solo clip para que no haya cortes entre
/// frases. `vaciar()` corta todo de inmediato (interrupcion).
///
/// Espejo de `playbackQueue.ts` del frontend web (alli con Web Audio).
class ColaAudio {
  ColaAudio() {
    // La voz del asistente se mezcla con el microfono abierto: sin pedir foco de audio (que pausaria la grabacion).
    _player.setAudioContext(AudioContext(
      android: const AudioContextAndroid(
        audioFocus: AndroidAudioFocus.none,
        contentType: AndroidContentType.speech,
        usageType: AndroidUsageType.media,
      ),
      iOS: AudioContextIOS(
        category: AVAudioSessionCategory.playAndRecord,
        options: const {AVAudioSessionOptions.defaultToSpeaker, AVAudioSessionOptions.mixWithOthers},
      ),
    ));
    _fin = _player.onPlayerComplete.listen((_) => _alTerminar());
  }

  final AudioPlayer _player = AudioPlayer();
  late final StreamSubscription<void> _fin;

  final List<Uint8List> _pendientes = [];
  int _sampleRate = 22050;
  bool _sonando = false;

  /// true cuando empieza a sonar algo; false cuando la cola se vacia (termino o se corto).
  void Function(bool reproduciendo)? onCambio;

  bool get reproduciendo => _sonando;

  void encolar(int sampleRate, Uint8List pcm) {
    if (pcm.isEmpty) return;
    _sampleRate = sampleRate; // el servidor usa una sola tasa (la de la voz de Piper) en toda la conversacion
    _pendientes.add(pcm);
    if (!_sonando) _reproducirSiguiente();
  }

  Future<void> _reproducirSiguiente() async {
    if (_pendientes.isEmpty) return;
    final total = _pendientes.fold<int>(0, (a, b) => a + b.length);
    final pcm = Uint8List(total);
    var pos = 0;
    for (final trozo in _pendientes) {
      pcm.setRange(pos, pos + trozo.length, trozo);
      pos += trozo.length;
    }
    _pendientes.clear();

    final avisar = !_sonando;
    _sonando = true;
    if (avisar) onCambio?.call(true);
    try {
      await _player.play(BytesSource(_envolverEnWav(pcm, _sampleRate), mimeType: 'audio/wav'));
    } catch (_) {
      _alTerminar();
    }
  }

  void _alTerminar() {
    if (_pendientes.isNotEmpty) {
      _reproducirSiguiente();
      return;
    }
    if (_sonando) {
      _sonando = false;
      onCambio?.call(false);
    }
  }

  /// Corta lo que suena y descarta lo que estaba en espera.
  Future<void> vaciar() async {
    final habia = _sonando || _pendientes.isNotEmpty;
    _pendientes.clear();
    _sonando = false;
    try {
      await _player.stop();
    } catch (_) {}
    if (habia) onCambio?.call(false);
  }

  Future<void> dispose() async {
    await _fin.cancel();
    await _player.dispose();
  }

  static Uint8List _envolverEnWav(Uint8List pcm, int sampleRate) {
    const canales = 1;
    const bits = 16;
    final byteRate = sampleRate * canales * bits ~/ 8;
    final cabecera = ByteData(44);
    void texto(int offset, String s) {
      for (var i = 0; i < s.length; i++) {
        cabecera.setUint8(offset + i, s.codeUnitAt(i));
      }
    }

    texto(0, 'RIFF');
    cabecera.setUint32(4, 36 + pcm.length, Endian.little);
    texto(8, 'WAVE');
    texto(12, 'fmt ');
    cabecera.setUint32(16, 16, Endian.little);
    cabecera.setUint16(20, 1, Endian.little); // PCM
    cabecera.setUint16(22, canales, Endian.little);
    cabecera.setUint32(24, sampleRate, Endian.little);
    cabecera.setUint32(28, byteRate, Endian.little);
    cabecera.setUint16(32, canales * bits ~/ 8, Endian.little);
    cabecera.setUint16(34, bits, Endian.little);
    texto(36, 'data');
    cabecera.setUint32(40, pcm.length, Endian.little);

    final wav = Uint8List(44 + pcm.length);
    wav.setRange(0, 44, cabecera.buffer.asUint8List());
    wav.setRange(44, wav.length, pcm);
    return wav;
  }
}
