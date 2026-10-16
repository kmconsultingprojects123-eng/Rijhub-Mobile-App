import '../data/mock/mock_repositories.dart';
import '../data/repositories/repositories.dart';

/// The one place that decides which implementation backs each repository.
///
/// The old rijhub.com API is not used by the redesigned app. Until the new
/// backend is live everything runs on mock data; add an `AppDependencies.api`
/// factory with HTTP-backed repositories when it is.
class AppDependencies {
  const AppDependencies({
    required this.auth,
    required this.catalog,
    required this.artisans,
    required this.jobs,
    required this.bookings,
    required this.artisanDashboard,
  });

  /// Sample data. The mocks share one record of accounts, so bookings,
  /// earnings, requests and past hires belong to whoever is signed in, and
  /// a new account starts empty.
  factory AppDependencies.mock() {
    final accounts = MockAccounts();
    return AppDependencies(
      auth: MockAuthRepository(accounts: accounts),
      catalog: MockCatalogRepository(),
      artisans: MockArtisanRepository(accounts: accounts),
      jobs: MockJobRepository(accounts: accounts),
      bookings: MockBookingRepository(accounts: accounts),
      artisanDashboard: MockArtisanDashboardRepository(accounts: accounts),
    );
  }

  final AuthRepository auth;
  final CatalogRepository catalog;
  final ArtisanRepository artisans;
  final JobRepository jobs;
  final BookingRepository bookings;
  final ArtisanDashboardRepository artisanDashboard;
}
