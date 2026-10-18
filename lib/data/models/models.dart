import 'package:flutter/foundation.dart';

import '../geo/places.dart';
import 'ask_models.dart';

export '../geo/places.dart' show GeoPoint;

export 'ask_models.dart';
export 'market_models.dart';

/// Domain models used by the redesigned app. They describe what the UI needs,
/// not the shape of any backend; repositories translate API payloads into
/// these types.

enum UserRole { client, artisan }

@immutable
class AppUser {
  const AppUser({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.phone,
    required this.role,
    this.email,
    this.homeArea,
    this.city = 'Abuja',
    this.photo,
    this.tradeIds = const [],
  });

  final String id;
  final String firstName;
  final String lastName;

  /// E.164, for example +2348031234567.
  final String phone;
  final UserRole role;
  final String? email;

  /// The neighbourhood the person chose for "near you" results. Null until
  /// they choose one; results then cover the whole [city].
  final String? homeArea;
  final String city;

  /// Asset path or URL.
  final String? photo;

  /// The trades an artisan works in ([ServiceCategory.id]s), as picked at
  /// sign-up, main trade first. They drive "New jobs for you" and the "My
  /// trades" filter. Empty for clients.
  final List<String> tradeIds;

  String get fullName => '$firstName $lastName';

  /// Where the person is based, to show: their [homeArea], or the [city].
  String get area => homeArea ?? city;

  Map<String, Object?> toJson() => {
        'id': id,
        'firstName': firstName,
        'lastName': lastName,
        'phone': phone,
        'role': role.name,
        'email': email,
        'area': homeArea,
        'city': city,
        'photo': photo,
        'tradeIds': tradeIds,
      };

  /// Sessions saved before trades were stored have no `tradeIds`; they
  /// read as none rather than failing.
  factory AppUser.fromJson(Map<String, Object?> json) => AppUser(
        id: json['id']! as String,
        firstName: json['firstName']! as String,
        lastName: json['lastName']! as String,
        phone: json['phone']! as String,
        role: UserRole.values.byName(json['role']! as String),
        email: json['email'] as String?,
        homeArea: json['area'] as String?,
        city: json['city'] as String? ?? 'Abuja',
        photo: json['photo'] as String?,
        tradeIds: switch (json['tradeIds']) {
          final List<Object?> ids => List.unmodifiable(ids.whereType<String>()),
          _ => const [],
        },
      );
}

@immutable
class ServiceCategory {
  const ServiceCategory({
    required this.id,
    required this.name,
    required this.iconKey,
    this.artisanPlural,
  });

  final String id;
  final String name;

  /// Looked up by the UI (see `category_icons.dart`), so the data layer stays
  /// free of Flutter icon types.
  final String iconKey;

  /// What the people who do this work are called, as a plural that starts
  /// a sentence: "AC technicians", "Plumbers". For messages such as "No AC
  /// technicians free right now" (use `TextCase.midSentence` inside a
  /// sentence). Null when there is no better word than "artisans".
  final String? artisanPlural;
}

@immutable
class Artisan {
  const Artisan({
    required this.id,
    required this.name,
    required this.trade,
    required this.categoryId,
    required this.area,
    required this.distanceKm,
    required this.rating,
    required this.reviewCount,
    required this.jobsCompleted,
    required this.startingPrice,
    this.isVerified = false,
    this.isAvailableToday = false,
    this.nextFreeAt,
    this.replyMinutes,
    this.photo,
    this.coverPhoto,
    this.coverFocusX = 0,
    this.coverFocusY = -0.25,
    this.location,
  });

  final String id;
  final String name;

  /// Display name of the trade, for example "AC technician".
  final String trade;
  final String categoryId;

  /// Where they are based: a neighbourhood, for example "Wuse 2".
  final String area;

  /// How far they are from the area that was asked about, in km. Without
  /// an area (all of Abuja), from the city centre, which is too rough to
  /// show; show [area] instead.
  final double distanceKm;
  final double rating;
  final int reviewCount;
  final int jobsCompleted;

  /// Lowest listed price, in naira.
  final int startingPrice;
  final bool isVerified;

  /// Free to take a job now, shown as "Free now". (The name is older than
  /// the wording.)
  final bool isAvailableToday;

  /// When an artisan who isn't free now can next take a job, shown as
  /// "Next free: Tue 9:00". Null when they are free now or haven't said.
  final DateTime? nextFreeAt;

