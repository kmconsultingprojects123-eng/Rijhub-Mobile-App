import 'dart:math' as math;

import '../models/models.dart';

/// The RijHub API's JSON (snake_case, times in UTC) to the app's models
/// (times local) and back. Every mapping between the two lives here.

typedef Json = Map<String, Object?>;

Json asMap(Object? value) => (value! as Map).cast<String, Object?>();

List<Json> asList(Object? value) =>
    [for (final item in (value as List?) ?? const []) asMap(item)];

String _s(Json j, String key) => j[key]! as String;
String? _so(Json j, String key) => j[key] as String?;
int _i(Json j, String key) => (j[key]! as num).toInt();
int? _io(Json j, String key) => (j[key] as num?)?.toInt();
double _d(Json j, String key) => (j[key] as num?)?.toDouble() ?? 0;
bool _b(Json j, String key) => j[key] == true;
List<String> _strings(Object? value) =>
    [for (final item in (value as List?) ?? const []) item as String];

DateTime _t(Json j, String key) => DateTime.parse(j[key]! as String).toLocal();
DateTime? _to(Json j, String key) =>
    j[key] == null ? null : DateTime.parse(j[key]! as String).toLocal();

/// A time as the API takes it: UTC, ISO 8601.
String iso(DateTime time) => time.toUtc().toIso8601String();

// ---------------------------------------------------------------- people

AppUser userFrom(Json j) => AppUser(
      id: _s(j, 'id'),
      firstName: _s(j, 'first_name'),
      lastName: _s(j, 'last_name'),
      phone: _s(j, 'phone'),
      role: j['role'] == 'artisan' ? UserRole.artisan : UserRole.client,
      email: _so(j, 'email'),
      homeArea: _so(j, 'home_area'),
      city: _so(j, 'city') ?? 'Abuja',
      photo: _so(j, 'photo'),
      tradeIds: _strings(j['trade_ids']),
    );

GeoPoint? _geo(Object? value) {
  if (value == null) return null;
  final j = asMap(value);
  return GeoPoint(_d(j, 'lat'), _d(j, 'lng'));
}

// ---------------------------------------------------------------- catalog

ServiceCategory tradeFrom(Json j) => ServiceCategory(
      id: _s(j, 'id'),
      name: _s(j, 'name'),
      iconKey: _s(j, 'icon_key'),
      artisanPlural: _so(j, 'artisan_plural'),
    );

PriceGuideItem guideFrom(Json j) => PriceGuideItem(
      problem: _s(j, 'problem'),
      categoryId: _s(j, 'category_id'),
      minPrice: _i(j, 'min_price'),
      maxPrice: _i(j, 'max_price'),
      updatedOn: _t(j, 'updated_on'),
    );

MarketStats statsFrom(Json j) => MarketStats(
      verifiedArtisans: _i(j, 'verified_artisans'),
      averageRating: _d(j, 'average_rating'),
      cover: _so(j, 'cover'),
      faces: _strings(j['faces']),
    );

FaqItem faqFrom(Json j) => FaqItem(
      id: _s(j, 'id'),
      topic: _s(j, 'topic'),
      question: _s(j, 'question'),
      answer: _s(j, 'answer'),
    );

Triage triageFrom(Json j) => Triage(
      categoryId: _s(j, 'category_id'),
      serviceName: _s(j, 'service_name'),
      reply: _s(j, 'reply'),
      priceMin: _i(j, 'price_min'),
      priceMax: _i(j, 'price_max'),
      isUrgent: _b(j, 'is_urgent'),
      heard: _so(j, 'heard'),
      confident: j['confident'] != false,
      kind: _so(j, 'kind') ?? 'problem',
    );

// ---------------------------------------------------------------- artisans

