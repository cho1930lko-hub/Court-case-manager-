/// Shared date helpers. Stored dates use DD/MM/YYYY.
class AppDates {
  AppDates._();
  static const _devanagariDigits = '०१२३४५६७८९';
  static String asciiDigits(String input) {
    final b = StringBuffer();
    for (final rune in input.runes) {
      final ch = String.fromCharCode(rune), i = _devanagariDigits.indexOf(ch);
      b.write(i >= 0 ? '$i' : ch);
    }
    return b.toString();
  }
  static DateTime? _make(int y, int m, int d) {
    if (y < 1900 || y > 2200 || m < 1 || m > 12 || d < 1 || d > 31) return null;
    final v = DateTime(y,m,d);
    return v.year == y && v.month == m && v.day == d ? v : null;
  }
  static DateTime? parse(String? raw) {
    if (raw == null) return null;
    final s = asciiDigits(raw.trim());
    if (s.isEmpty) return null;
    final iso = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})(?:[T ].*)?$').firstMatch(s);
    if (iso != null) return _make(int.parse(iso.group(1)!),int.parse(iso.group(2)!),int.parse(iso.group(3)!));
    final dmy = RegExp(r'^(\d{1,2})\s*[/\-.]\s*(\d{1,2})\s*[/\-.]\s*(\d{2}|\d{4})$').firstMatch(s);
    if (dmy != null) { var y=int.parse(dmy.group(3)!); if(y<100)y+=2000; return _make(y,int.parse(dmy.group(2)!),int.parse(dmy.group(1)!)); }
    final serial = RegExp(r'^(\d{5})(?:\.\d+)?$').firstMatch(s);
    if (serial != null) { final n=int.parse(serial.group(1)!); if(n>=20000&&n<=80000){final d=DateTime(1899,12,30+n); return DateTime(d.year,d.month,d.day);} }
    return null;
  }
  static String two(int n)=>n.toString().padLeft(2,'0');
  static String format(DateTime d)=>'${two(d.day)}/${two(d.month)}/${d.year}';
  static String normalize(String? raw){if(raw==null)return ''; final d=parse(raw); return d==null?raw.trim():format(d);}
  static bool isValid(String? raw)=>parse(raw)!=null;
  static DateTime dateOnly(DateTime d)=>DateTime(d.year,d.month,d.day);
  static String sqlSortKey(String column)=>"(substr($column,7,4) || substr($column,4,2) || substr($column,1,2))";
}
