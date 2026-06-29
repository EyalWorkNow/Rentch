import 'dart:math' as math;

import 'package:dating_app/core/services/signature_service.dart';

enum ContractStatus { draft, sent, signed, declined, cancelled }

/// Maximum a CASH-cost security (cash deposit / bank guarantee / a deposited
/// security check) may legally be under Israel's 2017 חוק שכירות הוגנת: the
/// LOWER of one-third of the total lease-term rent OR three months' rent.
/// A pure function — no I/O, safe to call from UI on every keystroke.
int maxLegalDepositNis({required int monthlyRent, required int termMonths}) {
  if (monthlyRent <= 0 || termMonths <= 0) return 0;
  final thirdOfTerm = (monthlyRent * termMonths / 3).floor();
  final threeMonths = monthlyRent * 3;
  return math.min(thirdOfTerm, threeMonths);
}

/// Result of checking an entered deposit against the legal cap.
class DepositLegality {
  const DepositLegality({
    required this.ok,
    required this.cap,
    required this.message,
  });

  /// True when the deposit is within the cap (or can't be evaluated yet).
  final bool ok;

  /// The legal cap in ₪ for the given rent/term (0 if not computable).
  final int cap;

  /// Hebrew warning to show when [ok] is false; empty otherwise.
  final String message;
}

/// Non-blocking legality check for a cash-cost security deposit. When the
/// deposit exceeds [maxLegalDepositNis] it returns ok=false plus a Hebrew note
/// the form can surface inline.
DepositLegality depositLegality(int deposit, int monthlyRent, int termMonths) {
  final cap = maxLegalDepositNis(monthlyRent: monthlyRent, termMonths: termMonths);
  if (cap <= 0 || deposit <= cap) {
    return DepositLegality(ok: true, cap: cap, message: '');
  }
  return DepositLegality(
    ok: false,
    cap: cap,
    message:
        'לפי חוק שכירות הוגנת, פיקדון במזומן/ערבות מוגבל ל-₪$cap '
        '(השווה לנמוך מבין ⅓ מתקופת השכירות או 3 חודשי שכירות). מומלץ להוריד.',
  );
}

/// Which body of legal text backs a contract before it is sent.
///   • [standard] — the boilerplate residential lease "מטעם עורכי הדין של Rently".
///   • [aiTailored] — that text after the paid AI-improve pass tailored it to the
///     specific property/match.
enum ContractTemplateKind { standard, aiTailored }

/// The standard residential-lease text the app offers, "מטעם עורכי הדין של
/// Rently". It is intentionally a reasonable, plain-Hebrew template — NOT legal
/// advice — and always carries the disclaimer below. Placeholders in {{...}} are
/// filled from the property/match data via [StandardLeaseTemplate.fill].
class StandardLeaseTemplate {
  const StandardLeaseTemplate._();

  /// Shown next to the template everywhere it appears. Required by design so a
  /// user never mistakes the boilerplate for vetted legal counsel.
  static const String disclaimer =
      'מסמך זה הוא תבנית כללית מטעם עורכי הדין של Rently ואינו תחליף לייעוץ '
      'משפטי. מומלץ להיוועץ בעורך/ת דין לפני חתימה.';

  static const String credit = 'מטעם עורכי הדין של Rently';

