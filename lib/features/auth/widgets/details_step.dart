import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:provider/provider.dart';

import '../../../app/session.dart';
import '../../../core/theme/theme.dart';
import '../../../core/utils/category_icons.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/models/models.dart';
import '../../../data/repositories/repositories.dart';
import 'auth_feedback.dart';
import 'auth_step_header.dart';
import 'auth_step_layout.dart';

/// The last step, for new numbers only: the name people will see and, for
/// artisans, what they do. Someone who hasn't picked a side of the app yet
/// (signing up from the welcome screen) first says how they'll use RijHub.
/// Creating the account signs the person in, which the sheet sees and
/// finishes. Email waits until a receipt needs it.
class AuthDetailsStep extends StatefulWidget {
  const AuthDetailsStep({super.key, required this.onBusyChanged});

  /// True while the account is being created, false if that fails. The
  /// sheet holds its back button meanwhile.
  final ValueChanged<bool> onBusyChanged;

  @override
  State<AuthDetailsStep> createState() => _AuthDetailsStepState();
}

class _AuthDetailsStepState extends State<AuthDetailsStep> {
  static const _maxTrades = 3;

  final _name = TextEditingController();
  final _focus = FocusNode();

  /// Category ids, in the order they were picked.
  final _picked = <String>{};

  /// No side of the app has been picked on this device yet, so the step
  /// asks which one the account is for.
  late final bool _askRole;

  /// The side the account is for. Null until it is picked, when asked.
  UserRole? _role;

  /// Null while loading.
  List<ServiceCategory>? _trades;
  bool _tradesFailed = false;

  /// A fourth trade was tapped.
  bool _atLimit = false;
  bool _saving = false;
  String? _error;

  bool get _isArtisan => _role == UserRole.artisan;

  bool get _canSubmit =>
      _role != null &&
      isFullName(_name.text) &&
      (!_isArtisan || _picked.isNotEmpty);

  /// Trades already given in the chat: not asked again.
  bool _tradesKnown = false;

  @override
  void initState() {
    super.initState();
    final session = context.read<SessionController>();
    _askRole = !session.hasOnboarded;
    if (!_askRole) _role = context.read<AuthFlowController>().role;
    // Trades already picked while looking around, so they aren't asked for.
    _picked.addAll(session.guestTrades.take(_maxTrades));
    _tradesKnown = _picked.isNotEmpty;
    // Loaded before "Find work" is picked, so the list is there at once.
    if (!_tradesKnown && (_askRole || _isArtisan)) _loadTrades();
    // The name comes first, unless the side is asked for: then it follows.
    if (!_askRole) _focusName();
  }

  @override
  void dispose() {
    _name.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// After this frame: autofocus can't take focus from the step this one
  /// replaces, nor reach a field that has only just appeared.
  void _focusName() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  void _pickRole(UserRole role) {
    // The first pick brings up the name field, which is next.
    if (_role == null) _focusName();
    setState(() => _role = role);
  }

  Future<void> _loadTrades() async {
    try {
      final trades = await context.read<CatalogRepository>().categories();
      if (!mounted) return;
      setState(() {
        _trades = trades;
        // An artisan can't go on without a trade, so an empty list is as
        // much a dead end as a failed one.
        _tradesFailed = trades.isEmpty;
      });
    } catch (_) {
      if (mounted) setState(() => _tradesFailed = true);
    }
  }

  void _retryTrades() {
    setState(() {
      _trades = null;
      _tradesFailed = false;
    });
    _loadTrades();
  }

  void _toggle(String id) {
    // Picking trades isn't typing, so the keyboard makes way for the list.
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      final picked = _picked.contains(id);
      _atLimit = !picked && _picked.length >= _maxTrades;
      if (picked) {
        _picked.remove(id);
      } else if (!_atLimit) {
        _picked.add(id);
      }
    });
  }

  void _onSubmitted(String _) {
    if (!_isArtisan) _create();
  }

  Future<void> _create() async {
    if (_saving || !_canSubmit) return;
    final role = _role!;
    final session = context.read<SessionController>();
    final flow = context.read<AuthFlowController>();
    setState(() {
      _saving = true;
      _error = null;
    });
    widget.onBusyChanged(true);
    try {
      // The side they picked is the one the account is created for, and
      // the one the app opens on.
      if (_askRole) await session.continueAsGuest(role);
      await flow.createAccount(
        fullName: _name.text.trim(),
        tradeIds: role == UserRole.artisan ? _picked.toList() : const [],
      );
    } on AuthException catch (e) {
      _createFailed(e.message);
    } catch (e, s) {
      _createFailed(reportUnexpectedAuthError(e, s));
    }
  }

  void _createFailed(String message) {
    if (!mounted) return;
    setState(() {
      _saving = false;
      _error = message;
    });
    widget.onBusyChanged(false);
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    final role = _role;
    return AuthStepLayout(
      action: AppButton(
        label: _isArtisan ? 'Create profile' : 'Create account',
        isLoading: _saving,
        onPressed: _canSubmit ? _create : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(),
          if (_askRole) ...[
            SizedBox(height: AppSpace.s24),
            _RolePicker(role: role, onPicked: _pickRole),
          ],
          if (role != null) ...[
            SizedBox(height: AppSpace.s24),
            AppTextField(
              // As on their ID: an artisan's is checked against it.
              label: 'Full name, as it is on your ID',
              controller: _name,
              focusNode: _focus,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.name],
              autocorrect: false,
              enableSuggestions: false,
              // Rebuilds so the button turns on at the second letter.
              onChanged: (_) => setState(() {}),
              onSubmitted: _onSubmitted,
            ),
          ],
          if (_isArtisan && !_tradesKnown) ...[
            SizedBox(height: AppSpace.s24),
            _TradePicker(
              trades: _trades,
              failed: _tradesFailed,
              picked: _picked,
              atLimit: _atLimit,
              onToggle: _toggle,
              onRetry: _retryTrades,
            ),
          ],
          if (error != null) ...[
            SizedBox(height: AppSpace.s16),
            AuthStatusLine(message: error),
          ],
        ],
      ),
    );
  }

  AuthStepHeader _header() {
    if (_askRole) {
      return AuthStepHeader(
        title: 'Create your account',
        message: 'This number is new to Employi.',
      );
    }
    if (_isArtisan) {
      return AuthStepHeader(
        title: 'Set up your profile',
        message: 'Clients will see this on your profile.',
      );
    }
    return AuthStepHeader(
      title: "What's your name?",
      message: "So artisans know who they're working with.",
    );
  }
}

