import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

import '../config/app_config.dart';
import '../offline/interprete_local.dart' show esAlucinacion;
import '../offline/motor_voz_local.dart';
import '../offline/sin_conexion.dart';
import 'auth_service.dart';
import 'cola_audio.dart';

enum EstadoConversacion { apagada, conectando, escuchando, pensando, hablando, error }

/// Lo que se muestra del intercambio en curso. Se limpia solo un rato despues de
/// que el agente termina de hablar (espejo de `TurnoVisible` de la web).
class TurnoVisible {
  final String transcript;
  final String respuesta;
  final String? error;
  const TurnoVisible({this.transcript = '', this.respuesta = '', this.error});

  bool get vacio => transcript.isEmpty && respuesta.isEmpty && error == null;
}

/// Conversacion continua con el agente (RF13/RF16) por WebSocket `/ws/voz`: abre
/// el microfono una vez y manda el audio sin parar; el servidor detecta cuando
/// terminas cada frase, responde hablando y avisa que hacer con la pantalla.
/// No hay botones de "grabar" ni "enviar".
///
/// Es el espejo de `useVoiceSession.ts` del frontend web y usa el mismo
/// protocolo (ver back_agent/app/routers/ws_voz.py):
///   cliente -> servidor: hello, PCM16 mono 16 kHz, contexto, pantalla, interrupt, bye
///   servidor -> cliente: ready, state, vad, transcript, ui_action, reply, interrupted, error, audio
class VoiceSession extends ChangeNotifier {
  VoiceSession({required this.sesionId, this.onUiAction, this.sinConexion}) {
    _cola.onCambio = (sonando) {
      _sonando = sonando;
      if (!sonando) _silencioHasta = DateTime.now().add(_colaDeEco);
      if (modoLocal) _alCambiarReproduccionLocal(sonando);
    };
  }

  final String sesionId;

  /// El modo sin conexion (modelos descargados en el telefono). Null = no existe: la app solo habla con el servidor.
  final SinConexion? sinConexion;

  /// Recibe cada tanda de acciones de interfaz (RF18) con su numero de version.
  final void Function(List<dynamic> acciones, int? version)? onUiAction;

  static const _reintentosMax = 8;
  static const _tiempoLectura = Duration(milliseconds: 3500);

  /// Lo que se deja de mandar audio despues de que el asistente termina de sonar (para no oir su propio eco).
  static const _colaDeEco = Duration(milliseconds: 800);

  final AudioRecorder _grabador = AudioRecorder();
  final ColaAudio _cola = ColaAudio();

  WebSocket? _ws;
  StreamSubscription<Uint8List>? _micSub;
  StreamSubscription<dynamic>? _wsSub;
  Timer? _reintento;
  Timer? _reinicioTurno;

  int _generacion = 0;
  int _intentos = 0;
  bool _listo = false;
  bool _cerradaAProposito = false;
  bool _pantallaEnviada = false;

  // ---- modo sin conexion: el reconocimiento, la respuesta y la voz corren en el telefono
  MotorVozLocal? _motor;
  int _ttsPendientes = 0; // frases pedidas al motor cuyo audio aun no llego
  int _descartarVozHasta = 0; // ids de voz menores o iguales a este se ignoran (se interrumpio)

  /// true mientras la conversacion se atiende en el telefono (sin internet).
  bool modoLocal = false;

  /// ¿Hay pantalla para el formulario de tarjeta de Stripe? Si no (Stripe sin configurar), el agente solo ofrece efectivo.
  bool _tarjetaDisponible = false;

  // Half-duplex en el telefono: el servidor da por terminado el turno del asistente cuando TERMINA DE ENVIAR el audio, pero
  // el telefono todavia lo esta reproduciendo. Mientras suena no se manda microfono (sin cancelacion de eco fiable, el
  // asistente se oiria a si mismo); apenas termina, se vuelve a escuchar sin tocar nada.
  bool _sonando = false;
  DateTime _silencioHasta = DateTime.fromMillisecondsSinceEpoch(0);

