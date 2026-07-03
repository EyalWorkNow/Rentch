import 'package:dating_app/core/search/lifestyle_knowledge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('detectReligiosity', () {
    test('reads the four levels', () {
      expect(LifestyleKnowledge.detectReligiosity('אני חילוני'),
          Religiosity.secular);
      expect(LifestyleKnowledge.detectReligiosity('משפחה מסורתית'),
          Religiosity.traditional);
      expect(LifestyleKnowledge.detectReligiosity('אנחנו דתיים לאומיים'),
          Religiosity.religious);
      expect(LifestyleKnowledge.detectReligiosity('בחור חרדי ליטאי'),
          Religiosity.haredi);
    });

    test('"שומר שבת" counts as religious', () {
      expect(LifestyleKnowledge.detectReligiosity('אנחנו שומרי שבת'),
          Religiosity.religious);
    });

    test('negation "לא דתי" is secular, not religious', () {
      expect(LifestyleKnowledge.detectReligiosity('אני לא דתי'),
          Religiosity.secular);
    });

    test('null when nothing is stated', () {
      expect(LifestyleKnowledge.detectReligiosity('3 חדרים בתל אביב עד 6000'),
          isNull);
    });
  });

  group('areaCharacter', () {
    test('known towns/neighbourhoods classified', () {
      expect(LifestyleKnowledge.areaCharacter(neighborhood: '', city: 'בני ברק'),
          AreaChar.haredi);
      expect(LifestyleKnowledge.areaCharacter(neighborhood: '', city: 'אפרת'),
          AreaChar.religious);
      expect(
          LifestyleKnowledge.areaCharacter(
              neighborhood: 'פלורנטין', city: 'תל אביב'),
          AreaChar.secular);
    });

    test('unknown area → null (neutral)', () {
      expect(
          LifestyleKnowledge.areaCharacter(neighborhood: '', city: 'עיר דמיונית'),
          isNull);
    });
  });

  group('religiosityFit', () {
    test('same character is the best fit; opposite is worst', () {
      // Haredi tenant strongly prefers a haredi area, strongly rejects secular.
      expect(
          LifestyleKnowledge.religiosityFit(
              Religiosity.haredi, AreaChar.haredi),
          greaterThan(LifestyleKnowledge.religiosityFit(
              Religiosity.haredi, AreaChar.secular)));
      // Secular tenant prefers secular over haredi.
      expect(
          LifestyleKnowledge.religiosityFit(
              Religiosity.secular, AreaChar.secular),
          greaterThan(LifestyleKnowledge.religiosityFit(
              Religiosity.secular, AreaChar.haredi)));
    });
  });
}
