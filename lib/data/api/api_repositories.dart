import '../models/models.dart';
import '../repositories/repositories.dart';
import 'api_client.dart';
import 'api_codec.dart';
import 'api_context.dart';
import 'phone_verifier.dart';
import 'uploads.dart';

/// The repositories, backed by the RijHub API. Screens see the same
/// contracts as with sample data; only `AppDependencies.api` picks these.
/// Chat, notices, money, the account and the artisan's setup are in
/// `api_social.dart`.

// ---------------------------------------------------------------- signing in

class ApiAuthRepository implements AuthRepository {
  ApiAuthRepository(this._c, {PhoneVerifier phone = const NoPhoneVerifier()})
      : _phone = phone;

  final ApiContext _c;

  /// Texts codes when the API leaves that to the app (Firebase).
  final PhoneVerifier _phone;

  /// Marks a code texted by [_phone]; the rest is its text's name.
  static const _byPhone = 'firebase:';

  /// A number that's verified but has no account yet, waiting for its
  /// details: its sign-up token.
  final _signupTokens = <String, String>{};

  /// Proof for numbers the phone confirmed by itself, until it's used.
  final _proofs = <String, String>{};

  /// The push token this device registered, to drop on signing out.
  String? deviceToken;

  /// Called on signing in, and on launch with a saved sign-in: the moment
  /// this phone registers for push notifications.
  void Function()? onAccount;

  /// Tells the server this phone's push token, so notifications reach it.
  Future<void> registerDevice(String token, {required String platform}) async {
    await _c.api.post('/v1/me/devices', {'token': token, 'platform': platform});
    deviceToken = token;
  }

  @override
  Future<OtpChallenge> requestCode(String phone,
          {OtpChannel channel = OtpChannel.sms}) =>
      _auth(() async {
        final j = asMap(await _c.api
            .post('/v1/auth/otp', {'phone': phone, 'channel': channel.name}));
        final number = j['phone']! as String;
        final resendAt = DateTime.parse(j['resend_at']! as String).toLocal();
        if (j['via'] == 'firebase') {
          // The API leaves the text to the app.
          final sent = await _phone.send(number);
          final proof = sent.proof;
          if (proof != null) _proofs[number] = proof;
          return OtpChallenge(
            phone: number,
            channel: OtpChannel.sms,
            requestId: '$_byPhone${sent.verificationId ?? ''}',
            resendAvailableAt: resendAt,
            verified: proof != null,
          );
        }
        return OtpChallenge(
          phone: number,
          channel:
              j['channel'] == 'whatsapp' ? OtpChannel.whatsapp : OtpChannel.sms,
          requestId: number,
          resendAvailableAt: resendAt,
        );
      });

  @override
  Future<VerifyResult> verifyCode(OtpChallenge challenge, String code) =>
      _auth(() async {
        final Json j;
        if (challenge.requestId.startsWith(_byPhone)) {
          final proof = challenge.verified
              ? _proofs.remove(challenge.phone)
              : await _phone.confirm(
                  challenge.requestId.substring(_byPhone.length), code);
          if (proof == null) {
            throw const AuthException(
                'That took a while. Ask for a new code to carry on.');
          }
          j = asMap(
              await _c.api.post('/v1/auth/firebase', {'id_token': proof}));
        } else {
          j = asMap(await _c.api.post(
              '/v1/auth/verify', {'phone': challenge.phone, 'code': code}));
        }
        if (j['status'] == 'new') {
          _signupTokens[challenge.phone] = j['signup_token']! as String;
          return const VerifyResult();
        }
        await _c.api.saveTokens(j['tokens']);
        return VerifyResult(user: userFrom(asMap(j['user'])));
      });

  @override
  Future<AppUser> createAccount({
    required String phone,
    required UserRole role,
    required String firstName,
    required String lastName,
    String? email,
    String? area,
    List<String> tradeIds = const [],
  }) =>
      _auth(() async {
        final token = _signupTokens[phone];
        if (token == null) {
          throw const AuthException(
              'That took a while. Ask for a new code to carry on.');
        }
        final j = asMap(await _c.api.post('/v1/auth/signup', {
          'signup_token': token,
          'first_name': firstName,
          'last_name': lastName,
          'role': role.name,
          if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
          'area': area,
          'trade_ids': tradeIds.take(3).toList(),
        }));
        await _c.api.saveTokens(j['tokens']);
        _signupTokens.remove(phone);
        return userFrom(asMap(j['user']));
      });

