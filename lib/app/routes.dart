/// Route paths. Screens navigate with these rather than raw strings.
///
/// Kept apart from `router.dart`, which imports every screen, so screens can
/// use the paths without depending on each other.
abstract final class Routes {
  static const splash = '/splash';
  static const welcome = '/welcome';

  static const home = '/home';
  static const explore = '/explore';
  static const bookings = '/bookings';
  static const messages = '/messages';
  static const account = '/account';
}
