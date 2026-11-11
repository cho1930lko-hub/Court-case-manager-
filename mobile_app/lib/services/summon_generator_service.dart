import 'package:intl/intl.dart';

/// Ports the original Streamlit summon_gen.py rules to the offline Flutter app.
/// The source rows are local cases-table records; this service never mutates them.
class SummonGenerationResult {
  const SummonGenerationResult({
    required this.html,
    required this.stNos,
    required this.witnessCount,
    required this.skippedStNos,
  });

  final String? html;
  final List<String> stNos;
  final int witnessCount;
  final List<String> skippedStNos;
}

class SummonGeneratorService {
  SummonGeneratorService._();

  static const Map<String, String> titles = {
    'SAMAN': 'समन साक्षी',
    'BW': 'जमानती वारंट (BW) साक्षी',
    'NBW': 'गैर जमानती वारंट (NBW) साक्षी',
    'MRITYU': 'मृत्यु आख्या',
  };

  static const Map<String, String> bodies = {
    'SAMAN': 'साक्षी मुकदमा उपरोक्त के संबंध में अपना साक्ष्य देने के लिए अपने पहचान पत्र / आधार कार्ड व एक पासपोर्ट साइज फोटो के साथ उपर्युक्त नियत तारीख पेशी पर सुबह 10:30 बजे उपस्थित होना सुनिश्चित करें। ऐसा करने में कोई त्रुटि न हो।',
    'BW': 'उपरोक्त साक्षी से 5-5 हजार की दो जमानतें तथा इतनी ही धनराशि का बंधपत्र न्यायालय में साक्ष्य हेतु उपस्थित होने के बाबत दाखिल कराएं। ऐसा ना करने पर उपर्युक्त साक्षी को गिरफ्तार कर नियत पेशी पर इस न्यायालय पर प्रस्तुत करें।',
    'NBW': 'उपरोक्त साक्षी को नियत तारीख पेशी से पूर्व या तक गिरफ्तार कर मेरे समक्ष पेश करें।',
    'MRITYU': 'एतद् द्वारा आदेशित किया जाता है कि उपर्युक्त अभियुक्त की मृत्यु से संबंधित प्रमाण-पत्र नियत तिथि पर न्यायालय के समक्ष अनिवार्य रूप से प्रस्तुत किया जाए।',
  };

  static const Map<String, (String, bool)> _courts = {
    'ASJ EX POCSO': ('अपर सत्र न्यायाधीश (POCSO)', true),
    'ASJ SC/ST ACT': ('अपर सत्र न्यायाधीश SC/ST', true),
    'ASJ SCST': ('अपर सत्र न्यायाधीश SC/ST', true),
    'SPL पॉक्सो': ('विशेष न्यायालय POCSO', true),
    'SC/ST': ('विशेष न्यायालय SC/ST', true),
    'ASJ': ('अपर सत्र न्यायाधीश', true),
    'DJ': ('जिला एवं सत्र न्यायाधीश', true),
    'जिला एवं सत्र': ('जिला एवं सत्र न्यायाधीश', true),
    'CJM': ('मुख्य न्यायिक मजिस्ट्रेट', false),
    'CJSD': ('मुख्य न्यायिक मजिस्ट्रेट', false),
    'ACJM': ('अपर मुख्य न्यायिक मजिस्ट्रेट', false),
  };

  static List<Map<String, Object?>> pendingCases(
    List<Map<String, Object?>> cases,
  ) {
    return cases.where((row) {
      return (row['summons_status'] ?? '').toString().trim() == 'बनाना है';
    }).toList();
  }

  static String detectType(String witnessField) {
    final value = witnessField.trim();
    if (RegExp(r'^NBW', caseSensitive: false).hasMatch(value)) return 'NBW';
    if (RegExp(r'^BW', caseSensitive: false).hasMatch(value)) return 'BW';
    if (RegExp(r'^MRITYU', caseSensitive: false).hasMatch(value)) return 'MRITYU';
    return 'SAMAN';
  }

  static String cleanPrefix(String value) {
    return value.replaceFirst(
      RegExp(r'^\s*(BW|NBW|MRITYU)\s*', caseSensitive: false),
      '',
    ).trim();
  }

