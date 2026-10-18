import '../models/models.dart';

/// Contracts for the rest of the app: asking RijHub, browsing artisans,
/// booking, quotes, chat, notifications, money, the account and the
/// artisan's own setup. Like the others, screens use only these; the mock
/// implementations stand in until the new backend exists.

/// Thrown by any repository with a message that is safe to show.
class AppException implements Exception {
  const AppException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// RijHub reading a problem described in words, a voice note or photos.
abstract interface class AskRepository {
  /// What RijHub heard in [note].
  Future<String> transcribe(VoiceNote note);

  /// Which trade [input] is about, what the job is called and what it
  /// usually costs in [area].
  Future<Triage> triage(AskInput input, {String? area});
}

enum ArtisanSort { recommended, nearest, rating, price }

/// Finding artisans and reading their profiles.
abstract interface class DirectoryRepository {
  /// Artisans matching [query] (a name, trade or problem) and the filters,
  /// in [area].
  Future<List<Artisan>> search({
    required String area,
    String? query,
    String? categoryId,
    bool freeNow = false,
    bool verifiedOnly = false,
    ArtisanSort sort = ArtisanSort.recommended,
    int limit = 30,
  });

  Future<ArtisanProfile> profile(String artisanId, {String? area});

  /// Every review, newest first.
  Future<List<Review>> reviews(String artisanId);

  /// The client's saved artisans, most recently saved first.
  Future<List<Artisan>> saved({String? area});
  Future<Set<String>> savedIds();

  /// Saves or unsaves an artisan; returns whether it is now saved.
  Future<bool> toggleSaved(String artisanId);
}

/// Requesting, following and finishing bookings, for both sides.
abstract interface class BookingFlowRepository {
  /// What booking [service] costs, with RijHub's fee.
  Future<PriceBreakdown> price(ServiceOffer service);

  /// Sends a booking request to the artisan, paid and held by RijHub. The
  /// booking starts as [BookingStatus.requested] until they accept.
  Future<Booking> request(BookingDraft draft);

  Future<Booking> byId(String bookingId);

  /// Finished and cancelled bookings, newest first.
  Future<List<Booking>> past({required UserRole as});

  /// Cancels; a held payment goes back to the client.
  Future<Booking> cancel(String bookingId, {required String reason});

  /// Moves a booking to another time.
  Future<Booking> reschedule(String bookingId, DateTime to);

  /// The client says the job is done: the payment goes to the artisan.
  Future<Booking> confirmDone(String bookingId);

  Future<Booking> review(String bookingId, {required int rating, String? text});

  // The artisan's side.

  Future<Booking> onMyWay(String bookingId);

  /// Starts the job with the client's 4-digit [code]. Throws
  /// [AppException] when it doesn't match.
  Future<Booking> start(String bookingId, String code);

  /// The artisan has finished; the client is asked to confirm.
  Future<Booking> finish(String bookingId);
}

/// A client's posted jobs and the quotes they draw.
abstract interface class ClientJobRepository {
  Future<ClientJob> post(JobDraft draft, {String? toArtisanId});
  Future<List<ClientJob>> mine();
  Future<ClientJob> byId(String jobId);

  /// Accepts [quoteId]: the job becomes a booking, requested at the
  /// quoted price.
  ///
  /// For a quote with a range, [price] is the one the client picked in it.
  Future<Booking> accept(String jobId, String quoteId,
      {required TimeWindow window, int? price});
  Future<ClientJob> decline(String jobId, String quoteId);
  Future<ClientJob> close(String jobId);

  /// Changes an open job's details. Quotes already in stay.
  Future<ClientJob> update(String jobId, JobDraft draft);
}

/// An artisan quoting on posted jobs.
abstract interface class QuoteRepository {
  Future<JobPost> job(String jobId);

  /// The quote the signed-in artisan sent on [jobId], if any.
  Future<Quote?> myQuoteOn(String jobId);
  Future<Quote> send(String jobId, QuoteDraft draft);
  Future<List<Quote>> mine();
  Future<void> withdraw(String quoteId);

  /// Clients asking the signed-in artisan, by name, for a price.
  Future<List<ClientJob>> quoteRequests();
}

abstract interface class ChatRepository {
  Future<List<Conversation>> conversations();
  Future<Conversation> byId(String conversationId);

  /// The conversation with [artisanId] (or, for an artisan, with the
  /// client of [bookingId]), started if there is none.
  Future<Conversation> withArtisan(String artisanId);
  Future<Conversation> forBooking(String bookingId);

  /// The conversation with RijHub's support team.
  Future<Conversation> withSupport();

  /// The messages so far, then each change.
  Stream<List<ChatMessage>> watch(String conversationId);
  Future<void> send(
    String conversationId, {
    String? text,
    VoiceNote? voiceNote,
    String? photo,
  });
  Future<void> markRead(String conversationId);

  /// Unread messages across conversations, now and as it changes.
  Stream<int> unreadCount();
}

abstract interface class NoticeRepository {
  Future<List<AppNotice>> notices();
  Future<void> markAllRead();
  Future<void> markRead(String noticeId);
  Stream<int> unreadCount();
  Future<NotificationPrefs> prefs();
  Future<void> savePrefs(NotificationPrefs prefs);
}

abstract interface class WalletRepository {
  Future<WalletSummary> summary();
  Future<List<WalletTx>> transactions();
  Future<PayoutAccount?> payoutAccount();
  Future<List<Bank>> banks();

  /// The account holder's name for [accountNumber] at [bank]. Throws
  /// [AppException] when the bank doesn't know the number.
  Future<String> resolveAccount(Bank bank, String accountNumber);
  Future<PayoutAccount> savePayoutAccount(Bank bank, String accountNumber);

  /// Sends [amount] to the payout account.
  Future<WalletTx> withdraw(int amount);
}

/// The person's own account.
abstract interface class AccountRepository {
  Future<AppUser> updateProfile({
    required String firstName,
    required String lastName,
    String? email,
    String? photo,
  });
  Future<List<SavedPlace>> places();
  Future<SavedPlace> savePlace(SavedPlace place);
  Future<void> deletePlace(String placeId);

  /// Deletes the account and everything in it.
  Future<void> deleteAccount();

  /// Uses the same account on the other side of RijHub: a client starts
  /// working (with [tradeIds]), or an artisan books for themselves.
  Future<AppUser> switchRole(UserRole to, {List<String> tradeIds = const []});
}

/// An artisan's own profile: what clients see, and the ID check.
abstract interface class ArtisanSetupRepository {
  Future<ArtisanProfile> myProfile();
  Future<void> saveAbout({
    required String about,
    required int experienceYears,
    String? businessName,
    List<String> certifications = const [],
  });
  Future<ServiceOffer> saveService(ServiceOffer service);
  Future<void> deleteService(String serviceId);
  Future<WorkPhoto> addWorkPhoto(String image, {String? caption});
  Future<void> deleteWorkPhoto(String photoId);
  Future<void> saveServiceArea(ServiceArea area);
  Future<void> saveHours(WorkingHours hours);
  Future<Verification> verification();

  /// Sends the NIN and selfie for checking.
  Future<Verification> submitVerification({
    required String nin,
    required String selfie,
  });
}

abstract interface class SupportRepository {
  Future<List<FaqItem>> faqs();
}
