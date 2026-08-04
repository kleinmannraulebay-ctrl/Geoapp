import 'package:intl/intl.dart';

final _pct = NumberFormat.decimalPatternDigits(locale: 'de', decimalDigits: 1);
final _date = DateFormat('dd.MM.yyyy', 'de');

String formatPct(double ratio) => '${_pct.format(ratio * 100)} %';

String formatDateMs(int? ms) =>
    ms == null ? '–' : _date.format(DateTime.fromMillisecondsSinceEpoch(ms));

String formatDay(String? day) {
  if (day == null || day.isEmpty) return '–';
  final dt = DateTime.tryParse(day);
  return dt == null ? day : _date.format(dt);
}

/// ISO-3166-alpha-2 → Flaggen-Emoji ('DE' → 🇩🇪).
String flagEmoji(String iso2) {
  if (iso2.length != 2 || iso2 == '-9') return '🌐';
  final base = 0x1F1E6;
  final a = iso2.codeUnitAt(0), b = iso2.codeUnitAt(1);
  if (a < 65 || a > 90 || b < 65 || b > 90) return '🌐';
  return String.fromCharCodes([base + a - 65, base + b - 65]);
}
