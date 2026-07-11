// Hard, critical review of the nearby-section ORDERING ("what shows first") across
// 30 diverse + adversarial personas. Prints the ordered sections for human
// judgement — this is an eval harness, not a pass/fail suite.
import 'package:dating_app/core/search/nearby_relevance.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String order(String q) {
    final secs = relevantNearbySections(NearbyProfile.fromText(q));
    return secs.take(5).map((s) => '${s.kind.name}(${s.priority})').join('  ');
  }

  void show(int i, String label, String q) =>
      print('${i.toString().padLeft(2)}. $label\n    "$q"\n    → ${order(q)}\n');

  test('30 nearby-ordering use-cases — print for critical review', () {
    show(1, 'family + toddler', 'משפחה עם פעוט מחפשים דירה');
    show(2, 'family + teens', 'משפחה עם ילדים בתיכון');
    show(3, 'family generic (kids)', 'משפחה עם ילדים');
    show(4, 'couple WITH a child (the bug)', 'זוג עם ילד בהרצליה תקציב מוגבל');
    show(5, 'couple, no kids', 'זוג צעיר בלי ילדים');
    show(6, 'single young', 'רווק צעיר מחפש דירה במרכז');
    show(7, 'roommates', 'שלושה שותפים סטודנטים');
    show(8, 'student near campus', 'סטודנט ליד האוניברסיטה');
    show(9, 'elderly couple, quiet', 'זוג מבוגר מחפש שקט');
    show(10, 'religious family', 'משפחה דתית שומרת שבת עם ילדים');
    show(11, 'secular family (no shuls)', 'משפחה חילונית עם ילדים');
    show(12, 'dog owner', 'יש לי כלב גדול מחפש דירה');
    show(13, 'WFH freelancer', 'עובד מהבית פרילנסר צריך חדר עבודה');
    show(14, 'specific HMO (כללית)', 'חשוב לי קופת חולים כללית קרוב');
    show(15, 'wheelchair accessibility', 'דירה נגישה לכיסא גלגלים בלי מדרגות');
    show(16, 'foodie / dining explicit', 'אוהב מסעדות ובתי קפה ואוכל טוב');
    show(17, 'nightlife seeker', 'אוהב לצאת בלילה לברים ומועדונים');
    show(18, 'culture lover', 'אוהב תיאטרון מוזיאונים וקולנוע');
    show(19, 'fitness / active', 'ספורטיבי צריך חדר כושר ובריכה');
    show(20, 'car owner (parking)', 'יש לי רכב חייב חניה');
    show(21, 'car-free / transit', 'אין לי רכב צריך תחבורה ציבורית ורכבת');
    show(22, 'budget-tight', 'תקציב נמוך מחפש משהו זול');
    show(23, 'luxury', 'דירת יוקרה פנטהאוז מפואר');
    show(24, 'muslim (mosque)', 'משפחה מוסלמית קרוב למסגד');
    show(25, 'christian (church)', 'קרוב לכנסייה');
    show(26, 'young vibrant area', 'אזור צעיר תוסס והיפסטרי');
    show(27, 'groceries / errands', 'חשוב סופר ומכולת קרובים לקניות');
    show(28, 'green / parks', 'אוהב פארקים והרבה ירוק וטבע');
    // ── adversarial / combos ──
    show(29, 'ADV: elderly religious + visiting grandkid', 'זוג מבוגר דתי עם נכד שמבקר');
    show(30, 'ADV: secular family + dog + teens', 'משפחה חילונית עם כלב וילדים בתיכון');
    expect(true, true);
  });
}
