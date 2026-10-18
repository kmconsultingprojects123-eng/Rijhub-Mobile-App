import 'dart:async';
import 'dart:math' as math;

import '../models/models.dart';
import '../repositories/repositories.dart';
import 'mock_data.dart';
import 'mock_market_data.dart';
import 'mock_repositories.dart';

Future<void> _wait([int ms = 400]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

/// The mock backend's memory for everything beyond the home screens:
/// bookings made and changed, jobs, quotes, conversations, notifications,
/// money and profiles, per account. With [live] on, it also plays the other
/// side for a moment after each action (an artisan accepts, replies,
/// quotes), so flows can be tried end to end on one phone.
class MockMarket {
  MockMarket(this.accounts, {this.live = true});

  final MockAccounts accounts;
  final bool live;

  final _random = math.Random(42);
  DateTime get now => DateTime.now();
  AppUser? get user => accounts.current;
  String? get uid => accounts.current?.id;

  /// Runs [action] after [delay] when playing the other side.
  void later(Duration delay, void Function() action) {
    if (live) Timer(delay, action);
  }

  // ---------------------------------------------------------------- artisans

  List<Artisan> artisans({String area = MockData.city}) => [
        ...MockData.artisansAt(accounts.startedAt, area: area),
        ...MarketData.extraArtisans(now),
      ];

  Artisan artisan(String id, {String area = MockData.city}) =>
      artisans(area: area).firstWhere(
        (a) => a.id == id,
        orElse: () =>
            throw const AppException('That artisan is no longer on RijHub.'),
      );

  final _saved = <String?, List<String>>{};
  List<String> savedOf(String? id) => _saved[id] ??=
      id == MarketData.chidinma ? ['a_ibrahim', 'a_kunle'] : <String>[];

  // Profiles the signed-in artisan has edited.
  final _myProfiles = <String, ArtisanProfile>{};
  final _verification = <String, Verification>{};

  // ---------------------------------------------------------------- bookings

  /// Bookings made since launch, by id, as each side sees them.
  final _clientView = <String, Booking>{};
  final _artisanView = <String, Booking>{};
  final _codes = <String, String>{'b_1': '4829'};

  List<Booking> bookingsOf(String? userId, UserRole role) => [
        ...MockData.bookingsFor(userId, role, accounts.startedAt),
        ...accounts.newBookingsOf(userId),
        ...MarketData.pastFor(userId, role, now),
      ].map(accounts.patched).toList();

  Booking booking(String id) {
    final role = user?.role ?? UserRole.client;
    final mine = bookingsOf(uid, role).where((b) => b.id == id);
    if (mine.isNotEmpty) return mine.first;
    final made = (role == UserRole.client ? _clientView : _artisanView)[id];
    if (made != null) return accounts.patched(made);
    throw const AppException("We couldn't find that booking.");
  }

  void change(String bookingId, BookingChange change) {
    accounts.changeBooking(bookingId, change);
  }

  // ---------------------------------------------------------------- jobs

  final _clientJobs = <String?, List<ClientJob>>{};
  List<ClientJob> clientJobsOf(String? id) =>
      _clientJobs[id] ??= List.of(MarketData.clientJobsFor(id, now));

  final _quotes = <String?, List<Quote>>{};
  List<Quote> quotesOf(String? id) =>
      _quotes[id] ??= List.of(MarketData.artisanQuotesFor(id, now));

  final _quoteRequests = <String?, List<ClientJob>>{};
  List<ClientJob> quoteRequestsOf(String? id) =>
      _quoteRequests[id] ??= List.of(MarketData.quoteRequestsFor(id, now));

  // ---------------------------------------------------------------- chat

  final _convos = <String, MockConvo>{};
  final _chatUnread = <String?, StreamController<int>>{};

  Map<String, MockConvo> convosOf(String? id) {
    final prefix = '$id/';
    if (!_convos.keys.any((k) => k.startsWith(prefix))) {
      for (final (c, messages) in MarketData.conversationsFor(
        id,
        now,
        MockData.firstBookingAt(accounts.startedAt),
      )) {
        _convos['$prefix${c.id}'] = MockConvo(c, List.of(messages));
      }
      _convos['$prefix~'] = MockConvo.marker;
    }
    return {
      for (final e in _convos.entries)
        if (e.key.startsWith(prefix) && e.value != MockConvo.marker)
          e.key.substring(prefix.length): e.value,
    };
  }

  MockConvo convo(String conversationId) {
    final found = convosOf(uid)[conversationId];
    if (found == null) throw const AppException('That conversation has ended.');
    return found;
  }

  MockConvo startConvo(Conversation c) {
    convosOf(uid);
    return _convos['$uid/${c.id}'] ??= MockConvo(c, []);
  }

  int chatUnread(String? id) =>
      convosOf(id).values.fold(0, (sum, c) => sum + c.unread);

  StreamController<int> chatUnreadStream(String? id) =>
      _chatUnread[id] ??= StreamController<int>.broadcast();

  void post(String conversationId, ChatMessage message, {String? forUser}) {
    final owner = forUser ?? uid;
    final c = convosOf(owner)[conversationId];
    if (c == null) return;
    c.messages.add(message);
    c.updatedAt = message.sentAt;
    if (!message.fromMe && !message.read) c.unread++;
    c.emit();
    chatUnreadStream(owner).add(chatUnread(owner));
  }

  ChatMessage message({
    required bool fromMe,
    String? text,
    MessageKind kind = MessageKind.text,
    VoiceNote? voiceNote,
    String? photo,
    bool read = false,
  }) =>
      ChatMessage(
        id: 'm_${now.microsecondsSinceEpoch}_${_random.nextInt(9999)}',
        fromMe: fromMe,
        kind: kind,
        text: text,
        voiceNote: voiceNote,
        photo: photo,
        sentAt: now,
        read: read || fromMe,
      );

  // ---------------------------------------------------------------- notices

  final _notices = <String?, List<AppNotice>>{};
  final _noticeUnread = <String?, StreamController<int>>{};
  final _prefs = <String?, NotificationPrefs>{};

  List<AppNotice> noticesOf(String? id) =>
      _notices[id] ??= List.of(MarketData.noticesFor(id, now));

  StreamController<int> noticeStream(String? id) =>
      _noticeUnread[id] ??= StreamController<int>.broadcast();

  int noticeUnread(String? id) => noticesOf(id).where((n) => !n.read).length;

  void notify(AppNotice notice, {String? forUser}) {
    final owner = forUser ?? uid;
    noticesOf(owner).insert(0, notice);
    noticeStream(owner).add(noticeUnread(owner));
  }

  AppNotice notice(NoticeKind kind, String title, String body,
          {String? route}) =>
      AppNotice(
        id: 'n_${now.microsecondsSinceEpoch}',
        kind: kind,
        title: title,
        body: body,
        at: now,
        route: route,
      );

  // ---------------------------------------------------------------- money

  final _tx = <String?, List<WalletTx>>{};
  List<WalletTx> txOf(String? id) =>
      _tx[id] ??= List.of(MarketData.transactionsFor(id, now));

  final _payout = <String?, PayoutAccount?>{};
  PayoutAccount? payoutOf(String? id) => _payout.containsKey(id)
      ? _payout[id]
      : (id == MarketData.emeka
          ? const PayoutAccount(
              bank: Bank(code: '058', name: 'GTBank'),
              accountNumber: '0123454821',
              accountName: 'EMEKA NWOSU',
            )
          : null);

  final _available = <String?, int>{};
  int availableOf(String? id) =>
      _available[id] ??= id == MarketData.emeka ? 54000 : 0;

  // ---------------------------------------------------------------- places

  final _places = <String?, List<SavedPlace>>{};
  List<SavedPlace> placesOf(String? id) =>
      _places[id] ??= List.of(MarketData.placesFor(id));

  String code() => (1000 + _random.nextInt(9000)).toString();
  String? codeFor(String bookingId) => _codes[bookingId];
  void setCode(String bookingId, String code) => _codes[bookingId] = code;
  void addClientBooking(Booking b) => _clientView[b.id] = b;
}

class MockConvo {
  MockConvo(this.meta, this.messages)
      : unread = messages.where((m) => !m.fromMe && !m.read).length,
        updatedAt = meta.updatedAt;

  static final marker = MockConvo(
    Conversation(id: '~', title: '', updatedAt: DateTime(2000)),
    [],
  );

  final Conversation meta;
  final List<ChatMessage> messages;
  int unread;
  DateTime updatedAt;
  final controller = StreamController<List<ChatMessage>>.broadcast();

  void emit() => controller.add(List.unmodifiable(messages));

  Conversation get view => Conversation(
        id: meta.id,
        title: meta.title,
        photo: meta.photo,
        subtitle: meta.subtitle,
        bookingId: meta.bookingId,
        artisanId: meta.artisanId,
        online: meta.online,
        lastMessage: messages.isEmpty ? null : messages.last,
        unread: unread,
        updatedAt: updatedAt,
      );
}

// ---------------------------------------------------------------- ask

class MockAskRepository implements AskRepository {
  MockAskRepository(this._m);
  final MockMarket _m;

  @override
  Future<String> transcribe(VoiceNote note) async {
    await _wait(900);
    return MarketData.sampleHeard;
  }

  @override
  Future<Triage> triage(AskInput input, {String? area}) async {
    await _wait(_m.live ? 1100 : 300);
    final words = input.words.isNotEmpty
        ? input.words
        : (input.photos.isNotEmpty ? 'ac not cooling' : '');
    final t = MarketData.triage(words);
    return Triage(
      categoryId: t.categoryId,
      serviceName: t.serviceName,
      reply: t.reply,
      priceMin: t.priceMin,
      priceMax: t.priceMax,
      isUrgent: t.isUrgent,
      heard: input.voiceNote?.heard,
      confident: t.confident,
    );
  }
}

// ---------------------------------------------------------------- directory

class MockDirectoryRepository implements DirectoryRepository {
  MockDirectoryRepository(this._m);
  final MockMarket _m;

  @override
  Future<List<Artisan>> search({
    required String area,
    String? query,
    String? categoryId,
    bool freeNow = false,
    bool verifiedOnly = false,
    ArtisanSort sort = ArtisanSort.recommended,
    int limit = 30,
  }) async {
    await _wait(350);
    final q = query?.trim().toLowerCase() ?? '';
    final guessed = q.isEmpty ? null : MarketData.triage(q);
    final results = [
      for (final a in _m.artisans(area: area))
        if ((categoryId == null || a.categoryId == categoryId) &&
            (!freeNow || a.isAvailableToday) &&
            (!verifiedOnly || a.isVerified) &&
            (q.isEmpty ||
                a.name.toLowerCase().contains(q) ||
                a.trade.toLowerCase().contains(q) ||
                MockData.categories
                    .firstWhere((c) => c.id == a.categoryId)
                    .name
                    .toLowerCase()
                    .contains(q) ||
                (guessed!.confident && guessed.categoryId == a.categoryId)))
          a,
    ];
    switch (sort) {
      case ArtisanSort.nearest:
        results.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
      case ArtisanSort.rating:
        results.sort((a, b) => b.rating.compareTo(a.rating));
      case ArtisanSort.price:
        results.sort((a, b) => a.startingPrice.compareTo(b.startingPrice));
      case ArtisanSort.recommended:
        double score(Artisan a) =>
            a.rating * 2 - a.distanceKm / 5 + (a.isAvailableToday ? 0.5 : 0);
        results.sort((a, b) => score(b).compareTo(score(a)));
    }
    return results.take(limit).toList();
  }

  @override
  Future<ArtisanProfile> profile(String artisanId, {String? area}) async {
    await _wait(450);
    final a = _m.artisan(artisanId, area: area ?? MockData.city);
    return _m._myProfiles[artisanId] ?? MarketData.profileFor(a, _m.now);
  }

  @override
  Future<List<Review>> reviews(String artisanId) async {
    await _wait(400);
    final known = _m.artisans().where((a) => a.id == artisanId);
    if (known.isEmpty) return const [];
    return MarketData.reviewsFor(known.first, _m.now);
  }

  @override
  Future<List<Artisan>> saved({String? area}) async {
    await _wait(300);
    final ids = _m.savedOf(_m.uid);
    final all = _m.artisans(area: area ?? MockData.city);
    return [
      for (final id in ids.reversed) ...all.where((a) => a.id == id),
    ];
  }

  @override
  Future<Set<String>> savedIds() async => _m.savedOf(_m.uid).toSet();

  @override
  Future<bool> toggleSaved(String artisanId) async {
    await _wait(150);
    final ids = _m.savedOf(_m.uid);
    if (ids.remove(artisanId)) return false;
    ids.add(artisanId);
    return true;
  }
}

// ---------------------------------------------------------------- bookings

class MockBookingFlowRepository implements BookingFlowRepository {
  MockBookingFlowRepository(this._m);
  final MockMarket _m;

  static int feeFor(int price) =>
      (math.max(300, math.min(2500, price * 0.05)) / 50).round() * 50;

  @override
  Future<PriceBreakdown> price(ServiceOffer service) async {
    await _wait(150);
    return PriceBreakdown(price: service.price, fee: feeFor(service.price));
  }

  @override
  Future<Booking> request(BookingDraft draft) async {
    final user = _m.user;
    if (user == null) throw const AppException('Sign in to book.');
    await _wait(900);
    final id = 'b_${_m.now.millisecondsSinceEpoch}';
    final code = _m.code();
    final conversationId = 'c_${draft.artisan.id}';
    final booking = Booking(
      id: id,
      serviceName: draft.service.name,
      categoryId: draft.service.categoryId,
      scheduledAt: draft.window.start,
      status: BookingStatus.requested,
      counterpartName: draft.artisan.name,
      counterpartPhoto: draft.artisan.photo,
      counterpartPhone: '+2347000000199',
      area: draft.area,
      landmark: draft.landmark,
      price: draft.service.price,
      fee: feeFor(draft.service.price),
      startCode: code,
      artisanId: draft.artisan.id,
      notes: draft.notes,
      photos: draft.photos,
      voiceNote: draft.voiceNote,
      payment: PaymentState.held,
      conversationId: conversationId,
    );
    _m.setCode(id, code);
    _m.addClientBooking(booking);
    _m.accounts.addBooking(user.id, booking);
    _m.startConvo(Conversation(
      id: conversationId,
      title: draft.artisan.name,
      photo: draft.artisan.photo,
      subtitle: draft.service.name,
      bookingId: id,
      artisanId: draft.artisan.id,
      updatedAt: _m.now,
    ));
    _m.post(
        conversationId,
        _m.message(
          fromMe: false,
          kind: MessageKind.system,
          text:
              'Request sent to ${draft.artisan.firstName}. Your payment is held safely until the job is done.',
          read: true,
        ));
    if (draft.notes != null && draft.notes!.trim().isNotEmpty) {
      _m.post(conversationId, _m.message(fromMe: true, text: draft.notes));
    }
    _m.notify(_m.notice(
      NoticeKind.payment,
      'Payment held: ₦${booking.total}',
      'We release it to ${draft.artisan.firstName} when you confirm the job is done.',
      route: '/account/payments',
    ));
    final owner = user.id;
    _m.later(const Duration(seconds: 4), () {
      _m.change(id, const BookingChange(status: BookingStatus.confirmed));
      _m.post(
          conversationId,
          _m.message(
            fromMe: false,
            kind: MessageKind.system,
            text: '${draft.artisan.firstName} accepted. Booking confirmed.',
            read: true,
          ),
          forUser: owner);
      _m.post(
          conversationId,
          _m.message(
            fromMe: false,
            text: "Hello! I've seen your request and I'll be there on time.",
          ),
          forUser: owner);
      _m.notify(
          _m.notice(
            NoticeKind.booking,
            '${draft.artisan.firstName} accepted your booking',
            '${draft.service.name} is confirmed. Your start code is $code.',
            route: '/booking/$id',
          ),
          forUser: owner);
    });
    return booking;
  }

  @override
  Future<Booking> byId(String bookingId) async {
    await _wait(250);
    return _m.booking(bookingId);
  }

  @override
  Future<List<Booking>> past({required UserRole as}) async {
    await _wait(350);
    return _m.bookingsOf(_m.uid, as).where((b) => b.isOver).toList()
      ..sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt));
  }

  Future<Booking> _apply(String id, BookingChange change,
      {int ms = 600}) async {
    await _wait(ms);
    _m.booking(id);
    _m.change(id, change);
    return _m.booking(id);
  }

  @override
  Future<Booking> cancel(String bookingId, {required String reason}) async {
    final b = await _apply(
      bookingId,
      BookingChange(
        status: BookingStatus.cancelled,
        payment: PaymentState.refunded,
        cancelReason: reason,
      ),
    );
    _m.notify(_m.notice(
      NoticeKind.payment,
      'Refund on its way: ₦${b.total}',
      'Your ${b.serviceName} booking is cancelled, so the payment goes back to you.',
      route: '/account/payments',
    ));
    return b;
  }

  @override
  Future<Booking> reschedule(String bookingId, DateTime to) =>
      _apply(bookingId, BookingChange(scheduledAt: to));

  @override
  Future<Booking> confirmDone(String bookingId) async {
    final b = await _apply(
      bookingId,
      const BookingChange(
        status: BookingStatus.completed,
        payment: PaymentState.released,
      ),
    );
    _m.notify(_m.notice(
      NoticeKind.payment,
      'Payment released to ${b.counterpartName.split(' ').first}',
      'Thanks for confirming. How did it go? Leave a review.',
      route: '/booking/${b.id}',
    ));
    return b;
  }

  @override
  Future<Booking> review(String bookingId,
          {required int rating, String? text}) =>
      _apply(bookingId, BookingChange(yourRating: rating), ms: 500);

  @override
  Future<Booking> onMyWay(String bookingId) => _apply(
        bookingId,
        const BookingChange(status: BookingStatus.onTheWay, etaMinutes: 20),
      );

  @override
  Future<Booking> start(String bookingId, String code) async {
    await _wait(600);
    final expected = _m.codeFor(bookingId);
    if (expected != null && code != expected) {
      throw const AppException(
        "That code doesn't match. Ask the client to read it from their booking.",
      );
    }
    _m.change(bookingId, const BookingChange(status: BookingStatus.inProgress));
    return _m.booking(bookingId);
  }

  @override
  Future<Booking> finish(String bookingId) => _apply(
        bookingId,
        const BookingChange(status: BookingStatus.completed),
      );
}