  @override
  void useAccount(AppUser user) {
    _c.live.start();
    _c.changed(ApiContext.everything);
    onAccount?.call();
  }

  @override
  Future<void> signOut() async {
    _c.live.stop();
    final device = deviceToken;
    if (device != null) {
      try {
        await _c.api.delete('/v1/me/devices/${Uri.encodeComponent(device)}');
      } on Object {
        // Offline: the token moves to whoever signs in next anyway.
      }
      deviceToken = null;
    }
    await _c.api.tokens.clear();
    _c.changed(ApiContext.everything);
  }

  Future<T> _auth<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on ApiException catch (e) {
      throw AuthException(e.message);
    }
  }
}

// ---------------------------------------------------------------- reference data

class ApiCatalogRepository implements CatalogRepository {
  ApiCatalogRepository(this._c);

  final ApiContext _c;
  List<ServiceCategory>? _trades;
  List<String>? _areas;
  List<PriceGuideItem>? _guide;

  @override
  Future<List<ServiceCategory>> categories() async => _trades ??= [
        for (final j in asList(await _c.api.get('/v1/catalog/trades')))
          tradeFrom(j),
      ];

  @override
  Future<List<String>> areas() async => _areas ??= [
        for (final j in asList(await _c.api.get('/v1/catalog/areas')))
          j['name']! as String,
      ];

  @override
  Future<List<PriceGuideItem>> priceGuide() async => _guide ??= [
        for (final j in asList(await _c.api.get('/v1/catalog/price-guide')))
          guideFrom(j),
      ];

  @override
  Future<MarketStats> stats() async =>
      statsFrom(asMap(await _c.api.get('/v1/catalog/stats')));
}

class ApiArtisanRepository implements ArtisanRepository {
  ApiArtisanRepository(this._c);

  final ApiContext _c;

  @override
  Future<List<Artisan>> topRatedNearby({
    required String area,
    String? categoryId,
    bool freeNow = false,
    int limit = 6,
  }) async =>
      [
        for (final j
            in asList(await _c.api.get('/v1/artisans/top-rated', query: {
          'area': area,
          'category_id': categoryId,
          'free_now': freeNow,
          'limit': limit,
        })))
          artisanFrom(j),
      ];

  @override
  Future<List<HiredArtisan>> hiredBefore() => _c.forMember(() async {
        try {
          return [
            for (final j in asList(await _c.api.get('/v1/me/hired')))
              hiredFrom(j)
          ];
        } on ApiException catch (e) {
          if (e.code == 'clients_only') return const <HiredArtisan>[];
          rethrow;
        }
      }, const <HiredArtisan>[]);
}

class ApiJobRepository implements JobRepository {
  ApiJobRepository(this._c);

  final ApiContext _c;

  @override
  Future<List<JobPost>> openJobsNearby({
    required String area,
    Set<String>? categoryIds,
    int limit = 10,
  }) async =>
      [
        for (final j in asList(await _c.api.get('/v1/jobs/open', query: {
          'area': area,
          'category_ids': (categoryIds == null || categoryIds.isEmpty)
              ? null
              : categoryIds.join(','),
          'limit': limit,
        })))
          jobPostFrom(j),
      ];

  @override
  Future<int> openJobsThisWeek({String? area, String? categoryId}) async =>
      (await demand(area: area, categoryId: categoryId)).openThisWeek;

  @override
  Future<JobDemand> demand({String? area, String? categoryId}) async =>
      demandFrom(asMap(await _c.api.get('/v1/jobs/demand',
          query: {'area': area, 'category_id': categoryId})));
}

class ApiBookingRepository implements BookingRepository {
  ApiBookingRepository(this._c);

  final ApiContext _c;

  @override
  Future<List<Booking>> upcoming({required UserRole as}) => _c.forMember(
        () async => [
          for (final j in asList(
              await _c.api.get('/v1/bookings', query: {'scope': 'upcoming'})))
            bookingFrom(j),
        ],
        const <Booking>[],
      );
}