Artisan artisanFrom(Json j) => Artisan(
      id: _s(j, 'id'),
      name: _s(j, 'name'),
      trade: _s(j, 'trade'),
      categoryId: _s(j, 'category_id'),
      area: _s(j, 'area'),
      distanceKm: _d(j, 'distance_km'),
      rating: _d(j, 'rating'),
      reviewCount: _io(j, 'review_count') ?? 0,
      jobsCompleted: _io(j, 'jobs_completed') ?? 0,
      startingPrice: _io(j, 'starting_price') ?? 0,
      isVerified: _b(j, 'is_verified'),
      isAvailableToday: _b(j, 'is_available_today'),
      nextFreeAt: _to(j, 'next_free_at'),
      replyMinutes: _io(j, 'reply_minutes'),
      photo: _so(j, 'photo'),
      coverPhoto: _so(j, 'cover_photo'),
      coverFocusX: _d(j, 'cover_focus_x'),
      coverFocusY: _d(j, 'cover_focus_y'),
      location: _geo(j['location']),
    );

HiredArtisan hiredFrom(Json j) => HiredArtisan(
      artisan: artisanFrom(asMap(j['artisan'])),
      serviceName: _s(j, 'service_name'),
      lastHiredOn: _t(j, 'last_hired_on'),
      yourRating: _io(j, 'your_rating'),
    );

ServiceOffer serviceFrom(Json j) => ServiceOffer(
      id: _s(j, 'id'),
      categoryId: _s(j, 'category_id'),
      name: _s(j, 'name'),
      price: _i(j, 'price'),
      priceMax: _io(j, 'price_max'),
      unit: _so(j, 'unit'),
    );

Json serviceTo(ServiceOffer s) => {
      'category_id': s.categoryId,
      'name': s.name,
      'price': s.price,
      'price_max': s.priceMax,
      'unit': s.unit,
    };

/// Whether [s] is one of the artisan's listed services (the API knows it
/// by id), rather than a problem the Ask conversation read ("ask_…"), one
/// the client described ("custom"), or several put together ("multi_…").
bool isListedService(ServiceOffer s) =>
    s.id != 'custom' && !s.id.startsWith('ask_') && !s.id.startsWith('multi_');

/// What the API needs to price or book [offer]: each service in it, by id
/// when it's listed, else by name and price.
List<Json> bookedServices(ServiceOffer offer) => [
      for (final s in offer.parts.isEmpty ? [offer] : offer.parts)
        isListedService(s)
            ? {'service_id': s.id}
            : {'name': s.name, 'category_id': s.categoryId, 'price': s.price},
    ];

WorkPhoto workFrom(Json j) => WorkPhoto(
      id: _s(j, 'id'),
      image: _s(j, 'image'),
      caption: _so(j, 'caption'),
      focusX: _d(j, 'focus_x'),
      focusY: _d(j, 'focus_y'),
    );

Review reviewFrom(Json j) => Review(
      id: _s(j, 'id'),
      authorName: _s(j, 'author_name'),
      authorPhoto: _so(j, 'author_photo'),
      rating: _i(j, 'rating'),
      text: _so(j, 'text'),
      serviceName: _so(j, 'service_name'),
      at: _t(j, 'at'),
      reply: _so(j, 'reply'),
    );

ArtisanProfile profileFrom(Json j) {
  final ratings = asMap(j['ratings']);
  final area = asMap(j['service_area']);
  final hours = asMap(j['hours']);
  return ArtisanProfile(
    artisan: artisanFrom(asMap(j['artisan'])),
    about: _so(j, 'about') ?? '',
    experienceYears: _io(j, 'experience_years') ?? 0,
    businessName: _so(j, 'business_name'),
    certifications: _strings(j['certifications']),
    services: [for (final s in asList(j['services'])) serviceFrom(s)],
    work: [for (final w in asList(j['work'])) workFrom(w)],
    ratings: RatingSummary(
      average: _d(ratings, 'average'),
      count: _io(ratings, 'count') ?? 0,
      byStars: {
        for (final MapEntry(:key, :value)
            in asMap(ratings['by_stars'] ?? const <String, Object?>{}).entries)
          if (int.tryParse(key) != null)
            int.parse(key): (value! as num).toInt(),
      },
    ),
    reviews: [for (final r in asList(j['reviews'])) reviewFrom(r)],
    serviceArea:
        ServiceArea(area: _s(area, 'area'), radiusKm: _i(area, 'radius_km')),
    hours: workingHoursFrom(hours),
    joinedOn: _t(j, 'joined_on'),
    responseRate: _io(j, 'response_rate'),
    languages: _strings(j['languages']),
  );
}