/// "How will you use Employi?": the welcome screen's two ways in, for a
/// new number that arrived before either was picked.
class _RolePicker extends StatelessWidget {
  const _RolePicker({required this.role, required this.onPicked});

  final UserRole? role;
  final ValueChanged<UserRole> onPicked;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'How will you use Employi?',
          style: AppText.labelSmall.copyWith(color: c.textPrimary),
        ),
        SizedBox(height: AppSpace.s12),
        SelectionCard(
          icon: IconsaxPlusLinear.user_search,
          title: 'Hire an artisan',
          subtitle: 'For homes and businesses',
          selected: role == UserRole.client,
          onTap: () => onPicked(UserRole.client),
        ),
        SizedBox(height: AppSpace.s12),
        SelectionCard(
          icon: IconsaxPlusLinear.briefcase,
          title: 'Find work',
          subtitle: "I'm an artisan",
          selected: role == UserRole.artisan,
          onTap: () => onPicked(UserRole.artisan),
        ),
      ],
    );
  }
}

/// "What do you do?": up to three trades from the catalogue, as chips.
class _TradePicker extends StatelessWidget {
  const _TradePicker({
    required this.trades,
    required this.failed,
    required this.picked,
    required this.atLimit,
    required this.onToggle,
    required this.onRetry,
  });

  /// Null while loading.
  final List<ServiceCategory>? trades;
  final bool failed;
  final Set<String> picked;
  final bool atLimit;
  final ValueChanged<String> onToggle;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final trades = this.trades;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'What do you do?',
          style: AppText.labelSmall.copyWith(color: c.textPrimary),
        ),
        SizedBox(height: AppSpace.s4),
        // The limit note takes the hint's place, so the chips don't move
        // under the finger that just tapped one.
        if (atLimit)
          Semantics(
            container: true,
            liveRegion: true,
            child: Row(
              children: [
                Icon(
                  IconsaxPlusBold.info_circle,
                  size: AppSize.iconSmall,
                  color: c.warning,
                ),
                SizedBox(width: AppSpace.s4),
                Flexible(
                  child: Text(
                    'You can pick up to 3 for now.',
                    style: AppText.caption.copyWith(color: c.textSecondary),
                  ),
                ),
              ],
            ),
          )
        else
          Text(
            'Pick up to 3.',
            style: AppText.caption.copyWith(color: c.textTertiary),
          ),
        SizedBox(height: AppSpace.s8),
        if (failed)
          InlineError(
            message: "We couldn't load the list of trades.",
            onRetry: onRetry,
          )
        else if (trades == null)
          const _TradeSkeletons()
        else
          // Chips are 40 tall in a 48-point touch area, so rows sit 8 apart
          // with no run spacing.
          Wrap(
            spacing: AppSpace.s8,
            children: [
              for (final trade in trades)
                AppChip(
                  label: trade.name,
                  icon: CategoryIcons.of(trade.iconKey),
                  selected: picked.contains(trade.id),
                  onTap: () => onToggle(trade.id),
                ),
            ],
          ),
      ],
    );
  }
}

/// Chip-shaped placeholders, in the same rows the chips will take.
class _TradeSkeletons extends StatelessWidget {
  const _TradeSkeletons();

  static const _widths = [116.0, 124.0, 104.0, 128.0, 96.0, 120.0, 112.0];

  @override
  Widget build(BuildContext context) {
    return SkeletonPulse(
      child: Wrap(
        spacing: AppSpace.s8,
        children: [
          for (final width in _widths)
            SizedBox(
              height: AppSize.minTapTarget,
              child: Center(
                widthFactor: 1,
                child: SkeletonBox(
                  width: width.w,
                  height: 40,
                  radius: AppRadius.pill,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
