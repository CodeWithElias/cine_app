import 'cine_models.dart';

/// Un estreno del carrusel "Estrenos y adelantos": ficha + trailer de YouTube. Si la
/// pelicula esta en la cartelera real, `peliculaReal` la enlaza para poder comprarla.
///
/// Es el mismo catalogo que `MOVIES_PREVIEW` de `GlassyCarousel.tsx` en la web.
class Estreno {
  final String titulo;
  final String? subtitulo;
  final String director;
  final int anio;
  final String genero;
  final String rating;
  final String posterUrl;
  final String youtubeId;
  final String sinopsis;
  final Pelicula? peliculaReal;

  const Estreno({
    required this.titulo,
    this.subtitulo,
    required this.director,
    required this.anio,
    required this.genero,
    required this.rating,
    required this.posterUrl,
    required this.youtubeId,
    required this.sinopsis,
    this.peliculaReal,
  });

  Uri get urlTrailer => Uri.parse('https://www.youtube.com/watch?v=$youtubeId');

  Estreno conPelicula(Pelicula p) => Estreno(
        titulo: titulo,
        subtitulo: subtitulo,
        director: director,
        anio: anio,
        genero: genero,
        rating: rating,
        posterUrl: posterUrl,
        youtubeId: youtubeId,
        sinopsis: sinopsis,
        peliculaReal: p,
      );
}

const List<Estreno> estrenosBase = [
  Estreno(
    titulo: 'Dune: Part Two',
    subtitulo: 'Duna: Parte Dos',
    director: 'Denis Villeneuve',
    anio: 2024,
    genero: 'Epic Sci-Fi',
    rating: '8.8',
    posterUrl: 'https://image.tmdb.org/t/p/w780/8b8R8l88Qje9dn9OE8PY05Nxl1X.jpg',
    youtubeId: 'Way9Dexny3w',
    sinopsis: 'Paul Atreides se une a Chani y a los Fremen mientras busca venganza contra los conspiradores que destruyeron a su familia.',
  ),
  Estreno(
    titulo: 'Blade Runner 2049',
    subtitulo: 'Blade Runner 2049',
    director: 'Denis Villeneuve',
    anio: 2017,
    genero: 'Neo-Noir',
    rating: '8.0',
    posterUrl: 'https://image.tmdb.org/t/p/w780/gajva2L0rPYkEWjzgFlBXCAVBE5.jpg',
    youtubeId: 'gCcx85zbxz4',
    sinopsis: 'Treinta años después de los eventos de la primera película, un nuevo blade runner desentierra un secreto guardado durante mucho tiempo.',
  ),
  Estreno(
    titulo: 'Spider-Man: Spider-Verse',
    subtitulo: 'Across the Spider-Verse',
    director: 'Joaquim Dos Santos & Kemp Powers',
    anio: 2023,
    genero: 'Animación / Acción',
    rating: '8.7',
    posterUrl: 'https://image.tmdb.org/t/p/w780/8Vt6mWEReuy4Of61Lnj5Xj704m8.jpg',
    youtubeId: 'cqGjhVJWtEg',
    sinopsis: 'Miles Morales es catapultado a través del Multiverso, donde se encuentra con un equipo de Spider-People encargado de proteger su existencia.',
  ),
  Estreno(
    titulo: 'Oppenheimer',
    subtitulo: 'Oppenheimer',
    director: 'Christopher Nolan',
    anio: 2023,
    genero: 'Historical Drama',
    rating: '8.9',
    posterUrl: 'https://image.tmdb.org/t/p/w780/8Gxv8gSFCU0XGDykEGv7zR1n2ua.jpg',
    youtubeId: 'uYPbbksJxIg',
    sinopsis: 'La historia del científico J. Robert Oppenheimer y su liderazgo en el desarrollo de la bomba atómica en el Proyecto Manhattan.',
  ),
  Estreno(
    titulo: 'Interstellar',
    subtitulo: 'Interestelar',
    director: 'Christopher Nolan',
    anio: 2014,
    genero: 'Epic Sci-Fi',
    rating: '8.7',
    posterUrl: 'https://image.tmdb.org/t/p/w780/gEU2QniE6E77NI6lCU6MxlNBvIx.jpg',
    youtubeId: 'zSWdZVtXT7E',
    sinopsis: 'Un equipo de exploradores viaja a través de un agujero de gusano en el espacio en un intento por asegurar la supervivencia de la humanidad.',
  ),
  Estreno(
    titulo: 'El Viaje de Chihiro',
    subtitulo: 'Spirited Away',
    director: 'Hayao Miyazaki',
    anio: 2001,
    genero: 'Anime Fantasy',
    rating: '8.6',
    posterUrl: 'https://image.tmdb.org/t/p/w780/39wmItIWsg5sZMyRUHLkWBcuVCM.jpg',
    youtubeId: 'ByXuk9QqQkk',
    sinopsis: 'Chihiro entra a un mundo misterioso gobernado por dioses, espíritus y una bruja donde sus padres son transformados.',
  ),
];

bool _coincide(Pelicula p, Estreno e) {
  final t1 = p.titulo.toLowerCase();
  final t2 = e.titulo.toLowerCase();
  final t3 = (e.subtitulo ?? '').toLowerCase();
  return t1.contains(t2) || t2.contains(t1) || (t3.isNotEmpty && (t1.contains(t3) || t3.contains(t1)));
}

/// Los estrenos de la lista fija enlazados con la cartelera real, mas las peliculas activas
/// que no estan en la lista (con su propia ficha y un trailer generico), igual que en la web.
List<Estreno> estrenosConCartelera(List<Pelicula> cartelera) {
  final enlazados = [
    for (final e in estrenosBase)
      () {
        final real = cartelera.where((p) => _coincide(p, e)).firstOrNull;
        return real == null ? e : e.conPelicula(real);
      }(),
  ];
  final extras = [
    for (final p in cartelera)
      if (!enlazados.any((e) => e.peliculaReal?.idPelicula == p.idPelicula))
        Estreno(
          titulo: p.titulo,
          director: 'Director Cinema',
          anio: 2026,
          genero: p.genero ?? 'Estreno',
          rating: '8.5',
          posterUrl: p.posterUrl ?? '',
          youtubeId: 'Way9Dexny3w', // trailer generico, como en la web
          sinopsis: p.sinopsis ?? 'Disfruta de este gran estreno en nuestras salas con tecnología láser y sonido envolvente.',
          peliculaReal: p,
        ),
  ];
  return [...enlazados, ...extras];
}
