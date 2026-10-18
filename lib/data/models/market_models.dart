import 'package:flutter/foundation.dart';

import 'models.dart';

// ---------------------------------------------------------------- RijHub

/// RijHub at a glance, for the welcome: how many ID-checked artisans there
/// are, and how clients rate them.
@immutable
class MarketStats {
  const MarketStats({
    required this.verifiedArtisans,
    required this.averageRating,
    this.cover,
    this.faces = const [],
  });

  final int verifiedArtisans;
  final double averageRating;

  /// A photo of an artisan at work.
  final String? cover;

  /// A few of those artisans' photos.
  final List<String> faces;
}

// ---------------------------------------------------------------- artisans

/// One thing an artisan does, with its price.
@immutable
class ServiceOffer {
  const ServiceOffer({
    required this.id,
    required this.categoryId,
    required this.name,
    required this.price,
    this.priceMax,
    this.unit,
    this.parts = const [],
  });

  final String id;
  final String categoryId;

  /// "AC servicing", "Gas top-up".
  final String name;

  /// Naira. With [priceMax], the price is a range ("₦8,000 – ₦12,000").
  final int price;
  final int? priceMax;

  /// What the price is for, when it isn't the whole job: "per unit".
  final String? unit;

  /// The services this offer puts together, when several are booked as
  /// one ("AC servicing + Gas top-up"), each at its own price. Empty for a
  /// single service.
  final List<ServiceOffer> parts;

  ServiceOffer copyWith(
          {String? name, int? price, int? priceMax, String? unit}) =>
      ServiceOffer(
        id: id,
        categoryId: categoryId,
        name: name ?? this.name,
        price: price ?? this.price,
        priceMax: priceMax,
        unit: unit,
        parts: parts,
      );
}

/// A photo of finished work.
@immutable
class WorkPhoto {
  const WorkPhoto({
    required this.id,
    required this.image,
    this.caption,
    this.focusX = 0,
    this.focusY = 0,
  });

  final String id;
  final String image;
  final String? caption;

  /// Where the subject sits, from -1 to 1 (an `Alignment`).
  final double focusX;
  final double focusY;
}

@immutable
class Review {
  const Review({
    required this.id,
    required this.authorName,
    required this.rating,
    required this.at,
    this.text,
    this.serviceName,
    this.authorPhoto,
    this.reply,
  });

  final String id;

  /// First name and initial: "Chidinma O.".
  final String authorName;
  final String? authorPhoto;

  /// 1 to 5.
  final int rating;
  final String? text;
  final String? serviceName;
  final DateTime at;

  /// The artisan's answer, if they gave one.
  final String? reply;
}

@immutable
class RatingSummary {
  const RatingSummary({
    required this.average,
    required this.count,
    required this.byStars,
  });

  final double average;
  final int count;

  /// How many reviews gave each number of stars, 1 to 5.
  final Map<int, int> byStars;
}

/// Where an artisan takes work.
@immutable
class ServiceArea {
  const ServiceArea({required this.area, required this.radiusKm});

  /// The neighbourhood they are based in.
  final String area;

  /// How far they travel from it.
  final int radiusKm;
}

/// The days and hours an artisan takes bookings.
@immutable
class WorkingHours {
  const WorkingHours({
    required this.days,
    required this.startMinutes,
    required this.endMinutes,
  });

  /// `DateTime.monday` (1) to `DateTime.sunday` (7).
  final Set<int> days;

  /// Minutes after midnight.
  final int startMinutes;
  final int endMinutes;

  static const usual = WorkingHours(
    days: {1, 2, 3, 4, 5, 6},
    startMinutes: 8 * 60,
    endMinutes: 18 * 60,
  );
}

/// Everything a client sees on an artisan's profile.
@immutable
class ArtisanProfile {
  const ArtisanProfile({
    required this.artisan,
    required this.about,
    required this.experienceYears,
    required this.services,
    required this.work,
    required this.ratings,
    required this.reviews,
    required this.serviceArea,
    required this.hours,
    required this.joinedOn,
    this.responseRate,
    this.languages = const ['English'],
    this.businessName,
    this.certifications = const [],
  });

  final Artisan artisan;
  final String about;
  final int experienceYears;

  /// The name they trade under, if any: "Smart Hands Plumbing".
  final String? businessName;

  /// Certificates by name: "NABTEB Plumbing Certificate".
  final List<String> certifications;
  final List<ServiceOffer> services;
  final List<WorkPhoto> work;
  final RatingSummary ratings;

  /// The newest few. The full list comes from `ArtisanRepository.reviews`.
  final List<Review> reviews;
  final ServiceArea serviceArea;
  final WorkingHours hours;
  final DateTime joinedOn;

  /// 0–100.
  final int? responseRate;
  final List<String> languages;
}

// ---------------------------------------------------------------- jobs

/// A client's own posted job, with the quotes it has drawn.
enum JobStatus {
  /// Open for quotes.
  open,

  /// A quote was accepted; the job became a booking.
  booked,

