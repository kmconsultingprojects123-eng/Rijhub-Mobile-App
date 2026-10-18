import 'dart:convert';
import 'dart:io';

import '../models/models.dart';
import '../repositories/repositories.dart';
import 'api_codec.dart';
import 'api_context.dart';
import 'uploads.dart';

/// The API-backed repositories for chat, notices, money, the account, the
/// artisan's own setup and help. The rest are in `api_repositories.dart`.

// ---------------------------------------------------------------- chat

class ApiChatRepository implements ChatRepository {
  ApiChatRepository(this._c);

  final ApiContext _c;

  @override
  Future<List<Conversation>> conversations() => _c.forMember(
        () async => [
          for (final j in asList(await _c.api.get('/v1/conversations')))
            conversationFrom(j),
        ],
        const <Conversation>[],
      );

  @override
  Future<Conversation> byId(String conversationId) async => conversationFrom(
      asMap(await _c.api.get('/v1/conversations/$conversationId')));

  @override
  Future<Conversation> withArtisan(String artisanId) async => conversationFrom(
      asMap(await _c.api.post('/v1/conversations/with/$artisanId')));

  @override
  Future<Conversation> forBooking(String bookingId) async {
    final booking = asMap(await _c.api.get('/v1/bookings/$bookingId'));
    final id = booking['conversation_id'] as String?;
    if (id == null) {
      throw const AppException(
          'You can message each other once the booking is paid.');
    }
    return byId(id);
  }

  @override
  Future<Conversation> withSupport() async =>
      conversationFrom(asMap(await _c.api.get('/v1/conversations/support')));

  @override
  Stream<List<ChatMessage>> watch(String conversationId) => _c.watching(
        conversationId,
        () async => [
          for (final j in asList(
              await _c.api.get('/v1/conversations/$conversationId/messages')))
            messageFrom(j),
        ],
        poll: const Duration(seconds: 10),
      );

  @override
  Future<void> send(String conversationId,
      {String? text, VoiceNote? voiceNote, String? photo}) async {
    final photoUrl =
        photo == null ? null : await _c.uploads.upload(photo, UploadKind.chat);
    final voiceUrl = voiceNote == null
        ? null
        : await _c.uploads.upload(voiceNote.path, UploadKind.voice);
    if (photo != null &&
        photoUrl == null &&
        (text == null || text.trim().isEmpty)) {
      throw const AppException(
          "Photos can't be sent yet. Write a message instead.");
    }
    if (voiceNote != null && voiceUrl == null) {
      throw const AppException(
          "Voice notes can't be sent yet. Write a message instead.");
    }
    await _c.api.post('/v1/conversations/$conversationId/messages', {
      if (text != null && text.trim().isNotEmpty) 'text': text.trim(),
      if (photoUrl != null) 'photo': photoUrl,
      if (voiceNote != null && voiceUrl != null)
        'voice_note': voiceTo(voiceNote, voiceUrl),
    });
    _c.changed(conversationId);
  }

  @override
  Future<void> markRead(String conversationId) async {
    await _c.api.post('/v1/conversations/$conversationId/read');
    _c.changed(ApiContext.unreadMessages);
  }

  @override
  Stream<int> unreadCount() => _c.watching(
        ApiContext.unreadMessages,
        () => _c.forMember(() async {
          final j = asMap(await _c.api.get('/v1/conversations/unread-count'));
          return (j['count']! as num).toInt();
        }, 0),
        poll: const Duration(seconds: 30),
      );
}

// ---------------------------------------------------------------- notices

class ApiNoticeRepository implements NoticeRepository {
  ApiNoticeRepository(this._c);

  final ApiContext _c;

  @override
  Future<List<AppNotice>> notices() => _c.forMember(
        () async => [
          for (final j in asList(await _c.api.get('/v1/notifications')))
            noticeFrom(j)
        ],
        const <AppNotice>[],
      );

  @override
  Future<void> markAllRead() async {
    await _c.api.post('/v1/notifications/read-all');
    _c.changed(ApiContext.notices);
  }