// ---------------------------------------------------------------- jobs

class MockClientJobRepository implements ClientJobRepository {
  MockClientJobRepository(this._m);
  final MockMarket _m;

  @override
  Future<ClientJob> post(JobDraft draft, {String? toArtisanId}) async {
    final user = _m.user;
    if (user == null) throw const AppException('Sign in to post a job.');
    await _wait(800);
    final job = ClientJob(
      id: 'j_${_m.now.millisecondsSinceEpoch}',
      title: draft.title,
      categoryId: draft.categoryId,
      area: draft.area,
      landmark: draft.landmark,
      postedAt: _m.now,
      status: JobStatus.open,
      description: draft.description,
      photos: draft.photos,
      voiceNote: draft.voiceNote,
      budgetMin: draft.budgetMin,
      budgetMax: draft.budgetMax,
      isUrgent: draft.isUrgent,
    );
    final jobs = _m.clientJobsOf(user.id)..insert(0, job);
    final owner = user.id;
    // A few artisans in the trade quote within moments.
    _m.later(const Duration(seconds: 5), () {
      final candidates = _m
          .artisans(area: draft.area)
          .where((a) =>
              a.categoryId == draft.categoryId &&
              (toArtisanId == null || a.id == toArtisanId))
          .take(toArtisanId == null ? 2 : 1)
          .toList();
      final index = jobs.indexWhere((j) => j.id == job.id);
      if (index < 0 || candidates.isEmpty) return;
      final base = draft.budgetMin ?? candidates.first.startingPrice;
      final quotes = [
        for (final (i, a) in candidates.indexed)
          Quote(
            id: 'q_${job.id}_$i',
            jobId: job.id,
            artisan: a,
            price: (base + i * 1500) ~/ 500 * 500,
            message: i == 0
                ? 'I can come today and fix it properly. Price covers labour.'
                : 'Available tomorrow morning. I will check everything first.',
            canStartAt: _m.now.add(Duration(hours: 3 + i * 18)),
            sentAt: _m.now,
          ),
      ];
      jobs[index] = jobs[index].copyWith(quotes: quotes);
      _m.notify(
          _m.notice(
            NoticeKind.quote,
            quotes.length == 1
                ? 'New quote: ₦${quotes.first.price}'
                : '${quotes.length} quotes for "${draft.title}"',
            'Compare prices, ratings and when they can come.',
            route: '/jobs/${job.id}',
          ),
          forUser: owner);
    });
    return job;
  }

