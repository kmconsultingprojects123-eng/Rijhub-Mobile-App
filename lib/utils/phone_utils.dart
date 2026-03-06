// ...new file...

/// Small phone utilities used by registration & verification flows.
///
/// - normalizePhoneForApi: returns E.164 without plus (e.g. 2348012345678)
///   which matches the project's API docs and SendChamp expectations.
/// - formatPhoneForDisplay: returns a human-friendly string like `(+234) 8012345678`.

String normalizePhoneForApi(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return s;

  // Remove spaces, parentheses, dashes and other separators
  s = s.replaceAll(RegExp(r'[\s\-()]+'), '');

  // Remove leading + if present
  if (s.startsWith('+')) s = s.substring(1);

  // Remove international "00" prefix (e.g., 0080123...)
  if (s.startsWith('00')) {
    // drop the leading 00
    s = s.substring(2);
  }

  // If user typed a local number starting with 0 (e.g., 0801234...), convert
  // to 234... by stripping the leading 0 and prefixing 234.
  if (s.startsWith('0')) {
    s = '234' + s.substring(1);
    return s;
  }

  // If it already starts with country code (e.g., 234...) return as-is
  if (RegExp(r'^234\d{7,}$').hasMatch(s)) return s;

  // If it starts with other country code (not 234) and includes only digits,
  // keep it as-is (do not force +234 on non-Nigerian numbers).
  if (RegExp(r'^\d{7,}$').hasMatch(s)) {
    // If it's a short local form without leading zero (e.g., 8012345678)
    // assume Nigerian number and prefix 234.
    // Treat 10-digit numbers starting with 7/8/9 as Nigerian local numbers.
    if (s.length == 10 && RegExp(r'^[789]\d{8}').hasMatch(s)) {
      return '234' + s;
    }
  }

  return s;
}

String formatPhoneForDisplay(String apiPhone) {
  var s = apiPhone.trim();
  if (s.isEmpty) return s;

  // Remove leading + if present
  if (s.startsWith('+')) s = s.substring(1);

  // If it starts with 234 (Nigeria), display as (+234) localpart
  if (s.startsWith('234') && s.length > 3) {
    final local = s.substring(3);
    return '(+234) ' + local;
  }

  // If it already looks like a local number (10 digits), show as-is
  if (RegExp(r'^\d{10}').hasMatch(s)) return s;

  // Fallback: return the original (with plus if it was present)
  if (apiPhone.startsWith('+')) return apiPhone;
  return apiPhone;
}
