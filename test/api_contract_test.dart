// The app's API repositories against a real RijHub API: every mapping from
// the API's JSON to the app's models, exercised the way the screens use
// them, on both sides of a booking.
//
// Skipped unless pointed at a running API on sample data
// (scripts/seed_dev_data.py), with codes written to its log:
//
//   RIJHUB_API=http://127.0.0.1:8077 RIJHUB_API_LOG=/path/to/uvicorn.log \
//     flutter test test/api_contract_test.dart
//
// Run the API with SMS_BACKEND=log, OTP_RESEND_SECONDS=0 and a generous
// OTP_PER_NUMBER_PER_HOUR, as sign-ins repeat on every run. Against a
// deployed API, point RIJHUB_API_LOG at a file its log is copied into.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rijhub/data/api/api_client.dart';
import 'package:rijhub/data/api/api_context.dart';
import 'package:rijhub/data/api/api_repositories.dart';
import 'package:rijhub/data/api/api_social.dart';
import 'package:rijhub/data/api/realtime.dart';
import 'package:rijhub/data/api/token_store.dart';
import 'package:rijhub/data/api/uploads.dart';
import 'package:rijhub/data/models/models.dart';
import 'package:rijhub/data/repositories/repositories.dart';

final _api = Platform.environment['RIJHUB_API'];
final _log = Platform.environment['RIJHUB_API_LOG'];

/// One person's app: their own tokens and repositories.
class _App {
  _App(Uri base) {
    final api = ApiClient(baseUrl: base, tokens: MemoryTokenStore());
    c = ApiContext(
      api: api,
      uploads: Uploader(api),
      live: Realtime(api),
      checkout: (url, {required callback}) async =>
          fail('test mode never opens a checkout'),
    );
  }

  late final ApiContext c;
  late final auth = ApiAuthRepository(c);
  late final catalog = ApiCatalogRepository(c);
  late final directory = ApiDirectoryRepository(c);
  late final artisans = ApiArtisanRepository(c);
  late final booking = ApiBookingFlowRepository(c);
  late final bookings = ApiBookingRepository(c);
  late final dashboard = ApiArtisanDashboardRepository(c);
  late final jobs = ApiJobRepository(c);
  late final clientJobs = ApiClientJobRepository(c);
  late final quotes = ApiQuoteRepository(c);
  late final chat = ApiChatRepository(c);
  late final notices = ApiNoticeRepository(c);
  late final wallet = ApiWalletRepository(c);
  late final account = ApiAccountRepository(c);
  late final setup = ApiArtisanSetupRepository(c);
  late final support = ApiSupportRepository(c);
  late final ask = ApiAskRepository(c);

  Future<AppUser> signIn(String phone) async {
    final before = (await _codesFor(phone)).length;
    final challenge = await auth.requestCode(phone);
    final result =
        await auth.verifyCode(challenge, await _newCodeFor(phone, before));
    final user = result.user!;
    auth.useAccount(user);
    return user;
  }
}

/// The codes the API "sent" [phone], oldest first, from its log
/// (SMS_BACKEND=log).
Future<List<String>> _codesFor(String phone) async {
  final code = RegExp('to ${RegExp.escape(phone)}: (\\d{6}) is your');
  final codes = <String>[];
  for (final line in await File(_log!).readAsLines()) {
    final m = code.firstMatch(line);
    if (m != null) codes.add(m.group(1)!);
  }
  return codes;
}

