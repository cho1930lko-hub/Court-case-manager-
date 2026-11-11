import 'package:flutter_test/flutter_test.dart';
import 'package:court_case_manager/services/summon_generator_service.dart';

void main() {
  group('SummonGeneratorService', () {
    test('only includes cases marked बनाना है', () {
      final rows = [
        {'st_no': '001', 'summons_status': 'बनाना है'},
        {'st_no': '002', 'summons_status': 'ISSUED'},
        {'st_no': '003', 'summons_status': ' NOT ISSUED '},
      ];
      expect(
        SummonGeneratorService.pendingCases(rows).map((e) => e['st_no']),
        ['001'],
      );
    });

    test('detects NBW before BW and recognizes all original types', () {
      expect(SummonGeneratorService.detectType('NBW रामलाल'), 'NBW');
      expect(SummonGeneratorService.detectType('BW रामलाल'), 'BW');
      expect(SummonGeneratorService.detectType('MRITYU अभियुक्त'), 'MRITYU');
      expect(SummonGeneratorService.detectType('रामलाल'), 'SAMAN');
    });

    test('splits comma-separated witnesses and groups by original order', () {
      final result = SummonGeneratorService.generate(
        [
          {
            'st_no': '10',
            'fir_no': '12/2024',
            'sections': '323',
            'accused_name': 'राज्य बनाम राम',
            'court_name': 'ASJ EX POCSO',
            'next_hearing': '2026-11-20',
            'summoned_witnesses': 'BW गवाह तीन, गवाह चार',
          },
          {
            'st_no': '2',
            'fir_no': '13/2024',
            'sections': '302',
            'accused_name': 'राज्य बनाम श्याम',
            'court_name': 'CJM',
            'next_hearing': '20/11/2026',
            'summoned_witnesses': 'गवाह एक',
          },
          {
            'st_no': '3',
            'fir_no': '14/2024',
            'sections': '304',
            'accused_name': 'राज्य बनाम मोहन',
            'court_name': 'DJ',
            'next_hearing': '20-11-2026',
            'summoned_witnesses': 'NBW गवाह पांच',
          },
        ],
        janpad: 'श्रावस्ती',
        generatedAt: DateTime(2026, 11, 11),
      );

      expect(result.witnessCount, 4);
      expect(result.stNos, ['10', '2', '3']);
      final html = result.html!;
      expect(html.indexOf('गवाह एक'), lessThan(html.indexOf('गवाह तीन')));
      expect(html.indexOf('गवाह तीन'), lessThan(html.indexOf('गवाह पांच')));
      expect(html, contains('A4 landscape'));
      expect(html, contains('अपर सत्र न्यायाधीश (POCSO)'));
      expect(html, contains('20/11/2026'));
      expect(RegExp(r'class="page"').allMatches(html).length, 2);
    });

    test('escapes user-controlled case data before inserting into HTML', () {
      final result = SummonGeneratorService.generate(
        [
          {
            'st_no': '5',
            'fir_no': '1/2026',
            'sections': '<script>alert(1)</script>',
            'accused_name': 'राम & श्याम',
            'court_name': 'CJM',
            'next_hearing': '21/11/2026',
            'summoned_witnesses': 'गवाह <img src=x>',
          },
        ],
        janpad: 'श्रावस्ती',
        generatedAt: DateTime(2026, 11, 11),
      );
      expect(result.html, contains('राम &amp; श्याम'));
      expect(result.html, contains('&lt;script&gt;'));
      expect(result.html, contains('&lt;img src=x&gt;'));
      expect(result.html, isNot(contains('<script>alert(1)</script>')));
    });

    test('returns no HTML when every row has an empty witness field', () {
      final result = SummonGeneratorService.generate(
        [
          {'st_no': '9', 'summoned_witnesses': ''},
        ],
        janpad: 'श्रावस्ती',
        generatedAt: DateTime(2026, 11, 11),
      );
      expect(result.html, isNull);
      expect(result.stNos, isEmpty);
      expect(result.skippedStNos, ['9']);
    });
  });
}
