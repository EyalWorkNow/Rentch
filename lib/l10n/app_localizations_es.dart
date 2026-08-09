// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get onboardingHeadline => 'Tu apartamento te espera aquí';

  @override
  String get onboardingSubtitle =>
      'Búsqueda inteligente según lo que realmente te importa: presupuesto, zona y estilo de vida. Publica un apartamento en pocos toques, con todas tus coincidencias y chats en un solo lugar.';

  @override
  String get getStarted => 'Empezar';

  @override
  String get next => 'Siguiente';

  @override
  String get introSwipeTitle => 'Descubre apartamentos deslizando';

  @override
  String get introSwipeBody =>
      'Desliza a la derecha 👍 para guardar un apartamento que te guste, a la izquierda 👎 para pasar. También puedes buscar con Ati (búsqueda inteligente), en la galería o en el mapa.';

  @override
  String get introAtiTitle => 'Ati: la búsqueda inteligente';

  @override
  String get introAtiBody =>
      'Cuéntale a Ati lo que buscas, con tus propias palabras, y ella encontrará los apartamentos que mejor te queden.';

  @override
  String get introTourTitle => 'Recorridos en 3D';

  @override
  String get introTourBody =>
      'Entra al apartamento antes incluso de salir de casa: un recorrido de 360° y una experiencia en 3D directo desde tu pantalla.';

  @override
  String get introMatchTitle => 'Coincidencias y chat';

  @override
  String get introMatchBody =>
      'Cuando hay una coincidencia mutua, puedes chatear directamente, programar una visita y cerrar el trato, todo en un solo lugar.';

  @override
  String get introProfileTitle => 'Tu perfil';

  @override
  String get introProfileBody =>
      'Completa tus datos para obtener coincidencias más precisas. Cuanto más completo esté tu perfil, mejores serán las coincidencias.';

  @override
  String get skip => 'Omitir';

  @override
  String get letsGetStarted => '¡Empecemos!';
}
