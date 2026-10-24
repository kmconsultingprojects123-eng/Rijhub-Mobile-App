import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:provider/provider.dart';

import '../../app/routes.dart';
import '../../app/live_updates.dart';
import '../../core/theme/theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../account/account_pages.dart';
import '../shared/page.dart';

// ---------------------------------------------------------------- wallet

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  int _tab = 0;
  bool _hidden = false;
  bool _sending = false;

  /// Sends what's waiting to the bank now, in one tap.
  Future<void> _send(int amount, Future<void> Function() reload) async {
    setState(() => _sending = true);
    try {
      await context.read<WalletRepository>().withdraw(amount);
      if (!mounted) return;
      showToast(context, '${Naira.format(amount)} is on its way to your bank.');
      await reload();
    } on AppException catch (e) {
      if (mounted) showToast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Loader<
        (WalletSummary, List<WalletTx>, PayoutAccount?, ArtisanProfile)>(
      reloadOn: context.read<LiveUpdates>(),
      load: () async {
        final w = context.read<WalletRepository>();
        final r = await Future.wait<Object?>([
          w.summary(),
          w.transactions(),
          w.payoutAccount(),
          context.read<ArtisanSetupRepository>().myProfile(),
        ]);
        return (
          r[0]! as WalletSummary,
          r[1]! as List<WalletTx>,
          r[2] as PayoutAccount?,
          r[3]! as ArtisanProfile
        );
      },
      loading:
          const PageScaffold(title: 'Wallet and payouts', body: ListSkeleton()),
      builder: (context, data, reload) {
        final (s, tx, account, profile) = data;
        final jobs = profile.artisan.jobsCompleted;
        String money(int n) => _hidden ? '₦•••••' : Naira.format(n);
        final shown = switch (_tab) {
          1 => tx.where((t) => t.status == TxStatus.pending).toList(),
          2 => tx.where((t) => t.status != TxStatus.pending).toList(),
          _ => tx,
        };
        return PageScaffold(
          title: 'Wallet and payouts',
          actions: [
            AppIconButton(
              icon:
                  _hidden ? IconsaxPlusLinear.eye_slash : IconsaxPlusLinear.eye,
              semanticLabel: _hidden ? 'Show amounts' : 'Hide amounts',
              onPressed: () => setState(() => _hidden = !_hidden),
            ),
          ],
          body: RefreshIndicator(
            color: c.brandStroke,
            onRefresh: reload,
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                  AppSpace.gutter, 4.w, AppSpace.gutter, 24.w),
              children: [
                _MoneyCard(
                  summary: s,
                  account: account,
                  money: money,
                  sending: _sending,
                  onAddAccount: () async {
                    final saved =
                        await context.push<bool>(Routes.payoutAccount);
                    if (saved == true) await reload();
                  },
                  onSend: () => _send(s.available, reload),
                ),
                SizedBox(height: 12.w),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Stat(
                          label: 'On hold',
                          value: money(s.held),
                          hint: 'Yours when clients confirm'),
                      SizedBox(width: 10.w),
                      _Stat(
                          label: 'Earned on Employi',
                          value: money(s.earnedTotal),
                          hint: switch (jobs) {
                            0 => 'No jobs yet',
                            1 => 'From 1 job',
                            _ => 'From $jobs jobs'
                          }),
                    ],
                  ),
                ),
                // Where the money goes, to change it. Without an account the
                // card above asks for one.
                if (account != null) ...[
                  SizedBox(height: 16.w),
                  Pressable(
                    onTap: () async {
                      final saved =
                          await context.push<bool>(Routes.payoutAccount);
                      if (saved == true) await reload();
                    },
                    semanticLabel:
                        'Bank account, ${account.bank.name} ${account.masked}. Change',
                    child: Container(
                      padding: EdgeInsets.all(14.w),
                      decoration: BoxDecoration(
                        color: c.surface,
                        borderRadius: BorderRadius.circular(16.w),
                        border: Border.all(color: c.border),
                      ),
                      child: Row(
                        children: [
                          Icon(IconsaxPlusLinear.bank,
                              size: 22.w, color: c.textPrimary),
                          SizedBox(width: 12.w),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${account.bank.name} ${account.masked}',
                                    style: AppText.titleSmall),
                                Text(
                                  account.accountName,
                                  style: AppText.bodySmall
                                      .copyWith(color: c.textSecondary),
                                ),
                              ],
                            ),
                          ),
                          Text('Change',
                              style: AppText.labelSmall
                                  .copyWith(color: c.brandText)),
                        ],
                      ),
                    ),
                  ),
                ],
                SizedBox(height: 22.w),
                Text('Activity', style: AppText.title),
                SizedBox(height: 10.w),
                SegmentedTabs(
                    labels: const ['All', 'Pending', 'Completed'],
                    selected: _tab,
                    onChanged: (i) => setState(() => _tab = i)),
                SizedBox(height: 6.w),
                if (shown.isEmpty)
                  Padding(
                    padding: EdgeInsets.only(top: 40.w),
                    child: const EmptyState(
                        icon: IconsaxPlusLinear.wallet_2,
                        title: 'Nothing here yet',
                        message: 'Your earnings and payouts show here.'),
                  ),
                for (final t in shown) TxRow(tx: t),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// What happened to the artisan's money. Earnings go straight to their