  /// How long they usually take to answer a new request, in minutes, shown
  /// as "replies ~10 min". Null until they have answered enough requests
  /// to say.
  final int? replyMinutes;

  /// Profile photo (asset path or URL).
  final String? photo;

  /// A work photo for cards (asset path or URL).
  final String? coverPhoto;

  /// Where the subject sits in [coverPhoto], from -1 to 1 on each axis, so
  /// cards can crop around it (an `Alignment`).
  final double coverFocusX;
  final double coverFocusY;

  /// Roughly where they are based, for the map. Never their exact address.
  final GeoPoint? location;

  /// "Emeka", for sentences such as "You hired Emeka".
  String get firstName => name.split(' ').first;

  Artisan copyWith({double? distanceKm, GeoPoint? location}) => Artisan(
        id: id,
        name: name,
        trade: trade,
        categoryId: categoryId,
        area: area,
        distanceKm: distanceKm ?? this.distanceKm,
        rating: rating,
        reviewCount: reviewCount,
        jobsCompleted: jobsCompleted,
        startingPrice: startingPrice,
        isVerified: isVerified,
        isAvailableToday: isAvailableToday,
        nextFreeAt: nextFreeAt,
        replyMinutes: replyMinutes,
        photo: photo,
        coverPhoto: coverPhoto,
        coverFocusX: coverFocusX,
        coverFocusY: coverFocusY,
        location: location ?? this.location,
      );
}

/// An artisan the signed-in client has hired before, for "Book again".
@immutable
class HiredArtisan {
  const HiredArtisan({
    required this.artisan,
    required this.serviceName,
    required this.lastHiredOn,
    this.yourRating,
  });

  final Artisan artisan;

  /// What they were hired for last time, for example "AC servicing".
  final String serviceName;

  /// The day of the last job together.
  final DateTime lastHiredOn;

  /// The stars the client gave that job, 1 to 5. Null if they didn't rate
  /// it.
  final int? yourRating;
}

@immutable
class JobPost {
  const JobPost({
    required this.id,
    required this.title,
    required this.categoryId,
    required this.area,
    required this.distanceKm,
    required this.postedAt,
    this.budgetMin,
    this.budgetMax,
    this.isUrgent = false,
    this.quoteCount = 0,
    this.description,
    this.clientPhoneVerified = false,
    this.clientJobsPosted = 0,
    this.location,
    this.photos = const [],
  });

  final String id;
  final String title;
  final String categoryId;
  final String area;

  /// How far the job is from the area that was asked about, in km. Without
  /// an area (all of Abuja), from the city centre, which is too rough to
  /// show.
  final double distanceKm;
  final DateTime postedAt;

  /// Naira. Both null means the client is open to quotes.
  final int? budgetMin;
  final int? budgetMax;
  final bool isUrgent;
  final int quoteCount;

  /// What the client wrote about the job, for the job sheet. Null when
  /// they gave only a title.
  final String? description;

  /// The client who posted it has verified their phone number.
  final bool clientPhoneVerified;

  /// How many jobs the client has posted on RijHub, this one included.
  final int clientJobsPosted;

  /// Roughly where the job is, for the map (the street comes only with a
  /// booking).
  final GeoPoint? location;

  /// Photos the client added of the problem.
  final List<String> photos;

  JobPost copyWith({double? distanceKm, GeoPoint? location}) => JobPost(
        id: id,
        title: title,
        categoryId: categoryId,
        area: area,
        distanceKm: distanceKm ?? this.distanceKm,
        postedAt: postedAt,
        budgetMin: budgetMin,
        budgetMax: budgetMax,
        isUrgent: isUrgent,
        quoteCount: quoteCount,
        description: description,
        clientPhoneVerified: clientPhoneVerified,
        clientJobsPosted: clientJobsPosted,
        location: location ?? this.location,
        photos: photos,
      );
}

/// How much work there is in an area, for a trade or for all of them.
@immutable
class JobDemand {
  const JobDemand({
    required this.openThisWeek,
    required this.postedToday,
    this.typicalBudgetMin,
    this.typicalBudgetMax,
  });

  /// Jobs posted in the last 7 days that are still open for quotes.
  final int openThisWeek;

  /// Jobs posted since midnight.
  final int postedToday;

  /// Most budgets fall between these, in naira ("most budgets ₦8,000 –
  /// ₦15,000"). Null when there are too few jobs to say.
  final int? typicalBudgetMin;
  final int? typicalBudgetMax;
}