WorkingHours workingHoursFrom(Json j) => WorkingHours(
      days: {for (final d in (j['days']! as List)) (d as num).toInt()},
      startMinutes: _i(j, 'start_minutes'),
      endMinutes: _i(j, 'end_minutes'),
    );

Json workingHoursTo(WorkingHours h) => {
      'days': (h.days.toList()..sort()),
      'start_minutes': h.startMinutes,
      'end_minutes': h.endMinutes,
    };

// ---------------------------------------------------------------- jobs

const _jobStatus = {
  'open': JobStatus.open,
  'booked': JobStatus.booked,
  'closed': JobStatus.closed
};
const _quoteStatus = {
  'pending': QuoteStatus.pending,
  'accepted': QuoteStatus.accepted,
  'declined': QuoteStatus.declined,
  'withdrawn': QuoteStatus.withdrawn,
};

JobPost jobPostFrom(Json j) => JobPost(
      id: _s(j, 'id'),
      title: _s(j, 'title'),
      categoryId: _s(j, 'category_id'),
      area: _s(j, 'area'),
      distanceKm: _d(j, 'distance_km'),
      postedAt: _t(j, 'posted_at'),
      budgetMin: _io(j, 'budget_min'),
      budgetMax: _io(j, 'budget_max'),
      isUrgent: _b(j, 'is_urgent'),
      quoteCount: _io(j, 'quote_count') ?? 0,
      description: _so(j, 'description'),
      clientPhoneVerified: j['client_phone_verified'] != false,
      clientJobsPosted: _io(j, 'client_jobs_posted') ?? 0,
      location: _geo(j['location']),
      photos: _strings(j['photos']),
    );

JobDemand demandFrom(Json j) => JobDemand(
      openThisWeek: _io(j, 'open_this_week') ?? 0,
      postedToday: _io(j, 'posted_today') ?? 0,
      typicalBudgetMin: _io(j, 'typical_budget_min'),
      typicalBudgetMax: _io(j, 'typical_budget_max'),
    );

Quote quoteFrom(Json j) => Quote(
      id: _s(j, 'id'),
      jobId: _s(j, 'job_id'),
      artisan: artisanFrom(asMap(j['artisan'])),
      price: _i(j, 'price'),
      priceMax: _io(j, 'price_max'),
      message: _so(j, 'message'),
      canStartAt: _to(j, 'can_start_at'),
      sentAt: _t(j, 'sent_at'),
      status: _quoteStatus[j['status']] ?? QuoteStatus.pending,
      jobTitle: _so(j, 'job_title'),
    );

ClientJob clientJobFrom(Json j) => ClientJob(
      id: _s(j, 'id'),
      title: _s(j, 'title'),
      categoryId: _s(j, 'category_id'),
      area: _s(j, 'area'),
      landmark: _so(j, 'landmark'),
      postedAt: _t(j, 'posted_at'),
      status: _jobStatus[j['status']] ?? JobStatus.open,
      description: _so(j, 'description'),
      photos: _strings(j['photos']),
      voiceNote: voiceFrom(j['voice_note']),
      budgetMin: _io(j, 'budget_min'),
      budgetMax: _io(j, 'budget_max'),
      isUrgent: _b(j, 'is_urgent'),
      quotes: [for (final q in asList(j['quotes'])) quoteFrom(q)],
      bookingId: _so(j, 'booking_id'),
    );

// ---------------------------------------------------------------- bookings

const _bookingStatus = {
  'requested': BookingStatus.requested,
  'confirmed': BookingStatus.confirmed,
  'on_the_way': BookingStatus.onTheWay,
  'in_progress': BookingStatus.inProgress,
  'completed': BookingStatus.completed,
  'cancelled': BookingStatus.cancelled,
};
const _payment = {
  'not_paid': PaymentState.notPaid,
  'held': PaymentState.held,
  'released': PaymentState.released,
  'refunded': PaymentState.refunded,
};

VoiceNote? voiceFrom(Object? value) {
  if (value == null) return null;
  final j = asMap(value);
  return VoiceNote(
    path: _s(j, 'url'),
    duration: Duration(seconds: _i(j, 'duration_seconds')),
    heard: _so(j, 'heard'),
  );
}