  @override
  Future<void> markRead(String noticeId) async {
    await _c.api.post('/v1/notifications/$noticeId/read');
    _c.changed(ApiContext.notices);
  }

  @override
  Stream<int> unreadCount() => _c.watching(
        ApiContext.notices,
        () => _c.forMember(() async {
          final j = asMap(await _c.api.get('/v1/notifications/unread-count'));
          return (j['count']! as num).toInt();
        }, 0),
        poll: const Duration(seconds: 30),
      );

  @override
  Future<NotificationPrefs> prefs() async =>
      prefsFrom(asMap(await _c.api.get('/v1/me/notification-prefs')));

  @override
  Future<void> savePrefs(NotificationPrefs prefs) async =>
      _c.api.put('/v1/me/notification-prefs', prefsTo(prefs));
}

// ---------------------------------------------------------------- money

class ApiWalletRepository implements WalletRepository {
  ApiWalletRepository(this._c);

  final ApiContext _c;
  List<Bank>? _banks;

  @override
  Future<WalletSummary> summary() async =>
      walletFrom(asMap(await _c.api.get('/v1/wallet')));

  @override
  Future<List<WalletTx>> transactions() async => [
        for (final j in asList(await _c.api.get('/v1/wallet/transactions')))
          txFrom(j)
      ];

  @override
  Future<PayoutAccount?> payoutAccount() async {
    final j = await _c.api.get('/v1/wallet/payout-account');
    return j == null ? null : payoutFrom(asMap(j));
  }

  @override
  Future<List<Bank>> banks() async => _banks ??= [
        for (final j in asList(await _c.api.get('/v1/banks'))) bankFrom(j)
      ];

  @override
  Future<String> resolveAccount(Bank bank, String accountNumber) async {
    final j = asMap(await _c.api.post('/v1/banks/resolve',
        {'bank_code': bank.code, 'account_number': accountNumber}));
    return j['account_name']! as String;
  }

  @override
  Future<PayoutAccount> savePayoutAccount(
          Bank bank, String accountNumber) async =>
      payoutFrom(asMap(await _c.api.put('/v1/wallet/payout-account', {
        'bank_code': bank.code,
        'bank_name': bank.name,
        'account_number': accountNumber,
      })));

  @override
  Future<WalletTx> withdraw(int amount) async => txFrom(
      asMap(await _c.api.post('/v1/wallet/withdraw', {'amount': amount})));
}

// ---------------------------------------------------------------- the account

/// An id the app made for something not yet saved ("p_1729…", "s_1729…"):
/// the API gives it a real one when it's created.
bool _isNew(String id, String prefix) =>
    RegExp('^${prefix}_\\d+\$').hasMatch(id);

class ApiAccountRepository implements AccountRepository {
  ApiAccountRepository(this._c);

  final ApiContext _c;

  @override
  Future<AppUser> updateProfile({
    required String firstName,
    required String lastName,
    String? email,
    String? photo,
  }) async {
    final photoUrl = photo == null
        ? null
        : await _c.uploads.upload(photo, UploadKind.avatar);
    final hasEmail = email != null && email.trim().isNotEmpty;
    return userFrom(asMap(await _c.api.patch('/v1/me', {
      'first_name': firstName,
      if (lastName.trim().isNotEmpty) 'last_name': lastName,
      if (hasEmail) 'email': email.trim() else 'clear_email': true,
      if (photoUrl != null) 'photo': photoUrl,
    })));
  }

  @override
  Future<List<SavedPlace>> places() async =>
      [for (final j in asList(await _c.api.get('/v1/me/places'))) placeFrom(j)];

  @override
  Future<SavedPlace> savePlace(SavedPlace place) async {
    final body = {
      'label': place.label,
      'area': place.area,
      'address': place.address
    };
    return placeFrom(asMap(_isNew(place.id, 'p')
        ? await _c.api.post('/v1/me/places', body)
        : await _c.api.put('/v1/me/places/${place.id}', body)));
  }

