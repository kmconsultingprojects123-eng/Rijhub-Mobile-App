import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';

/// How the Ask conversation should start. [welcome] is the first open:
/// RijHub introduces itself and the person picks a way in.
enum AskStart { typing, camera, voice, welcome }

/// What the Ask conversation opens with: a problem already said (a chip, a
/// search), or the camera or microphone ready to go.
@immutable
class AskLaunch {
  const AskLaunch({this.text, this.start = AskStart.typing, this.artisanId});

  /// Sent straight away, as if typed.
  final String? text;
  final AskStart start;

  /// Asking one artisan for a price, from their profile.
  final String? artisanId;
}

/// Opens the Ask conversation.
void openAsk(BuildContext context,
    {String? text, AskStart start = AskStart.typing, String? artisanId}) {
  context.push(Routes.ask,
      extra: AskLaunch(text: text, start: start, artisanId: artisanId));
}

/// Common problems, one tap each, with their icons' keys.
const commonProblems = [
  ('AC not cooling', 'ac'),
  ('No light', 'electrical'),
  ('Leaking pipe', 'plumbing'),
  ("Generator won't start", 'generator'),
  ('Deep cleaning', 'cleaning'),
];
