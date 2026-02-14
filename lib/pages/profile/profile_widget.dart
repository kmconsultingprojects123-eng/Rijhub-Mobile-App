import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'profile_model.dart';
import 'dart:convert';
import '../../services/user_service.dart';
import '../../utils/navigation_utils.dart';
import '../../services/token_storage.dart';
import '../../services/api_error_handler.dart';
import '../../api_config.dart';
import '../../services/artist_service.dart';
import '/main.dart';
import '../../state/auth_notifier.dart';
export 'profile_model.dart';

class ProfileWidget extends StatefulWidget {
  const ProfileWidget({super.key});

  static String routeName = 'profile';
  static String routePath = '/profile';

  @override
  State<ProfileWidget> createState() => _ProfileWidgetState();
}

class _ProfileWidgetState extends State<ProfileWidget> {
  late ProfileModel _model;
  final scaffoldKey = GlobalKey<ScaffoldState>();
  bool _loggingOut = false;
  bool _isLoading = false;
  bool _deletingAccount = false;

  // Cache user data locally
  String? displayName;
  String? profileImageUrl;
  String? userLocation;
  String? userEmail;
  String? userPhone;

  // artisan-specific
  bool _loadingArtisan = false;
  String? _artisanError;
  String? artisanTrade;
  double? artisanRating;
  int? artisanExperienceYears;
  bool? artisanVerified;
  List<String> artisanPortfolio = [];

