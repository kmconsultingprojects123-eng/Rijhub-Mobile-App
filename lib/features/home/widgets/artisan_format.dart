import 'package:intl/intl.dart';

import '../../../core/utils/formatters.dart';
import '../../../data/models/models.dart';

/// How the artisan home words money, times and people, shared by its
/// widgets so a budget or a countdown reads the same everywhere.
abstract final class ArtisanFormat {
  static final _grouped = NumberFormat('#,##0', 'en_US');

  /// "₦8,000–12,000", a single amount, or "Open to quotes". One naira sign
  /// and no spaces, so a budget stays short beside an area and a distance.
  static String budget(int? min, int? max) {
    if (min == null && max == null) return 'Open to quotes';
    if (min != null && max != null && min != max) {
      return '₦${_grouped.format(min)}–${_grouped.format(max)}';
    }
    return Naira.format(min ?? max!);
  }

  /// The same for screen readers: "Budget ₦8,000 to ₦12,000".
  static String spokenBudget(int? min, int? max) {
    if (min == null && max == null) return 'Open to quotes';
    if (min != null && max != null && min != max) {
      return 'Budget ${Naira.format(min)} to ${Naira.format(max)}';
    }
    return 'Budget ${Naira.format(min ?? max!)}';
  }

  /// "4 PM" on the hour, otherwise "4:30 PM".
  static String clock(DateTime time) => DateFormat(
        time.minute == 0 ? 'h a' : 'h:mm a',
      ).format(time);

  /// "4–6 PM", or "11 AM–1 PM" across noon.
  static String window(TimeWindow span) {
    final start = span.start;
    final end = span.end;
    final sameHalf = (start.hour < 12) == (end.hour < 12);
    if (!sameHalf) return '${clock(start)}–${clock(end)}';
    final bare = DateFormat(start.minute == 0 ? 'h' : 'h:mm').format(start);
    return '$bare–${clock(end)}';
  }

  /// The window for screen readers: "4 to 6 PM".
  static String spokenWindow(TimeWindow span) =>
      window(span).replaceAll('–', ' to ');

  /// How long until [start]: "in 25 min", "in 1 h 10", "in 3 h", or "Now"
  /// once it is due. Each number stays with its unit.
  static String startsIn(DateTime start, DateTime now) {
    final minutes = minutesLeft(start, now);
    if (minutes <= 0) return 'Now';
    if (minutes < 60) return 'in $minutes\u00A0min';
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    return rest == 0 ? 'in $hours\u00A0h' : 'in $hours\u00A0h\u00A0$rest';
  }

  /// The same in words: "in 1 hour 10 minutes".
  static String spokenStartsIn(DateTime start, DateTime now) {
    final minutes = minutesLeft(start, now);
    if (minutes <= 0) return 'now';
    String unit(int n, String word) => '$n $word${n == 1 ? '' : 's'}';
    if (minutes < 60) return 'in ${unit(minutes, 'minute')}';
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    return rest == 0
        ? 'in ${unit(hours, 'hour')}'
        : 'in ${unit(hours, 'hour')} ${unit(rest, 'minute')}';
  }

  /// Whole minutes until [deadline], rounded up, so the last minute reads
  /// "1 min" rather than "0 min". Zero once it has passed.
  static int minutesLeft(DateTime deadline, DateTime now) {
    final seconds = deadline.difference(now).inSeconds;
    return seconds <= 0 ? 0 : (seconds + 59) ~/ 60;
  }

  /// "Chidinma O." from "Chidinma Okafor": what an artisan sees of a client.
  static String shortName(String fullName) {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    if (parts.length < 2) return parts.first;
    return '${parts.first} ${parts.last[0].toUpperCase()}.';
  }

  /// [text] with its last two words kept together, so a title or a
  /// sentence that wraps never leaves one short word on a line of its own
  /// ("water", "book.").
  static String noWidow(String text) {
    final last = text.trimRight().lastIndexOf(' ');
    if (last <= 0) return text;
    return '${text.substring(0, last)}\u00A0${text.substring(last + 1)}';
  }

  /// "4.6 km", kept on one line.
  static String km(double km) => '${km.toStringAsFixed(1)}\u00A0km';

  /// "4.6 kilometres away", for screen readers.
  static String spokenKm(double km) =>
      '${km.toStringAsFixed(1)} kilometres away';
}