class ApiArtisanDashboardRepository implements ArtisanDashboardRepository {
  ApiArtisanDashboardRepository(this._c);

  final ApiContext _c;

  /// What a guest looking at the work side sees: the steps to getting
  /// booked, none done yet.
  static const _guest = ArtisanDashboard(
    isAvailable: false,
    earningsThisWeek: 0,
    earningsLastWeek: 0,
    availableBalance: 0,
    jobsThisWeek: 0,
    rating: 0,
    reviewCount: 0,
    responseRate: 0,
    setupSteps: [
      SetupStep(
          id: 'services',
          label: 'Add your services and prices',
          done: false,
          reason: 'Clients book from your prices',
          effort: '2 minutes',
          blocksBookings: true),
      SetupStep(
          id: 'identity',
          label: 'Check your ID',
          done: false,
          reason: 'Clients only book ID-checked artisans',
          effort: '2 minutes',
          blocksBookings: true),
      SetupStep(
          id: 'work_photos',
          label: 'Add photos of your work',
          done: false,
          reason: 'Clients can see what you do before they book',
          effort: '1 minute'),
    ],
  );

  @override
  Future<ArtisanDashboard> dashboard() => _c.forMember(
      () async =>
          dashboardFrom(asMap(await _c.api.get('/v1/artisan/dashboard'))),
      _guest);

  @override
  Future<void> setAvailability(bool available, {DateTime? busyUntil}) async {
    await _c.api.put('/v1/artisan/availability', {
      'status': available ? 'available' : (busyUntil != null ? 'busy' : 'off'),
      if (!available && busyUntil != null) 'busy_until': iso(busyUntil),
    });
  }

  @override
  Future<List<DirectRequest>> requests() => _c.forMember(
        () async => [
          for (final j in asList(await _c.api.get('/v1/artisan/requests')))
            requestFrom(j),
        ],
        const <DirectRequest>[],
      );

  @override
  Future<Booking?> respond(String requestId, {required bool accept}) async {
    try {
      if (accept) {
        return bookingFrom(
            asMap(await _c.api.post('/v1/bookings/$requestId/accept')));
      }
      await _c.api.post('/v1/bookings/$requestId/decline');
      return null;
    } on ApiException catch (e) {
      if (e.code == 'request_expired') throw RequestExpiredException(e.message);
      // Answered already (here or on another phone): nothing to do.
      if (e.code == 'booking_changed') return null;
      rethrow;
    }
  }
}

// ---------------------------------------------------------------- asking

class ApiAskRepository implements AskRepository {
  ApiAskRepository(this._c);

  final ApiContext _c;

  @override
  Future<String> transcribe(VoiceNote note) async {
    final url = await _c.uploads.upload(note.path, UploadKind.voice);
    if (url == null) {
      throw const AppException(
          "I can't listen to voice notes yet. Type a few words instead.");
    }
    final j =
        asMap(await _c.api.post('/v1/ask/transcribe', {'audio_url': url}));
    return j['text']! as String;
  }

  @override
  Future<TradeReading> trades(String text) async {
    final j = asMap(await _c.api.post('/v1/ask/trades', {'text': text}));
    return TradeReading(
      tradeIds: [
        for (final t in (j['trade_ids'] as List?) ?? const []) t as String
      ],
      other: j['other'] as String?,
    );
  }

  @override
  Future<Triage> triage(AskInput input, {String? area}) async =>
      triageFrom(asMap(await _c.api.post('/v1/ask/triage', {
        'text': input.text?.trim().isEmpty ?? true ? null : input.text!.trim(),
        'heard': input.voiceNote?.heard,
        'area': area,
      })));
}

// ---------------------------------------------------------------- finding artisans

class ApiDirectoryRepository implements DirectoryRepository {
  ApiDirectoryRepository(this._c);

  final ApiContext _c;
  Set<String>? _savedIds;

  @override
  Future<List<Artisan>> search({
    required String area,
    String? query,
    String? categoryId,
    bool freeNow = false,
    bool verifiedOnly = false,
    ArtisanSort sort = ArtisanSort.recommended,
    int limit = 30,
  }) async =>
      // Everyone listed is ID-checked, so [verifiedOnly] changes nothing.
      [
        for (final j in asList(await _c.api.get('/v1/artisans', query: {
          'area': area,
          'q': (query == null || query.trim().isEmpty) ? null : query.trim(),
          'category_id': categoryId,
          'free_now': freeNow,
          'sort': sort.name,
          'limit': limit,
        })))
          artisanFrom(j),
      ];