  @override
  Future<List<ClientJob>> mine() async {
    await _wait(350);
    return List.of(_m.clientJobsOf(_m.uid));
  }

  @override
  Future<ClientJob> byId(String jobId) async {
    await _wait(250);
    return _m.clientJobsOf(_m.uid).firstWhere(
          (j) => j.id == jobId,
          orElse: () => throw const AppException('That job was closed.'),
        );
  }

  @override
  Future<Booking> accept(
    String jobId,
    String quoteId, {
    required TimeWindow window,
    int? price,
  }) async {
    final user = _m.user;
    if (user == null) throw const AppException('Sign in to accept a quote.');
    final jobs = _m.clientJobsOf(user.id);
    final index = jobs.indexWhere((j) => j.id == jobId);
    final job = jobs[index];
    final quote = job.quotes.firstWhere((q) => q.id == quoteId);
    final booking = await MockBookingFlowRepository(_m).request(BookingDraft(
      artisan: quote.artisan,
      service: ServiceOffer(
        id: quote.id,
        categoryId: job.categoryId,
        name: job.title,
        price: price ?? quote.priceMax ?? quote.price,
      ),
      window: window,
      area: job.area,
      landmark: job.landmark,
      notes: job.description,
      photos: job.photos,
      voiceNote: job.voiceNote,
    ));
    // The quote was the artisan's own offer, so accepting it confirms the
    // booking: there's nothing left for them to agree to.
    _m.change(booking.id, const BookingChange(status: BookingStatus.confirmed));
    jobs[index] = job.copyWith(
      status: JobStatus.booked,
      bookingId: booking.id,
      quotes: [
        for (final q in job.quotes)
          q.withStatus(
              q.id == quoteId ? QuoteStatus.accepted : QuoteStatus.declined),
      ],
    );
    return _m.booking(booking.id);
  }