  /// Closed by the client, or expired.
  closed,
}

enum QuoteStatus { pending, accepted, declined, withdrawn }

/// An artisan's price for a posted job.
@immutable
class Quote {
  const Quote({
    required this.id,
    required this.jobId,
    required this.artisan,
    required this.price,
    required this.sentAt,
    this.priceMax,
    this.message,
    this.canStartAt,
    this.status = QuoteStatus.pending,
    this.jobTitle,
  });

  final String id;
  final String jobId;
  final Artisan artisan;

  /// Naira. With [priceMax], a range: the final price depends on what they
  /// find.
  final int price;
  final int? priceMax;

  /// What they wrote with it.
  final String? message;

  /// The soonest they can come.
  final DateTime? canStartAt;
  final DateTime sentAt;
  final QuoteStatus status;

  /// For the artisan's own list of quotes.
  final String? jobTitle;

  Quote withStatus(QuoteStatus status) => Quote(
        id: id,
        jobId: jobId,
        artisan: artisan,
        price: price,
        priceMax: priceMax,
        message: message,
        canStartAt: canStartAt,
        sentAt: sentAt,
        status: status,
        jobTitle: jobTitle,
      );
}

@immutable
class ClientJob {
  const ClientJob({
    required this.id,
    required this.title,
    required this.categoryId,
    required this.area,
    required this.postedAt,
    required this.status,
    this.description,
    this.photos = const [],
    this.voiceNote,
    this.landmark,
    this.budgetMin,
    this.budgetMax,
    this.isUrgent = false,
    this.quotes = const [],
    this.bookingId,
  });

  final String id;
  final String title;
  final String categoryId;
  final String area;
  final String? landmark;
  final DateTime postedAt;
  final JobStatus status;
  final String? description;
  final List<String> photos;
  final VoiceNote? voiceNote;
  final int? budgetMin;
  final int? budgetMax;
  final bool isUrgent;
  final List<Quote> quotes;

  /// Once a quote is accepted.
  final String? bookingId;

  int get pendingQuotes =>
      quotes.where((q) => q.status == QuoteStatus.pending).length;

  ClientJob copyWith({
    JobStatus? status,
    List<Quote>? quotes,
    String? bookingId,
  }) =>
      ClientJob(
        id: id,
        title: title,
        categoryId: categoryId,
        area: area,
        landmark: landmark,
        postedAt: postedAt,
        status: status ?? this.status,
        description: description,
        photos: photos,
        voiceNote: voiceNote,
        budgetMin: budgetMin,
        budgetMax: budgetMax,
        isUrgent: isUrgent,
        quotes: quotes ?? this.quotes,
        bookingId: bookingId ?? this.bookingId,
      );
}

/// A job to post, from the Ask conversation or the job form.
@immutable
class JobDraft {
  const JobDraft({
    required this.title,
    required this.categoryId,
    required this.area,
    this.description,
    this.photos = const [],
    this.voiceNote,
    this.landmark,
    this.budgetMin,
    this.budgetMax,
    this.isUrgent = false,
  });

  final String title;
  final String categoryId;
  final String area;
  final String? description;
  final List<String> photos;
  final VoiceNote? voiceNote;
  final String? landmark;
  final int? budgetMin;
  final int? budgetMax;
  final bool isUrgent;
}

/// An artisan's quote, before it is sent.
@immutable
class QuoteDraft {
  const QuoteDraft({
    required this.price,
    this.priceMax,
    this.message,
    this.canStartAt,
  });

  final int price;
  final int? priceMax;
  final String? message;
  final DateTime? canStartAt;
}

// ---------------------------------------------------------------- booking

/// A booking to request from one artisan.
@immutable
class BookingDraft {
  const BookingDraft({
    required this.artisan,
    required this.service,
    required this.window,
    required this.area,
    this.landmark,
    this.notes,
    this.photos = const [],
    this.voiceNote,
  });

  final Artisan artisan;
  final ServiceOffer service;
  final TimeWindow window;
  final String area;

  /// Street, house or landmark: "12 Aminu Kano Crescent, near Banex".
  final String? landmark;
  final String? notes;
  final List<String> photos;
  final VoiceNote? voiceNote;
}

/// What a booking costs: the artisan's price and RijHub's fee.
@immutable
class PriceBreakdown {
  const PriceBreakdown({required this.price, required this.fee});

  final int price;
  final int fee;
  int get total => price + fee;
}

// ---------------------------------------------------------------- chat

enum MessageKind { text, voice, photo, booking, quote, system }

@immutable
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.fromMe,
    required this.kind,
    required this.sentAt,
    this.text,
    this.voiceNote,
    this.photo,
    this.read = true,
  });

  final String id;
  final bool fromMe;
  final MessageKind kind;

  /// The message, or a caption for a photo, or a line for a system event
  /// ("Booking confirmed").
  final String? text;
  final VoiceNote? voiceNote;
  final String? photo;
  final DateTime sentAt;

  /// Seen by the other side (for mine), or by me (for theirs).
  final bool read;

  /// How the message reads in a list: its text, "Voice note", "Photo".
  String get preview => switch (kind) {
        MessageKind.voice => 'Voice note',
        MessageKind.photo => text ?? 'Photo',
        _ => text ?? '',
      };
}