  // Add cache for performance
  static Map<String, dynamic>? _cachedProfileData;
  static Map<String, dynamic>? _cachedArtisanData;
  static bool _isCacheStale = false;

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => ProfileModel());

    // Load cached KYC flag so badge can show immediately after a successful KYC submission
    try {
      TokenStorage.getKycVerified().then((v) {
        if (v != null && mounted) setState(() => artisanVerified = v);
      });
    } catch (_) {}

    // Load cached data first, then refresh in background
    _loadCachedData();
    _loadProfile();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Mark cache as stale when navigating to profile page
    _isCacheStale = true;
  }

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  // Load cached data immediately for instant display
  void _loadCachedData() {
    if (_cachedProfileData != null && !_isCacheStale) {
      setState(() {
        displayName = (_cachedProfileData!['name'] ?? _cachedProfileData!['fullName'] ?? _cachedProfileData!['username'] ?? _cachedProfileData!['displayName'])?.toString();
        userEmail = (_cachedProfileData!['email'] ?? _cachedProfileData!['contact'] ?? _cachedProfileData!['username'])?.toString();
        userPhone = (_cachedProfileData!['phone'] ?? _cachedProfileData!['phoneNumber'] ?? _cachedProfileData!['mobile'])?.toString();
        profileImageUrl = (_cachedProfileData!['profileImage'] is Map) ? (_cachedProfileData!['profileImage']['url']?.toString() ?? '') : (_cachedProfileData!['profileImage'] ?? _cachedProfileData!['photo'] ?? _cachedProfileData!['avatar'])?.toString();
        userLocation = (_cachedProfileData!['location'] ?? _cachedProfileData!['city'] ?? _cachedProfileData!['serviceArea']?['address'])?.toString() ?? '';
      });
    }

    if (_cachedArtisanData != null && !_isCacheStale) {
      setState(() {
        artisanTrade = (_cachedArtisanData!['trade'] ?? _cachedArtisanData!['occupation'] ?? _cachedArtisanData!['profession'] ?? _cachedArtisanData!['job'])?.toString();
        artisanRating = (_cachedArtisanData!['rating'] ?? _cachedArtisanData!['avgRating'] ?? _cachedArtisanData!['ratingAverage'] ?? _cachedArtisanData!['score']) != null
            ? double.tryParse((_cachedArtisanData!['rating'] ?? _cachedArtisanData!['avgRating'] ?? _cachedArtisanData!['ratingAverage'] ?? _cachedArtisanData!['score']).toString())
            : null;
        artisanExperienceYears = (_cachedArtisanData!['experienceYears'] ?? _cachedArtisanData!['experience'] ?? _cachedArtisanData!['yearsExperience']) != null
            ? int.tryParse((_cachedArtisanData!['experienceYears'] ?? _cachedArtisanData!['experience'] ?? _cachedArtisanData!['yearsExperience']).toString())
            : null;
        artisanVerified = (_cachedArtisanData!['verified'] ?? _cachedArtisanData!['isVerified'] ?? _cachedArtisanData!['kycVerified']) is bool
            ? (_cachedArtisanData!['verified'] ?? _cachedArtisanData!['isVerified'] ?? _cachedArtisanData!['kycVerified']) as bool
            : ((_cachedArtisanData!['verified'] ?? _cachedArtisanData!['isVerified'] ?? _cachedArtisanData!['kycVerified']) != null
            ? (_cachedArtisanData!['verified'] ?? _cachedArtisanData!['isVerified'] ?? _cachedArtisanData!['kycVerified']).toString().toLowerCase() == 'true'
            : null);

        artisanPortfolio = [];
        final candidates = [_cachedArtisanData!['portfolio'], _cachedArtisanData!['portfolioImages'], _cachedArtisanData!['images'], _cachedArtisanData!['photos'], _cachedArtisanData!['media']];
        for (final pc in candidates) {
          if (pc == null) continue;
          if (pc is List) {
            for (final item in pc) {
              if (item == null) continue;
              if (item is String) artisanPortfolio.add(item);
              else if (item is Map && item['url'] != null) artisanPortfolio.add(item['url'].toString());
              else if (item is Map && item['path'] != null) artisanPortfolio.add(item['path'].toString());
            }
          }
        }
      });
    }
  }

  Future<void> _handleLogout() async {
    if (_loggingOut) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Log out?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface)),
        content: Text('Are you sure you want to log out?', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withAlpha((0.7 * 255).toInt()))),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.of(c).pop(true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _loggingOut = true);

    // Clear cache on logout
    _cachedProfileData = null;
    _cachedArtisanData = null;
    _isCacheStale = true;

    try {
      // Centralized logout/cleanup via AuthNotifier
      await AuthNotifier.instance.logout();
    } catch (_) {}

    if (!mounted) return;
    // Navigate to splash via GoRouter so the full routing rules apply and
    // history is replaced.
    try {
      GoRouter.of(context).go(SplashScreenPage2Widget.routePath);
    } catch (_) {
      // As a last resort, fall back to Navigator replacement
      try {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => SplashScreenPage2Widget()),
          (Route<dynamic> route) => false,
        );
      } catch (_) {}
    }
  }

  Future<void> _handleDeleteAccount() async {
    if (_deletingAccount) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Delete account?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface)),
        content: Text(
          'This will permanently delete your account and all related data. This action is irreversible. Are you sure you want to continue?',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withAlpha((0.7 * 255).toInt())),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.of(c).pop(true),
            child: const Text('Delete account'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _deletingAccount = true);

    try {
      final client = ApiClient();
      final url = '$API_BASE_URL/api/users/me';
      final token = await TokenStorage.getToken();
      final headers = <String, String>{ 'Accept': 'application/json' };
      if (token != null && token.isNotEmpty) headers['Authorization'] = 'Bearer $token';

      final resp = await client.safeDelete(url, headers: headers, context: context);
      if (resp.ok) {
        // Clear caches
        _cachedProfileData = null;
        _cachedArtisanData = null;
        _isCacheStale = true;

        // Ensure local logout/cleanup
        try {
          await AuthNotifier.instance.logout();
        } catch (_) {}

        // Notify user and navigate to splash/login
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('Account deleted')));

        try {
          GoRouter.of(context).go(SplashScreenPage2Widget.routePath);
        } catch (_) {
          try {
            Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => SplashScreenPage2Widget()), (r) => false);
          } catch (_) {}
        }
      } else {
        // safeDelete already shows a user-friendly message via ApiErrorHandler
        if (resp.message.isNotEmpty) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(resp.message)));
        }
      }
    } catch (e) {
      // Best-effort: show a simple error
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('Unable to delete account. Please try again.')));
    } finally {
      if (mounted) setState(() => _deletingAccount = false);
    }
  }

  // Validate candidate URL/path before using Image.network
  bool _isValidHttpUrl(String? url) {
    if (url == null) return false;
    final s = url.trim();
    if (s.isEmpty) return false;
    final lower = s.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://')) return true;
    if (lower.startsWith('//')) return true;
    if (s.startsWith('/')) return true;
    return false;
  }

  Future<void> _loadProfile() async {
    if (!mounted || _isLoading) return;

    setState(() {
      _isLoading = true;
      _loadingArtisan = true;
      _artisanError = null;
    });

    try {
      // Check if we have valid cache first
      if (_cachedProfileData == null || _isCacheStale) {
        final profile = await UserService.getProfile();
        if (!mounted) return;

        if (profile != null) {
          // Cache the profile data
          _cachedProfileData = Map<String, dynamic>.from(profile);

          setState(() {
            displayName = (profile['name'] ?? profile['fullName'] ?? profile['username'] ?? profile['displayName'])?.toString();
            userEmail = (profile['email'] ?? profile['contact'] ?? profile['username'])?.toString();
            userPhone = (profile['phone'] ?? profile['phoneNumber'] ?? profile['mobile'])?.toString();
            profileImageUrl = (profile['profileImage'] is Map) ? (profile['profileImage']['url']?.toString() ?? '') : (profile['profileImage'] ?? profile['photo'] ?? profile['avatar'])?.toString();
          });
        }
      }

      // Use canonical cached location
      if (userLocation == null || _isCacheStale) {
        try {
          final loc = await UserService.getCanonicalLocation();
          final addr = loc['address'] as String?;
          if (addr != null && addr.isNotEmpty) {
            if (mounted) setState(() => userLocation = addr);
          }
        } catch (_) {}
      }

      // Load artisan data if needed
      if (_cachedArtisanData == null || _isCacheStale) {
        try {
          bool profileRoleIsArtisan = false;
          try {
            if (_cachedProfileData != null) {
              final candidates = [_cachedProfileData!['role'], _cachedProfileData!['type'], _cachedProfileData!['accountType'], _cachedProfileData!['userType'], _cachedProfileData!['authProvider']];
              for (final c in candidates) {
                if (c == null) continue;
                final s = c.toString().toLowerCase();
                if (s.contains('artisan')) { profileRoleIsArtisan = true; break; }
              }
            }
          } catch (_) {}

          final cachedIsArtisan = await UserService.isArtisan();
          final isArtisan = cachedIsArtisan || profileRoleIsArtisan;

          if (isArtisan) {
            final artisan = await ArtistService.getMyProfile();
            Map<String, dynamic>? finalArtisan = artisan;

            if (finalArtisan == null && _cachedProfileData != null) {
              try {
                String? userId;
                final candidates = ['_id', 'id', 'userId', 'user_id', 'uid'];
                for (final k in candidates) {
                  if (_cachedProfileData![k] != null) {
                    userId = _cachedProfileData![k].toString();
                    break;
                  }
                }
                if ((userId == null || userId.isEmpty) && _cachedProfileData!['user'] is Map && _cachedProfileData!['user']['_id'] != null) {
                  userId = _cachedProfileData!['user']['_id'].toString();
                }
                if (userId != null && userId.isNotEmpty) {
                  finalArtisan = await ArtistService.getByUserId(userId);

                }
              } catch (e) {}
            }

            if (finalArtisan != null) {
              // Normalize to a non-null Map so the analyzer can promote types inside setState
              final art = Map<String, dynamic>.from(finalArtisan);

              // Cache artisan data
              _cachedArtisanData = art;

              setState(() {
                artisanTrade = (art['trade'] ?? art['occupation'] ?? art['profession'] ?? art['job'])?.toString();
                artisanRating = (art['rating'] ?? art['avgRating'] ?? art['ratingAverage'] ?? art['score']) != null
                    ? double.tryParse((art['rating'] ?? art['avgRating'] ?? art['ratingAverage'] ?? art['score']).toString())
                    : null;
                artisanExperienceYears = (art['experienceYears'] ?? art['experience'] ?? art['yearsExperience']) != null
                    ? int.tryParse((art['experienceYears'] ?? art['experience'] ?? art['yearsExperience']).toString())
                    : null;
                artisanVerified = (art['verified'] ?? art['isVerified'] ?? art['kycVerified']) is bool
                    ? (art['verified'] ?? art['isVerified'] ?? art['kycVerified']) as bool
                    : ((art['verified'] ?? art['isVerified'] ?? art['kycVerified']) != null
                    ? (art['verified'] ?? art['isVerified'] ?? art['kycVerified']).toString().toLowerCase() == 'true'
                    : null);

                artisanPortfolio = [];
                final candidates = [art['portfolio'], art['portfolioImages'], art['images'], art['photos'], art['media']];
                for (final pc in candidates) {
                  if (pc == null) continue;
                  if (pc is List) {
                    for (final item in pc) {
                      if (item == null) continue;
                      if (item is String) artisanPortfolio.add(item);
                      else if (item is Map && item['url'] != null) artisanPortfolio.add(item['url'].toString());
                      else if (item is Map && item['path'] != null) artisanPortfolio.add(item['path'].toString());
                    }
                  }
                }
              });
            } else {
              setState(() => _artisanError = 'No artisan profile');
            }
          }
        } catch (e) {
          setState(() => _artisanError = 'Unable to load artisan info');
        } finally {
          if (mounted) setState(() => _loadingArtisan = false);
        }
      }

      // Mark cache as fresh
      _isCacheStale = false;

    } catch (e) {
      // Silent error
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<dynamic> _pushEditProfile() async {
    try {
      final res = await NavigationUtils.safePush(context, const EditProfileUserWidget());
      if (res != null) return res;
    } catch (e) {
      // Silent error
    }

    try {
      final root = appNavigatorKey.currentState;
      if (root != null) {
        return await root.push(MaterialPageRoute(builder: (_) => const EditProfileUserWidget()));
      } else {
        return await Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => const EditProfileUserWidget()));
      }
    } catch (e) {
      // Silent error
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    // Ensure this page is inside NavBarPage so the bottom navigation shows.
    // Only redirect automatically when the current router location actually
    // points to the profile path. This avoids clobbering other navigations
    // (for example when About/Support call GoRouter.go('/infoPage')).
    final bool _isNestedNavBar = context.findAncestorWidgetOfExactType<NavBarPage>() != null;
    if (!_isNestedNavBar) {
      bool shouldRedirect = true;
      try {
        final router = GoRouter.of(context);
        // Use a dynamic read to avoid analyzer type errors for router internals.
        final dynamic cfg = router.routerDelegate.currentConfiguration;
        final String cfgStr = cfg?.toString() ?? '';
        // If the current router configuration string doesn't contain the profile
        // path, assume we're navigating elsewhere and avoid replacing the NavBar.
        if (cfgStr.isNotEmpty && !cfgStr.contains(ProfileWidget.routePath) && !cfgStr.contains('/profile')) {
          shouldRedirect = false;
        }
      } catch (_) {
        // If any error reading router config, default to redirect behavior.
      }

      if (shouldRedirect) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          try {
            NavigationUtils.safePushReplacement(context, NavBarPage(initialPage: 'profile'));
          } catch (_) {
            try { Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => NavBarPage(initialPage: 'profile'))); } catch (_) {}
          }
        });
      }
    }

    // Pre-compute expensive theme values
    final onSurface = colorScheme.onSurface;
    final onSurfaceAlpha10 = onSurface.withAlpha((0.1 * 255).toInt());

    return Scaffold(
      key: scaffoldKey,
      backgroundColor: isDark ? Colors.black : Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Header - Optimized with const
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: onSurfaceAlpha10, width: 1)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const SizedBox(width: 48),
                  Text('Profile', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w500, fontSize: 18)),
                  if (_isLoading)
                    SizedBox(
                      width: 48,
                      child: Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colorScheme.primary,
                          ),
                        ),
                      ),
                    )
                  else
                    const SizedBox(width: 48),
                ],
              ),
            ),

            // Content - Use ListView.builder for menu items
            Expanded(
              child: RefreshIndicator(
                onRefresh: _loadProfile,
                color: colorScheme.primary,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(24.0, 0.0, 24.0, MediaQuery.of(context).padding.bottom + 140.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const SizedBox(height: 40.0),

                        // Profile header - Extract to separate widget for better performance
                        _ProfileHeader(
                          displayName: displayName,
                          profileImageUrl: profileImageUrl,
                          userLocation: userLocation,
                          userEmail: userEmail,
                          isDark: isDark,
                          colorScheme: colorScheme,
                          isValidHttpUrl: _isValidHttpUrl,
                          loadingArtisan: _loadingArtisan,
                          artisanError: _artisanError,
                          artisanTrade: artisanTrade,
                          artisanVerified: artisanVerified,
                          artisanRating: artisanRating,
                          artisanPortfolio: artisanPortfolio,
                          onTap: () async {
                            try {
                              final result = await _pushEditProfile();
                              if (result is Map<String, dynamic>) {
                                // Update cache with new data
                                _cachedProfileData = Map<String, dynamic>.from(result);
                                _isCacheStale = false;

                                setState(() {
                                  displayName = (result['name'] ?? result['fullName'] ?? result['username'] ?? result['displayName'])?.toString();
                                  userEmail = (result['email'] ?? result['contact'] ?? result['username'])?.toString();
                                  userPhone = (result['phone'] ?? result['phoneNumber'] ?? result['mobile'])?.toString();
                                  profileImageUrl = (result['profileImage'] is Map) ? (result['profileImage']['url']?.toString() ?? '') : (result['profileImage'] ?? result['photo'] ?? result['avatar'])?.toString();
                                  userLocation = (result['location'] ?? result['city'] ?? result['serviceArea']?['address'])?.toString() ?? '';
                                });
                              } else {
                                await _loadProfile();
                              }
                            } catch (_) {
                              await _loadProfile();
                            }
                          },
                        ),

                        const SizedBox(height: 48.0),

                        // Menu section - Optimized with const and pre-built widgets
                        _ProfileMenuSection(
                          onEditProfile: () async {
                            try {
                              final result = await _pushEditProfile();
                              if (result is Map<String, dynamic>) {
                                // Update cache with new data
                                _cachedProfileData = Map<String, dynamic>.from(result);
                                _isCacheStale = false;

                                setState(() {
                                  displayName = (result['name'] ?? result['fullName'] ?? result['username'] ?? result['displayName'])?.toString();
                                  userEmail = (result['email'] ?? result['contact'] ?? result['username'])?.toString();
                                  userPhone = (result['phone'] ?? result['phoneNumber'] ?? result['mobile'])?.toString();
                                  profileImageUrl = (result['profileImage'] is Map)
                                      ? (result['profileImage']['url']?.toString() ?? '')
                                      : (result['profileImage'] ?? result['photo'] ?? result['avatar'])?.toString();
                                  userLocation = (result['location'] ?? result['city'] ?? result['serviceArea']?['address'])?.toString() ?? '';
                                });
                              } else {
                                await _loadProfile();
                              }
                            } catch (_) {
                              await _loadProfile();
                            }
                          },
                          onMyJobs: () {
                            try {
                              // Determine role synchronously from cached profile
                              final profile = AppStateNotifier.instance.profile;
                              bool isArtisan = false;
                              try {
                                if (profile != null) {
                                  final candidates = [profile['role'], profile['type'], profile['accountType'], profile['userType'], profile['authProvider']];
                                  for (final c in candidates) {
                                    if (c == null) continue;
                                    final s = c.toString().toLowerCase();
                                    if (s.contains('artisan')) { isArtisan = true; break; }
                                  }
                                }
                              } catch (_) {}

                              if (isArtisan) {
                                try {
                                  GoRouter.of(context).pushNamed(ArtisanJobsHistoryWidget.routeName);
                                  return;
                                } catch (_) {
                                  try { NavigationUtils.safePush(context, const ArtisanJobsHistoryWidget()); return; } catch (_) {}
                                }
                              } else {
                                try {
                                  GoRouter.of(context).pushNamed(JobHistoryPageWidget.routeName);
                                  return;
                                } catch (_) {
                                  try { NavigationUtils.safePush(context, const JobHistoryPageWidget()); return; } catch (_) {}
                                }
                              }
                            } catch (_) {}
                          },
                          onWallet: () {
                            try {
                              GoRouter.of(context).pushNamed(UserWalletpageWidget.routeName);
                              return;
                            } catch (e) {
                              try {
                                NavigationUtils.safePush(context, const UserWalletpageWidget());
                                return;
                              } catch (_) {}
                            }
                          },
                          onHelpSupport: () {
                            try {
                              GoRouter.of(context).pushNamed(SupportPageWidget.routeName);
                              return;
                            } catch (e) {
                              try {
                                NavigationUtils.safePush(context, const SupportPageWidget());
                                return;
                              } catch (_) {}
                            }
                          },
                          onAboutUs: () {
                            try {
                              GoRouter.of(context).pushNamed(InfoPageWidget.routeName);
                              return;
                            } catch (e) {
                              try {
                                NavigationUtils.safePush(context, const InfoPageWidget());
                                return;
                              } catch (_) {}
                            }
                          },
                          theme: theme,
                          colorScheme: colorScheme,
                        ),

                        const SizedBox(height: 24),

                        // Logout button
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          child: SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: colorScheme.error,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: _handleLogout,
                              child: _loggingOut
                                  ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                                  : Text('Log out', style: theme.textTheme.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w500)),
                            ),
                          ),
                        ),

                        const SizedBox(height: 12),

                        // Delete Account (danger)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          child: SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(color: colorScheme.error),
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: _handleDeleteAccount,
                              child: _deletingAccount
                                  ? SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: colorScheme.error),
                                    )
                                  : Text('Delete account', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: colorScheme.error, fontWeight: FontWeight.w600)),
                            ),
                          ),
                        ),

                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Extracted ProfileHeader widget for better performance