  @override
  Future<ClientJob> decline(String jobId, String quoteId) async {
    await _wait(300);
    final jobs = _m.clientJobsOf(_m.uid);
    final index = jobs.indexWhere((j) => j.id == jobId);
    return jobs[index] = jobs[index].copyWith(quotes: [
      for (final q in jobs[index].quotes)
        q.id == quoteId ? q.withStatus(QuoteStatus.declined) : q,
    ]);
  }

  @override
  Future<ClientJob> close(String jobId) async {
    await _wait(400);
    final jobs = _m.clientJobsOf(_m.uid);
    final index = jobs.indexWhere((j) => j.id == jobId);
    return jobs[index] = jobs[index].copyWith(status: JobStatus.closed);
  }

  @override
  Future<ClientJob> update(String jobId, JobDraft draft) async {
    await _wait(500);
    final jobs = _m.clientJobsOf(_m.uid);
    final index = jobs.indexWhere((j) => j.id == jobId);
    final old = jobs[index];
    return jobs[index] = ClientJob(
      id: old.id,
      title: draft.title,
      categoryId: draft.categoryId,
      area: draft.area,
      landmark: draft.landmark,
      postedAt: old.postedAt,
      status: old.status,
      description: draft.description,
      photos: draft.photos,
      voiceNote: old.voiceNote,
      budgetMin: draft.budgetMin,
      budgetMax: draft.budgetMax,
      isUrgent: draft.isUrgent,
      quotes: old.quotes,
      bookingId: old.bookingId,
    );
  }
}