@immutable
class Conversation {
  const Conversation({
    required this.id,
    required this.title,
    required this.updatedAt,
    this.photo,
    this.subtitle,
    this.bookingId,
    this.artisanId,
    this.lastMessage,
    this.unread = 0,
    this.online = false,
  });

  final String id;

  /// The other person's name.
  final String title;
  final String? photo;

  /// What it's about: "AC servicing · Today, 2:30 PM".
  final String? subtitle;
  final String? bookingId;
  final String? artisanId;
  final ChatMessage? lastMessage;
  final int unread;
  final bool online;
  final DateTime updatedAt;
}

// ---------------------------------------------------------------- notices

enum NoticeKind { booking, quote, message, payment, review, account, news }

/// An in-app notification.
@immutable
class AppNotice {
  const AppNotice({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.at,
    this.read = false,
    this.route,
  });

  final String id;
  final NoticeKind kind;
  final String title;
  final String body;
  final DateTime at;
  final bool read;

  /// Where tapping it goes, as an app path.
  final String? route;

  AppNotice markRead() => AppNotice(
        id: id,
        kind: kind,
        title: title,
        body: body,
        at: at,
        read: true,
        route: route,
      );
}

@immutable
class NotificationPrefs {
  const NotificationPrefs({
    this.bookings = true,
    this.messages = true,
    this.quotes = true,
    this.payments = true,
    this.tips = false,
  });

  final bool bookings;
  final bool messages;
  final bool quotes;
  final bool payments;

  /// Offers and news from RijHub.
  final bool tips;

  NotificationPrefs copyWith({
    bool? bookings,
    bool? messages,
    bool? quotes,
    bool? payments,
    bool? tips,
  }) =>
      NotificationPrefs(
        bookings: bookings ?? this.bookings,
        messages: messages ?? this.messages,
        quotes: quotes ?? this.quotes,
        payments: payments ?? this.payments,
        tips: tips ?? this.tips,
      );
}

// ---------------------------------------------------------------- money

enum TxKind {
  /// A client paid for a booking (held until the job is done).
  payment,

  /// Money back to a client.
  refund,

  /// An artisan was paid for a finished job.
  earning,

  /// Money sent to the artisan's bank.
  payout,
}

enum TxStatus { pending, successful, failed }

@immutable
class WalletTx {
  const WalletTx({
    required this.id,
    required this.kind,
    required this.amount,
    required this.status,
    required this.at,
    required this.title,
    this.reference,
  });

  final String id;
  final TxKind kind;

  /// Naira, always positive; [kind] says which way it went.
  final int amount;
  final TxStatus status;
  final DateTime at;

  /// "AC servicing with Emeka".
  final String title;
  final String? reference;

  /// Money coming in to this person.
  bool get isIn => kind == TxKind.earning || kind == TxKind.refund;
}

@immutable
class WalletSummary {
  const WalletSummary({
    required this.available,
    required this.held,
    required this.earnedTotal,
    this.paidTotal = 0,
  });

  /// An artisan's money ready to withdraw.
  final int available;

  /// Paid by clients for jobs not yet done: released when they are.
  final int held;
  final int earnedTotal;

  /// What a client has paid on RijHub, in total.
  final int paidTotal;
}

@immutable
class Bank {
  const Bank({required this.code, required this.name});

  final String code;
  final String name;
}

@immutable
class PayoutAccount {
  const PayoutAccount({
    required this.bank,
    required this.accountNumber,
    required this.accountName,
  });

  final Bank bank;

  /// 10-digit NUBAN.
  final String accountNumber;

  /// As the bank has it, found from the number.
  final String accountName;

  String get masked =>
      '•••• ${accountNumber.substring(accountNumber.length - 4)}';
}

// ---------------------------------------------------------------- account

/// The ID check: NIN, a live selfie, and a match between them.
enum VerificationState { notStarted, pending, verified, failed }

@immutable
class Verification {
  const Verification({required this.state, this.reason, this.updatedAt});

  final VerificationState state;

  /// Why it failed, written for the artisan.
  final String? reason;
  final DateTime? updatedAt;
}

/// An address the person books at often.
@immutable
class SavedPlace {
  const SavedPlace({
    required this.id,
    required this.label,
    required this.area,
    required this.address,
  });

  final String id;

  /// "Home", "Office".
  final String label;
  final String area;

  /// Street and landmark: "12 Aminu Kano Crescent, near Banex Plaza".
  final String address;
}

@immutable
class FaqItem {
  const FaqItem({
    required this.id,
    required this.topic,
    required this.question,
    required this.answer,
  });

  final String id;
  final String topic;
  final String question;
  final String answer;
}