  static DateTime? parseDate(String value) {
    final text = value.trim();
    if (text.isEmpty) return null;
    for (final pattern in ['dd/MM/yyyy', 'dd-MM-yyyy', 'yyyy-MM-dd']) {
      try {
        return DateFormat(pattern).parseStrict(text);
      } catch (_) {
        // Try the next supported legacy format.
      }
    }
    final isoPart = text.split(RegExp(r'[T ]')).first;
    try {
      return DateTime.parse(isoPart);
    } catch (_) {
      return null;
    }
  }

  static String formatDate(Object? value) {
    if (value == null) return '';
    final raw = value.toString().trim();
    final parsed = parseDate(raw);
    return parsed == null ? raw : DateFormat('dd/MM/yyyy').format(parsed);
  }

  static String _escape(Object? value) {
    return (value ?? '').toString()
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
  }

  static (String, String, bool) resolveCourt(String raw, String janpad) {
    final value = raw.trim();
    final upper = value.toUpperCase();
    for (final entry in _courts.entries) {
      if (upper.contains(entry.key.toUpperCase())) {
        final name = entry.value.$1;
        return (name, '$name जनपद $janpad', entry.value.$2);
      }
    }
    return (value, '$value जनपद $janpad', false);
  }

  static SummonGenerationResult generate(
    List<Map<String, Object?>> rows, {
    required String janpad,
    DateTime? generatedAt,
  }) {
    final grouped = <String, List<String>>{
      'SAMAN': [],
      'BW': [],
      'NBW': [],
      'MRITYU': [],
    };
    final stNos = <String>{};
    final skipped = <String>[];
    var witnessCount = 0;

    for (final row in rows) {
      final field = (row['summoned_witnesses'] ?? '').toString().trim();
      final stNo = (row['st_no'] ?? '').toString().trim();
      if (field.isEmpty) {
        if (stNo.isNotEmpty) skipped.add(stNo);
        continue;
      }
      final type = detectType(field);
      final names = cleanPrefix(field)
          .split(',')
          .map((name) => name.trim())
          .where((name) => name.isNotEmpty)
          .toList();
      if (names.isEmpty) {
        if (stNo.isNotEmpty) skipped.add(stNo);
        continue;
      }
      stNos.add(stNo);
      for (final name in names) {
        final court = resolveCourt(
          (row['court_name'] ?? '').toString(),
          janpad,
        );
        grouped[type]!.add(_blockHtml(
          row: row,
          type: type,
          witness: name,
          janpad: janpad,
          courtName: court.$1,
          courtDisplay: court.$2,
          isSessionCourt: court.$3,
          today: DateFormat('dd/MM/yyyy').format(generatedAt ?? DateTime.now()),
        ));
        witnessCount++;
      }
    }

    if (witnessCount == 0) {
      return SummonGenerationResult(
        html: null,
        stNos: const [],
        witnessCount: 0,
        skippedStNos: skipped,
      );
    }

    final allBlocks = [
      ...grouped['SAMAN']!,
      ...grouped['BW']!,
      ...grouped['NBW']!,
      ...grouped['MRITYU']!,
    ];
    final pages = <String>[];
    for (var index = 0; index < allBlocks.length; index += 2) {
      final first = allBlocks[index];
      final second = index + 1 < allBlocks.length
          ? allBlocks[index + 1]
          : '<div class="block empty"></div>';
      pages.add('<section class="page">$first$second</section>');
    }

    final today = DateFormat('dd/MM/yyyy').format(generatedAt ?? DateTime.now());
    final html = _documentHtml(
      pages.join('\n'),
      janpad: janpad,
      today: today,
    );
    final orderedStNos = stNos.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return SummonGenerationResult(
      html: html,
      stNos: orderedStNos,
      witnessCount: witnessCount,
      skippedStNos: skipped,
    );
  }