class MockQuoteRepository implements QuoteRepository {
  MockQuoteRepository(this._m);
  final MockMarket _m;

  @override
  Future<JobPost> job(String jobId) async {
    await _wait(250);
    final area = _m.user?.area ?? MockData.city;
    final jobs = MockData.jobs(_m.accounts.startedAt, area: area);
    return jobs.firstWhere(
      (j) => j.id == jobId,
      orElse: () => throw const AppException('That job is no longer open.'),
    );
  }

  @override
  Future<Quote?> myQuoteOn(String jobId) async {
    final mine = _m.quotesOf(_m.uid).where((q) => q.jobId == jobId);
    return mine.isEmpty ? null : mine.first;
  }

  @override
  Future<Quote> send(String jobId, QuoteDraft draft) async {
    final user = _m.user;
    if (user == null) throw const AppException('Sign in to send a quote.');
    await _wait(700);
    final title = _m
            .quoteRequestsOf(user.id)
            .where((j) => j.id == jobId)
            .firstOrNull
            ?.title ??
        MockData.jobs(_m.accounts.startedAt)
            .where((j) => j.id == jobId)
            .firstOrNull
            ?.title;
    final me = _m.artisans().where((a) => a.id == 'a_emeka').first;
    final quote = Quote(
      id: 'q_${_m.now.millisecondsSinceEpoch}',
      jobId: jobId,
      artisan: me,
      price: draft.price,
      priceMax: draft.priceMax,
      message: draft.message,
      canStartAt: draft.canStartAt,
      sentAt: _m.now,
      jobTitle: title,
    );
    _m.quotesOf(user.id).insert(0, quote);
    _m.quoteRequestsOf(user.id).removeWhere((j) => j.id == jobId);
    return quote;
  }

  @override
  Future<List<Quote>> mine() async {
    await _wait(300);
    return List.of(_m.quotesOf(_m.uid));
  }

  @override
  Future<void> withdraw(String quoteId) async {
    await _wait(300);
    final quotes = _m.quotesOf(_m.uid);
    final i = quotes.indexWhere((q) => q.id == quoteId);
    if (i >= 0) quotes[i] = quotes[i].withStatus(QuoteStatus.withdrawn);
  }

  @override
  Future<List<ClientJob>> quoteRequests() async {
    await _wait(300);
    return List.of(_m.quoteRequestsOf(_m.uid));
  }
}

// ---------------------------------------------------------------- chat

class MockChatRepository implements ChatRepository {
  MockChatRepository(this._m);
  final MockMarket _m;