/// What a common job usually costs in the city, worked out from jobs done
/// on RijHub.
@immutable
class PriceGuideItem {
  const PriceGuideItem({
    required this.problem,
    required this.categoryId,
    required this.minPrice,
    required this.maxPrice,
    required this.updatedOn,
  });

  /// The job as people ask for it: "AC servicing (1 unit)".
  final String problem;
  final String categoryId;

  /// Naira. Most jobs of this kind cost between these.
  final int minPrice;
  final int maxPrice;

  /// When the range was last worked out ("Updated Oct 2026").
  final DateTime updatedOn;
}

enum BookingStatus {
  requested,
  confirmed,
  onTheWay,
  inProgress,
  completed,
  cancelled,
}

/// Where the client's money is. RijHub holds it from booking until the
/// client says the job is done, then releases it to the artisan.
enum PaymentState { notPaid, held, released, refunded }

@immutable
class Booking {
  const Booking({
    required this.id,
    required this.serviceName,
    required this.categoryId,
    required this.scheduledAt,
    required this.status,
    required this.counterpartName,
    required this.area,
    this.counterpartPhoto,
    this.counterpartPhone,
    this.price,
    this.startCode,
    this.landmark,
    this.distanceKm,
    this.artisanId,
    this.notes,
    this.photos = const [],
    this.voiceNote,
    this.fee,
    this.payment = PaymentState.notPaid,
    this.yourRating,
    this.conversationId,
    this.cancelReason,
    this.etaMinutes,
  });

  final String id;
  final String serviceName;
  final String categoryId;
  final DateTime scheduledAt;
  final BookingStatus status;

  /// The artisan (for clients) or the client (for artisans).
  final String counterpartName;
  final String? counterpartPhoto;

  /// A number to call about the booking, E.164. The backend will hand out
  /// a relay number, so neither side sees the other's own.
  final String? counterpartPhone;
  final String area;
  final int? price;

  /// The 4-digit code the client gives the artisan on arrival, which
  /// starts the job. Only the client is sent it: null on the artisan's
  /// side.
  final String? startCode;

  /// How to find the place, beyond the area: "near Banex Plaza".
  final String? landmark;

  /// How far the job is from the artisan, in km, on the artisan's side.
  /// Null for clients.
  final double? distanceKm;

  /// The artisan's id, on the client's side, to open their profile.
  final String? artisanId;

  /// What the client said about the job.
  final String? notes;
  final List<String> photos;
  final VoiceNote? voiceNote;

  /// RijHub's fee, in naira, on top of [price].
  final int? fee;
  final PaymentState payment;

  /// The stars the client gave, once they have reviewed it.
  final int? yourRating;
  final String? conversationId;
  final String? cancelReason;

  /// Minutes until the artisan arrives, while on the way.
  final int? etaMinutes;

  int get total => (price ?? 0) + (fee ?? 0);

  bool get isOver =>
      status == BookingStatus.completed || status == BookingStatus.cancelled;

  Booking copyWith({
    BookingStatus? status,
    PaymentState? payment,
    int? yourRating,
    String? cancelReason,
    int? etaMinutes,
    DateTime? scheduledAt,
  }) =>
      Booking(
        id: id,
        serviceName: serviceName,
        categoryId: categoryId,
        scheduledAt: scheduledAt ?? this.scheduledAt,
        status: status ?? this.status,
        counterpartName: counterpartName,
        area: area,
        counterpartPhoto: counterpartPhoto,
        counterpartPhone: counterpartPhone,
        price: price,
        startCode: startCode,
        landmark: landmark,
        distanceKm: distanceKm,
        artisanId: artisanId,
        notes: notes,
        photos: photos,
        voiceNote: voiceNote,
        fee: fee,
        payment: payment ?? this.payment,
        yourRating: yourRating ?? this.yourRating,
        conversationId: conversationId,
        cancelReason: cancelReason ?? this.cancelReason,
        etaMinutes: etaMinutes ?? this.etaMinutes,
      );
}

/// A stretch of time a job can happen in, such as today 4–6 PM.
@immutable
class TimeWindow {
  const TimeWindow({required this.start, required this.end});

  final DateTime start;
  final DateTime end;
}