  /// Builds the additional-terms body for a standard lease, auto-filled from the
  /// supplied facts. Kept deterministic so it hashes cleanly into the signature.
  static String fill({
    required String landlordName,
    required String tenantName,
    required String propertyTitle,
    required int monthlyRent,
    required int deposit,
    required int durationMonths,
    required DateTime startDate,
    required DateTime endDate,
  }) {
    String money(int v) => '$v ש"ח';
    String d(DateTime x) =>
        '${x.day.toString().padLeft(2, '0')}/${x.month.toString().padLeft(2, '0')}/${x.year}';
    final landlord = landlordName.trim().isNotEmpty ? landlordName.trim() : 'המשכיר';
    final tenant = tenantName.trim().isNotEmpty ? tenantName.trim() : 'השוכר';
    final property =
        propertyTitle.trim().isNotEmpty ? propertyTitle.trim() : 'הנכס נשוא ההסכם';

    final security = deposit > 0 ? money(deposit) : '10,000 ש"ח';
    // The real standard residential lease the user supplied (חוזה-שכירות.pdf),
    // transcribed faithfully with the facts we already collect injected; the few
    // fields we don't hold (ת.ז., מס' חדרים, תקופת אופציה, שם בית הדין) stay as
    // fill-in lines the parties complete at signing. Deterministic → hashes
    // cleanly into the Ed25519 signature like the old template.
    return '''
הסכם שכירות דירה — $credit

נערך ונחתם ביום ____ בחודש ____ שנת ____.
בין: $landlord, ת.ז. __________ ("המשכיר") — מצד אחד;
לבין: $tenant, ת.ז. __________ ("השוכר") — מצד שני.

הואיל והמשכיר הינו הבעלים ו/או בעל זכות החזקה הייחודית בדירה שברחוב $property ("הדירה");
והואיל והדירה תהיה פנויה למגורים החל מיום ${d(startDate)};
והואיל והשוכר מצהיר כי לא שילם דמי מפתח וכי השכירות אינה מוגנת לפי חוק הגנת הדייר;
לפיכך הוסכם והותנה בין הצדדים כדלקמן:

1. המבוא להסכם זה מהווה חלק בלתי נפרד הימנו ותנאי מתנאיו.

2. המשכיר משכיר והשוכר שוכר את הדירה למגורים בלבד, לתקופה של $durationMonths חודשים, החל מיום ${d(startDate)} וכלה ביום ${d(endDate)} ("התקופה הקצובה").

3. לשוכר אופציה להארכת השכירות בתקופה נוספת של ____ חודשים, בתנאי שהודיע על מימושה 3 חודשים לפני תום התקופה הקצובה, עמד בכל התחייבויותיו ומסר שיקים מראש לכל תקופת האופציה.

4. דמי השכירות:
   א. עבור התקופה הקצובה ישלם השוכר דמי שכירות חודשיים בסך ${money(monthlyRent)}, אשר ישולמו מראש.
   ב. התשלום ייעשה באמצעות שיקים שיימסרו למשכיר במעמד חתימת ההסכם.
   ג. חל יום התשלום בשבת/חג — ישולם ביום שלמחרת.
   ד. איחור העולה על 7 ימים בתשלום מהווה הפרה יסודית, המזכה את המשכיר בביטול ההסכם ובדרישת פינוי לאלתר, מבלי לגרוע מכל סעד אחר.
   ה. כל איחור בתשלום יישא ריבית פיגורים בשיעור 2% לחודש (או חלק יחסי מכך).
   ו. בתקופת האופציה יעלו דמי השכירות ב-5% או בהתאם לעליית מדד השכירות מיום החתימה, הגבוה מביניהם.

5. השוכר יישא בכל תשלומי המים, החשמל, הגז וועד הבית לתקופת שכירותו, ישמור את הקבלות ויעבירן למשכיר לפי דרישה.

6. השוכר יישא בתשלומי הארנונה החלים על הדירה ויעביר את הרישום ברשות על שמו.

7. השוכר אינו רשאי להעביר זכויותיו על פי הסכם זה ו/או להשכיר את הדירה בשכירות משנה, כולה או חלקה, ללא הסכמת המשכיר בכתב.

8. פינוי לפני תום התקופה אינו פוטר את השוכר מתשלום דמי השכירות עד תומה; ואולם, מצא השוכר דייר חלופי לשביעות רצון המשכיר אשר יקבל על עצמו את מלוא ההתחייבויות שבהסכם — יהא רשאי להפסיק את השכירות.

9. השוכר ישמור על הדירה ויתקן על חשבונו כל פגם או נזק שנגרם משימושו (למעט בלאי סביר ורגיל). המשכיר יתקן תוך זמן סביר ליקויים מהותיים שבאחריותו (נזילות, מערכת חשמל מרכזית וכיו"ב); לא תוקן ליקוי דחוף תוך 48 שעות — רשאי השוכר לתקנו ולקזז את עלותו, כנגד קבלות, מדמי השכירות.

10. השוכר יפנה את הדירה בתום התקופה הקצובה ויחזיר את החזקה הבלעדית בה לידי המשכיר או בא-כוחו.

11. השוכר מצהיר כי ראה ובדק את הדירה ומצאה במצב טוב, תקין ומתאים לדרישותיו, ומוותר על כל טענת אי-התאמה או טענה בגין פגם/מום גלוי או נסתר.

12. השוכר ישמור על ניקיון הדירה וסביבתה, על השקט ועל יחסי שכנות טובים.

13. השוכר לא יבצע כל שינוי בדירה או בסביבתה ללא הסכמת המשכיר בכתב.

14. השוכר יאפשר למשכיר או לבא-כוחו להיכנס לדירה, בתיאום מראש, לצורך פיקוח, ביצוע תיקונים או הצגת הדירה בפני אחרים.

15. כל שינוי שיבוצע בדירה (בהסכמה או שלא בהסכמה) יהיה לרכוש המשכיר, והשוכר לא יהיה זכאי להחזר הוצאותיו בגינו.

16. לא פינה השוכר את הדירה במועד — ישלם למשכיר 200 ש"ח לכל יום של פיגור בפינוי, מבלי לגרוע מכל סעד אחר.

17. בתום השכירות יפנה השוכר כל חפץ שאינו בבעלות המשכיר; חפצים שיותרו בדירה — רשאי המשכיר לנהוג בהם כרצונו, ללא הודעה.

18. לא קיים השוכר תנאי מתנאי הסכם זה — רשאי המשכיר לתבוע פיצויים, לבטל את ההסכם ולדרוש פינוי מיידי של הדירה.

19. בטחונות: במעמד החתימה ימסור השוכר שני שיקי ביטחון פתוחים (מוגבלים לסך $security) וכן יחתמו בפניו שני ערבים-קבלנים, להבטחת מלוא התחייבויותיו. השיקים יוחזרו לאחר פינוי הדירה ולאחר שיוודא המשכיר כי לא נותר חוב.

20. לא עמד השוכר בתשלום חוב כלשהו — רשאי המשכיר להפקיד שיק לגביית החוב; חזר השיק — יישא השוכר בעמלת ההחזרה ובהוצאות הגבייה.

21. חובת ההוכחה לכל תשלום, ויתור או רשות לפי הסכם זה — על השוכר.

22. כל פרט שיש בו חשש ריבית יחול לפי היתר עיסקא נוסח "ברית פנחס".

23. כל סכסוך הנובע מהסכם זה יידון בפני בית הדין ____________; חתימה על הסכם זה כמוה כחתימה על שטר בוררות כנהוג באותו בית דין.

24. הצדדים מאשרים כי קיבלו בקניין סודר בפני בית דין חשוב להתחייב בכל האמור בהסכם זה, בתנאי ב"ג וב"ר.

ולראיה באו הצדדים על החתום:
המשכיר: $landlord ______________      השוכר: $tenant ______________
ערבים-קבלנים לכל התחייבויות השוכר: 1. ______________   2. ______________

* $disclaimer''';
  }
}