/// bank when a job is confirmed, so this mostly says where it went; money
/// still waiting (no bank account yet, or a transfer that failed) gets the
/// one button that sends it.
class _MoneyCard extends StatelessWidget {
  const _MoneyCard({
    required this.summary,
    required this.account,
    required this.money,
    required this.sending,
    required this.onAddAccount,
    required this.onSend,
  });

  final WalletSummary summary;
  final PayoutAccount? account;
  final String Function(int) money;
  final bool sending;
  final VoidCallback onAddAccount;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = summary, a = account;
    final waiting = s.available > 0;
    // Earned less what's waiting: sent, or on its way.
    final sent = (s.earnedTotal - s.available).clamp(0, s.earnedTotal);
    final (String label, int amount, String note) = switch ((a, waiting)) {
      (null, _) => (
          waiting ? 'Waiting to be sent' : 'Paid straight to your bank',
          waiting ? s.available : sent,
          "Add your bank account, and we'll send your money there as soon as each job is confirmed."
        ),
      (_, true) => (
          'Waiting to be sent',
          s.available,
          'It goes to ${a!.bank.name} ${a.masked} by itself. Send it now if you\'d rather not wait.'
        ),
      _ => (
          'Sent to your bank',
          sent,
          'Paid to ${a!.bank.name} ${a.masked} as soon as each job is confirmed.'
        ),
    };
    return Container(
      padding: EdgeInsets.all(18.w),
      decoration: BoxDecoration(
          color: c.surfaceStrong, borderRadius: BorderRadius.circular(22.w)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: AppText.bodySmall
                  .copyWith(color: c.onSurfaceStrong.withValues(alpha: 0.7))),
          SizedBox(height: 4.w),
          Text(money(amount),
              style: AppText.display.copyWith(
                  color: c.onSurfaceStrong, fontWeight: FontWeight.w800)),
          SizedBox(height: 6.w),
          Text(note,
              style: AppText.bodySmall
                  .copyWith(color: c.onSurfaceStrong.withValues(alpha: 0.7))),
          if (a == null || waiting) ...[
            SizedBox(height: 14.w),
            AppButton(
              label: a == null ? 'Add your bank account' : 'Send to my bank',
              variant: AppButtonVariant.inverse,
              isLoading: sending,
              onPressed: sending ? null : (a == null ? onAddAccount : onSend),
            ),
          ],
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.hint});

  final String label;
  final String value;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Expanded(
      child: Container(
        padding: EdgeInsets.all(14.w),
        decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16.w),
            border: Border.all(color: c.border)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: AppText.caption.copyWith(color: c.textSecondary)),
            SizedBox(height: 4.w),
            Text(value, style: AppText.title),
            Text(hint, style: AppText.caption.copyWith(color: c.textTertiary)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- bank

class PayoutAccountScreen extends StatefulWidget {
  const PayoutAccountScreen({super.key});

  @override
  State<PayoutAccountScreen> createState() => _PayoutAccountScreenState();
}

class _PayoutAccountScreenState extends State<PayoutAccountScreen> {
  Bank? _bank;
  final _number = TextEditingController();
  final _numberFocus = FocusNode();
  String? _name;
  String? _error;
  bool _checking = false;
  bool _saving = false;
  Timer? _debounce;
  int _check = 0;

  @override
  void initState() {
    super.initState();
    context.read<WalletRepository>().payoutAccount().then((a) {
      if (!mounted) return;
      // Nothing saved yet: start typing the number straight away.
      if (a == null) {
        _numberFocus.requestFocus();
        return;
      }
      setState(() {
        _bank = a.bank;
        _number.text = a.accountNumber;
        _name = a.accountName;
      });
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _number.dispose();
    _numberFocus.dispose();
    super.dispose();
  }

  void _changed() {
    _debounce?.cancel();
    setState(() {
      _name = null;
      _error = null;
    });
    if (_number.text.length != 10) return;
    // The number first, then the bank: its list opens by itself.
    if (_bank == null) {
      _numberFocus.unfocus();
      _pickBank();
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 600), _resolve);
  }

  Future<void> _resolve() async {
    final id = ++_check;
    setState(() => _checking = true);
    try {
      final name = await context
          .read<WalletRepository>()
          .resolveAccount(_bank!, _number.text);
      if (mounted && id == _check) setState(() => _name = name);
    } on AppException catch (e) {
      if (mounted && id == _check) setState(() => _error = e.message);
    } finally {
      if (mounted && id == _check) setState(() => _checking = false);
    }
  }

  Future<void> _pickBank() async {
    final banks = await context.read<WalletRepository>().banks();
    if (!mounted) return;
    final picked = await showModalBottomSheet<Bank>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: context.colors.surface,
      builder: (_) => _BankPicker(banks: banks),
    );
    if (picked != null) {
      setState(() => _bank = picked);
      _changed();
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final repo = context.read<WalletRepository>();
    final saved = await runAction(
        context, () => repo.savePayoutAccount(_bank!, _number.text));
    if (!mounted) return;
    setState(() => _saving = false);
    if (saved == null) return;
    showToast(context, 'Bank account saved');
    goBack(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PageScaffold(
      title: 'Bank account',
      subtitle: 'Where your earnings go',
      bottom: AppButton(
        label: 'Save bank account',
        isLoading: _saving,
        onPressed: _name == null || _saving ? null : _save,
      ),
      body: ListView(
        padding:
            EdgeInsets.fromLTRB(AppSpace.gutter, 8.w, AppSpace.gutter, 24.w),
        children: [
          AppTextField(
            controller: _number,
            focusNode: _numberFocus,
            label: 'Account number',
            hint: '10 digits',
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(10)
            ],
            errorText: _error,
            onChanged: (_) => _changed(),
          ),
          SizedBox(height: 14.w),
          Text('Bank', style: AppText.labelSmall),
          SizedBox(height: 6.w),
          Pressable(
            onTap: _pickBank,
            semanticLabel: _bank == null
                ? 'Pick your bank'
                : 'Bank, ${_bank!.name}. Change',
            child: Container(
              height: AppSize.input,
              padding: EdgeInsets.symmetric(horizontal: 14.w),
              decoration: BoxDecoration(
                  color: c.surfaceMuted,
                  borderRadius: AppRadius.mdAll,
                  border: Border.all(color: c.inputBorder)),
              child: Row(
                children: [
                  Icon(IconsaxPlusLinear.bank,
                      size: 18.w, color: c.textSecondary),
                  SizedBox(width: 10.w),
                  Expanded(
                      child: Text(_bank?.name ?? 'Pick your bank',
                          style: AppText.bodyLarge.copyWith(
                              color: _bank == null
                                  ? c.textTertiary
                                  : c.textPrimary))),
                  Icon(IconsaxPlusLinear.arrow_down,
                      size: 16.w, color: c.textSecondary),
                ],
              ),
            ),
          ),
          SizedBox(height: 12.w),
          if (_checking)
            Row(
              children: [
                SizedBox(
                    width: 16.w,
                    height: 16.w,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: c.brandStroke)),
                SizedBox(width: 10.w),
                Text('Checking with the bank…',
                    style: AppText.bodySmall.copyWith(color: c.textSecondary)),
              ],
            )
          else if (_name != null)
            Container(
              padding: EdgeInsets.all(12.w),
              decoration: BoxDecoration(
                  color: c.successSubtle,
                  borderRadius: BorderRadius.circular(14.w)),
              child: Row(
                children: [
                  Icon(IconsaxPlusBold.tick_circle,
                      size: 20.w, color: c.success),
                  SizedBox(width: 10.w),
                  Expanded(child: Text(_name!, style: AppText.titleSmall)),
                ],
              ),
            ),
          SizedBox(height: 16.w),
          Text(
            'The account must be in your name. We check it with your bank, so the name fills in by itself.',
            style: AppText.bodySmall.copyWith(color: c.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _BankPicker extends StatefulWidget {
  const _BankPicker({required this.banks});

  final List<Bank> banks;

  @override
  State<_BankPicker> createState() => _BankPickerState();
}

class _BankPickerState extends State<_BankPicker> {
  final _q = TextEditingController();

  /// The banks most people in Nigeria use, first and in this order, so most
  /// artisans find theirs without searching; the rest follow A to Z.
  static const _common = [
    'opay',
    'moniepoint',
    'palmpay',
    'kuda',
    'guaranty trust',
    'access bank',
    'zenith',
    'first bank',
    'united bank for africa',
    'fidelity',
    'wema',
    'sterling',
    'union bank',
    'ecobank',
    'stanbic',
    'first city monument',
    'polaris',
  ];

  static int _rank(String bank) {
    final name = bank.toLowerCase();
    final i = _common.indexWhere(name.contains);
    return i < 0 ? _common.length : i;
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final q = _q.text.trim().toLowerCase();
    final shown =
        widget.banks.where((b) => b.name.toLowerCase().contains(q)).toList()
          ..sort((a, b) {
            final r = _rank(a.name).compareTo(_rank(b.name));
            return r != 0 ? r : a.name.compareTo(b.name);
          });
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.75,
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpace.gutter),
            child: AppTextField(
                controller: _q,
                semanticLabel: 'Search banks',
                hint: 'Search banks',
                autofocus: true,
                onChanged: (_) => setState(() {})),
          ),
          Expanded(
            child: shown.isEmpty
                ? Center(
                    child: Text('No banks match "${_q.text}"',
                        style: AppText.body.copyWith(color: c.textSecondary)))
                : ListView.builder(
                    itemCount: shown.length,
                    itemBuilder: (context, i) => ListTile(
                      title: Text(shown[i].name, style: AppText.body),
                      onTap: () => Navigator.of(context).pop(shown[i]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- withdraw

class WithdrawScreen extends StatefulWidget {
  const WithdrawScreen({super.key});

  @override
  State<WithdrawScreen> createState() => _WithdrawScreenState();
}

class _WithdrawScreenState extends State<WithdrawScreen> {
  final _amount = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  int? get _n => int.tryParse(_amount.text.replaceAll(RegExp(r'[^0-9]'), ''));

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Loader<(WalletSummary, PayoutAccount?)>(
      load: () async {
        final w = context.read<WalletRepository>();
        final r = await Future.wait<Object?>([w.summary(), w.payoutAccount()]);
        return (r[0]! as WalletSummary, r[1] as PayoutAccount?);
      },
      loading: const PageScaffold(title: 'Withdraw', body: ListSkeleton()),
      builder: (context, data, _) {
        final (s, account) = data;
        final n = _n;
        final tooMuch = n != null && n > s.available;
        return PageScaffold(
          title: 'Withdraw',
          subtitle: '${Naira.format(s.available)} available',
          bottom: AppButton(
            label: n == null || n == 0
                ? 'Enter an amount'
                : 'Withdraw ${Naira.format(n)}',
            isLoading: _sending,
            onPressed: n == null ||
                    n < 100 ||
                    tooMuch ||
                    _sending ||
                    account == null
                ? null
                : () async {
                    setState(() => _sending = true);
                    final repo = context.read<WalletRepository>();
                    final tx = await runAction(context, () => repo.withdraw(n));
                    if (!context.mounted) return;
                    setState(() => _sending = false);
                    if (tx == null) return;
                    showToast(context,
                        '${Naira.format(n)} is on its way to ${account.bank.name}');
                    goBack(context, true);
                  },
          ),
          body: ListView(
            padding: EdgeInsets.fromLTRB(
                AppSpace.gutter, 8.w, AppSpace.gutter, 24.w),
            children: [
              AppTextField(
                controller: _amount,
                label: 'Amount',
                hint: '₦20,000',
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                autofocus: true,
                errorText:
                    tooMuch ? "That's more than you have available." : null,
                onChanged: (_) => setState(() {}),
              ),
              SizedBox(height: 10.w),
              Wrap(
                spacing: 8.w,
                children: [
                  PromptChip(
                      label: 'All · ${Naira.format(s.available)}',
                      onTap: () =>
                          setState(() => _amount.text = '${s.available}')),
                  for (final v in [10000, 20000])
                    if (v < s.available)
                      PromptChip(
                          label: Naira.format(v),
                          onTap: () => setState(() => _amount.text = '$v')),
                ],
              ),
              SizedBox(height: 20.w),
              if (account != null) ...[
                InfoLine(
                    icon: IconsaxPlusLinear.bank,
                    label: 'To',
                    value: '${account.bank.name} ${account.masked}'),
                InfoLine(label: 'Name', value: account.accountName),
                const InfoLine(label: 'Fee', value: 'Free'),
                const InfoLine(
                    label: 'Arrives', value: 'Usually within minutes'),
              ] else
                InlineNote(
                  icon: IconsaxPlusLinear.bank,
                  title: 'Add your bank account first',
                  message: 'So we know where to send your money.',
                  iconColor: c.warning,
                ),
            ],
          ),
        );
      },
    );
  }
}
