// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get onboardingHeadline => 'Votre appartement vous attend ici';

  @override
  String get onboardingSubtitle =>
      'Une recherche intelligente basée sur ce qui compte vraiment pour vous — budget, quartier et style de vie. Publiez une annonce en quelques clics, avec toutes vos correspondances et discussions au même endroit.';

  @override
  String get getStarted => 'Commencer';

  @override
  String get next => 'Suivant';

  @override
  String get introSwipeTitle => 'Découvrez des appartements en glissant';

  @override
  String get introSwipeBody =>
      'Glissez à droite 👍 pour enregistrer un appartement que vous aimez, à gauche 👎 pour passer. Vous pouvez aussi chercher avec Ati (recherche intelligente), dans la galerie ou sur la carte.';

  @override
  String get introAtiTitle => 'Ati — la recherche intelligente';

  @override
  String get introAtiBody =>
      'Dites à Ati ce que vous cherchez, avec vos propres mots, et elle trouvera les appartements qui vous correspondent le mieux.';

  @override
  String get introTourTitle => 'Visites en 3D';

  @override
  String get introTourBody =>
      'Entrez dans l\'appartement avant même de quitter chez vous — une visite à 360° et une expérience 3D directement depuis votre écran.';

  @override
  String get introMatchTitle => 'Correspondances et chat';

  @override
  String get introMatchBody =>
      'Lorsqu\'il y a une correspondance mutuelle, vous pouvez discuter directement, planifier une visite et conclure l\'affaire — le tout au même endroit.';

  @override
  String get introProfileTitle => 'Votre profil';

  @override
  String get introProfileBody =>
      'Complétez vos informations pour obtenir des correspondances plus précises. Plus votre profil est complet, meilleures sont les correspondances.';

  @override
  String get skip => 'Passer';

  @override
  String get letsGetStarted => 'C\'est parti !';
}