  static String _blockHtml({
    required Map<String, Object?> row,
    required String type,
    required String witness,
    required String janpad,
    required String courtName,
    required String courtDisplay,
    required bool isSessionCourt,
    required String today,
  }) {
    final stNo = _escape(row['st_no']);
    final firNo = _escape(row['fir_no']);
    final accused = _escape(row['accused_name']);
    final sections = _escape(row['sections']);
    final hearing = _escape(formatDate(row['next_hearing']));
    final courtClass = isSessionCourt ? 'block-court session' : 'block-court';
    final label = type == 'MRITYU' ? 'नाम पता अभियुक्त:' : 'नाम पता साक्षी:';
    final note = type == 'MRITYU'
        ? ''
        : '<div class="note">नोट:- तामीलकर्ता साक्षी का मोबाइल नंबर अवश्य अंकित करें।</div>';

    return '''
<div class="block">
  <div class="block-title">${titles[type]}</div>
  <div class="$courtClass">न्यायालय : ${_escape(courtDisplay)}</div>
  <table class="info">
    <tr><td class="label">राज्य बनाम</td><td>$accused</td></tr>
    <tr><td class="label">ST NO / मु0न0</td><td>$stNo</td></tr>
    <tr><td class="label">मु0अ0स0</td><td>$firNo</td></tr>
    <tr><td class="label">धारा</td><td>$sections</td></tr>
    <tr><td class="label">जनपद</td><td>${_escape(janpad)}</td></tr>
    <tr><td class="label">तारीख पेशी</td><td><strong>$hearing</strong></td></tr>
  </table>
  <div class="witness-label">$label</div>
  <div class="witness-name">${_escape(witness)}</div>
  <div class="body-text">${bodies[type]}</div>
  $note
  <div class="sign">
    <span class="sign-space"></span>
    <div class="sign-lines">
      <div>${_escape(courtName)}</div>
      <div>जनपद ${_escape(janpad)}</div>
      <div>$today</div>
    </div>
  </div>
</div>
''';
  }

  static String _documentHtml(
    String pages, {
    required String janpad,
    required String today,
  }) {
    return '''
<!DOCTYPE html>
<html lang="hi">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>समन दस्तावेज़ - $today</title>
<style>
* { box-sizing: border-box; }
html, body { margin: 0; padding: 0; background: #fff; }
body { font-family: "Noto Sans Devanagari", "Nirmala UI", "Mangal", sans-serif; color: #111; font-size: 11pt; }
@page { size: A4 landscape; margin: 8mm 7mm; }
.page {
  width: 277mm; height: 190mm; margin: 0 auto;
  display: grid; grid-template-columns: 1fr 1fr;
  border: 1px solid #aaa; overflow: hidden;
  page-break-after: always; break-after: page;
}
.page:last-child { page-break-after: auto; break-after: auto; }
.block {
  height: 190mm; padding: 5mm 6mm;
  border-right: 1px solid #666;
  display: flex; flex-direction: column; overflow: hidden;
}
.block:last-child { border-right: 0; }
.block.empty { border: 0; }
.block-title { text-align: center; font-weight: 700; font-size: 15pt; text-decoration: underline; margin-bottom: 2mm; }
.block-court { text-align: center; font-size: 12pt; font-weight: 700; margin-bottom: 3mm; }
.block-court.session { color: #00008B; }
table.info { width: 100%; border-collapse: collapse; margin-bottom: 3mm; font-size: 11.5pt; }
table.info td { border: 1px solid #444; padding: 2mm 3mm; vertical-align: middle; }
table.info td.label { background: #f0f0f0; font-weight: 700; width: 36%; white-space: nowrap; }
.witness-label { font-weight: 700; font-size: 11pt; margin-bottom: 1mm; }
.witness-name { font-style: italic; font-size: 12pt; margin-bottom: 3mm; line-height: 1.45; }
.body-text { font-size: 11pt; line-height: 1.6; text-align: justify; flex-grow: 1; }
.note { font-size: 10.5pt; font-weight: 700; text-decoration: underline; margin-top: 3mm; margin-bottom: 3mm; }
.sign { text-align: right; font-size: 11pt; margin-top: auto; }
.sign-space { height: 12mm; display: block; }
.sign-lines div { margin: 0; padding: 0; line-height: 1.3; }
</style>
</head>
<body>
$pages
</body>
</html>
''';
  }
}