  @override
  Future<ArtisanProfile> profile(String artisanId, {String? area}) async =>
      profileFrom(asMap(
          await _c.api.get('/v1/artisans/$artisanId', query: {'area': area})));

  @override
  Future<List<Review>> reviews(String artisanId) async => [
        for (final j
            in asList(await _c.api.get('/v1/artisans/$artisanId/reviews')))
          reviewFrom(j)
      ];

  @override
  Future<List<Artisan>> saved({String? area}) => _c.forMember(
        () async => [
          for (final j in asList(
              await _c.api.get('/v1/me/saved', query: {'area': area})))
            artisanFrom(j),
        ],
        const <Artisan>[],
      );

  @override
  Future<Set<String>> savedIds() => _c.forMember(() async {
        final ids = {
          for (final id in (await _c.api.get('/v1/me/saved/ids'))! as List)
            id as String
        };
        _savedIds = ids;
        return ids;
      }, const <String>{});

  @override
  Future<bool> toggleSaved(String artisanId) async {
    final ids = _savedIds ?? await savedIds();
    if (ids.contains(artisanId)) {
      await _c.api.delete('/v1/me/saved/$artisanId');
      _savedIds = {...ids}..remove(artisanId);
      return false;
    }
    await _c.api.put('/v1/me/saved/$artisanId');
    _savedIds = {...ids, artisanId};
    return true;
  }
}

// ---------------------------------------------------------------- booking

class ApiBookingFlowRepository implements BookingFlowRepository {
  ApiBookingFlowRepository(this._c);

  final ApiContext _c;

  Future<Booking> _act(String id, String action, [Json? body]) async =>
      bookingFrom(asMap(
          await _c.api.post('/v1/bookings/$id/$action', body ?? const {})));

  @override
  Future<PriceBreakdown> price(ServiceOffer service) async {
    final total = service.parts.isEmpty
        ? service.price
        : service.parts.fold(0, (sum, s) => sum + s.price);
    return priceFrom(
        asMap(await _c.api.get('/v1/bookings/fee', query: {'price': total})));
  }

  @override
  Future<Booking> request(BookingDraft draft) async {
    final photos = await _c.uploads.uploadAll(draft.photos, UploadKind.problem);
    final note = draft.voiceNote;
    final voice = note == null
        ? null
        : await _c.uploads.upload(note.path, UploadKind.voice);
    final created = asMap(await _c.api.post('/v1/bookings', {
      'artisan_id': draft.artisan.id,
      'services': bookedServices(draft.service),
      'window': windowTo(draft.window),
      'area': draft.area,
      'landmark': draft.landmark,
      'notes': draft.notes,
      'photos': photos,
      if (note != null && voice != null) 'voice_note': voiceTo(note, voice),
    }));
    return bookingFrom(await _c.pay(created));
  }

  @override
  Future<Booking> byId(String bookingId) async =>
      bookingFrom(asMap(await _c.api.get('/v1/bookings/$bookingId')));

  @override
  Future<List<Booking>> past({required UserRole as}) => _c.forMember(
        () async => [
          for (final j in asList(
              await _c.api.get('/v1/bookings', query: {'scope': 'past'})))
            bookingFrom(j),
        ],
        const <Booking>[],
      );

  @override
  Future<Booking> cancel(String bookingId, {required String reason}) =>
      _act(bookingId, 'cancel', {'reason': reason});

  @override
  Future<Booking> reschedule(String bookingId, DateTime to) =>
      _act(bookingId, 'reschedule', {'start': iso(to)});

  @override
  Future<Booking> confirmDone(String bookingId) => _act(bookingId, 'confirm');

  @override
  Future<Booking> review(String bookingId,
          {required int rating, String? text}) =>
      _act(bookingId, 'review', {
        'rating': rating,
        if (text != null && text.trim().isNotEmpty) 'text': text.trim(),
      });

  @override
  Future<Booking> onMyWay(String bookingId) => _act(bookingId, 'on-my-way');

  @override
  Future<Booking> start(String bookingId, String code) =>
      _act(bookingId, 'start', {'code': code});