/// [note] as the API stores it, once uploaded to [url].
Json voiceTo(VoiceNote note, String url) => {
      'url': url,
      'duration_seconds': math.max(1, math.min(300, note.duration.inSeconds)),
      'heard': note.heard,
    };

TimeWindow windowFrom(Object? value) {
  final j = asMap(value);
  return TimeWindow(start: _t(j, 'start'), end: _t(j, 'end'));
}

Json windowTo(TimeWindow w) => {'start': iso(w.start), 'end': iso(w.end)};

Booking bookingFrom(Json j) => Booking(
      id: _s(j, 'id'),
      serviceName: _s(j, 'service_name'),
      categoryId: _s(j, 'category_id'),
      scheduledAt: _t(j, 'scheduled_at'),
      status: _bookingStatus[j['status']] ?? BookingStatus.requested,
      counterpartName: _s(j, 'counterpart_name'),
      counterpartPhoto: _so(j, 'counterpart_photo'),
      counterpartPhone: _so(j, 'counterpart_phone'),
      area: _s(j, 'area'),
      price: _io(j, 'price'),
      startCode: _so(j, 'start_code'),
      landmark: _so(j, 'landmark'),
      distanceKm: (j['distance_km'] as num?)?.toDouble(),
      artisanId: _so(j, 'artisan_id'),
      notes: _so(j, 'notes'),
      photos: _strings(j['photos']),
      voiceNote: voiceFrom(j['voice_note']),
      fee: _io(j, 'fee'),
      payment: _payment[j['payment']] ?? PaymentState.notPaid,
      yourRating: _io(j, 'your_rating'),
      conversationId: _so(j, 'conversation_id'),
      cancelReason: _so(j, 'cancel_reason'),
      etaMinutes: _io(j, 'eta_minutes'),
    );

DirectRequest requestFrom(Json j) => DirectRequest(
      id: _s(j, 'id'),
      clientName: _s(j, 'client_name'),
      clientPhoto: _so(j, 'client_photo'),
      message: _so(j, 'message'),
      photos: _strings(j['photos']),
      voiceNote: voiceFrom(j['voice_note']),
      distanceKm: (j['distance_km'] as num?)?.toDouble(),
      landmark: _so(j, 'landmark'),
      serviceName: _s(j, 'service_name'),
      categoryId: _s(j, 'category_id'),
      area: _s(j, 'area'),
      window: windowFrom(j['window']),
      price: _i(j, 'price'),
      expiresAt: _t(j, 'expires_at'),
    );

PriceBreakdown priceFrom(Json j) =>
    PriceBreakdown(price: _i(j, 'price'), fee: _i(j, 'fee'));

ArtisanDashboard dashboardFrom(Json j) => ArtisanDashboard(
      isAvailable: _b(j, 'is_available'),
      busyUntil: j['availability'] == 'busy' ? _to(j, 'busy_until') : null,
      earningsThisWeek: _io(j, 'earnings_this_week') ?? 0,
      earningsLastWeek: _io(j, 'earnings_last_week') ?? 0,
      availableBalance: _io(j, 'available_balance') ?? 0,
      earnedToDate: _io(j, 'earned_to_date') ?? 0,
      jobsThisWeek: _io(j, 'jobs_this_week') ?? 0,
      rating: _d(j, 'rating'),
      reviewCount: _io(j, 'review_count') ?? 0,
      responseRate: _io(j, 'response_rate') ?? 100,
      setupSteps: [
        for (final s in asList(j['setup_steps']))
          SetupStep(
            id: _s(s, 'id'),
            label: _s(s, 'label'),
            done: _b(s, 'done'),
            reason: _so(s, 'reason'),
            effort: _so(s, 'effort'),
            blocksBookings: _b(s, 'blocks_bookings'),
          ),
      ],
    );

// ---------------------------------------------------------------- chat

const _messageKind = {
  'text': MessageKind.text,
  'voice': MessageKind.voice,
  'photo': MessageKind.photo,
  'booking': MessageKind.booking,
  'quote': MessageKind.quote,
  'system': MessageKind.system,
};

