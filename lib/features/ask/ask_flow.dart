import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../app/media.dart';
import '../../app/push.dart';
import '../../app/session.dart';
import '../../core/utils/formatters.dart';
import '../../data/catalog/trades.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';

/// One thing in the Ask conversation.
sealed class AskItem {
  const AskItem();
}

class MeText extends AskItem {
  const MeText(this.text);
  final String text;
}

class MeVoice extends AskItem {
  MeVoice(this.note);
  VoiceNote note;
}

class MePhoto extends AskItem {
  const MePhoto(this.path);
  final String path;
}

class BotText extends AskItem {
  const BotText(this.text);
  final String text;
}

class BotTyping extends AskItem {
  const BotTyping();
}

/// The first thing a new person sees: real artisans, and how many.
class BotWelcome extends AskItem {
  const BotWelcome(this.stats);
  final MarketStats stats;
}

/// The trades to pick from, in the artisan welcome.
class BotTrades extends AskItem {
  const BotTrades();
}

/// This week's jobs for the trades picked, on a map, and the newest one.
class BotJobsTeaser extends AskItem {
  const BotJobsTeaser({required this.jobs, required this.area});
  final List<JobPost> jobs;
  final String? area;
}

/// Who can help: a map, the best match and a couple more.
class BotMatches extends AskItem {
  const BotMatches({
    required this.triage,
    required this.artisans,
    required this.area,
  });
  final Triage triage;
  final List<Artisan> artisans;
  final String? area;

  int get free => artisans.where((a) => a.isAvailableToday).length;
  Artisan get best => artisans.firstWhere((a) => a.isAvailableToday,
      orElse: () => artisans.first);
}

/// The booking, ready to confirm.
class BotSummary extends AskItem {
  const BotSummary({
    required this.draft,
    required this.price,
    this.services = const [],
  });
  final BookingDraft draft;
  final PriceBreakdown price;

  /// Each service booked, when there's more than one.
  final List<ServiceOffer> services;
}

/// An artisan's services and prices, to pick one from.
class BotServices extends AskItem {
  const BotServices({required this.artisan, required this.services});
  final Artisan artisan;
  final List<ServiceOffer> services;
}

class BotBooked extends AskItem {
  const BotBooked(this.booking);
  final Booking booking;
}

class BotJobPosted extends AskItem {
  const BotJobPosted({required this.job, required this.sentTo, this.to});
  final ClientJob job;
  final int sentTo;

  /// The one artisan it went to, when it was a price request.
  final Artisan? to;
}

/// A one-tap answer under RijHub's last message.
@immutable
class Reply {
  const Reply(this.label, this.onTap, {this.iconKey, this.primary = false});
  final String label;
  final VoidCallback onTap;

  /// A trade's icon key, for problem and trade chips.
  final String? iconKey;
  final bool primary;
}

/// What the input at the bottom is waiting for. [none] hides it, for a
/// step that ends with a button instead ([AskFlow.cta]).
enum ComposerMode { chat, address, phone, code, name, none }

/// A big button in place of the input, with an optional line under it.
@immutable
class Cta {
  const Cta(this.label, this.onTap, {this.note});
  final String label;
  final VoidCallback onTap;
  final String? note;
}

/// What happens after the person signs in inside the conversation.
enum _Pending { book, quotes, priceRequest }

/// The Ask conversation: RijHub reads the problem, shows who can help, and
/// books or gathers quotes, asking for an account only at the end.
class AskFlow extends ChangeNotifier {
  AskFlow({
    required this.session,
    required this.authFlow,
    required this.ask,
    required this.artisans,
    required this.bookingFlow,
    required this.clientJobs,
    required this.account,
    required this.directory,
    required this.media,
    required this.jobs,
    required this.catalog,
    required this.push,
    this.onPay,
    this.onPickDay,
    this.onOpen,
  });

  final SessionController session;
  final AuthFlowController authFlow;
  final AskRepository ask;
  final ArtisanRepository artisans;
  final BookingFlowRepository bookingFlow;
  final ClientJobRepository clientJobs;
  final AccountRepository account;
  final DirectoryRepository directory;
  final MediaService media;
  final JobRepository jobs;
  final CatalogRepository catalog;
  final PushPermission push;

  /// Takes payment for [total]; true once paid.
  final Future<bool> Function(int total, String description)? onPay;

