import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/// Naira amounts. Whole naira only; prices on RijHub are never fractional.
abstract final class Naira {
  static final _grouped = NumberFormat('#,##0', 'en_US');

  /// ₦8,000
  static String format(num amount) => '₦${_grouped.format(amount)}';

  /// ₦8,000 – ₦12,000, a single amount, or "Open to quotes".
  static String range(int? min, int? max) {
    if (min == null && max == null) return 'Open to quotes';
    if (min != null && max != null && min != max) {
      return '${format(min)} – ${format(max)}';
    }
    return format(min ?? max!);
  }
}

/// Nigerian mobile numbers. We store the 10 national digits ("8031234567")
/// and show them as "803 123 4567" next to a fixed +234 prefix.
abstract final class NigerianPhone {
  static const countryCode = '+234';

  /// Keeps up to 10 national digits. Accepts pasted "+234…" numbers and the
  /// local "0803…" form.
  static String normalize(String input) {
    var digits = input.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('234')) digits = digits.substring(3);
    if (digits.startsWith('0')) digits = digits.substring(1);
    return digits.length > 10 ? digits.substring(0, 10) : digits;
  }

  /// Mobile ranges: 70x, 71x, 80x, 81x, 90x, 91x.
  static bool isValid(String national) =>
      RegExp(r'^[789][01]\d{8}$').hasMatch(national);

  static String formatNational(String national) {
    final b = StringBuffer();
    for (var i = 0; i < national.length; i++) {
      if (i == 3 || i == 6) b.write(' ');
      b.write(national[i]);
    }
    return b.toString();
  }

  static String toE164(String national) => '$countryCode$national';

  static String display(String national) =>
      '$countryCode ${formatNational(national)}';
}

/// Formats input as "803 123 4567" while typing, keeping the caret after
/// the same digit so a correction mid-number doesn't jump to the end.
class NigerianPhoneInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final national = NigerianPhone.normalize(newValue.text);
    final formatted = NigerianPhone.formatNational(national);

    final raw = newValue.text;
    final caret = newValue.selection.baseOffset.clamp(0, raw.length);
    var digitsBefore =
        raw.substring(0, caret).replaceAll(RegExp(r'\D'), '').length;
    // Digits normalize() dropped from the front (+234 or a leading 0).
    final allDigits = raw.replaceAll(RegExp(r'\D'), '');
    var dropped = 0;
    if (allDigits.startsWith('234')) dropped = 3;
    if (allDigits.substring(dropped).startsWith('0')) dropped += 1;
    digitsBefore = (digitsBefore - dropped).clamp(0, national.length);

    var offset = 0;
    for (var seen = 0;
        offset < formatted.length && seen < digitsBefore;
        offset++) {
      if (formatted[offset] != ' ') seen++;
    }
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: offset),
    );
  }
}

abstract final class RelativeTime {
  /// "Just now", "15 min ago", "3 h ago", "Yesterday", "4 days ago", "12 Oct".
  /// The number and its unit never split across lines.
  static String short(DateTime time, {DateTime? now}) {
    final d = (now ?? DateTime.now()).difference(time);
    if (d.inMinutes < 1) return 'Just now';
    if (d.inMinutes < 60) return '${d.inMinutes}\u00A0min ago';
    if (d.inHours < 24) return '${d.inHours}\u00A0h ago';
    if (d.inDays == 1) return 'Yesterday';
    if (d.inDays < 7) return '${d.inDays}\u00A0days ago';
    return DateFormat('d MMM').format(time);
  }

  /// The same, in words for screen readers: "15 minutes ago".
  static String spoken(DateTime time, {DateTime? now}) {
    final d = (now ?? DateTime.now()).difference(time);
    String plural(int n, String unit) => '$n $unit${n == 1 ? '' : 's'} ago';
    if (d.inMinutes < 1) return 'Just now';
    if (d.inMinutes < 60) return plural(d.inMinutes, 'minute');
    if (d.inHours < 24) return plural(d.inHours, 'hour');
    if (d.inDays == 1) return 'Yesterday';
    if (d.inDays < 7) return plural(d.inDays, 'day');
    return DateFormat('d MMMM').format(time);
  }
}

abstract final class Schedule {
  /// "Today", "Tomorrow", "Yesterday" or "Fri 18 Oct". Compares calendar
  /// dates, so daylight-saving changes can't shift the answer.
  static String dayLabel(DateTime time, {DateTime? now}) {
    final diff = _calendarDays(now ?? DateTime.now(), time);
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Tomorrow';
    if (diff == -1) return 'Yesterday';
    return DateFormat('EEE d MMM').format(time);
  }

  /// "2:30 PM".
  static String time(DateTime time) => DateFormat('h:mm a').format(time);

  /// "Today, 2:30 PM", "Tomorrow, 9:00 AM" or "Fri 18 Oct, 9:00 AM".
  static String dayAndTime(DateTime time, {DateTime? now}) =>
      '${dayLabel(time, now: now)}, ${Schedule.time(time)}';

  /// For the middle of a sentence: "today at 2:30 PM", "tomorrow at
  /// 9:00 AM", "on Fri 18 Oct at 9:00 AM".
  static String inSentence(DateTime time, {DateTime? now}) {
    final day = dayLabel(time, now: now);
    final when = switch (day) {
      'Today' || 'Tomorrow' || 'Yesterday' => day.toLowerCase(),
      _ => 'on $day',
    };
    return '$when at ${Schedule.time(time)}';
  }
}

abstract final class Greeting {
  static String forTime(DateTime now) {
    if (now.hour < 12) return 'Good morning';
    if (now.hour < 17) return 'Good afternoon';
    return 'Good evening';
  }
}

abstract final class TextCase {
  /// [text] as it reads mid-sentence: "Electrical" becomes "electrical",
  /// and "AC repair" or "TV & decoder" keep their acronym.
  static String midSentence(String text) {
    final opensWithAcronym =
        text.length > 1 && text[1] != text[1].toLowerCase();
    if (text.isEmpty || opensWithAcronym) return text;
    return '${text[0].toLowerCase()}${text.substring(1)}';
  }

  /// "AC repair", "AC repair and electrical", "AC repair, electrical and
  /// plumbing": names in a sentence, all but the first mid-sentence.
  static String list(List<String> names) {
    final words = [
      for (var i = 0; i < names.length; i++)
        i == 0 ? names[i] : midSentence(names[i]),
    ];
    if (words.length < 2) return words.join();
    return '${words.sublist(0, words.length - 1).join(', ')} and ${words.last}';
  }
}

int _calendarDays(DateTime from, DateTime to) =>
    DateTime.utc(to.year, to.month, to.day)
        .difference(DateTime.utc(from.year, from.month, from.day))
        .inDays;
