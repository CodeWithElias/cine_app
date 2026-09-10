/// Datos de prueba - mismas peliculas que usa el mock de
/// Parcial1_Sw2_Frontend/src/views/Cartelera.tsx, para que se vea igual en
/// los dos frentes mientras no hay conexion a un backend real de catalogo.
class Pelicula {
  final String titulo;
  final String sinopsis;
  final String posterUrl;
  final int duracionMinutos;
  final String clasificacion;
  final String genero;
  final List<String> horarios;

  const Pelicula({
    required this.titulo,
    required this.sinopsis,
    required this.posterUrl,
    required this.duracionMinutos,
    required this.clasificacion,
    required this.genero,
    required this.horarios,
  });
}

const List<Pelicula> mockPeliculas = [
  Pelicula(
    titulo: 'Duna: Parte Dos',
    sinopsis: 'Paul Atreides se une a Chani y a los Fremen mientras busca venganza contra los conspiradores que destruyeron a su familia.',
    posterUrl: 'https://lh3.googleusercontent.com/aida-public/AB6AXuCo6z4UdTfATjr6Eqlu1pEZvmT0DwoX5B0qZ96XgQKe9VMJQ706-cHHeQd7-lotLmFcptZsLDzeeI9xzCqc9nYssjD_vJXtiUpX8_vy9_VClazA7swJiklxwsHzOZresTirl8XAyHk9WmFESbZubvPdm-pGQREFD15VGe5voLGhA3bqD5uYEZRRq5M3BPUW13w0C_HNGiRCnqH2gfpNNbwyrdiA4uTvXeWrbeSuv-B037tgKPPRbv0LEA',
    duracionMinutos: 166,
    clasificacion: '+14 Años',
    genero: 'Sci-Fi • Aventura Épica',
    horarios: ['17:30', '20:15', '22:45'],
  ),
  Pelicula(
    titulo: 'Oppenheimer',
    sinopsis: 'Historia del físico J. Robert Oppenheimer y su rol en el Proyecto Manhattan que alteró la historia humana.',
    posterUrl: 'https://lh3.googleusercontent.com/aida-public/AB6AXuBqKJAHKMk2UrBZxP-Q2Oe8t1ByJbEN0aj8n1-cEh-Zh2XZ-QQeovFwzMA_7Fy9YCg702os4PGj8E1M0bN3jgy3Iip349uC-mvILF7TXvJUJRHXsvg-ra-G9-JyxoCoBq-OdGs8RfJwXFdVwV3ER0-Ojmya7JN3eR1vC6ijBCCFC1fDyt_LcU9PK_LXahPRtQ7L1-xxBf258bdExlV_DZnPUFahs5EdFBZibNcPoLKUHotD06rhGWpO6w',
    duracionMinutos: 180,
    clasificacion: '+16 Años',
    genero: 'Drama Histórico',
    horarios: ['16:00', '19:45', '23:00'],
  ),
  Pelicula(
    titulo: 'Spider-Man: Beyond',
    sinopsis: 'Miles Morales viaja a través del multiverso desafiando las leyes canónicas de la Sociedad Arácnida.',
    posterUrl: 'https://lh3.googleusercontent.com/aida-public/AB6AXuAoSaJow42RXnlL9NO45KLL2-1nWag1KjqkvePsaZarrDK6jTQRAudG7VG4_I6q0pXeB7KT5RQX9WfYHXpfUdIJR6TvQB1QpsXOalCzLvtBLvzRJIObXWVHgjn5UGtLfnG3pRnVac4jou7Ni41etAoy6vBUT5luybCcjwKs10lGIHLIuo293-jB_ycipjctz0YZgtDEs0deepZfCEC44PaDsWY8r1vW9qnzv_AJAUray-ryiVTAH9ILug',
    duracionMinutos: 140,
    clasificacion: 'Todo Público',
    genero: 'Animación • Acción',
    horarios: ['15:15', '18:20', '21:10'],
  ),
  Pelicula(
    titulo: 'El Viaje de Chihiro',
    sinopsis: 'Edición 4K conmemorativa. Chihiro entra en un mundo mágico de espíritus para salvar a sus padres.',
    posterUrl: 'https://lh3.googleusercontent.com/aida-public/AB6AXuBYry0C1IcnL4Ltv4OFETHIWyBkrHbvpjPXzDqTucsL10WlZMB4PgNlS_t7pTaYCy1sOUOBFLVd_O-f2nM4xHy-UHQ_pZKSUp1sS0O9lEw_8A3YqsWBR8Kov0D9vIWj6DqHGGsDHKbPwvBoNaLDIbnMU5nveCOou1dosTK5hb72iD2ZHVaeaLN3o-TGU35nEmafISH2D4Kl7K0eJB32cjynfenu7fZhPpREt4Oegiws7QCrf5knifSgCg',
    duracionMinutos: 125,
    clasificacion: 'Todo Público',
    genero: 'Ghibli Clásico',
    horarios: ['14:30', '17:40', '20:30'],
  ),
  Pelicula(
    titulo: 'Blade Runner 2049',
    sinopsis: 'Treinta años después de los eventos del primer film, un nuevo blade runner descubre un secreto enterrado.',
    posterUrl: 'https://lh3.googleusercontent.com/aida-public/AB6AXuCz9gT6ZQ8Y8b-AyeZPc3ZPaTL4cgKdqq_7U2KzuJFz2zJQSwlhH6l4T3RS72t2o0h-Fh67VDg71TYs9vwlVIowLIxALu4vnZurMs6vo9bG8_o6bfFh0bpgi4RaDElYLTRtzOYiel9cZNQTXpRRBIeE6DUupXywfGaCtQthq1K21K6HOTPwnL7FVD3mf3n58PA5wmzPt-8-nT-Q-hhSwpTz0nN8gWJuEY6jW10pO7TFUKhNIVwRbYE5ZA',
    duracionMinutos: 164,
    clasificacion: '+16 Años',
    genero: 'Cyberpunk Neo-Noir',
    horarios: ['18:00', '21:30', '23:45'],
  ),
];
