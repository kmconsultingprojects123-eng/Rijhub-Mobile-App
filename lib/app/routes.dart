/// Route paths. Screens navigate with these rather than raw strings.
///
/// Kept apart from `router.dart`, which imports every screen, so screens can
/// use the paths without depending on each other.
abstract final class Routes {
  static const splash = '/splash';

  /// First open: RijHub says hello in a conversation.
  static const welcome = '/welcome';

  // The five tabs. Artisans see Jobs in [explore] and Schedule in
  // [bookings].
  static const home = '/home';
  static const explore = '/explore';
  static const bookings = '/bookings';
  static const messages = '/messages';
  static const account = '/account';

  /// The Ask conversation: say what's wrong, get matched.
  static const ask = '/ask';

  /// Search and the map, full screen.
  static const search = '/search';
  static const map = '/map';

  static String artisan(String id) => '/artisan/$id';
  static String artisanReviews(String id) => '/artisan/$id/reviews';
  static String artisanWork(String id, [int index = 0]) =>
      '/artisan/$id/work?i=$index';

  /// Book [artisanId]; the Ask conversation passes what it learned along.
  static String book(String artisanId) => '/book/$artisanId';
  static String booking(String id) => '/booking/$id';

  /// A client's posted job and its quotes.
  static String clientJob(String id) => '/jobs/$id';
  static String editJob(String id) => '/jobs/$id/edit';
  static const postJob = '/post-job';

  /// A job on the artisan's job board.
  static String job(String id) => '/job/$id';
  static String sendQuote(String jobId) => '/job/$jobId/quote';

  /// A booking request sent to the signed-in artisan.
  static String request(String id) => '/requests/$id';

  /// A client asking the signed-in artisan, by name, for a price.
  static String quoteRequest(String id) => '/quote-requests/$id';

  static String chat(String id) => '/chat/$id';
  static const notifications = '/notifications';

  // Account.
  static const editProfile = '/account/edit';
  static const saved = '/account/saved';
  static const places = '/account/places';
  static const myJobs = '/account/jobs';
  static const payments = '/account/payments';
  static const wallet = '/account/wallet';
  static const payoutAccount = '/account/wallet/bank';
  static const withdraw = '/account/wallet/withdraw';
  static const verification = '/account/verification';
  static const myProfile = '/account/profile';
  static const services = '/account/services';
  static const portfolio = '/account/work';
  static const workArea = '/account/area';
  static const hours = '/account/hours';
  static const reviews = '/account/reviews';
  static const quotes = '/account/quotes';
  static const settings = '/account/settings';
  static const notificationSettings = '/account/settings/notifications';
  static const about = '/account/settings/about';
  static const deleteAccount = '/account/delete';

  static const support = '/support';
  static String faq(String id) => '/support/faq/$id';
  static const voiceSupport = '/support/call';
  static const terms = '/legal/terms';
  static const privacy = '/legal/privacy';
}