  /// Lets the person pick a day and time; null when they back out.
  final Future<TimeWindow?> Function()? onPickDay;

  /// Opens an app path (a booking, a job, a list).
  final void Function(String path)? onOpen;

  final items = <AskItem>[];
  List<Reply> replies = const [];
  ComposerMode mode = ComposerMode.chat;

  /// The first open, until the person picks a way in: shows "I'm an
  /// artisan" and "Look around" under the input.
  bool welcome = false;

  /// Shown in place of the input when [mode] is [ComposerMode.none].
  Cta? cta;

  /// The trades picked in the artisan welcome, in order; at most 3.
  final pickedTrades = <String>{};

  /// The trades are sent, so the picker is now a record.
  bool tradesSent = false;
  bool recording = false;
  bool busy = false;
  String? error;
  bool _disposed = false;

  // What the person has told us.
  final _words = <String>[];
  final _photos = <String>[];
  VoiceNote? _voice;

  // Where the conversation is.
  Triage? _triage;
  List<Artisan> _matches = const [];
  Artisan? _artisan;
  ServiceOffer? _service;

  /// More of the artisan's services, added on the summary.
  final _extras = <ServiceOffer>[];
  TimeWindow? _window;
  String? _area;
  String? _address;
  _Pending? _pending;

  /// Asking one artisan for a price for something not on their list.
  bool _askingPrice = false;

  String get _you => session.user?.firstName ?? '';
  String get _areaName => session.area ?? 'Abuja';

