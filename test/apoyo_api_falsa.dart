import 'package:cine_app/models/cine_models.dart';
import 'package:cine_app/services/cine_api.dart';

/// API de mentira: el catalogo y la sala vienen de memoria, no del backend.
class ApiFalsa extends CineApi {
  static final manana = DateTime.now().add(const Duration(days: 1));
  static String get fecha =>
      '${manana.year}-${manana.month.toString().padLeft(2, '0')}-${manana.day.toString().padLeft(2, '0')}';

  final pelicula = const Pelicula(
    idPelicula: 1,
    titulo: 'Oppenheimer',
    genero: 'Drama',
    duracionMin: 180,
    clasificacion: '+16',
    estado: 'activa',
  );
  final barbie = const Pelicula(
    idPelicula: 2,
    titulo: 'Barbie',
    genero: 'Comedia',
    duracionMin: 110,
    clasificacion: 'Todo público',
    estado: 'activa',
  );

  Funcion funcion(int id, int idPelicula, String hora) => Funcion(
    idFuncion: id,
    idPelicula: idPelicula,
    idSala: 7,
    idPrecio: 3,
    fecha: fecha,
    horaInicio: hora,
    horaFin: '23:00:00',
    estado: 'programada',
  );

  @override
  Future<List<Pelicula>> listarPeliculas() async => [pelicula, barbie];

  @override
  Future<List<Funcion>> listarFunciones() async => [
    funcion(10, 1, '20:00:00'),
    funcion(11, 2, '18:30:00'),
  ];

  @override
  Future<List<AsientoDisponibilidad>> obtenerDisponibilidad(
    int idFuncion,
  ) async => [
    for (final fila in ['A', 'B'])
      for (var n = 1; n <= 4; n++)
        AsientoDisponibilidad(
          idAsiento: (fila == 'A' ? 0 : 10) + n,
          fila: fila,
          numero: n,
          estado: (fila == 'A' && n == 1) ? 'ocupado' : 'disponible',
        ),
  ];

  @override
  Future<double> obtenerPrecio(int idPrecio) async => 35;

  @override
  Future<Sala> obtenerSala(int idSala) async =>
      const Sala(idSala: 7, nombre: 'Sala 1', tipo: 'IMAX');
}