  @override
  Future<Booking> finish(String bookingId) => _act(bookingId, 'finish');
}

// ---------------------------------------------------------------- posted jobs

class ApiClientJobRepository implements ClientJobRepository {
  ApiClientJobRepository(this._c);

  final ApiContext _c;

  Future<Json> _jobBody(JobDraft d, {bool withVoice = true}) async {
    final photos = await _c.uploads.uploadAll(d.photos, UploadKind.problem);
    final note = d.voiceNote;
    final voice = (withVoice && note != null)
        ? await _c.uploads.upload(note.path, UploadKind.voice)
        : null;
    return {
      'title': d.title,
      'category_id': d.categoryId,
      'area': d.area,
      'landmark': d.landmark,
      'description': d.description,
      'photos': photos,
      if (note != null && voice != null) 'voice_note': voiceTo(note, voice),
      'budget_min': d.budgetMin,
      'budget_max': d.budgetMax,
      'is_urgent': d.isUrgent,
    };
  }

  @override
  Future<ClientJob> post(JobDraft draft, {String? toArtisanId}) async =>
      clientJobFrom(asMap(await _c.api.post('/v1/jobs', {
        ...await _jobBody(draft),
        if (toArtisanId != null) 'to_artisan_id': toArtisanId,
      })));

  @override
  Future<List<ClientJob>> mine() => _c.forMember(
        () async => [
          for (final j in asList(await _c.api.get('/v1/jobs/mine')))
            clientJobFrom(j)
        ],
        const <ClientJob>[],
      );

  @override
  Future<ClientJob> byId(String jobId) async =>
      clientJobFrom(asMap(await _c.api.get('/v1/jobs/$jobId')));

  @override
  Future<Booking> accept(String jobId, String quoteId,
      {required TimeWindow window, int? price}) async {
    final created =
        asMap(await _c.api.post('/v1/jobs/$jobId/quotes/$quoteId/accept', {
      'window': windowTo(window),
      if (price != null) 'price': price,
    }));
    return bookingFrom(await _c.pay(created));
  }

  @override
  Future<ClientJob> decline(String jobId, String quoteId) async =>
      clientJobFrom(
          asMap(await _c.api.post('/v1/jobs/$jobId/quotes/$quoteId/decline')));

  @override
  Future<ClientJob> close(String jobId) async =>
      clientJobFrom(asMap(await _c.api.post('/v1/jobs/$jobId/close')));

  @override
  Future<ClientJob> update(String jobId, JobDraft draft) async =>
      clientJobFrom(asMap(await _c.api
          .patch('/v1/jobs/$jobId', await _jobBody(draft, withVoice: false))));
}

// ---------------------------------------------------------------- quotes

class ApiQuoteRepository implements QuoteRepository {
  ApiQuoteRepository(this._c);

  final ApiContext _c;

  @override
  Future<JobPost> job(String jobId) async =>
      jobPostFrom(asMap(await _c.api.get('/v1/jobs/$jobId/public')));

  @override
  Future<Quote?> myQuoteOn(String jobId) => _c.forMember(() async {
        final j = await _c.api.get('/v1/jobs/$jobId/my-quote');
        return j == null ? null : quoteFrom(asMap(j));
      }, null);

  @override
  Future<Quote> send(String jobId, QuoteDraft draft) async =>
      quoteFrom(asMap(await _c.api.post('/v1/jobs/$jobId/quotes', {
        'price': draft.price,
        'price_max': draft.priceMax,
        'message': draft.message,
        if (draft.canStartAt != null) 'can_start_at': iso(draft.canStartAt!),
      })));

  @override
  Future<List<Quote>> mine() => _c.forMember(
        () async => [
          for (final j in asList(await _c.api.get('/v1/quotes/mine')))
            quoteFrom(j)
        ],
        const <Quote>[],
      );

  @override
  Future<void> withdraw(String quoteId) async =>
      _c.api.delete('/v1/quotes/$quoteId');

  @override
  Future<List<ClientJob>> quoteRequests() => _c.forMember(
        () async => [
          for (final j
              in asList(await _c.api.get('/v1/artisan/quote-requests')))
            clientJobFrom(j),
        ],
        const <ClientJob>[],
      );
}