  void _set(void Function() change) {
    if (_disposed) return;
    change();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _say(String text) => _set(() => items.add(BotText(text)));

  Future<void> _typing([int ms = 700]) async {
    _set(() => items.add(const BotTyping()));
    await Future<void>.delayed(Duration(milliseconds: ms));
    _set(() => items.removeWhere((i) => i is BotTyping));
  }

  // ---------------------------------------------------------------- start

  /// Opens the conversation. With [artisan], it is about booking them.
  Future<void> start({String? text, Artisan? artisan}) async {
    if (artisan != null) {
      _artisan = artisan;
      await _offerServicesOf(artisan);
      return;
    }
    if (text != null && text.trim().isNotEmpty) {
      await sendText(text);
      return;
    }
    _say(
        "Hi${_you.isEmpty ? '' : ' $_you'}! What needs fixing? Type it, send a photo or record a voice note, "
        "and I'll find a trusted artisan near you.");
    _set(() => replies = [
          for (final (label, key) in _problems)
            Reply(label, () => sendText(label), iconKey: key),
        ]);
  }

  static const _problems = [
    ('AC not cooling', 'ac'),
    ('No light', 'electrical'),
    ('Leaking pipe', 'plumbing'),
    ("Generator won't start", 'generator'),
    ('Deep cleaning', 'cleaning'),
  ];

  Future<void> _offerServicesOf(Artisan a) async {
    await _typing(400);
    _say("Let's book ${a.firstName}. What do you need done?");
    final profile = await directory.profile(a.id, area: _areaName);
    _set(() => items.add(BotServices(artisan: a, services: profile.services)));
  }

  /// Something [_artisan] doesn't list: describe it, and they send a price.
  Future<void> askForPrice() async {
    final a = _artisan!;
    _set(() {
      items.add(const MeText('Something else'));
      replies = const [];
    });
    _askingPrice = true;
    await _typing(400);
    _say(
        'Tell me what you need. A photo or a voice note helps ${a.firstName} price it properly.');
  }

  /// Books one of [_artisan]'s listed services.
  void pickService(ServiceOffer s) => _pickService(s);

  void _pickService(ServiceOffer s) {
    _set(() {
      items.add(MeText(s.name));
      replies = const [];
    });
    _service = s;
    _askWhen();
  }

  // ---------------------------------------------------------------- welcome

  /// The first open: who RijHub is, then a problem, "I'm an artisan" or a
  /// look around.
  Future<void> startWelcome() async {
    _set(() => welcome = true);
    final stats = await catalog.stats();
    _set(() => items.add(BotWelcome(stats)));
    await _typing(500);
    _say(
        "Hi! I'm RijHub. Tell me what needs fixing and I'll find a trusted artisan near you.");
    _say(
        'You pay through RijHub, and we hold your money until the job is done.');
    _set(() => replies = [
          for (final (label, key) in _problems)
            Reply(label, () => sendText(label), iconKey: key),
        ]);
  }

  /// Leaves the welcome as a guest of [role], once.
  Future<void> _enter(UserRole role) async {
    if (!welcome) return;
    _set(() => welcome = false);
    await session.continueAsGuest(role);
  }

  /// "Look around": straight to the app, as a client.
  Future<void> lookAround() async {
    await _enter(UserRole.client);
    onOpen?.call('/home');
  }

  /// "I'm an artisan": their trades, then this week's jobs for them.
  Future<void> artisanWelcome() async {
    _set(() {
      welcome = false;
      items.add(const MeText("I'm an artisan looking for work"));
      replies = const [];
      mode = ComposerMode.none;
    });
    await _typing(500);
    _say("Welcome! What's your trade? Pick up to 3.");
    _set(() => items.add(const BotTrades()));
  }

  void toggleTrade(String id) {
    if (tradesSent) return;
    _set(() {
      if (!pickedTrades.remove(id) && pickedTrades.length < 3) {
        pickedTrades.add(id);
      }
      replies = pickedTrades.isEmpty
          ? const []
          : [Reply('Show me jobs', _showJobs, primary: true)];
    });
  }

  Future<void> _showJobs() async {
    _set(() {
      tradesSent = true;
      items.add(MeText(
          [for (final id in pickedTrades) Trades.byId(id).name].join(', ')));
      replies = const [];
    });
    await _typing(600);
    final area = session.area;
    final demand = await Future.wait([
      for (final id in pickedTrades) jobs.demand(area: area, categoryId: id),
    ]);
    final found = await jobs.openJobsNearby(
        area: area ?? 'Abuja', categoryIds: pickedTrades, limit: 8);
    final count = demand.fold<int>(0, (n, d) => n + d.openThisWeek);
    final lows = demand.map((d) => d.typicalBudgetMin).whereType<int>();
    final highs = demand.map((d) => d.typicalBudgetMax).whereType<int>();
    final where = area == null ? 'in Abuja' : 'near you';
    _say(count == 0
        ? "No jobs for those trades $where this week yet. New ones come in every day, and I'll show you the moment they do."
        : '$count job${count == 1 ? ' was' : 's were'} posted $where this week.'
            '${lows.isEmpty ? '' : ' Most pay ${Naira.range(lows.reduce((a, b) => a < b ? a : b), highs.reduce((a, b) => a > b ? a : b))}.'}');
    _set(() {
      if (found.isNotEmpty) items.add(BotJobsTeaser(jobs: found, area: area));
      cta = Cta(
        count == 0 ? 'See jobs' : 'See all $count jobs',
        _enterAsArtisan,
        note: 'Free to join. You only add your number to send a quote.',
      );
    });
  }

  Future<void> _enterAsArtisan() async {
    await session.setGuestTrades(pickedTrades.toList());
    await session.continueAsGuest(UserRole.artisan);
    onOpen?.call('/explore');
  }

  // ---------------------------------------------------------------- input

  Future<void> sendText(String text) async {
    final t = text.trim();
    if (t.isEmpty) return;
    switch (mode) {
      case ComposerMode.address:
        _set(() {
          items.add(MeText(t));
          mode = ComposerMode.chat;
        });
        _address = t;
        _area ??= _areaName;
        await _review();
        return;
      case ComposerMode.phone:
        await _sendPhone(t);
        return;
      case ComposerMode.code:
        await _checkCode(t);
        return;
      case ComposerMode.name:
        await _saveName(t);
        return;
      case ComposerMode.chat:
      case ComposerMode.none:
        break;
    }
    await _enter(UserRole.client);
    _set(() {
      items.add(MeText(t));
      replies = const [];
    });
    if (_artisan != null && _askingPrice) {
      _words.add(t);
      await _requestPrice();
      return;
    }
    if (_artisan != null && _service == null) {
      // Booking one artisan: what they said is the job.
      _words.add(t);
      final profile = await directory.profile(_artisan!.id, area: _areaName);
      _service = profile.services.isEmpty
          ? ServiceOffer(
              id: 'custom',
              categoryId: _artisan!.categoryId,
              name: t,
              price: _artisan!.startingPrice)
          : profile.services.first;
      _askWhen();
      return;
    }
    _words.add(t);
    await _readProblem();
  }

  Future<void> sendPhoto({required bool camera}) async {
    final path = await media.pickPhoto(camera: camera);
    if (path == null) return;
    await _enter(UserRole.client);
    _set(() {
      items.add(MePhoto(path));
      replies = const [];
    });
    _photos.add(path);
    if (_askingPrice) {
      if (_words.isEmpty && _voice == null) {
        await _typing(400);
        _say(
            'Got it. Add a few words about what you need, and I\'ll send it to ${_artisan!.firstName}.');
      }
      return;
    }
    if (_words.isEmpty && _voice == null) {
      await _typing(500);
      _say(
          "Got the photo. What's going wrong? A few words or a voice note helps me find the right person.");
      return;
    }
    await _readProblem();
  }

  Future<void> startVoice() async {
    final ok = await media.startRecording();
    if (!ok) {
      _say(
          "I can't hear you yet: allow the microphone in Settings, or type instead.");
      return;
    }
    _set(() => recording = true);
  }

  Future<void> cancelVoice() async {
    await media.cancelRecording();
    _set(() => recording = false);
  }

  Future<void> sendVoice() async {
    final note = await media.stopRecording();
    _set(() => recording = false);
    if (note == null) return;
    await _enter(UserRole.client);
    final bubble = MeVoice(note);
    _set(() {
      items.add(bubble);
      replies = const [];
    });
    final String heard;
    try {
      heard = await ask.transcribe(note);
    } on AppException catch (e) {
      // Not understood (RijHub can't listen yet, or it didn't send): the
      // note still goes with the booking, and words are asked for.
      _voice = note;
      _say(e.message);
      return;
    }
    _set(() => bubble.note = note.withHeard(heard));
    _voice = bubble.note;
    if (mode == ComposerMode.address) {
      await sendText(heard);
      return;
    }
    if (_askingPrice) {
      _words.add(heard);
      await _requestPrice();
      return;
    }
    _words.add(heard);
    await _readProblem();
  }

  // ---------------------------------------------------------------- reading

  Future<void> _readProblem({String? categoryId}) async {
    _set(() => items.add(const BotTyping()));
    final input =
        AskInput(text: _words.join('. '), voiceNote: _voice, photos: _photos);
    Triage triage;
    try {
      triage = await ask.triage(input, area: session.area);
    } on AppException catch (e) {
      _set(() => items.removeWhere((i) => i is BotTyping));
      _say(e.message);
      return;
    }
    _set(() => items.removeWhere((i) => i is BotTyping));
    if (categoryId != null) {
      final trade = Trades.byId(categoryId);
      triage = Triage(
        categoryId: categoryId,
        serviceName:
            triage.categoryId == categoryId ? triage.serviceName : trade.name,
        reply: 'Got it: ${TextCase.midSentence(trade.name)}.',
        priceMin: triage.priceMin,
        priceMax: triage.priceMax,
        isUrgent: triage.isUrgent,
      );
    } else if (!triage.confident) {
      _say(triage.reply);
      _set(() => replies = [
            for (final t in Trades.all.take(8))
              Reply(t.name, () {
                _set(() {
                  items.add(MeText(t.name));
                  replies = const [];
                });
                _readProblem(categoryId: t.id);
              }, iconKey: t.iconKey),
          ]);
      return;
    }
    _triage = triage;
    _say(triage.reply);
    await _showMatches(triage);
  }

  Future<void> _showMatches(Triage triage) async {
    final area = session.area;
    final found = await artisans.topRatedNearby(
      area: area ?? 'Abuja',
      categoryId: triage.categoryId,
      limit: 6,
    );
    if (found.isEmpty) {
      _say(
          "No one's free for that near you right now. I can send your job out, and artisans will quote.");
      _set(() =>
          replies = [Reply('Get quotes', () => _getQuotes(), primary: true)]);
      return;
    }
    _matches = found;
    final card = BotMatches(triage: triage, artisans: found, area: area);
    _set(() {
      items.add(card);
      replies = [
        Reply('Book ${card.best.firstName}', () => chooseArtisan(card.best),
            primary: true),
        Reply('Get quotes from all ${found.length}', _getQuotes),
      ];
    });
  }

  // ---------------------------------------------------------------- booking

  /// Books [a] for the problem described.
  void chooseArtisan(Artisan a) {
    final triage = _triage;
    _artisan = a;
    _set(() {
      items.add(MeText('Book ${a.firstName}'));
      replies = const [];
    });
    _service = ServiceOffer(
      id: 'ask_${a.id}',
      categoryId: triage?.categoryId ?? a.categoryId,
      name: triage?.serviceName ?? a.trade,
      price: a.startingPrice,
    );
    _askWhen();
  }

  Future<void> _askWhen() async {
    final a = _artisan!;
    await _typing(450);
    _say('When should ${a.firstName} come?');
    _set(() => replies = [
          for (final (label, window) in suggestedWindows(DateTime.now()))
            Reply(label, () => _pickWhen(label, window)),
          Reply('Pick a day', () async {
            final picked = await onPickDay?.call();
            if (picked != null) _pickWhen(windowLabel(picked), picked);
          }),
        ]);
  }

  Future<void> _pickWhen(String label, TimeWindow window) async {
    _window = window;
    _set(() {
      items.add(MeText(label));
      replies = const [];
    });
    await _typing(450);
    final name = _artisan!.firstName;
    _say("Where should $name come? Add a landmark so it's easy to find.");
    final places =
        session.isSignedIn ? await account.places() : const <SavedPlace>[];
    _set(() {
      replies = [
        for (final p in places)
          Reply('${p.label} · ${p.address}', () => _pickPlace(p)),
        Reply(
            places.isEmpty ? 'Type the address' : 'Somewhere else',
            () => _set(() {
                  replies = const [];
                  mode = ComposerMode.address;
                })),
      ];
      if (places.isEmpty) mode = ComposerMode.address;
    });
  }

  Future<void> _pickPlace(SavedPlace p) async {
    _set(() {
      items.add(MeText('${p.label}: ${p.address}'));
      replies = const [];
    });
    _area = p.area;
    _address = p.address;
    await _review();
  }

  /// The service booked, or several as one, priced together.
  ServiceOffer get _booked => _extras.isEmpty
      ? _service!
      : ServiceOffer(
          id: 'multi_${_service!.id}',
          categoryId: _service!.categoryId,
          name: [_service!.name, for (final s in _extras) s.name].join(' + '),
          price: _service!.price + _extras.fold(0, (sum, s) => sum + s.price),
          parts: [_service!, ..._extras],
        );

  BookingDraft get _draft => BookingDraft(
        artisan: _artisan!,
        service: _booked,
        window: _window!,
        area: _area ?? _areaName,
        landmark: _address,
        notes: _words.isEmpty ? null : _words.join('. '),
        photos: List.unmodifiable(_photos),
        voiceNote: _voice,
      );

  Future<void> _review() async {
    await _typing(500);
    final price = await bookingFlow.price(_booked);
    _say("Here's your booking:");
    _set(() {
      items.add(_summary(price));
      replies = const [];
    });
  }

  BotSummary _summary(PriceBreakdown price) => BotSummary(
        draft: _draft,
        price: price,
        services: _extras.isEmpty ? const [] : [_service!, ..._extras],
      );

  /// The artisan's other listed services, to add to the booking.
  Future<List<ServiceOffer>> otherServices() async {
    final profile = await directory.profile(_artisan!.id, area: _areaName);
    final chosen = {_service!.name, for (final s in _extras) s.name};
    return [
      for (final s in profile.services)
        if (!chosen.contains(s.name)) s,
    ];
  }

  /// Adds [service] to the booking under review, and updates its price.
  Future<void> addService(ServiceOffer service) async {
    _extras.add(service);
    final price = await bookingFlow.price(_booked);
    final at = items.lastIndexWhere((i) => i is BotSummary);
    _set(() => items[at] = _summary(price));
  }

  /// Changes the time (and place) of the booking under review.
  Future<void> changeBooking() async {
    _set(() => items.add(const MeText('Change it')));
    await _askWhen();
  }

  /// Confirms the booking under review: signs in if needed, takes payment,
  /// and sends the request.
  Future<void> confirm() async {
    if (session.isGuest) {
      _pending = _Pending.book;
      await _askPhone(
          "To confirm, what's your phone number? I'll text you a code. No password needed.");
      return;
    }
    await _payAndBook();
  }

  Future<void> _payAndBook() async {
    final draft = _draft;
    final price = await bookingFlow.price(draft.service);
    final paid = await (onPay?.call(price.total,
            '${draft.service.name} with ${draft.artisan.firstName}') ??
        Future.value(true));
    if (!paid) {
      _say(
          "No problem. Your booking isn't sent until you pay. Tap Confirm when you're ready.");
      return;
    }
    _set(() => busy = true);
    try {
      final booking = await bookingFlow.request(draft);
      _set(() => busy = false);
      final reply = draft.artisan.replyMinutes;
      _say('Done! I sent your request to ${draft.artisan.firstName}'
          '${reply == null ? '.' : ', who usually replies in about $reply minutes.'}');
      _set(() => items.add(BotBooked(booking)));
      await _withPingOffer(
          'Want a ping when ${draft.artisan.firstName} replies?', [
        Reply('View booking', () => onOpen?.call('/booking/${booking.id}'),
            primary: true),
        Reply('Message ${draft.artisan.firstName}',
            () => onOpen?.call('/chat/${booking.conversationId}')),
      ]);
    } on AppException catch (e) {
      _set(() => busy = false);
      _say(e.message);
    }
  }

  /// Offers notifications once ever, right after something worth hearing
  /// back about, with [rest] as the other replies.
  Future<void> _withPingOffer(String question, List<Reply> rest) async {
    if (session.pushAsked || await push.granted()) {
      _set(() => replies = rest);
      return;
    }
    await session.markPushAsked();
    _say(question);
    _set(() => replies = [
          Reply('Turn on notifications', () async {
            _set(() {
              items.add(const MeText('Turn on notifications'));
              replies = const [];
            });
            final on = await push.request();
            _say(on
                ? "Done. I'll ping you, and only about your own jobs."
                : "No problem. You can turn them on in your phone's settings any time.");
            _set(() => replies = rest);
          }, primary: true),
          for (final r in rest) Reply(r.label, r.onTap, iconKey: r.iconKey),
        ]);
  }

  // ---------------------------------------------------------------- quotes

  Future<void> _getQuotes() async {
    _set(() {
      items.add(MeText(_matches.isEmpty
          ? 'Get quotes'
          : 'Get quotes from all ${_matches.length}'));
      replies = const [];
    });
    if (session.isGuest) {
      _pending = _Pending.quotes;
      await _askPhone(
          "I'll send your job to them. What's your phone number, so they can send you quotes? I'll text you a code.");
      return;
    }
    await _postJob();
  }

  Future<void> _postJob() async {
    final triage = _triage;
    if (triage == null) return;
    await _typing(500);
    final words = _words.join('. ');
    final job = await clientJobs.post(JobDraft(
      title: triage.serviceName,
      categoryId: triage.categoryId,
      area: _areaName,
      description: words.isEmpty ? null : words,
      photos: List.unmodifiable(_photos),
      voiceNote: _voice,
      budgetMin: triage.priceMin,
      budgetMax: triage.priceMax,
      isUrgent: triage.isUrgent,
    ));
    final n = _matches.isEmpty ? 5 : _matches.length;
    _say(
        "Sent! Quotes usually come in within 30 minutes. I'll tell you as each one arrives, and you can compare them side by side.");
    _set(() => items.add(BotJobPosted(job: job, sentTo: n)));
    await _withPingOffer('Want a ping as each quote comes in?', [
      Reply('See my job', () => onOpen?.call('/jobs/${job.id}'), primary: true),
    ]);
  }

  /// Sends what was described to the one artisan, for a price.
  Future<void> _requestPrice() async {
    if (session.isGuest) {
      _pending = _Pending.priceRequest;
      await _askPhone(
          "I'll send this to ${_artisan!.firstName}. What's your phone number, so they can send you a price? I'll text you a code.");
      return;
    }
    final a = _artisan!;
    await _typing(500);
    final words = _words.join('. ');
    final job = await clientJobs.post(
      JobDraft(
        title: words.length > 48 ? '${words.substring(0, 45)}…' : words,
        categoryId: a.categoryId,
        area: _areaName,
        description: words,
        photos: List.unmodifiable(_photos),
        voiceNote: _voice,
      ),
      toArtisanId: a.id,
    );
    _askingPrice = false;
    _say('Sent to ${a.firstName}'
        '${a.replyMinutes == null ? '' : ', who usually replies within ${a.replyMinutes} minutes'}. '
        "I'll tell you when the price comes in.");
    _set(() => items.add(BotJobPosted(job: job, sentTo: 1, to: a)));
    await _withPingOffer('Want a ping when ${a.firstName} sends a price?', [
      Reply('See the request', () => onOpen?.call('/jobs/${job.id}'),
          primary: true),
    ]);
  }

  // ---------------------------------------------------------------- account

  Future<void> _askPhone(String why) async {
    authFlow.begin();
    await _typing(450);
    _say(why);
    _set(() => mode = ComposerMode.phone);
  }

  Future<void> _sendPhone(String input) async {
    final national = NigerianPhone.normalize(input);
    if (!NigerianPhone.isValid(national)) {
      _set(() => error = 'Enter an 11-digit number, like 0803 123 4567.');
      return;
    }
    _set(() {
      error = null;
      items.add(MeText(NigerianPhone.display(national)));
      busy = true;
    });
    try {
      await authFlow.sendCode(national);
      _set(() {
        busy = false;
        mode = ComposerMode.code;
      });
      _say(
          'I sent a 6-digit code to ${NigerianPhone.display(national)}. Type it here.');
    } on Object {
      _set(() => busy = false);
      _say("I couldn't send the code. Check your connection and try again.");
    }
  }

  Future<void> resendCode() async {
    await authFlow.resend();
    _say('Sent a new code.');
  }

  /// Back to the number, to fix a typo.
  void changeNumber() {
    authFlow.reset();
    _set(() => mode = ComposerMode.phone);
    _say("No problem. What's the right number?");
  }

  Future<void> _checkCode(String code) async {
    if (code.length != 6) return;
    _set(() => busy = true);
    try {
      final known = await authFlow.verify(code);
      _set(() => busy = false);
      if (known == null) return;
      if (known) {
        _set(() => mode = ComposerMode.chat);
        _say('Welcome back, ${session.user?.firstName}!');
        await _continue();
      } else {
        _set(() => mode = ComposerMode.name);
        _say("Nice to meet you. What's your name?");
      }
    } on AuthException catch (e) {
      _set(() {
        busy = false;
        error = e.message;
      });
    }
  }

  Future<void> _saveName(String name) async {
    if (name.trim().split(RegExp(r'\s+')).length < 2) {
      _set(() => error = 'Add your first and last name.');
      return;
    }
    _set(() {
      error = null;
      items.add(MeText(name.trim()));
      busy = true;
    });
    await authFlow.createAccount(fullName: name);
    _set(() {
      busy = false;
      mode = ComposerMode.chat;
    });
    _say('Thanks, ${session.user?.firstName}. Your account is ready.');
    await _continue();
  }

  Future<void> _continue() async {
    final pending = _pending;
    _pending = null;
    switch (pending) {
      case _Pending.book:
        await _payAndBook();
      case _Pending.quotes:
        await _postJob();
      case _Pending.priceRequest:
        await _requestPrice();
      case null:
        break;
    }
  }

  void clearError() {
    if (error != null) _set(() => error = null);
  }
}

/// Times to offer: the next two-hour windows today, then two tomorrow.
List<(String, TimeWindow)> suggestedWindows(DateTime now) {
  final out = <(String, TimeWindow)>[];
  var start = DateTime(now.year, now.month, now.day, now.hour + 2);
  if (start.hour.isOdd) start = start.add(const Duration(hours: 1));
  while (out.length < 2 && start.day == now.day && start.hour <= 18) {
    final w =
        TimeWindow(start: start, end: start.add(const Duration(hours: 2)));
    out.add((windowLabel(w, now: now), w));
    start = start.add(const Duration(hours: 2));
  }
  final tomorrow = DateTime(now.year, now.month, now.day + 1);
  for (final h in [9, 14]) {
    final s = tomorrow.add(Duration(hours: h));
    final w = TimeWindow(start: s, end: s.add(const Duration(hours: 2)));
    out.add((windowLabel(w, now: now), w));
  }
  return out.take(4).toList();
}

/// "Today, 4–6 PM", "Tomorrow, 11 AM–1 PM", "Fri 18 Oct, 9–11 AM".
String windowLabel(TimeWindow w, {DateTime? now}) {
  String h(DateTime t) =>
      '${t.hour % 12 == 0 ? 12 : t.hour % 12}${t.minute == 0 ? '' : ':${t.minute.toString().padLeft(2, '0')}'}';
  String p(DateTime t) => t.hour < 12 ? 'AM' : 'PM';
  final same = p(w.start) == p(w.end);
  final range = same
      ? '${h(w.start)}–${h(w.end)} ${p(w.end)}'
      : '${h(w.start)} ${p(w.start)}–${h(w.end)} ${p(w.end)}';
  return '${Schedule.dayLabel(w.start, now: now)}, $range';
}