class _ProfileHeader extends StatelessWidget {
  final String? displayName;
  final String? profileImageUrl;
  final String? userLocation;
  final String? userEmail;
  final bool isDark;
  final ColorScheme colorScheme;
  final bool Function(String? url) isValidHttpUrl;
  final bool loadingArtisan;
  final String? artisanError;
  final String? artisanTrade;
  final bool? artisanVerified;
  final double? artisanRating;
  final List<String> artisanPortfolio;
  final VoidCallback onTap;

  const _ProfileHeader({
    required this.displayName,
    required this.profileImageUrl,
    required this.userLocation,
    required this.userEmail,
    required this.isDark,
    required this.colorScheme,
    required this.isValidHttpUrl,
    required this.loadingArtisan,
    required this.artisanError,
    required this.artisanTrade,
    required this.artisanVerified,
    required this.artisanRating,
    required this.artisanPortfolio,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurfaceAlpha30 = colorScheme.onSurface.withAlpha((0.3 * 255).toInt());
    final onSurfaceAlpha50 = colorScheme.onSurface.withAlpha((0.5 * 255).toInt());
    final onSurfaceAlpha60 = colorScheme.onSurface.withAlpha((0.6 * 255).toInt());

    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Stack(
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colorScheme.surface,
                  border: Border.all(color: onSurfaceAlpha30, width: 2),
                ),
                child: ClipOval(
                  child: isValidHttpUrl(profileImageUrl)
                      ? Image.network(
                    profileImageUrl!,
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Center(
                        child: CircularProgressIndicator(
                          value: loadingProgress.expectedTotalBytes != null
                              ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                              : null,
                          color: colorScheme.primary,
                        ),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) => Icon(
                      Icons.person_outline,
                      size: 48,
                      color: onSurfaceAlpha30,
                    ),
                    cacheWidth: 200, // Optimize image loading
                    cacheHeight: 200,
                  )
                      : Icon(
                    Icons.person_outline,
                    size: 48,
                    color: onSurfaceAlpha30,
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colorScheme.primary,
                    border: Border.all(color: isDark ? Colors.black : Colors.white, width: 3),
                  ),
                  child: Icon(Icons.edit_outlined, size: 16, color: colorScheme.onPrimary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Show KYC badge next to name when artisan is verified
          // Rebuild the name row with optional badge
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  displayName ?? 'User',
                  style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (artisanVerified == true) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: Colors.green.withAlpha(30), borderRadius: BorderRadius.circular(12)),
                  child: Row(children: [ const Icon(Icons.verified, size: 14, color: Colors.green), const SizedBox(width: 6), Text('KYC verified', style: theme.textTheme.bodySmall?.copyWith(color: Colors.green, fontWeight: FontWeight.w600)), ]),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            userEmail ?? '',
            style: theme.textTheme.bodyMedium?.copyWith(color: onSurfaceAlpha60),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          if (userLocation != null && userLocation!.isNotEmpty)
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(Icons.location_on_outlined, size: 14, color: onSurfaceAlpha50),
                const SizedBox(height: 4),
                Tooltip(
                  message: userLocation!,
                  waitDuration: const Duration(milliseconds: 300),
                  showDuration: const Duration(seconds: 3),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: Text(
                      userLocation!,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(color: onSurfaceAlpha60),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          if (loadingArtisan)
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: colorScheme.primary),
              ),
            ),
          if (artisanError != null && !loadingArtisan)
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(artisanError!, style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.error)),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => context.findAncestorStateOfType<_ProfileWidgetState>()?._loadProfile(),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          if (!loadingArtisan && artisanTrade != null)
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Tooltip(
                      message: artisanTrade ?? '',
                      waitDuration: const Duration(milliseconds: 300),
                      showDuration: const Duration(seconds: 3),
                      child: Builder(builder: (context) {
                        // Normalize trade label: remove surrounding brackets or decode JSON list
                        String label = (artisanTrade ?? '');
                        try {
                          if (label.trim().startsWith('[') && label.trim().endsWith(']')) {
                            final parsed = jsonDecode(label);
                            if (parsed is List) label = parsed.map((e) => e?.toString() ?? '').where((s) => s.isNotEmpty).join(', ');
                          }
                        } catch (_) {
                          // fallback: strip leading/trailing brackets
                          if (label.startsWith('[') && label.endsWith(']')) label = label.substring(1, label.length - 1);
                        }

                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: colorScheme.primary.withAlpha((0.12 * 255).toInt()),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            label,
                            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: colorScheme.primary),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }),
                    ),
                  ),
                  if (artisanVerified == true) ...[
                    const SizedBox(width: 8),
                    Icon(Icons.verified, size: 16, color: Colors.green),
                  ],
                  if (artisanRating != null) ...[
                    const SizedBox(width: 8),
                    Icon(Icons.star, size: 14, color: Colors.amber),
                    const SizedBox(width: 4),
                    Text(artisanRating!.toStringAsFixed(1), style: theme.textTheme.bodySmall),
                  ],
                ],
              ),
            ),
          if (artisanPortfolio.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12.0),
              child: SizedBox(
                height: 80,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  scrollDirection: Axis.horizontal,
                  itemCount: artisanPortfolio.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final url = artisanPortfolio[i];
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 120,
                        height: 80,
                        child: url.isNotEmpty
                            ? Image.network(
                          url,
                          fit: BoxFit.cover,
                          cacheWidth: 240,
                          cacheHeight: 160,
                          errorBuilder: (_, __, ___) => Container(color: colorScheme.surface),
                        )
                            : Container(color: colorScheme.surface),
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// Extracted ProfileMenuSection widget for better performance
class _ProfileMenuSection extends StatelessWidget {
  final VoidCallback onEditProfile;
  final VoidCallback onMyJobs;
  final VoidCallback onWallet;
  final VoidCallback onHelpSupport;
  final VoidCallback onAboutUs;
  final ThemeData theme;
  final ColorScheme colorScheme;

  const _ProfileMenuSection({
    required this.onEditProfile,
    required this.onMyJobs,
    required this.onWallet,
    required this.onHelpSupport,
    required this.onAboutUs,
    required this.theme,
    required this.colorScheme,
  });

  Widget _buildMenuItem({required IconData icon, required String title, required VoidCallback onTap, Color? iconColor}) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: (iconColor ?? colorScheme.primary).withAlpha((0.1 * 255).toInt()),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, size: 20, color: iconColor ?? colorScheme.primary),
      ),
      title: Text(title, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500)),
      trailing: Icon(Icons.chevron_right_rounded, color: colorScheme.onSurface.withAlpha((0.3 * 255).toInt()), size: 20),
      contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 16.0, bottom: 12),
          child: Text('GENERAL', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1.0)),
        ),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: colorScheme.onSurface.withAlpha((0.1 * 255).toInt()), width: 1),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
            child: Column(
              children: [
                _buildMenuItem(
                  icon: Icons.account_circle_outlined,
                  title: 'Edit Profile',
                  onTap: onEditProfile,
                ),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 16.0), child: Divider(height: 1)),
                _buildMenuItem(
                  icon: Icons.work_outline,
                  title: 'My Jobs',
                  onTap: onMyJobs,
                ),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 16.0), child: Divider(height: 1)),
                _buildMenuItem(
                  icon: Icons.account_balance_wallet_outlined,
                  title: 'Wallet',
                  onTap: onWallet,
                ),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 16.0), child: Divider(height: 1)),
                _buildMenuItem(
                  icon: Icons.help_outline,
                  title: 'Help & Support',
                  onTap: onHelpSupport,
                ),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 16.0), child: Divider(height: 1)),
                _buildMenuItem(
                  icon: Icons.info_outline,
                  title: 'About Us',
                  onTap: onAboutUs,
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ],
    );
  }
}