ChatMessage messageFrom(Json j) => ChatMessage(
      id: _s(j, 'id'),
      fromMe: _b(j, 'from_me'),
      kind: _messageKind[j['kind']] ?? MessageKind.text,
      text: _so(j, 'text'),
      voiceNote: voiceFrom(j['voice_note']),
      photo: _so(j, 'photo'),
      sentAt: _t(j, 'sent_at'),
      read: j['read'] != false,
    );

Conversation conversationFrom(Json j) => Conversation(
      id: _s(j, 'id'),
      title: _s(j, 'title'),
      photo: _so(j, 'photo'),
      subtitle: _so(j, 'subtitle'),
      bookingId: _so(j, 'booking_id'),
      artisanId: _so(j, 'artisan_id'),
      lastMessage: j['last_message'] == null
          ? null
          : messageFrom(asMap(j['last_message'])),
      unread: _io(j, 'unread') ?? 0,
      online: _b(j, 'online'),
      updatedAt: _t(j, 'updated_at'),
    );

// ---------------------------------------------------------------- notices

const _noticeKind = {
  'booking': NoticeKind.booking,
  'quote': NoticeKind.quote,
  'message': NoticeKind.message,
  'payment': NoticeKind.payment,
  'review': NoticeKind.review,
  'account': NoticeKind.account,
  'news': NoticeKind.news,
};

AppNotice noticeFrom(Json j) => AppNotice(
      id: _s(j, 'id'),
      kind: _noticeKind[j['kind']] ?? NoticeKind.account,
      title: _s(j, 'title'),
      body: _s(j, 'body'),
      at: _t(j, 'at'),
      read: _b(j, 'read'),
      route: _so(j, 'route'),
    );

NotificationPrefs prefsFrom(Json j) => NotificationPrefs(
      bookings: j['bookings'] != false,
      messages: j['messages'] != false,
      quotes: j['quotes'] != false,
      payments: j['payments'] != false,
      tips: _b(j, 'tips'),
    );

Json prefsTo(NotificationPrefs p) => {
      'bookings': p.bookings,
      'messages': p.messages,
      'quotes': p.quotes,
      'payments': p.payments,
      'tips': p.tips,
    };

// ---------------------------------------------------------------- money

const _txKind = {
  'payment': TxKind.payment,
  'refund': TxKind.refund,
  'earning': TxKind.earning,
  'payout': TxKind.payout,
};
const _txStatus = {
  'pending': TxStatus.pending,
  'successful': TxStatus.successful,
  'failed': TxStatus.failed,
};

WalletSummary walletFrom(Json j) => WalletSummary(
      available: _io(j, 'available') ?? 0,
      held: _io(j, 'held') ?? 0,
      earnedTotal: _io(j, 'earned_total') ?? 0,
      paidTotal: _io(j, 'paid_total') ?? 0,
    );

WalletTx txFrom(Json j) => WalletTx(
      id: _s(j, 'id'),
      kind: _txKind[j['kind']] ?? TxKind.payment,
      amount: _i(j, 'amount'),
      status: _txStatus[j['status']] ?? TxStatus.pending,
      at: _t(j, 'at'),
      title: _s(j, 'title'),
      reference: _so(j, 'reference'),
    );

Bank bankFrom(Json j) => Bank(code: _s(j, 'code'), name: _s(j, 'name'));

PayoutAccount payoutFrom(Json j) => PayoutAccount(
      bank: bankFrom(asMap(j['bank'])),
      accountNumber: _s(j, 'account_number'),
      accountName: _s(j, 'account_name'),
    );

// ---------------------------------------------------------------- account

const _verificationState = {
  'not_started': VerificationState.notStarted,
  'pending': VerificationState.pending,
  'verified': VerificationState.verified,
  'failed': VerificationState.failed,
};

Verification verificationFrom(Json j) => Verification(
      state: _verificationState[j['state']] ?? VerificationState.notStarted,
      reason: _so(j, 'reason'),
      updatedAt: _to(j, 'updated_at'),
    );

SavedPlace placeFrom(Json j) => SavedPlace(
      id: _s(j, 'id'),
      label: _s(j, 'label'),
      area: _s(j, 'area'),
      address: _s(j, 'address'),
    );