ContractStatus contractStatusFromString(String? raw) {
  switch ((raw ?? '').toLowerCase()) {
    case 'sent':
      return ContractStatus.sent;
    case 'signed':
      return ContractStatus.signed;
    case 'declined':
      return ContractStatus.declined;
    case 'cancelled':
      return ContractStatus.cancelled;
    default:
      return ContractStatus.draft;
  }
}

/// One party's cryptographic signature over the contract's content hash, plus
/// the optional handwritten signature image they drew.
class ContractSignature {
  const ContractSignature({
    required this.role, // 'landlord' | 'tenant'
    required this.signerUserId,
    required this.signerName,
    required this.publicKey,
    required this.signature,
    required this.signedHash,
    this.signatureImageUrl = '',
    this.signedAt,
  });

  final String role;
  final String signerUserId;
  final String signerName;
  final String publicKey; // base64 Ed25519 public key
  final String signature; // base64 Ed25519 signature over signedHash
  final String signedHash; // base64 SHA-256 of the canonical content at signing
  final String signatureImageUrl;
  final DateTime? signedAt;

  factory ContractSignature.fromJson(Map<String, dynamic> json) {
    return ContractSignature(
      role: json['role']?.toString() ?? '',
      signerUserId: json['signerUserId']?.toString() ?? '',
      signerName: json['signerName']?.toString() ?? '',
      publicKey: json['publicKey']?.toString() ?? '',
      signature: json['signature']?.toString() ?? '',
      signedHash: json['signedHash']?.toString() ?? '',
      signatureImageUrl: json['signatureImageUrl']?.toString() ?? '',
      signedAt: DateTime.tryParse(json['signedAt']?.toString() ?? ''),
    );
  }

  Map<String, dynamic> toJson() => {
        'role': role,
        'signerUserId': signerUserId,
        'signerName': signerName,
        'publicKey': publicKey,
        'signature': signature,
        'signedHash': signedHash,
        'signatureImageUrl': signatureImageUrl,
        'signedAt': (signedAt ?? DateTime.now().toUtc()).toIso8601String(),
      };
}