  EstadoConversacion estado = EstadoConversacion.apagada;
  bool reconectando = false;
  bool usuarioHablando = false;
  bool silenciado = false;
  TurnoVisible turno = const TurnoVisible();
  String? error;

  bool get activa => estado != EstadoConversacion.apagada && estado != EstadoConversacion.error;
  bool get conversando =>
      estado == EstadoConversacion.escuchando || estado == EstadoConversacion.pensando || estado == EstadoConversacion.hablando;

  void _cambiar(EstadoConversacion nuevo) {
    estado = nuevo;
    notifyListeners();
  }

  // ------------------------------------------------------------------ ciclo de vida

  Future<void> iniciar() async {
    if (estado != EstadoConversacion.apagada && estado != EstadoConversacion.error) return;
    final gen = ++_generacion;
    _cerradaAProposito = false;
    _intentos = 0;
    error = null;
    reconectando = false;
    modoLocal = false;
    turno = const TurnoVisible();
    _cambiar(EstadoConversacion.conectando);

    try {
      if (!await _grabador.hasPermission()) {
        error = 'No se pudo acceder al micrófono. Revisa los permisos de la app.';
        _cambiar(EstadoConversacion.error);
        return;
      }
      final flujo = await _grabador.startStream(const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
        echoCancel: true,
        noiseSuppress: true,
        // Sin ganancia automatica: en el telefono sube el ruido de fondo hasta que el detector de voz lo toma por voz y
        // Whisper "transcribe" palabras que nadie dijo.
        autoGain: false,
        // Fuente de audio de llamadas: el telefono le aplica su propia cancelacion de eco y de ruido (lo que usa una videollamada).
        androidConfig: AndroidRecordConfig(audioSource: AndroidAudioSource.voiceCommunication),
        // Por defecto el grabador se PAUSA cuando otro audio (la voz del asistente) toma el foco de audio y no se
        // reanuda: el asistente hablaba y despues ya no te escuchaba. La conversacion es continua: nunca se pausa.
        audioInterruption: AudioInterruptionMode.none,
      ));
      if (gen != _generacion) {
        await _grabador.stop();
        return;
      }
      _micSub = flujo.listen((trozo) {
        if (!_listo || silenciado || _sonando || DateTime.now().isBefore(_silencioHasta)) return;
        if (modoLocal) {
          _motor?.enviarAudio(trozo);
          return;
        }
        final ws = _ws;
        if (ws != null && ws.readyState == WebSocket.open) ws.add(trozo);
      });
      // Sin internet (o si el cliente prefiere el asistente del telefono) y con los modelos descargados: todo local.
      if (sinConexion != null && await sinConexion!.debeUsarLocal()) {
        if (gen != _generacion) return;
        await _arrancarLocal(gen);
      } else {
        await _abrirSocket(gen);
      }
    } catch (e) {
      if (gen != _generacion) return;
      await _liberarAudio();
      error = 'No se pudo abrir el micrófono.';
      _cambiar(EstadoConversacion.error);
    }
  }

  Future<void> terminar() async {
    _generacion++;
    _cerradaAProposito = true;
    _listo = false;
    _pantallaEnviada = false;
    _reintento?.cancel();
    final ws = _ws;
    _ws = null;
    await _wsSub?.cancel();
    _wsSub = null;
    if (ws != null) {
      try {
        if (ws.readyState == WebSocket.open) ws.add(jsonEncode({'type': 'bye'}));
        await ws.close();
      } catch (_) {}
    }
    await _liberarAudio();
    usuarioHablando = false;
    reconectando = false;
    modoLocal = false;
    _limpiarTurno();
    _cambiar(EstadoConversacion.apagada);
  }

  Future<void> alternar() => activa ? terminar() : iniciar();

  Future<void> _liberarAudio() async {
    _reintento?.cancel();
    await _micSub?.cancel();
    _micSub = null;
    try {
      if (await _grabador.isRecording()) await _grabador.stop();
    } catch (_) {}
    await _cerrarMotor();
    await _cola.vaciar();
  }

  // ------------------------------------------------------------------ socket

  Future<void> _abrirSocket(int gen) async {
    try {
      final ws = await WebSocket.connect(kVoiceWsUrl).timeout(const Duration(seconds: 8));
      if (gen != _generacion) {
        await ws.close();
        return;
      }
      _ws = ws;
      _wsSub = ws.listen(
        (dato) => _alRecibir(gen, dato),
        onDone: () => _alCerrarse(gen),
        onError: (_) => _alCerrarse(gen),
        cancelOnError: true,
      );
      _enviar({
        'type': 'hello',
        'rol': 'cliente',
        'sesion_id': sesionId,
        'token': AuthService.instance.token,
        // Sin cancelacion de eco fiable en el altavoz del telefono, hablar encima del agente lo interrumpiria solo:
        // se corta tocando el boton.
        'barge_in': false,
      });
    } catch (_) {
      _alCerrarse(gen);
    }
  }

  void _alCerrarse(int gen) {
    if (gen != _generacion || _cerradaAProposito) return;
    _listo = false;
    _pantallaEnviada = false;
    _ws = null;
    _wsSub?.cancel();
    _wsSub = null;
    if (_intentos >= 2 && sinConexion?.disponible == true) {
      // Se perdio la conexion en plena conversacion y hay modelos en el telefono: se sigue sin internet.
      _pasarALocal(gen);
      return;
    }
    if (_intentos < _reintentosMax) {
      // El microfono sigue abierto; solo se reconecta (el servidor conserva la sesion por sesion_id).
      _intentos++;
      reconectando = true;
      _cambiar(EstadoConversacion.conectando);
      final espera = Duration(milliseconds: (400 * (1 << _intentos)).clamp(400, 4000));
      _reintento = Timer(espera, () {
        if (gen == _generacion) _abrirSocket(gen);
      });
      return;
    }
    _liberarAudio();
    reconectando = false;
    _limpiarTurno();
    error = 'Se perdió la conexión con el asistente de voz. Revisa que el servicio esté encendido y vuelve a intentar.';
    _cambiar(EstadoConversacion.error);
  }

  void _alRecibir(int gen, dynamic dato) {
    if (gen != _generacion) return;
    if (dato is String) {
      try {
        _alEvento((jsonDecode(dato) as Map).cast<String, dynamic>());
      } catch (_) {
        // un mensaje ilegible no debe tumbar la conversacion
      }
      return;
    }
    if (dato is List<int>) {
      final bytes = dato is Uint8List ? dato : Uint8List.fromList(dato);
      if (bytes.length <= 8) return;
      final cabecera = ByteData.sublistView(bytes, 0, 8);
      final tasa = cabecera.getUint32(0, Endian.little);
      _cola.encolar(tasa, Uint8List.sublistView(bytes, 8));
    }
  }

  void _alEvento(Map<String, dynamic> e) {
    switch (e['type']) {
      case 'ready':
        _listo = true;
        _intentos = 0;
        reconectando = false;
        error = null;
        _cambiar(EstadoConversacion.escuchando);
        if (!_pantallaEnviada) {
          _pantallaEnviada = true;
          enviarPantalla(_tarjetaDisponible);
        }
      case 'state':
        final valor = e['value'];
        _cambiar(switch (valor) {
          'pensando' => EstadoConversacion.pensando,
          'hablando' => EstadoConversacion.hablando,
          _ => EstadoConversacion.escuchando,
        });
        // Mientras el agente piensa o habla se conserva lo que se muestra; al volver a escuchar empieza la cuenta para limpiarlo.
        if (valor == 'escuchando') {
          _programarReinicioTurno();
        } else {
          _reinicioTurno?.cancel();
        }
      case 'vad':
        usuarioHablando = e['hablando'] == true;
        if (usuarioHablando) _limpiarTurno(); // empieza un turno nuevo
        notifyListeners();
      case 'interrupted':
        _cola.vaciar();
      case 'transcript':
        _reinicioTurno?.cancel();
        turno = TurnoVisible(transcript: (e['text'] as String?) ?? '');
        notifyListeners();
      case 'reply':
        turno = TurnoVisible(transcript: turno.transcript, respuesta: (e['texto'] as String?) ?? '');
        notifyListeners();
      case 'ui_action':
        onUiAction?.call((e['acciones'] as List?) ?? const [], (e['v'] as num?)?.toInt());
      case 'error':
        final mensaje = (e['message'] as String?) ?? 'Ocurrió un problema.';
        error = mensaje;
        turno = TurnoVisible(transcript: turno.transcript, respuesta: turno.respuesta, error: mensaje);
        notifyListeners();
    }
  }

  void _programarReinicioTurno() {
    _reinicioTurno?.cancel();
    _reinicioTurno = Timer(_tiempoLectura, _limpiarTurno);
  }

  void _limpiarTurno() {
    _reinicioTurno?.cancel();
    if (!turno.vacio) {
      turno = const TurnoVisible();
      notifyListeners();
    }
  }

  // ------------------------------------------------------------------ modo sin conexion

  Future<void> _cerrarMotor() async {
    final m = _motor;
    _motor = null;
    _ttsPendientes = 0;
    await m?.cerrar();
  }

  /// Carga el motor de voz del telefono y empieza a escuchar. El microfono ya esta abierto.
  Future<void> _arrancarLocal(int gen) async {
    try {
      final motor = await sinConexion!.crearMotor();
      if (gen != _generacion) {
        await motor.cerrar();
        return;
      }
      _conectarMotor(motor);
      modoLocal = true;
      _listo = true;
      error = null;
      _cambiar(EstadoConversacion.escuchando);
    } catch (e) {
      if (gen != _generacion) return;
      await _liberarAudio();
      error = 'No se pudo iniciar el modo sin conexión: $e';
      _cambiar(EstadoConversacion.error);
    }
  }

  /// La conexion con el servidor se perdio en plena conversacion: se sigue con el asistente del telefono.
  Future<void> _pasarALocal(int gen) async {
    if (modoLocal) return;
    _listo = false;
    reconectando = false;
    _cambiar(EstadoConversacion.conectando);
    await _arrancarLocal(gen);
    if (modoLocal && gen == _generacion) {
      turno = const TurnoVisible(respuesta: 'Sin conexión: sigo con el asistente del teléfono.');
      notifyListeners();
      _programarReinicioTurno();
    }
  }

  void _conectarMotor(MotorVozLocal motor) {
    _motor = motor;
    motor.onVoz = (hablando) {
      usuarioHablando = hablando;
      if (hablando) _limpiarTurno();
      notifyListeners();
    };
    motor.onTexto = _alTextoLocal;
    motor.onAudioHablado = _alAudioLocal;
    motor.onError = (mensaje) {
      turno = TurnoVisible(transcript: turno.transcript, respuesta: turno.respuesta, error: mensaje);
      notifyListeners();
    };
  }

  /// Una frase del cliente ya reconocida en el telefono: se interpreta con los datos guardados y se contesta hablando.
  Future<void> _alTextoLocal(String texto) async {
    if (!modoLocal || esAlucinacion(texto)) return;
    _reinicioTurno?.cancel();
    turno = TurnoVisible(transcript: texto);
    _cambiar(EstadoConversacion.pensando);
    final respuesta = await sinConexion!.interpretar(texto);
    if (!modoLocal) return;
    turno = TurnoVisible(transcript: texto, respuesta: respuesta.texto);
    notifyListeners();
    if (respuesta.acciones.isNotEmpty) onUiAction?.call(respuesta.acciones, null);
    _hablarLocal(respuesta.texto);
  }

  /// Pide al motor decir el texto, una frase por vez para que la primera suene sin esperar a las demas.
  void _hablarLocal(String texto) {
    final motor = _motor;
    if (motor == null) return;
    final frases = RegExp(r'[^.!?¡¿]+[.!?]?').allMatches(texto).map((m) => m.group(0)!.trim()).where((f) => f.length > 1).toList();
    if (frases.isEmpty) {
      _cambiar(EstadoConversacion.escuchando);
      return;
    }
    _ttsPendientes += frases.length;
    for (final f in frases) {
      motor.hablar(f);
    }
  }

  void _alAudioLocal(int id, int tasa, Uint8List pcm) {
    if (!modoLocal) return;
    if (id <= _descartarVozHasta) return; // se interrumpio antes de que llegara
    if (_ttsPendientes > 0) _ttsPendientes--;
    if (pcm.isNotEmpty) {
      _cola.encolar(tasa, pcm);
    } else if (_ttsPendientes == 0 && !_sonando) {
      _cambiar(EstadoConversacion.escuchando);
    }
  }

  /// Empezo o termino de sonar la voz del telefono: el estado de la conversacion sigue a eso (en linea lo manda el servidor).
  void _alCambiarReproduccionLocal(bool sonando) {
    if (sonando) {
      _cambiar(EstadoConversacion.hablando);
    } else if (_ttsPendientes == 0 && estado == EstadoConversacion.hablando) {
      _motor?.reiniciarDeteccion();
      _cambiar(EstadoConversacion.escuchando);
      _programarReinicioTurno();
    }
  }

  // ------------------------------------------------------------------ mensajes al servidor

  void _enviar(Map<String, dynamic> mensaje) {
    final ws = _ws;
    if (ws != null && ws.readyState == WebSocket.open) ws.add(jsonEncode(mensaje));
  }

  /// Corta lo que esta diciendo el agente.
  void interrumpir() {
    _cola.vaciar();
    if (modoLocal) {
      _descartarVozHasta = _motor?.ultimoIdVoz ?? 0; // lo que el motor todavia este generando ya no se dice
      _ttsPendientes = 0;
      if (estado == EstadoConversacion.hablando) _cambiar(EstadoConversacion.escuchando);
      return;
    }
    _enviar({'type': 'interrupt'});
  }

  /// Entrada escrita (o un boton de la pantalla): misma logica que la voz, sin reconocimiento.
  void enviarTexto(String texto) {
    final limpio = texto.trim();
    if (limpio.isNotEmpty) _enviar({'type': 'text', 'text': limpio});
  }

  void silenciar(bool valor) {
    silenciado = valor;
    notifyListeners();
  }

  /// Le cuenta al agente lo que el cliente tiene marcado en pantalla. No es un turno: no se contesta.
  void enviarContexto(int version, Map<String, dynamic> compra) => _enviar({'type': 'contexto', 'v': version, 'compra': compra});

  void enviarPantalla(bool disponible) => _enviar({'type': 'pantalla', 'disponible': disponible});

  /// Se sabe si Stripe esta disponible (puede llegar despues de abrir la conversacion): se le avisa al agente.
  void setTarjetaDisponible(bool valor) {
    _tarjetaDisponible = valor;
    if (conversando) enviarPantalla(valor);
  }

  /// Como va el formulario de tarjeta: SOLO el estado de cada campo, nunca lo escrito (eso vive en el campo seguro de
  /// Stripe). El agente guia con esto ("ahora la fecha"). No es un turno.
  void enviarPagoCampos(int idVenta, Map<String, dynamic> campos) => _enviar({'type': 'pago_campos', 'idVenta': idVenta, 'campos': campos});

  /// Como termino el intento de pago (confirmado | rechazado | cancelado | error). El agente NO le cree a la pantalla:
  /// verifica contra el backend antes de decir "pago aceptado".
  void enviarPagoEvento(int idVenta, String evento, [String? mensaje]) =>
      _enviar({'type': 'pago_evento', 'idVenta': idVenta, 'evento': evento, 'mensaje': ?mensaje});

  @override
  void dispose() {
    _generacion++;
    _cerradaAProposito = true;
    _reinicioTurno?.cancel();
    _reintento?.cancel();
    _micSub?.cancel();
    _wsSub?.cancel();
    try {
      _ws?.add(jsonEncode({'type': 'bye'}));
      _ws?.close();
    } catch (_) {}
    _grabador.dispose();
    _cola.dispose();
    super.dispose();
  }
}
