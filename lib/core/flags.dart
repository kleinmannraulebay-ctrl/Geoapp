/// Flaggen-Emoji aus einem ISO-3166-1-alpha-2-Code (z. B. "DE" → 🇩🇪).
library;

String flagEmoji(String iso2) {
  final s = iso2.toUpperCase();
  if (s.length != 2 ||
      s.codeUnitAt(0) < 0x41 ||
      s.codeUnitAt(0) > 0x5A ||
      s.codeUnitAt(1) < 0x41 ||
      s.codeUnitAt(1) > 0x5A) {
    return '🌐';
  }
  return String.fromCharCodes([
    0x1F1E6 + s.codeUnitAt(0) - 0x41,
    0x1F1E6 + s.codeUnitAt(1) - 0x41,
  ]);
}
