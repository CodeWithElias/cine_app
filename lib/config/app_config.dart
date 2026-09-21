/// Configuracion del entorno. Nada de esto es secreto (son URLs de
/// desarrollo en la LAN y un Client ID de Google, que es publico por
/// diseno), pero se centraliza aca para no repetirlo/hardcodearlo en
/// cada pantalla.
///
/// IP de la PC donde corren los backends (Docker) en la red WiFi local.
/// Si tu PC cambia de red o de IP, este es el unico lugar que hay que tocar.
const String kHostIp = '192.168.1.36';

/// Backend NestJS (BackendParcial1/Backend) - login y datos de negocio.
const String kBackendApiUrl = 'http://$kHostIp:3333/api';

/// Agente de voz (back_agent) - FastAPI, transcribe/responde/sintetiza audio.
const String kVoiceAgentUrl = 'http://$kHostIp:8000';

/// Conversacion continua con el agente (WebSocket `/ws/voz`): mismo servicio
/// y mismo protocolo que usa el frontend web (src/core/voice).
const String kVoiceWsUrl = 'ws://$kHostIp:8000/ws/voz';

/// Mismo Client ID de Google (tipo Web) que ya usan el frontend y el backend.
/// El login nativo en Android igual requiere un cliente OAuth "Android"
/// separado registrado en la consola de Google Cloud (paquete + SHA-1),
/// pero ese cliente no se referencia por ID en ningun lado del codigo.
const String kGoogleServerClientId =
    '12414827958-bngsa5sj8ulotf6a6habeid68jtoou0s.apps.googleusercontent.com';