/// A rental agreement between a landlord and a tenant, signed end-to-end with
/// device-held keys. The binding terms are hashed into [contentHash]; both
/// parties sign that hash so the agreement is tamper-evident.
class RentalContract {
  const RentalContract({
    required this.id,
    required this.matchId,
    required this.propertyId,
    required this.propertyTitle,
    required this.landlordUserId,
    required this.landlordName,
    required this.tenantUserId,
    required this.tenantName,
    required this.monthlyRent,
    required this.deposit,
    required this.durationMonths,
    required this.startDate,
    required this.additionalTerms,
    required this.status,
    this.landlordSignature,
    this.tenantSignature,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String matchId;
  final String propertyId;
  final String propertyTitle;
  final String landlordUserId;
  final String landlordName;
  final String tenantUserId;
  final String tenantName;
  final int monthlyRent;
  final int deposit;
  final int durationMonths;
  final DateTime startDate;
  final String additionalTerms;
  final ContractStatus status;
  final ContractSignature? landlordSignature;
  final ContractSignature? tenantSignature;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  DateTime get endDate =>
      DateTime(startDate.year, startDate.month + durationMonths, startDate.day);

  bool get isLandlordSigned => landlordSignature != null;
  bool get isTenantSigned => tenantSignature != null;
  bool get isFullySigned => isLandlordSigned && isTenantSigned;

  ContractSignature? signatureForRole(String role) =>
      role == 'landlord' ? landlordSignature : tenantSignature;

  /// Deterministic, human-readable representation of the binding terms. Both
  /// devices hash exactly this string, so signatures are reproducible and any
  /// later change to a term changes the hash (invalidating prior signatures).
  String get canonicalContent {
    final b = StringBuffer()
      ..writeln('RENTLY RENTAL AGREEMENT')
      ..writeln('contractId=$id')
      ..writeln('property=$propertyId|$propertyTitle')
      ..writeln('landlord=$landlordUserId|$landlordName')
      ..writeln('tenant=$tenantUserId|$tenantName')
      ..writeln('monthlyRent=$monthlyRent')
      ..writeln('deposit=$deposit')
      ..writeln('durationMonths=$durationMonths')
      ..writeln('startDate=${startDate.toIso8601String().split('T').first}')
      ..writeln('endDate=${endDate.toIso8601String().split('T').first}')
      ..writeln('terms=${additionalTerms.trim()}');
    return b.toString();
  }

  String get contentHash => SignatureService.contentHash(canonicalContent);

  RentalContract copyWith({
    ContractStatus? status,
    ContractSignature? landlordSignature,
    ContractSignature? tenantSignature,
    DateTime? updatedAt,
  }) {
    return RentalContract(
      id: id,
      matchId: matchId,
      propertyId: propertyId,
      propertyTitle: propertyTitle,
      landlordUserId: landlordUserId,
      landlordName: landlordName,
      tenantUserId: tenantUserId,
      tenantName: tenantName,
      monthlyRent: monthlyRent,
      deposit: deposit,
      durationMonths: durationMonths,
      startDate: startDate,
      additionalTerms: additionalTerms,
      status: status ?? this.status,
      landlordSignature: landlordSignature ?? this.landlordSignature,
      tenantSignature: tenantSignature ?? this.tenantSignature,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory RentalContract.fromJson(Map<String, dynamic> json) {
    ContractSignature? sig(Object? v) {
      if (v is Map) return ContractSignature.fromJson(Map<String, dynamic>.from(v));
      return null;
    }

    return RentalContract(
      id: json['id']?.toString() ?? '',
      matchId: json['matchId']?.toString() ?? '',
      propertyId: json['propertyId']?.toString() ?? '',
      propertyTitle: json['propertyTitle']?.toString() ?? '',
      landlordUserId: json['landlordUserId']?.toString() ?? '',
      landlordName: json['landlordName']?.toString() ?? '',
      tenantUserId: json['tenantUserId']?.toString() ?? '',
      tenantName: json['tenantName']?.toString() ?? '',
      monthlyRent: (json['monthlyRent'] as num?)?.toInt() ?? 0,
      deposit: (json['deposit'] as num?)?.toInt() ?? 0,
      durationMonths: (json['durationMonths'] as num?)?.toInt() ?? 12,
      startDate: DateTime.tryParse(json['startDate']?.toString() ?? '') ??
          DateTime.now(),
      additionalTerms: json['additionalTerms']?.toString() ?? '',
      status: contractStatusFromString(json['status']?.toString()),
      landlordSignature: sig(json['landlordSignature']),
      tenantSignature: sig(json['tenantSignature']),
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? ''),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'matchId': matchId,
        'propertyId': propertyId,
        'propertyTitle': propertyTitle,
        'landlordUserId': landlordUserId,
        'landlordName': landlordName,
        'tenantUserId': tenantUserId,
        'tenantName': tenantName,
        'monthlyRent': monthlyRent,
        'deposit': deposit,
        'durationMonths': durationMonths,
        'startDate': startDate.toIso8601String(),
        'additionalTerms': additionalTerms,
        'status': status.name,
        if (landlordSignature != null)
          'landlordSignature': landlordSignature!.toJson(),
        if (tenantSignature != null)
          'tenantSignature': tenantSignature!.toJson(),
        'contentHash': contentHash,
        'createdAt': (createdAt ?? DateTime.now().toUtc()).toIso8601String(),
        'updatedAt': (updatedAt ?? DateTime.now().toUtc()).toIso8601String(),
      };
}
