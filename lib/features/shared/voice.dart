import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/media.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/models.dart';

/// A voice note that plays when tapped, with what was heard in it.
class PlayableVoiceNote extends StatefulWidget {
  const PlayableVoiceNote({super.key, required this.note, this.mine = false});

  final VoiceNote note;
  final bool mine;

  @override
  State<PlayableVoiceNote> createState() => _PlayableVoiceNoteState();
}

class _PlayableVoiceNoteState extends State<PlayableVoiceNote> {
  bool _playing = false;
  double _progress = 0;
  StreamSubscription<double>? _sub;

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _toggle() {
    final media = context.read<MediaService>();
    _sub?.cancel();
    if (_playing) {
      media.stopPlaying();
      setState(() => _playing = false);
      return;
    }
    setState(() {
      _playing = true;
      _progress = 0;
    });
    _sub = media.play(widget.note).listen(
      (p) => setState(() => _progress = p),
      onDone: () {
        if (mounted) setState(() => _playing = false);
      },
    );
  }

  @override
  Widget build(BuildContext context) => VoiceNoteBubble(
        mine: widget.mine,
        duration: widget.note.duration,
        heard: widget.note.heard,
        playing: _playing,
        progress: _progress,
        onPlay: _toggle,
        seed: widget.note.path.hashCode,
      );
}