  @override
  Future<void> deletePlace(String placeId) async =>
      _c.api.delete('/v1/me/places/$placeId');

  @override
  Future<void> deleteAccount() async {
    await _c.api.delete('/v1/me');
    _c.live.stop();
    await _c.api.tokens.clear();
    _c.changed(ApiContext.everything);
  }

  @override
  Future<AppUser> switchRole(UserRole to,
      {List<String> tradeIds = const []}) async {
    final j = asMap(await _c.api.post('/v1/me/role', {
      'role': to.name,
      'trade_ids': tradeIds.take(3).toList(),
    }));
    // The role travels in the access token, so a new pair comes back.
    await _c.api.saveTokens(j['tokens']);
    _c.changed(ApiContext.everything);
    return userFrom(asMap(j['user']));
  }
}

// ---------------------------------------------------------------- the artisan's setup

class ApiArtisanSetupRepository implements ArtisanSetupRepository {
  ApiArtisanSetupRepository(this._c);

  final ApiContext _c;

  @override
  Future<ArtisanProfile> myProfile() async =>
      profileFrom(asMap(await _c.api.get('/v1/artisan/profile')));

  @override
  Future<void> saveAbout({
    required String about,
    required int experienceYears,
    String? businessName,
    List<String> certifications = const [],
  }) async =>
      _c.api.put('/v1/artisan/about', {
        'about': about,
        'experience_years': experienceYears,
        'business_name': businessName,
        'certifications': certifications,
      });

  @override
  Future<ServiceOffer> saveService(ServiceOffer service) async =>
      serviceFrom(asMap(_isNew(service.id, 's')
          ? await _c.api.post('/v1/artisan/services', serviceTo(service))
          : await _c.api
              .put('/v1/artisan/services/${service.id}', serviceTo(service))));

  @override
  Future<void> deleteService(String serviceId) async =>
      _c.api.delete('/v1/artisan/services/$serviceId');

  @override
  Future<WorkPhoto> addWorkPhoto(String image, {String? caption}) async {
    final url = await _c.uploads.upload(image, UploadKind.work);
    if (url == null) {
      throw const AppException("Photos can't be added yet. Try again later.");
    }
    return workFrom(asMap(await _c.api.post('/v1/artisan/work', {
      'image': url,
      if (caption != null && caption.trim().isNotEmpty)
        'caption': caption.trim(),
    })));
  }

  @override
  Future<void> deleteWorkPhoto(String photoId) async =>
      _c.api.delete('/v1/artisan/work/$photoId');

  @override
  Future<void> saveServiceArea(ServiceArea area) async => _c.api
      .put('/v1/artisan/area', {'area': area.area, 'radius_km': area.radiusKm});

  @override
  Future<void> saveHours(WorkingHours hours) async =>
      _c.api.put('/v1/artisan/hours', workingHoursTo(hours));

  @override
  Future<Verification> verification() async =>
      verificationFrom(asMap(await _c.api.get('/v1/artisan/verification')));

  @override
  Future<Verification> submitVerification(
      {required String nin, required String selfie}) async {
    // The selfie goes to Dojah through the API and isn't stored anywhere.
    final file = File(selfie.replaceFirst('file://', ''));
    if (!await file.exists()) {
      throw const AppException(
          'Take the selfie again: we couldn\'t find that photo.');
    }
    return verificationFrom(
        asMap(await _c.api.post('/v1/artisan/verification/nin', {
      'nin': nin,
      'selfie_image': base64Encode(await file.readAsBytes()),
    })));
  }
}

// ---------------------------------------------------------------- help

class ApiSupportRepository implements SupportRepository {
  ApiSupportRepository(this._c);

  final ApiContext _c;
  List<FaqItem>? _faqs;

  @override
  Future<List<FaqItem>> faqs() async => _faqs ??= [
        for (final j in asList(await _c.api.get('/v1/support/faqs'))) faqFrom(j)
      ];
}