  @override
  Future<List<Conversation>> conversations() async {
    await _wait(300);
    final list = [for (final c in _m.convosOf(_m.uid).values) c.view]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  @override
  Future<Conversation> byId(String conversationId) async =>
      _m.convo(conversationId).view;

  @override
  Future<Conversation> withArtisan(String artisanId) async {
    await _wait(200);
    final existing =
        _m.convosOf(_m.uid).values.where((c) => c.meta.artisanId == artisanId);
    if (existing.isNotEmpty) return existing.first.view;
    final a = _m.artisan(artisanId);
    return _m
        .startConvo(Conversation(
          id: 'c_$artisanId',
          title: a.name,
          photo: a.photo,
          subtitle: a.trade,
          artisanId: artisanId,
          online: a.isAvailableToday,
          updatedAt: _m.now,
        ))
        .view;
  }

  @override
  Future<Conversation> forBooking(String bookingId) async {
    await _wait(200);
    final existing =
        _m.convosOf(_m.uid).values.where((c) => c.meta.bookingId == bookingId);
    if (existing.isNotEmpty) return existing.first.view;
    final b = _m.booking(bookingId);
    return _m
        .startConvo(Conversation(
          id: b.conversationId ?? 'c_$bookingId',
          title: b.counterpartName,
          photo: b.counterpartPhoto,
          subtitle: b.serviceName,
          bookingId: bookingId,
          artisanId: b.artisanId,
          updatedAt: _m.now,
        ))
        .view;
  }

  @override
  Future<Conversation> withSupport() async {
    await _wait(200);
    final existing = _m.convosOf(_m.uid)['c_support'];
    if (existing != null) return existing.view;
    final c = _m.startConvo(Conversation(
      id: 'c_support',
      title: 'RijHub support',
      subtitle: 'Usually replies in 10 minutes',
      online: true,
      updatedAt: _m.now,
    ));
    _m.post(
        'c_support',
        _m.message(
          fromMe: false,
          text:
              'Hi${_m.user == null ? '' : ' ${_m.user!.firstName}'}! How can we help today? Tell us about a booking, a payment or anything else.',
          read: true,
        ));
    return c.view;
  }

  @override
  Stream<List<ChatMessage>> watch(String conversationId) async* {
    final c = _m.convo(conversationId);
    yield List.unmodifiable(c.messages);
    yield* c.controller.stream;
  }

  @override
  Future<void> send(
    String conversationId, {
    String? text,
    VoiceNote? voiceNote,
    String? photo,
  }) async {
    final kind = voiceNote != null
        ? MessageKind.voice
        : (photo != null ? MessageKind.photo : MessageKind.text);
    _m.post(
        conversationId,
        _m.message(
          fromMe: true,
          kind: kind,
          text: text,
          voiceNote: voiceNote,
          photo: photo,
        ));
    final owner = _m.uid;
    final fromArtisan = _m.user?.role == UserRole.client;
    _m.later(const Duration(milliseconds: 2600), () {
      _m.post(
          conversationId,
          _m.message(
            fromMe: false,
            text: conversationId == 'c_support'
                ? "Thanks, we've got your message. Someone from our team will reply here shortly. We're open Monday to Friday 9 AM–6 PM, Saturday 10 AM–4 PM."
                : MarketData.replyTo(text ?? '', fromArtisan: fromArtisan),
          ),
          forUser: owner);
    });
  }

  @override
  Future<void> markRead(String conversationId) async {
    final c = _m.convosOf(_m.uid)[conversationId];
    if (c == null || c.unread == 0) return;
    c.unread = 0;
    for (var i = 0; i < c.messages.length; i++) {
      final m = c.messages[i];
      if (!m.read) {
        c.messages[i] = ChatMessage(
          id: m.id,
          fromMe: m.fromMe,
          kind: m.kind,
          text: m.text,
          voiceNote: m.voiceNote,
          photo: m.photo,
          sentAt: m.sentAt,
        );
      }
    }
    _m.chatUnreadStream(_m.uid).add(_m.chatUnread(_m.uid));
  }

  @override
  Stream<int> unreadCount() async* {
    final owner = _m.uid;
    yield _m.chatUnread(owner);
    yield* _m.chatUnreadStream(owner).stream;
  }
}

// ---------------------------------------------------------------- notices

class MockNoticeRepository implements NoticeRepository {
  MockNoticeRepository(this._m);
  final MockMarket _m;

  @override
  Future<List<AppNotice>> notices() async {
    await _wait(300);
    return List.of(_m.noticesOf(_m.uid));
  }

  @override
  Future<void> markAllRead() async {
    final list = _m.noticesOf(_m.uid);
    for (var i = 0; i < list.length; i++) {
      list[i] = list[i].markRead();
    }
    _m.noticeStream(_m.uid).add(0);
  }

  @override
  Future<void> markRead(String noticeId) async {
    final list = _m.noticesOf(_m.uid);
    final i = list.indexWhere((n) => n.id == noticeId);
    if (i >= 0) list[i] = list[i].markRead();
    _m.noticeStream(_m.uid).add(_m.noticeUnread(_m.uid));
  }

  @override
  Stream<int> unreadCount() async* {
    final owner = _m.uid;
    yield _m.noticeUnread(owner);
    yield* _m.noticeStream(owner).stream;
  }

  @override
  Future<NotificationPrefs> prefs() async =>
      _m._prefs[_m.uid] ?? const NotificationPrefs();

  @override
  Future<void> savePrefs(NotificationPrefs prefs) async {
    await _wait(200);
    _m._prefs[_m.uid] = prefs;
  }
}

// ---------------------------------------------------------------- money

class MockWalletRepository implements WalletRepository {
  MockWalletRepository(this._m);
  final MockMarket _m;