/// A client asking one artisan to take a job at a set price. The artisan
/// accepts or turns it down before [expiresAt]; after that it lapses and
/// the client is offered other artisans.
@immutable
class DirectRequest {
  const DirectRequest({
    required this.id,
    required this.clientName,
    required this.serviceName,
    required this.categoryId,
    required this.area,
    required this.window,
    required this.price,
    required this.expiresAt,
    this.message,
    this.photos = const [],
    this.voiceNote,
    this.clientPhoto,
    this.distanceKm,
    this.landmark,
  });

  final String id;

  /// As the artisan may see it before accepting: first name and initial,
  /// "Ngozi A.".
  final String clientName;
  final String? clientPhoto;

  /// What the client said, in their own words.
  final String? message;
  final List<String> photos;
  final VoiceNote? voiceNote;

  /// How far the job is from the artisan, in km.
  final double? distanceKm;
  final String? landmark;

  /// What the client wants done, for example "Socket repair".
  final String serviceName;
  final String categoryId;
  final String area;

  /// When the client wants it done.
  final TimeWindow window;

  /// What the client will pay, in naira.
  final int price;

  /// The last moment to answer. Count down to it in whole minutes rounded
  /// up, so the last minute reads "1 min", not "0 min".
  final DateTime expiresAt;
}

@immutable
class SetupStep {
  const SetupStep({
    required this.id,
    required this.label,
    required this.done,
    this.reason,
    this.effort,
    this.blocksBookings = false,
  });

  /// Stable key, for example "work_photos".
  final String id;
  final String label;
  final bool done;

  /// Why it's worth doing, shown when this is the next step.
  final String? reason;

  /// What the step takes, for example "2 minutes · NIN + selfie".
  final String? effort;

  /// Clients can't book the artisan until this step is done (the ID
  /// check). Quoting on jobs stays open. Such a step earns a banner; other
  /// steps only a quiet row.
  final bool blocksBookings;
}

/// Whether clients can book an artisan now.
enum AvailabilityStatus {
  /// Clients can book them now.
  available,

  /// Taking no bookings until `ArtisanDashboard.busyUntil`, then available
  /// again by itself.
  busy,

  /// Taking no bookings until they switch back on.
  off,
}

@immutable
class ArtisanDashboard {
  const ArtisanDashboard({
    required this.isAvailable,
    required this.earningsThisWeek,
    required this.earningsLastWeek,
    required this.availableBalance,
    required this.jobsThisWeek,
    required this.rating,
    required this.reviewCount,
    required this.responseRate,
    required this.setupSteps,
    this.busyUntil,
    this.earnedToDate = 0,
  });

  /// Clients can book them now. False while [busyUntil] is set, and while
  /// off.
  final bool isAvailable;

  /// When a busy spell ends and the artisan is available again by itself
  /// ("Busy until 3:00 PM"). Null when available or off.
  final DateTime? busyUntil;
  final int earningsThisWeek;
  final int earningsLastWeek;
  final int availableBalance;

  /// Everything earned on RijHub, in naira. 0 until the first paid job, so
  /// money can stay out of sight until there is some.
  final int earnedToDate;
  final int jobsThisWeek;
  final double rating;
  final int reviewCount;

  /// 0–100.
  final int responseRate;
  final List<SetupStep> setupSteps;

  int get setupDone => setupSteps.where((s) => s.done).length;
  bool get setupComplete => setupDone == setupSteps.length;

  AvailabilityStatus get availability {
    if (isAvailable) return AvailabilityStatus.available;
    if (busyUntil != null) return AvailabilityStatus.busy;
    return AvailabilityStatus.off;
  }

  /// This dashboard with clients able to book now ([available]), busy
  /// until [busyUntil], or neither (off).
  ArtisanDashboard withAvailability(bool available, {DateTime? busyUntil}) {
    assert(
      !available || busyUntil == null,
      'Busy means not available until then.',
    );
    return ArtisanDashboard(
      isAvailable: available,
      busyUntil: available ? null : busyUntil,
      earningsThisWeek: earningsThisWeek,
      earningsLastWeek: earningsLastWeek,
      availableBalance: availableBalance,
      earnedToDate: earnedToDate,
      jobsThisWeek: jobsThisWeek,
      rating: rating,
      reviewCount: reviewCount,
      responseRate: responseRate,
      setupSteps: setupSteps,
    );
  }

  /// Switching availability on or off also ends a busy spell.
  ArtisanDashboard copyWith({bool? isAvailable}) =>
      isAvailable == null ? this : withAvailability(isAvailable);
}
