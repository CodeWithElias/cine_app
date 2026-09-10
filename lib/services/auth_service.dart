import 'dart:convert';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';

class Usuario {
  final int idUsuario;
  final String nombre;
  final String rol;

  Usuario({required this.idUsuario, required this.nombre, required this.rol});
}

class AuthException implements Exception {
  final String message;
  AuthException(this.message);

  @override
  String toString() => message;
}

/// Login con Google + sesion contra el backend NestJS existente
/// (BackendParcial1/Backend, endpoint POST /auth/google). No se reimplementa
/// nada del lado del servidor: se reusa el mismo endpoint y el mismo
/// Client ID que ya usa el frontend web.
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  static const _tokenKey = 'lumen_token';

  bool _initialized = false;
  String? _token;
  Usuario? _usuario;

  String? get token => _token;
  Usuario? get usuario => _usuario;
  bool get estaLogueado => _token != null;

  Future<void> init() async {
    if (_initialized) return;
    await GoogleSignIn.instance.initialize(
      serverClientId: kGoogleServerClientId,
    );
    _initialized = true;

    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_tokenKey);
    if (stored != null) {
      final usuario = _decodeJwt(stored);
      if (usuario != null) {
        _token = stored;
        _usuario = usuario;
      } else {
        await prefs.remove(_tokenKey);
      }
    }
  }

  Future<Usuario> loginConGoogle() async {
    final GoogleSignInAccount cuenta;
    try {
      cuenta = await GoogleSignIn.instance.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw AuthException('Inicio de sesión cancelado.');
      }
      throw AuthException('No se pudo iniciar sesión con Google: ${e.description ?? e.code}');
    }

    final idToken = cuenta.authentication.idToken;
    if (idToken == null) {
      throw AuthException('Google no devolvió credenciales. Intenta de nuevo.');
    }

    final response = await http.post(
      Uri.parse('$kBackendApiUrl/auth/google'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'idToken': idToken}),
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      String detalle = 'Error ${response.statusCode} al iniciar sesión.';
      try {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        detalle = (body['message'] as String?) ?? detalle;
      } catch (_) {}
      throw AuthException(detalle);
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final accessToken = body['access_token'] as String?;
    if (accessToken == null) {
      throw AuthException('El backend devolvió una respuesta inválida.');
    }

    final usuario = _decodeJwt(accessToken);
    if (usuario == null) {
      throw AuthException('El backend devolvió un token inválido.');
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, accessToken);

    _token = accessToken;
    _usuario = usuario;
    return usuario;
  }

  Future<void> logout() async {
    await GoogleSignIn.instance.signOut();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    _token = null;
    _usuario = null;
  }

  /// El JWT ya fue firmado y validado por el backend — aca solo se lee el
  /// payload para mostrar datos del usuario, sin verificar la firma.
  Usuario? _decodeJwt(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      final payloadJson = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
      final payload = jsonDecode(payloadJson) as Map<String, dynamic>;
      final sub = payload['sub'];
      final nombre = payload['nombre'];
      final rol = payload['rol'];
      if (sub is! int || nombre is! String || rol is! String) return null;
      return Usuario(idUsuario: sub, nombre: nombre, rol: rol);
    } catch (_) {
      return null;
    }
  }
}