  @override
  Future<WalletSummary> summary() async {
    await _wait(350);
    final id = _m.uid;
    final role = _m.user?.role ?? UserRole.client;
    final upcoming = _m.bookingsOf(id, role).where((b) => !b.isOver);
    final held = upcoming
        .where(
            (b) => role == UserRole.artisan || b.payment == PaymentState.held)
        .fold<int>(
            0,
            (s, b) =>
                s + (role == UserRole.artisan ? (b.price ?? 0) : b.total));
    final tx = _m.txOf(id);
    return WalletSummary(
      available: _m.availableOf(id),
      held: held,
      earnedTotal: id == MarketData.emeka ? 1284500 : 0,
      paidTotal: tx
          .where((t) => t.kind == TxKind.payment)
          .fold(0, (s, t) => s + t.amount),
    );
  }

  @override
  Future<List<WalletTx>> transactions() async {
    await _wait(350);
    return List.of(_m.txOf(_m.uid))..sort((a, b) => b.at.compareTo(a.at));
  }

  @override
  Future<PayoutAccount?> payoutAccount() async {
    await _wait(200);
    return _m.payoutOf(_m.uid);
  }

  @override
  Future<List<Bank>> banks() async {
    await _wait(250);
    return MarketData.banks;
  }

  @override
  Future<String> resolveAccount(Bank bank, String accountNumber) async {
    await _wait(900);
    if (accountNumber.length != 10 || accountNumber.startsWith('000')) {
      throw const AppException(
        "We couldn't find that account. Check the number and the bank.",
      );
    }
    final user = _m.user;
    return (user?.fullName ?? 'Account holder').toUpperCase();
  }

  @override
  Future<PayoutAccount> savePayoutAccount(
      Bank bank, String accountNumber) async {
    final name = await resolveAccount(bank, accountNumber);
    final account = PayoutAccount(
        bank: bank, accountNumber: accountNumber, accountName: name);
    _m._payout[_m.uid] = account;
    return account;
  }

  @override
  Future<WalletTx> withdraw(int amount) async {
    final id = _m.uid;
    final account = _m.payoutOf(id);
    if (account == null) throw const AppException('Add a bank account first.');
    if (amount <= 0 || amount > _m.availableOf(id)) {
      throw const AppException("That's more than you have available.");
    }
    await _wait(900);
    _m._available[id] = _m.availableOf(id) - amount;
    final tx = WalletTx(
      id: 't_${_m.now.millisecondsSinceEpoch}',
      kind: TxKind.payout,
      amount: amount,
      status: TxStatus.pending,
      at: _m.now,
      title: 'To ${account.bank.name} ${account.masked}',
      reference: 'PO-${_m.code()}',
    );
    final list = _m.txOf(id)..insert(0, tx);
    _m.later(const Duration(seconds: 3), () {
      final i = list.indexWhere((t) => t.id == tx.id);
      if (i < 0) return;
      list[i] = WalletTx(
        id: tx.id,
        kind: tx.kind,
        amount: tx.amount,
        status: TxStatus.successful,
        at: tx.at,
        title: tx.title,
        reference: tx.reference,
      );
      _m.notify(
          _m.notice(
            NoticeKind.payment,
            'Payout sent: ₦$amount',
            'To ${account.bank.name} ${account.masked}.',
            route: '/account/wallet',
          ),
          forUser: id);
    });
    return tx;
  }
}

// ---------------------------------------------------------------- account

class MockAccountRepository implements AccountRepository {
  MockAccountRepository(this._m);
  final MockMarket _m;

  @override
  Future<AppUser> updateProfile({
    required String firstName,
    required String lastName,
    String? email,
    String? photo,
  }) async {
    final user = _m.user;
    if (user == null) throw const AppException('Sign in first.');
    await _wait(600);
    final updated = AppUser(
      id: user.id,
      firstName: firstName,
      lastName: lastName,
      phone: user.phone,
      role: user.role,
      email: email,
      homeArea: user.homeArea,
      city: user.city,
      photo: photo ?? user.photo,
      tradeIds: user.tradeIds,
    );
    _m.accounts.add(updated);
    _m.accounts.current = updated;
    return updated;
  }

  @override
  Future<List<SavedPlace>> places() async {
    await _wait(250);
    return List.of(_m.placesOf(_m.uid));
  }

  @override
  Future<SavedPlace> savePlace(SavedPlace place) async {
    await _wait(400);
    final list = _m.placesOf(_m.uid);
    final i = list.indexWhere((p) => p.id == place.id);
    if (i >= 0) {
      list[i] = place;
    } else {
      list.add(place);
    }
    return place;
  }

  @override
  Future<void> deletePlace(String placeId) async {
    await _wait(250);
    _m.placesOf(_m.uid).removeWhere((p) => p.id == placeId);
  }

  @override
  Future<void> deleteAccount() async {
    await _wait(900);
    final user = _m.user;
    if (user != null) _m.accounts.remove(user.phone);
  }

  @override
  Future<AppUser> switchRole(UserRole to,
      {List<String> tradeIds = const []}) async {
    final user = _m.user;
    if (user == null) throw const AppException('Sign in first.');
    await _wait(700);
    final updated = AppUser(
      id: user.id,
      firstName: user.firstName,
      lastName: user.lastName,
      phone: user.phone,
      role: to,
      email: user.email,
      homeArea: user.homeArea,
      city: user.city,
      photo: user.photo,
      tradeIds: to == UserRole.artisan
          ? (tradeIds.isEmpty ? user.tradeIds : List.unmodifiable(tradeIds))
          : user.tradeIds,
    );
    _m.accounts.add(updated);
    _m.accounts.current = updated;
    return updated;
  }
}

// ---------------------------------------------------------------- artisan setup

class MockArtisanSetupRepository implements ArtisanSetupRepository {
  MockArtisanSetupRepository(this._m);
  final MockMarket _m;

