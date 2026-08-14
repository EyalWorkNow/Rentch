import 'package:dating_app/l10n/app_localizations.dart';

// RentalProperty.floor / .condition / .propertyType are persisted as raw
// Hebrew strings (the canonical dropdown values in add_property_screen.dart —
// changing that would require a data migration). Every tenant-facing screen
// that renders one of these fields must go through these helpers instead of
// interpolating the raw value directly, or it leaks Hebrew text into an
// otherwise-localized English/Arabic/French/Spanish UI.

String floorLabel(String value, AppLocalizations l10n) {
  switch (value) {
    case 'מרתף':
      return l10n.addPropertyScreenFloorBasement;
    case 'קרקע':
      return l10n.addPropertyScreenFloorGround;
    default:
      return value;
  }
}

String conditionLabel(String value, AppLocalizations l10n) {
  switch (value) {
    case 'חדש מקבלן':
      return l10n.addPropertyScreenConditionNew;
    case 'משופץ':
      return l10n.addPropertyScreenConditionRenovated;
    case 'תקין':
      return l10n.addPropertyScreenConditionGood;
    case 'ישן':
      return l10n.addPropertyScreenConditionOld;
    default:
      return value;
  }
}

String propertyTypeLabel(String value, AppLocalizations l10n) {
  switch (value) {
    case 'דירה':
      return l10n.addPropertyScreenTypeApartment;
    case 'דירת גג':
      return l10n.addPropertyScreenTypePenthouse;
    case 'דירת גן':
      return l10n.addPropertyScreenTypeGardenApartment;
    case 'סטודיו':
      return l10n.addPropertyScreenTypeStudio;
    case 'קוטג׳':
      return l10n.addPropertyScreenTypeCottage;
    case 'בית פרטי':
      return l10n.addPropertyScreenTypePrivateHouse;
    case 'משרד':
      return l10n.addPropertyScreenTypeOffice;
    default:
      return value;
  }
}