/// The code sent after the log already held [before] codes for [phone]. A
/// deployed API's log arrives seconds late, so this waits up to a minute.
Future<String> _newCodeFor(String phone, int before) async {
  for (var tries = 0; tries < 600; tries++) {
    final codes = await _codesFor(phone);
    if (codes.length > before) return codes.last;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  fail('no new code for $phone in $_log');
}

TimeWindow _tomorrow() {
  final start = DateTime.now().add(const Duration(days: 1));
  final at = DateTime(start.year, start.month, start.day, 10);
  return TimeWindow(start: at, end: at.add(const Duration(hours: 2)));
}

void main() {
  if (_api == null || _log == null) {
    test('API contract (set RIJHUB_API and RIJHUB_API_LOG to run)', () {},
        skip: 'no API to talk to');
    return;
  }
  // flutter_test blocks real HTTP by default; this suite is about it.
  setUpAll(() => HttpOverrides.global = null);
  final base = Uri.parse(_api!);

  test('reference data and the directory, as a guest', () async {
    final guest = _App(base);
    expect(await guest.catalog.categories(), hasLength(14));
    expect(await guest.catalog.areas(), contains('Wuse 2'));
    expect(await guest.catalog.priceGuide(), isNotEmpty);
    final stats = await guest.catalog.stats();
    expect(stats.verifiedArtisans, greaterThan(0));
    expect((await guest.support.faqs()), hasLength(26));

    final top = await guest.artisans.topRatedNearby(area: 'Wuse 2');
    expect(top, isNotEmpty);
    expect(top.first.location, isNotNull);
    final found =
        await guest.directory.search(area: 'Wuse 2', query: 'my AC is leaking');
    final emeka = found.firstWhere((a) => a.name == 'Emeka Nwosu');
    final profile = await guest.directory.profile(emeka.id, area: 'Wuse 2');
    expect(profile.services, isNotEmpty);
    expect(profile.businessName, 'Cool Breeze AC Services');
    expect(profile.ratings.byStars[5], greaterThan(0));
    expect(await guest.directory.reviews(emeka.id), isNotEmpty);

    final triage =
        await guest.ask.triage(const AskInput(text: 'My AC is leaking water'));
    expect(triage.categoryId, 'ac');
    expect(triage.isUrgent, isTrue);

    final jobs = await guest.jobs.openJobsNearby(area: 'Jabi');
    expect(jobs, isNotEmpty);
    expect(
        (await guest.jobs.demand(area: 'Wuse 2')).openThisWeek, greaterThan(0));

    // Guests get empty lists, not errors.
    expect(await guest.bookings.upcoming(as: UserRole.client), isEmpty);
    expect(await guest.directory.savedIds(), isEmpty);
    expect((await guest.dashboard.dashboard()).setupSteps, isNotEmpty);
  });

  test('a booking from request to review, on both phones', () async {
    final client = _App(base);
    final artisan = _App(base);
    final me = await client.signIn('+2347000000100');
    expect(me.firstName, 'Chidinma');
    final emeka = await artisan.signIn('+2347000000201');
    expect(emeka.role, UserRole.artisan);

    final profile = await client.directory.profile(emeka.id);
    final service = profile.services.first;
    final both = ServiceOffer(
      id: 'multi_${service.id}',
      categoryId: service.categoryId,
      name: '${service.name} + ${profile.services[1].name}',
      price: service.price + profile.services[1].price,
      parts: [service, profile.services[1]],
    );
    final price = await client.booking.price(both);
    expect(price.price, both.price);
    expect(price.fee, greaterThan(0));

    final requested = await client.booking.request(BookingDraft(
      artisan: profile.artisan,
      service: both,
      window: _tomorrow(),
      area: 'Wuse 2',
      landmark: 'Near Banex Plaza',
      notes: 'The bedroom AC drips.',
    ));
    expect(requested.status, BookingStatus.requested);
    expect(requested.payment, PaymentState.held);
    expect(requested.total, price.total);
    expect(requested.scheduledAt.hour, 10); // local time, both ways

    final waiting = await artisan.dashboard.requests();
    final request = waiting.firstWhere((r) => r.id == requested.id);
    expect(request.clientName, 'Chidinma O.');
    final accepted = await artisan.dashboard.respond(request.id, accept: true);
    expect(accepted!.status, BookingStatus.confirmed);
    expect(accepted.counterpartName, 'Chidinma Okafor');

    final mine = await client.booking.byId(requested.id);
    expect(mine.startCode, hasLength(4));
    expect(
        (await client.bookings.upcoming(as: UserRole.client)).map((b) => b.id),
        contains(requested.id));

    // Chat, live: the artisan's thread hears the client's message.
    final convo = await artisan.chat.forBooking(requested.id);
    final heard = Completer<void>();
    final sub = artisan.chat.watch(convo.id).listen((messages) {
      if (messages.any((m) => m.text == 'See you at 10') &&
          !heard.isCompleted) {
        heard.complete();
      }
    });
    await client.chat.send(convo.id, text: 'See you at 10');
    await heard.future.timeout(const Duration(seconds: 15));
    await sub.cancel();

    await artisan.booking.onMyWay(requested.id);
    await expectLater(artisan.booking.start(requested.id, '00000'),
        throwsA(isA<AppException>()));
    final started = await artisan.booking.start(requested.id, mine.startCode!);
    expect(started.status, BookingStatus.inProgress);
    await artisan.booking.finish(requested.id);
    final released = await client.booking.confirmDone(requested.id);
    expect(released.payment, PaymentState.released);
    final reviewed =
        await client.booking.review(requested.id, rating: 5, text: 'Spotless');
    expect(reviewed.yourRating, 5);

    expect((await artisan.wallet.summary()).available, greaterThan(0));
    final txs = await client.wallet.transactions();
    expect(txs.first.kind, TxKind.payment);
    expect((await artisan.notices.notices()), isNotEmpty);
    expect(await client.notices.unreadCount().first, greaterThan(0));
    expect((await client.artisans.hiredBefore()).map((h) => h.artisan.id),
        contains(emeka.id));
    expect((await client.booking.past(as: UserRole.client)).map((b) => b.id),
        contains(requested.id));
  });

  test('a posted job, a quote, and booking it', () async {
    final client = _App(base);
    final artisan = _App(base);
    await client.signIn('+2347000000100');
    await artisan.signIn('+2347000000201');

    final job = await client.clientJobs.post(const JobDraft(
      title: 'Service two AC units',
      categoryId: 'ac',
      area: 'Wuse 2',
      description: 'Both split units, upstairs.',
      budgetMin: 10000,
      budgetMax: 20000,
    ));
    expect(job.status, JobStatus.open);
    final post = await artisan.quotes.job(job.id);
    expect(post.title, 'Service two AC units');
    final quote = await artisan.quotes.send(
        job.id,
        QuoteDraft(
          price: 15000,
          message: 'I can do both tomorrow.',
          canStartAt: _tomorrow().start,
        ));
    expect(quote.status, QuoteStatus.pending);
    expect((await artisan.quotes.myQuoteOn(job.id))!.id, quote.id);

    final withQuote = await client.clientJobs.byId(job.id);
    expect(withQuote.quotes.single.price, 15000);
    final booked =
        await client.clientJobs.accept(job.id, quote.id, window: _tomorrow());
    expect(booked.status, BookingStatus.confirmed);
    expect((await client.clientJobs.byId(job.id)).status, JobStatus.booked);
  });

  test('the account and the artisan\'s business pages', () async {
    final client = _App(base);
    await client.signIn('+2347000000100');
    final place = await client.account.savePlace(SavedPlace(
        id: 'p_${DateTime.now().millisecondsSinceEpoch}',
        label: 'Office',
        area: 'Jabi',
        address: '5 Obafemi Awolowo Way'));
    expect(
        (await client.account.places()).map((p) => p.id), contains(place.id));
    await client.account.deletePlace(place.id);
    final prefs = await client.notices.prefs();
    await client.notices.savePrefs(prefs.copyWith(tips: true));
    expect((await client.notices.prefs()).tips, isTrue);
    await client.notices.savePrefs(prefs);

    final artisan = _App(base);
    await artisan.signIn('+2347000000201');
    final dashboard = await artisan.dashboard.dashboard();
    expect(dashboard.setupSteps.map((s) => s.id),
        containsAll(['services', 'identity']));
    final added = await artisan.setup.saveService(ServiceOffer(
        id: 's_${DateTime.now().millisecondsSinceEpoch}',
        categoryId: 'ac',
        name: 'Duct cleaning',
        price: 9000));
    expect((await artisan.setup.myProfile()).services.map((s) => s.id),
        contains(added.id));
    await artisan.setup.deleteService(added.id);
    expect(
        (await artisan.setup.verification()).state, VerificationState.verified);
    await artisan.dashboard.setAvailability(false,
        busyUntil: DateTime.now().add(const Duration(hours: 2)));
    expect((await artisan.dashboard.dashboard()).availability,
        AvailabilityStatus.busy);
    await artisan.dashboard.setAvailability(true);
    expect((await artisan.dashboard.dashboard()).isAvailable, isTrue);
  });

  test('a new number signs up, and sends a photo', () async {
    final app = _App(base);
    // A number nobody has yet, different on every run.
    final ms = DateTime.now().millisecondsSinceEpoch;
    final number = '0700009${(ms % 10000).toString().padLeft(4, '0')}';
    final phone = '+234${number.substring(1)}';
    final before = (await _codesFor(phone)).length;
    final challenge = await app.auth.requestCode(number);
    expect(challenge.phone, phone);
    final verified =
        await app.auth.verifyCode(challenge, await _newCodeFor(phone, before));
    expect(verified.isNewUser, isTrue);
    final user = await app.auth.createAccount(
        phone: phone,
        role: UserRole.client,
        firstName: 'Ada',
        lastName: 'Okeke',
        area: 'Wuse 2');
    expect(user.firstName, 'Ada');
    app.auth.useAccount(user);

    // Straight to Cloud Storage with the API's signed link, then public.
    final photo = File('${Directory.systemTemp.createTempSync('rijhub').path}'
        '/leak.jpg')
      ..writeAsBytesSync(List<int>.generate(64, (i) => i));
    final url = await app.c.uploads.upload(photo.path, UploadKind.problem);
    expect(url, isNotNull);
    final http = HttpClient();
    final served = await (await http.getUrl(Uri.parse(url!))).close();
    expect(served.statusCode, 200);
    http.close();
  });
}