  String get _artisanId =>
      _m.uid == MarketData.emeka ? 'a_emeka' : 'a_${_m.uid}';

  ArtisanProfile _current() {
    final saved = _m._myProfiles[_artisanId];
    if (saved != null) return saved;
    final user = _m.user;
    if (_m.uid == MarketData.emeka) {
      return MarketData.profileFor(_m.artisan('a_emeka'), _m.now);
    }
    final trade =
        user?.tradeIds.isNotEmpty == true ? user!.tradeIds.first : 'electrical';
    final category = MockData.categories.firstWhere((c) => c.id == trade);
    return ArtisanProfile(
      artisan: Artisan(
        id: _artisanId,
        name: user?.fullName ?? 'You',
        trade: category.artisanPlural?.replaceAll(RegExp(r's$'), '') ??
            category.name,
        categoryId: trade,
        area: user?.area ?? MockData.city,
        distanceKm: 0,
        rating: 0,
        reviewCount: 0,
        jobsCompleted: 0,
        startingPrice: 0,
        photo: user?.photo,
      ),
      about: '',
      experienceYears: 0,
      services: const [],
      work: const [],
      ratings: const RatingSummary(average: 0, count: 0, byStars: {}),
      reviews: const [],
      serviceArea: ServiceArea(area: user?.area ?? MockData.city, radiusKm: 10),
      hours: WorkingHours.usual,
      joinedOn: _m.now,
    );
  }

  void _save(ArtisanProfile p) => _m._myProfiles[_artisanId] = p;

  ArtisanProfile _copy(
    ArtisanProfile p, {
    String? about,
    int? experienceYears,
    List<ServiceOffer>? services,
    List<WorkPhoto>? work,
    ServiceArea? serviceArea,
    WorkingHours? hours,
    String? businessName,
    List<String>? certifications,
  }) =>
      ArtisanProfile(
        artisan: p.artisan,
        about: about ?? p.about,
        experienceYears: experienceYears ?? p.experienceYears,
        businessName: businessName ?? p.businessName,
        certifications: certifications ?? p.certifications,
        services: services ?? p.services,
        work: work ?? p.work,
        ratings: p.ratings,
        reviews: p.reviews,
        serviceArea: serviceArea ?? p.serviceArea,
        hours: hours ?? p.hours,
        joinedOn: p.joinedOn,
        responseRate: p.responseRate,
        languages: p.languages,
      );

  @override
  Future<ArtisanProfile> myProfile() async {
    await _wait(350);
    return _current();
  }

  @override
  Future<void> saveAbout({
    required String about,
    required int experienceYears,
    String? businessName,
    List<String> certifications = const [],
  }) async {
    await _wait(500);
    _save(_copy(
      _current(),
      about: about,
      experienceYears: experienceYears,
      // An empty name clears it.
      businessName: businessName ?? '',
      certifications: certifications,
    ));
  }

  @override
  Future<ServiceOffer> saveService(ServiceOffer service) async {
    await _wait(450);
    final p = _current();
    final list = List.of(p.services);
    final i = list.indexWhere((s) => s.id == service.id);
    if (i >= 0) {
      list[i] = service;
    } else {
      list.add(service);
    }
    _save(_copy(p, services: list));
    return service;
  }

  @override
  Future<void> deleteService(String serviceId) async {
    await _wait(300);
    final p = _current();
    _save(_copy(p,
        services: p.services.where((s) => s.id != serviceId).toList()));
  }

  @override
  Future<WorkPhoto> addWorkPhoto(String image, {String? caption}) async {
    await _wait(700);
    final p = _current();
    final photo = WorkPhoto(
      id: 'w_${_m.now.millisecondsSinceEpoch}',
      image: image,
      caption: caption,
    );
    _save(_copy(p, work: [photo, ...p.work]));
    return photo;
  }

  @override
  Future<void> deleteWorkPhoto(String photoId) async {
    await _wait(300);
    final p = _current();
    _save(_copy(p, work: p.work.where((w) => w.id != photoId).toList()));
  }

  @override
  Future<void> saveServiceArea(ServiceArea area) async {
    await _wait(400);
    _save(_copy(_current(), serviceArea: area));
  }

  @override
  Future<void> saveHours(WorkingHours hours) async {
    await _wait(400);
    _save(_copy(_current(), hours: hours));
  }

  @override
  Future<Verification> verification() async {
    await _wait(250);
    final id = _m.uid;
    return _m._verification[id ?? ''] ??
        (id == MarketData.emeka
            ? Verification(
                state: VerificationState.verified,
                updatedAt: DateTime(2025, 3, 4))
            : const Verification(state: VerificationState.notStarted));
  }

  @override
  Future<Verification> submitVerification({
    required String nin,
    required String selfie,
  }) async {
    await _wait(1200);
    final id = _m.uid ?? '';
    if (nin.length != 11) {
      throw const AppException('A NIN has 11 digits. Check it and try again.');
    }
    final pending =
        Verification(state: VerificationState.pending, updatedAt: _m.now);
    _m._verification[id] = pending;
    _m.later(const Duration(seconds: 6), () {
      _m._verification[id] =
          Verification(state: VerificationState.verified, updatedAt: _m.now);
      _m.notify(
          _m.notice(
            NoticeKind.account,
            "You're verified",
            'Clients now see the verified badge on your profile, and they can book you.',
            route: '/account/verification',
          ),
          forUser: id);
    });
    return pending;
  }
}

class MockSupportRepository implements SupportRepository {
  @override
  Future<List<FaqItem>> faqs() async {
    await _wait(200);
    return MarketData.faqs;
  }
}
