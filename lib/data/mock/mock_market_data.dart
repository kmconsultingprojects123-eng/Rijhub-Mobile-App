import 'dart:math' as math;

import '../models/models.dart';
import 'mock_data.dart';

/// Sample content for the rest of the app: artisan profiles, reviews,
/// conversations, notifications, money and help. Generated from the sample
/// artisans in [MockData] so every profile has something real-looking in
/// it, and seeded for the two sample accounts.
abstract final class MarketData {
  static const _photos = 'assets/images/onboarding';
  static const chidinma = 'u_chidinma';
  static const emeka = 'u_emeka';

  /// A number from [seed] in 0 ..< [range], stable between launches.
  static int pick(String seed, int range) =>
      seed.codeUnits.fold<int>(7, (h, c) => (h * 31 + c) & 0x7fffffff) % range;

  // ---------------------------------------------------------------- triage

  /// Words that point at a trade, with what the job is usually called and
  /// what it usually costs in Abuja.
  static const triageRules = <_Rule>[
    _Rule(
        'ac',
        [
          'ac ',
          ' ac',
          'a/c',
          'air condition',
          'aircon',
          'cooling',
          'split unit',
          'gas top',
          'freon'
        ],
        'AC service and gas top-up',
        8000,
        12000,
        "Sounds like an AC service and a gas top-up. In Abuja that's usually"),
    _Rule(
        'electrical',
        [
          'light',
          'socket',
          'switch',
          'wiring',
          'nepa',
          'bulb',
          'changeover',
          'spark',
          'breaker',
          'fuse',
          'power',
          'electric'
        ],
        'Electrical fault repair',
        5000,
        15000,
        "Sounds like an electrical fault. Fixing one in Abuja is usually"),
    _Rule(
        'plumbing',
        [
          'leak',
          'pipe',
          'tap',
          'sink',
          'toilet',
          'drain',
          'shower',
          'water heater',
          'plumb',
          'blocked'
        ],
        'Leak and plumbing repair',
        5000,
        12000,
        "Sounds like a plumbing job. In Abuja that's usually"),
    _Rule(
        'generator',
        ['generator', ' gen ', 'gen won', 'carburet', 'plug', 'gen is'],
        'Generator repair',
        10000,
        20000,
        "Sounds like a generator repair. In Abuja that's usually"),
    _Rule(
        'solar',
        ['solar', 'inverter', 'battery bank', 'panel'],
        'Solar and inverter check',
        15000,
        40000,
        "Sounds like a solar or inverter check. In Abuja that's usually"),
    _Rule(
        'cleaning',
        ['clean', 'dust', 'post-construction', 'post construction', 'laundry'],
        'Home cleaning',
        15000,
        35000,
        "A home clean like that in Abuja is usually"),
    _Rule(
        'pest',
        [
          'rat',
          'cockroach',
          'pest',
          'termite',
          'fumigat',
          'bed bug',
          'mosquito',
          'ants'
        ],
        'Fumigation',
        15000,
        35000,
        "Sounds like a fumigation job. In Abuja that's usually"),
    _Rule(
        'carpentry',
        [
          'door',
          'wardrobe',
          'furniture',
          'wood',
          'cabinet',
          'bed frame',
          'shelf',
          'carpent'
        ],
        'Carpentry repair',
        8000,
        25000,
        "Sounds like carpentry. In Abuja that's usually"),
    _Rule('painting', ['paint', 'repaint', 'wall colour', 'wall color'],
        'Painting', 25000, 80000, "Painting a room in Abuja is usually"),
    _Rule(
        'mechanic',
        ['car ', 'engine', 'brake', 'vehicle', 'tyre', 'tire', 'mechanic'],
        'Car repair',
        10000,
        30000,
        "Sounds like a car repair. In Abuja that's usually"),
    _Rule(
        'tailoring',
        [
          'tailor',
          'sew',
          'dress',
          'agbada',
          'kaftan',
          'alter',
          'trouser',
          'native'
        ],
        'Tailoring',
        6500,
        25000,
        "Tailoring like that in Abuja is usually"),
    _Rule(
        'gardening',
        ['garden', 'lawn', 'grass', 'hedge', 'flower', 'compound'],
        'Garden care',
        4000,
        12000,
        "Garden care in Abuja is usually"),
    _Rule('moving', ['move house', 'moving', 'relocat', 'truck', 'pack my'],
        'Moving help', 20000, 60000, "Moving help in Abuja is usually"),
    _Rule(
        'tv',
        ['tv', 'decoder', 'dstv', 'gotv', 'satellite', 'dish', 'mount'],
        'TV and decoder setup',
        5000,
        15000,
        "Sounds like a TV or decoder job. In Abuja that's usually"),
  ];

  static const urgentWords = [
    'urgent',
    'now',
    'today',
    'leaking',
    'flood',
    'no light',
    'spark',
    'smoke',
    'burst',
    'emergency',
    'asap',
  ];

  /// What the mock "hears" in any voice note.
  static const sampleHeard = "My AC is not cooling and it's leaking water.";

  static Triage triage(String words) {
    final text = ' ${words.toLowerCase()} ';
    final urgent = urgentWords.any(text.contains);
    for (final rule in triageRules) {
      if (rule.words.any(text.contains)) {
        final range = '₦${_grouped(rule.min)} – ₦${_grouped(rule.max)}';
        return Triage(
          categoryId: rule.categoryId,
          serviceName: rule.service,
          reply: '${rule.lead} $range.',
          priceMin: rule.min,
          priceMax: rule.max,
          isUrgent: urgent,
        );
      }
    }
    return const Triage(
      categoryId: 'electrical',
      serviceName: 'General repair',
      reply: "I'm not sure which trade that is. Which of these is closest?",
      priceMin: 5000,
      priceMax: 20000,
      confident: false,
    );
  }

  static String _grouped(int n) {
    final s = n.toString();
    final out = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
      out.write(s[i]);
    }
    return out.toString();
  }

  // ---------------------------------------------------------------- profiles

  static const _services = <String, List<(String, int, int?, String?)>>{
    'ac': [
      ('AC servicing', 8000, null, 'per unit'),
      ('Gas top-up', 12000, 18000, null),
      ('AC repair (diagnosis)', 5000, null, null),
      ('AC installation', 20000, null, 'per unit'),
    ],
    'electrical': [
      ('Socket or switch repair', 5000, null, null),
      ('Changeover installation', 15000, null, null),
      ('House wiring check', 10000, 25000, null),
      ('Light fitting', 3000, null, 'per fitting'),
    ],
    'plumbing': [
      ('Leak repair', 5000, 12000, null),
      ('Toilet repair', 7000, null, null),
      ('Water heater installation', 15000, null, null),
      ('Drain unblocking', 6000, null, null),
    ],
    'generator': [
      ('Generator servicing', 10000, null, null),
      ('Generator repair', 12000, 25000, null),
      ('Changeover connection', 8000, null, null),
    ],
    'cleaning': [
      ('Deep cleaning (2-bed flat)', 25000, null, null),
      ('Regular cleaning', 15000, null, null),
      ('Post-construction cleaning', 45000, 80000, null),
    ],
    'mechanic': [
      ('Car diagnostics', 10000, null, null),
      ('Brake pads replacement', 15000, null, null),
      ('Engine servicing', 20000, 35000, null),
    ],
    'solar': [
      ('Solar system check', 15000, null, null),
      ('Inverter installation', 40000, 90000, null),
      ('Battery replacement', 10000, null, 'labour'),
    ],
    'carpentry': [
      ('Door repair', 8000, null, null),
      ('Wardrobe assembly', 15000, 25000, null),
      ('Kitchen cabinet repair', 12000, null, null),
    ],
    'painting': [
      ('Paint a room', 25000, 45000, null),
      ('Paint a 3-bed flat', 120000, 200000, null),
      ('Touch-ups', 10000, null, null),
    ],
    'tailoring': [
      ('Native wear (men)', 15000, null, null),
      ('Dress from your fabric', 18000, 35000, null),
      ('Alterations', 3000, null, 'per item'),
    ],
    'gardening': [
      ('Lawn mowing', 4000, null, null),
      ('Hedge trimming', 6000, null, null),
      ('Garden makeover', 30000, 80000, null),
    ],
    'moving': [
      ('Local move (1-bed)', 35000, null, null),
      ('Packing help', 15000, null, null),
    ],
    'pest': [
      ('Fumigation (2-bed flat)', 20000, null, null),
      ('Termite treatment', 35000, 60000, null),
    ],
    'tv': [
      ('TV wall mounting', 6000, null, null),
      ('Decoder setup', 5000, null, null),
      ('Satellite dish alignment', 8000, null, null),
    ],
  };

  static List<ServiceOffer> servicesFor(Artisan artisan) {
    final list = _services[artisan.categoryId] ?? const [];
    // The starting price on the card is the cheapest service.
    final scale = artisan.startingPrice / (list.isEmpty ? 1 : list.first.$2);
    return [
      for (var i = 0; i < list.length; i++)
        ServiceOffer(
          id: '${artisan.id}_s$i',
          categoryId: artisan.categoryId,
          name: list[i].$1,
          price: _round(i == 0 ? artisan.startingPrice : list[i].$2 * scale),
          priceMax: list[i].$3 == null ? null : _round(list[i].$3! * scale),
          unit: list[i].$4,
        ),
    ];
  }

  static int _round(num naira) => (naira / 500).round() * 500;

  static const _about = <String, String>{
    'ac': 'I service, repair and install split and standing units, and I '
        'bring my own gauges and gas. I explain what was wrong before I '
        'leave, and I come back free within a week if the same fault returns.',
    'electrical': 'Certified electrician for homes and small offices: '
        'faults, sockets, changeovers and full rewiring. I test everything '
        'before I leave.',
    'plumbing': 'Leaks, blocked drains, toilets and water heaters. I '
        'carry common parts, so most jobs are fixed on the first visit.',
    'generator': 'I service and repair petrol and diesel generators, and '
        'connect changeovers safely.',
    'cleaning': 'Deep, regular and post-construction cleaning with my own '
        'equipment and supplies.',
    'mechanic': 'Diagnostics, brakes, suspension and engine work. I can '
        'come to you for small jobs.',
    'solar': 'Solar panels, inverters and batteries: sizing, installation '
        'and maintenance.',
    'carpentry': 'Doors, wardrobes, cabinets and furniture repair, built '
        'to last.',
    'painting': 'Interior and exterior painting with clean finishes and '
        'no mess left behind.',
    'tailoring': 'Native and corporate wear for men and women, and quick '
        'alterations.',
    'gardening': 'Lawns, hedges and gardens kept neat, weekly or one-off.',
    'moving': 'Careful packing and moving within Abuja, with a covered '
        'truck.',
    'pest': 'Fumigation for homes and offices, safe for children and pets '
        'after the stated hours.',
    'tv': 'TV mounting, decoder setup and satellite dish alignment.',
  };

  static const _reviewTexts = [
    'Came on time, explained everything and left the place clean.',
    'Very professional. Fixed it in under an hour.',
    'Fair price and honest about what needed doing.',
    'Polite and careful. I will book again.',
    'Did a great job. Highly recommended.',
    'Quick to reply and arrived when he said he would.',
    'Good work, though he came a little late.',
    'Excellent. Even showed me how to avoid the problem next time.',
  ];

  static const _reviewers = [
    'Chidinma O.',
    'Tolu B.',
    'Aisha M.',
    'David E.',
    'Ngozi A.',
    'Femi K.',
    'Hauwa I.',
    'Bola S.',
    'Ibrahim Y.',
    'Grace N.',
  ];

  static List<Review> reviewsFor(Artisan artisan, DateTime now, {int? count}) {
    final n = count ?? math.min(12, artisan.reviewCount);
    final services = servicesFor(artisan);
    return [
      for (var i = 0; i < n; i++)
        Review(
          id: '${artisan.id}_r$i',
          authorName:
              _reviewers[(pick(artisan.id, 10) + i) % _reviewers.length],
          rating: (i % 7 == 6 && artisan.rating < 4.95) ? 4 : 5,
          text: _reviewTexts[(pick(artisan.name, 8) + i) % _reviewTexts.length],
          serviceName: services.isEmpty
              ? artisan.trade
              : services[i % services.length].name,
          at: now
              .subtract(Duration(days: 3 + i * 9 + pick('${artisan.id}$i', 6))),
          reply: i == 0 ? 'Thank you! Glad I could help.' : null,
        ),
    ];
  }

  static RatingSummary ratingsFor(Artisan artisan) {
    final total = artisan.reviewCount;
    final five = (total * (artisan.rating - 4).clamp(0.4, 0.95)).round();
    final four = ((total - five) * 0.8).round();
    final three = math.max(0, total - five - four - 1);
    final low = total - five - four - three;
    return RatingSummary(
      average: artisan.rating,
      count: total,
      byStars: {5: five, 4: four, 3: three, 2: math.max(0, low), 1: 0},
    );
  }

  static List<WorkPhoto> workFor(Artisan artisan) {
    final cover = artisan.coverPhoto;
    if (cover == null) return const [];
    return [
      WorkPhoto(
        id: '${artisan.id}_w0',
        image: cover,
        caption: _captions[artisan.categoryId]?[0],
        focusX: artisan.coverFocusX,
        focusY: artisan.coverFocusY,
      ),
      WorkPhoto(
        id: '${artisan.id}_w1',
        image: cover,
        caption: _captions[artisan.categoryId]?[1],
        focusX: 0.4,
        focusY: 0.2,
      ),
      WorkPhoto(
        id: '${artisan.id}_w2',
        image: cover,
        caption: _captions[artisan.categoryId]?[2],
        focusX: -0.2,
        focusY: 0.7,
      ),
    ];
  }

  static const _captions = <String, List<String>>{
    'ac': [
      'Split unit service, Wuse 2',
      'Outdoor unit, Maitama',
      'Gas top-up and leak fix'
    ],
    'electrical': [
      'Mains check, Garki',
      'New changeover, Jabi',
      'Rewired sitting room'
    ],
    'mechanic': ['Brake job, Jabi', 'Engine service', 'Suspension repair'],
    'tailoring': ['Agbada for a wedding', 'Fitted kaftan', 'Alterations'],
    'gardening': ['Front garden, Maitama', 'Hedges trimmed', 'New flower beds'],
  };

  static ArtisanProfile profileFor(Artisan artisan, DateTime now) =>
      ArtisanProfile(
        artisan: artisan,
        about: _about[artisan.categoryId] ?? 'Experienced and reliable.',
        experienceYears: 3 + pick(artisan.id, 9),
        services: servicesFor(artisan),
        work: workFor(artisan),
        ratings: ratingsFor(artisan),
        reviews: reviewsFor(artisan, now, count: 3),
        serviceArea: ServiceArea(
            area: artisan.area, radiusKm: 8 + pick(artisan.name, 8)),
        hours: WorkingHours.usual,
        joinedOn: DateTime(
            now.year - 1 - pick(artisan.id, 3), 1 + pick(artisan.name, 11)),
        responseRate: 90 + pick(artisan.id, 10),
        languages: const ['English', 'Pidgin'],
        businessName:
            artisan.id == 'a_emeka' ? 'Cool Breeze AC Services' : null,
        certifications: artisan.id == 'a_emeka'
            ? const ['NABTEB Refrigeration and Air Conditioning']
            : const [],
      );

  // ---------------------------------------------------------------- extra artisans

  /// Painters who quote on the sample client's job.
  static List<Artisan> extraArtisans(DateTime now) => const [
        Artisan(
          id: 'a_chuka',
          name: 'Chuka Obi',
          trade: 'Painter',
          categoryId: 'painting',
          area: 'Utako',
          distanceKm: 3.4,
          rating: 4.7,
          reviewCount: 39,
          jobsCompleted: 61,
          startingPrice: 22000,
          isVerified: true,
          isAvailableToday: true,
          replyMinutes: 20,
        ),
        Artisan(
          id: 'a_bola',
          name: 'Bola Ajayi',
          trade: 'Painter',
          categoryId: 'painting',
          area: 'Wuse',
          distanceKm: 2.1,
          rating: 4.6,
          reviewCount: 27,
          jobsCompleted: 40,
          startingPrice: 20000,
          isVerified: true,
          replyMinutes: 35,
        ),
      ];

  // ---------------------------------------------------------------- bookings

  static List<Booking> pastFor(String? userId, UserRole role, DateTime now) {
    DateTime ago(int days, int hour) =>
        DateTime(now.year, now.month, now.day - days, hour);
    if (userId == chidinma && role == UserRole.client) {
      return [
        Booking(
          id: 'b_p1',
          serviceName: 'Kitchen sink leak',
          categoryId: 'plumbing',
          scheduledAt: ago(21, 11),
          status: BookingStatus.completed,
          counterpartName: 'Yusuf Abdullahi',
          artisanId: 'a_yusuf',
          area: 'Wuse 2',
          price: 8500,
          fee: 500,
          payment: PaymentState.released,
          yourRating: 5,
          conversationId: 'c_yusuf',
        ),
        Booking(
          id: 'b_p2',
          serviceName: 'Changeover installation',
          categoryId: 'electrical',
          scheduledAt: ago(58, 15),
          status: BookingStatus.completed,
          counterpartName: 'Ibrahim Musa',
          counterpartPhoto: 'assets/mock/avatars/ibrahim_electrician.webp',
          artisanId: 'a_ibrahim',
          area: 'Wuse 2',
          price: 15000,
          fee: 750,
          payment: PaymentState.released,
          yourRating: 4,
        ),
        Booking(
          id: 'b_p3',
          serviceName: 'Deep cleaning (2-bed flat)',
          categoryId: 'cleaning',
          scheduledAt: ago(34, 9),
          status: BookingStatus.cancelled,
          counterpartName: 'Blessing Okoro',
          artisanId: 'a_blessing',
          area: 'Wuse 2',
          price: 25000,
          fee: 1250,
          payment: PaymentState.refunded,
          cancelReason: 'You cancelled: plans changed.',
        ),
      ];
    }
    if (userId == emeka && role == UserRole.artisan) {
      return [
        for (final (i, (name, service, area, price, rating)) in const [
          ('Tolu B.', 'AC servicing', 'Jabi', 8000, 5),
          ('Aisha M.', 'Gas top-up', 'Garki', 15000, 5),
          ('David E.', 'AC installation', 'Gwarinpa', 20000, 4),
          ('Hauwa I.', 'AC servicing', 'Maitama', 16000, 5),
          ('Femi K.', 'AC repair (diagnosis)', 'Utako', 5000, null),
        ].indexed)
          Booking(
            id: 'b_e$i',
            serviceName: service,
            categoryId: 'ac',
            scheduledAt: ago(2 + i * 3, 10 + i),
            status: BookingStatus.completed,
            counterpartName: name,
            area: area,
            price: price,
            payment: PaymentState.released,
            yourRating: rating,
          ),
      ];
    }
    return const [];
  }

  // ---------------------------------------------------------------- jobs

  static List<ClientJob> clientJobsFor(String? userId, DateTime now) {
    if (userId != chidinma) return const [];
    final extra = extraArtisans(now);
    final grace = MockData.artisansAt(now, area: 'Wuse 2')
        .firstWhere((a) => a.id == 'a_grace');
    return [
      ClientJob(
        id: 'j_c1',
        title: 'Paint the sitting room',
        categoryId: 'painting',
        area: 'Wuse 2',
        landmark: 'near Banex Plaza',
        postedAt: now.subtract(const Duration(hours: 20)),
        status: JobStatus.open,
        description: 'Medium-sized sitting room, about 4m by 5m. Walls and '
            'ceiling, off-white. I have the paint already.',
        budgetMin: 25000,
        budgetMax: 45000,
        quotes: [
          Quote(
            id: 'q_c1',
            jobId: 'j_c1',
            artisan: grace,
            price: 38000,
            message: 'I can do walls and ceiling in one day. I bring my '
                'own rollers and cover your furniture.',
            canStartAt: DateTime(now.year, now.month, now.day + 2, 9),
            sentAt: now.subtract(const Duration(hours: 18)),
          ),
          Quote(
            id: 'q_c2',
            jobId: 'j_c1',
            artisan: extra[0],
            price: 30000,
            priceMax: 35000,
            message: 'Depends on how many coats the ceiling needs. I can '
                'come tomorrow to look first.',
            canStartAt: DateTime(now.year, now.month, now.day + 1, 10),
            sentAt: now.subtract(const Duration(hours: 9)),
          ),
          Quote(
            id: 'q_c3',
            jobId: 'j_c1',
            artisan: extra[1],
            price: 42000,
            message: 'Price includes filling cracks before painting.',
            canStartAt: DateTime(now.year, now.month, now.day + 3, 8),
            sentAt: now.subtract(const Duration(hours: 2)),
          ),
        ],
      ),
    ];
  }

  /// A client who asked the sample artisan by name for a price.
  static List<ClientJob> quoteRequestsFor(String? userId, DateTime now) {
    if (userId != emeka) return const [];
    return [
      ClientJob(
        id: 'j_e1',
        title: 'Install a new split AC',
        categoryId: 'ac',
        area: 'Jabi',
        landmark: 'Cedar Court, flat 4',
        postedAt: now.subtract(const Duration(minutes: 35)),
        status: JobStatus.open,
        description: 'Bought a 1.5 HP split unit. Need it installed in the '
            'main bedroom, about 3 metres of piping. When can you come?',
        photos: const ['$_photos/ac_technicians.webp'],
        isUrgent: false,
      ),
    ];
  }

  static List<Quote> artisanQuotesFor(String? userId, DateTime now) {
    if (userId != emeka) return const [];
    final me = MockData.artisansAt(now).firstWhere((a) => a.id == 'a_emeka');
    return [
      Quote(
        id: 'q_e1',
        jobId: 'j_2',
        artisan: me,
        price: 18000,
        message: 'Two units, servicing and a gas check on both.',
        canStartAt: DateTime(now.year, now.month, now.day + 1, 9),
        sentAt: now.subtract(const Duration(hours: 3)),
        jobTitle: 'Service two split AC units',
      ),
      Quote(
        id: 'q_e2',
        jobId: 'job_old',
        artisan: me,
        price: 9000,
        sentAt: now.subtract(const Duration(days: 4)),
        status: QuoteStatus.accepted,
        jobTitle: 'AC making noise',
      ),
    ];
  }

  // ---------------------------------------------------------------- chat

  static List<(Conversation, List<ChatMessage>)> conversationsFor(
    String? userId,
    DateTime now,
    DateTime firstBooking,
  ) {
    DateTime minsAgo(int m) => now.subtract(Duration(minutes: m));
    if (userId == chidinma) {
      return [
        (
          Conversation(
            id: 'c_emeka',
            title: 'Emeka Nwosu',
            photo: 'assets/mock/avatars/emeka_ac.webp',
            subtitle: 'AC servicing · booking confirmed',
            bookingId: 'b_1',
            artisanId: 'a_emeka',
            online: true,
            updatedAt: minsAgo(6),
          ),
          [
            ChatMessage(
                id: 'm1',
                fromMe: false,
                kind: MessageKind.system,
                text:
                    'Booking confirmed. Your payment is held safely until the job is done.',
                sentAt: minsAgo(95)),
            ChatMessage(
                id: 'm2',
                fromMe: false,
                kind: MessageKind.text,
                text:
                    'Good afternoon ma. Is the unit in the sitting room or upstairs?',
                sentAt: minsAgo(40)),
            ChatMessage(
                id: 'm3',
                fromMe: true,
                kind: MessageKind.text,
                text:
                    'Upstairs, main bedroom. The gate is the black one near Banex.',
                sentAt: minsAgo(32)),
            ChatMessage(
                id: 'm4',
                fromMe: false,
                kind: MessageKind.text,
                text:
                    "Alright ma, I'll be there on time. I'll call when I'm close.",
                sentAt: minsAgo(6),
                read: false),
          ],
        ),
        (
          Conversation(
            id: 'c_grace',
            title: 'Grace Effiong',
            subtitle: 'Quote · Paint the sitting room',
            artisanId: 'a_grace',
            updatedAt: minsAgo(60 * 18),
          ),
          [
            ChatMessage(
                id: 'g1',
                fromMe: false,
                kind: MessageKind.text,
                text:
                    'Good morning! I sent you a quote for the sitting room. Happy to answer any questions.',
                sentAt: minsAgo(60 * 18),
                read: false),
          ],
        ),
        (
          Conversation(
            id: 'c_yusuf',
            title: 'Yusuf Abdullahi',
            subtitle: 'Kitchen sink leak · done',
            artisanId: 'a_yusuf',
            bookingId: 'b_p1',
            updatedAt: now.subtract(const Duration(days: 21)),
          ),
          [
            ChatMessage(
                id: 'y1',
                fromMe: true,
                kind: MessageKind.text,
                text: 'Thank you so much, no more leak!',
                sentAt: now.subtract(const Duration(days: 21, hours: 1))),
            ChatMessage(
                id: 'y2',
                fromMe: false,
                kind: MessageKind.text,
                text: "You're welcome ma. Call me any time.",
                sentAt: now.subtract(const Duration(days: 21))),
          ],
        ),
      ];
    }
    if (userId == emeka) {
      return [
        (
          Conversation(
            id: 'c_ngozi',
            title: 'Ngozi Adeyemi',
            subtitle: 'Request · Socket repair',
            online: true,
            updatedAt: minsAgo(1),
          ),
          [
            ChatMessage(
                id: 'n1',
                fromMe: false,
                kind: MessageKind.text,
                text:
                    "Two sockets in my kitchen are sparking. I've switched them off at the board for now.",
                sentAt: minsAgo(2),
                read: false),
            ChatMessage(
                id: 'n2',
                fromMe: false,
                kind: MessageKind.photo,
                photo: '$_photos/electrician.webp',
                sentAt: minsAgo(2),
                read: false),
            ChatMessage(
                id: 'n3',
                fromMe: false,
                kind: MessageKind.voice,
                voiceNote: const VoiceNote(
                    path: 'mock://ngozi',
                    duration: Duration(seconds: 12),
                    heard:
                        'The one near the fridge is the worst, it makes a noise when I plug anything.'),
                sentAt: minsAgo(1),
                read: false),
          ],
        ),
        (
          Conversation(
            id: 'c_emeka',
            title: 'Chidinma Okafor',
            subtitle: 'AC servicing · ${_time(firstBooking)}',
            bookingId: 'b_1',
            updatedAt: minsAgo(6),
          ),
          [
            ChatMessage(
                id: 'm1',
                fromMe: false,
                kind: MessageKind.system,
                text:
                    'Booking confirmed. The client has paid; you get it when the job is done.',
                sentAt: minsAgo(95)),
            ChatMessage(
                id: 'm2',
                fromMe: true,
                kind: MessageKind.text,
                text:
                    'Good afternoon ma. Is the unit in the sitting room or upstairs?',
                sentAt: minsAgo(40)),
            ChatMessage(
                id: 'm3',
                fromMe: false,
                kind: MessageKind.text,
                text:
                    'Upstairs, main bedroom. The gate is the black one near Banex.',
                sentAt: minsAgo(32)),
            ChatMessage(
                id: 'm4',
                fromMe: true,
                kind: MessageKind.text,
                text:
                    "Alright ma, I'll be there on time. I'll call when I'm close.",
                sentAt: minsAgo(6)),
          ],
        ),
        (
          Conversation(
            id: 'c_hauwa',
            title: 'Hauwa Ibrahim',
            subtitle: 'Service three split units · tomorrow',
            bookingId: 'b_3',
            updatedAt: minsAgo(60 * 5),
          ),
          [
            ChatMessage(
                id: 'h1',
                fromMe: false,
                kind: MessageKind.text,
                text: 'Please bring a ladder, the outdoor units are high.',
                sentAt: minsAgo(60 * 5)),
          ],
        ),
      ];
    }
    return const [];
  }

  static String _time(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    return 'today, $h:$m ${t.hour < 12 ? 'AM' : 'PM'}';
  }

  /// A short, plausible answer from the other side of a conversation.
  static String replyTo(String text, {required bool fromArtisan}) {
    final t = text.toLowerCase();
    if (!fromArtisan) return 'Thank you, see you then.';
    if (t.contains('price') || t.contains('how much') || t.contains('cost')) {
      return "The price on the booking covers it. If I find anything else, I'll tell you before I do it.";
    }
    if (t.contains('where') || t.contains('close') || t.contains('coming')) {
      return "I'm on my way. I'll call when I reach the gate.";
    }
    if (t.contains('?')) {
      return "Yes, that's fine. I'll sort it out when I get there.";
    }
    return 'Noted. Thank you!';
  }

  // ---------------------------------------------------------------- notices

  static List<AppNotice> noticesFor(String? userId, DateTime now) {
    DateTime ago(int minutes) => now.subtract(Duration(minutes: minutes));
    if (userId == chidinma) {
      return [
        AppNotice(
            id: 'n_c1',
            kind: NoticeKind.message,
            title: 'Emeka sent a message',
            body:
                "Alright ma, I'll be there on time. I'll call when I'm close.",
            at: ago(6),
            route: '/chat/c_emeka'),
        AppNotice(
            id: 'n_c2',
            kind: NoticeKind.quote,
            title: 'New quote: ₦42,000',
            body:
                'Bola Ajayi quoted on "Paint the sitting room". You have 3 quotes now.',
            at: ago(120),
            route: '/jobs/j_c1'),
        AppNotice(
            id: 'n_c3',
            kind: NoticeKind.booking,
            title: 'Booking confirmed',
            body:
                'Emeka Nwosu will service your AC today. Your payment is held safely.',
            at: ago(95),
            route: '/booking/b_1',
            read: true),
        AppNotice(
            id: 'n_c4',
            kind: NoticeKind.payment,
            title: 'Payment held: ₦12,600',
            body: 'We release it to Emeka when you confirm the job is done.',
            at: ago(96),
            route: '/account/payments',
            read: true),
        AppNotice(
            id: 'n_c5',
            kind: NoticeKind.review,
            title: 'How did Yusuf do?',
            body: 'You rated your kitchen sink repair 5 stars. Thank you!',
            at: now.subtract(const Duration(days: 20)),
            read: true),
      ];
    }
    if (userId == emeka) {
      return [
        AppNotice(
            id: 'n_e1',
            kind: NoticeKind.booking,
            title: 'New request: Socket repair',
            body:
                'Ngozi A. wants you today, 4–6 PM, for ₦6,000. Answer within 14 minutes.',
            at: ago(2),
            route: '/requests/r_1'),
        AppNotice(
            id: 'n_e2',
            kind: NoticeKind.quote,
            title: 'Tolu asked you for a quote',
            body: 'Install a new split AC in Jabi.',
            at: ago(35),
            route: '/quote-requests/j_e1'),
        AppNotice(
            id: 'n_e3',
            kind: NoticeKind.payment,
            title: 'Payout sent: ₦40,000',
            body: 'To GTBank •••• 4821. It usually arrives within minutes.',
            at: now.subtract(const Duration(days: 1)),
            route: '/account/wallet',
            read: true),
        AppNotice(
            id: 'n_e4',
            kind: NoticeKind.review,
            title: 'New 5-star review',
            body:
                'Hauwa I.: "Excellent. Even showed me how to avoid the problem next time."',
            at: now.subtract(const Duration(days: 2)),
            route: '/account/reviews',
            read: true),
      ];
    }
    return [
      AppNotice(
          id: 'n_w',
          kind: NoticeKind.news,
          title: 'Welcome to RijHub',
          body:
              'Tell us what needs fixing, and we will find a trusted artisan near you.',
          at: ago(1),
          read: false),
    ];
  }

  // ---------------------------------------------------------------- money

  static const banks = [
    Bank(code: '044', name: 'Access Bank'),
    Bank(code: '023', name: 'Citibank'),
    Bank(code: '050', name: 'Ecobank'),
    Bank(code: '070', name: 'Fidelity Bank'),
    Bank(code: '011', name: 'First Bank'),
    Bank(code: '214', name: 'FCMB'),
    Bank(code: '058', name: 'GTBank'),
    Bank(code: '030', name: 'Heritage Bank'),
    Bank(code: '301', name: 'Jaiz Bank'),
    Bank(code: '082', name: 'Keystone Bank'),
    Bank(code: '50211', name: 'Kuda'),
    Bank(code: '50515', name: 'Moniepoint'),
    Bank(code: '999992', name: 'OPay'),
    Bank(code: '999991', name: 'PalmPay'),
    Bank(code: '076', name: 'Polaris Bank'),
    Bank(code: '101', name: 'Providus Bank'),
    Bank(code: '221', name: 'Stanbic IBTC'),
    Bank(code: '232', name: 'Sterling Bank'),
    Bank(code: '032', name: 'Union Bank'),
    Bank(code: '033', name: 'UBA'),
    Bank(code: '215', name: 'Unity Bank'),
    Bank(code: '035', name: 'Wema Bank'),
    Bank(code: '057', name: 'Zenith Bank'),
  ];

  static List<WalletTx> transactionsFor(String? userId, DateTime now) {
    DateTime days(int d, [int h = 12]) =>
        DateTime(now.year, now.month, now.day - d, h);
    if (userId == chidinma) {
      return [
        WalletTx(
            id: 't_c1',
            kind: TxKind.payment,
            amount: 12600,
            status: TxStatus.pending,
            at: now.subtract(const Duration(minutes: 96)),
            title: 'AC servicing with Emeka',
            reference: 'RJH-48213'),
        WalletTx(
            id: 't_c2',
            kind: TxKind.refund,
            amount: 26250,
            status: TxStatus.successful,
            at: days(33),
            title: 'Deep cleaning, cancelled',
            reference: 'RJH-47002'),
        WalletTx(
            id: 't_c3',
            kind: TxKind.payment,
            amount: 9000,
            status: TxStatus.successful,
            at: days(21),
            title: 'Kitchen sink leak with Yusuf',
            reference: 'RJH-46550'),
        WalletTx(
            id: 't_c4',
            kind: TxKind.payment,
            amount: 15750,
            status: TxStatus.successful,
            at: days(58),
            title: 'Changeover installation with Ibrahim',
            reference: 'RJH-44101'),
      ];
    }
    if (userId == emeka) {
      return [
        WalletTx(
            id: 't_e1',
            kind: TxKind.earning,
            amount: 8000,
            status: TxStatus.successful,
            at: days(2, 15),
            title: 'AC servicing · Tolu B.',
            reference: 'RJH-48190'),
        WalletTx(
            id: 't_e2',
            kind: TxKind.payout,
            amount: 40000,
            status: TxStatus.successful,
            at: days(1, 9),
            title: 'To GTBank •••• 4821',
            reference: 'PO-9921'),
        WalletTx(
            id: 't_e3',
            kind: TxKind.earning,
            amount: 15000,
            status: TxStatus.successful,
            at: days(5, 13),
            title: 'Gas top-up · Aisha M.',
            reference: 'RJH-47712'),
        WalletTx(
            id: 't_e4',
            kind: TxKind.earning,
            amount: 20000,
            status: TxStatus.successful,
            at: days(8, 11),
            title: 'AC installation · David E.',
            reference: 'RJH-47305'),
        WalletTx(
            id: 't_e5',
            kind: TxKind.payout,
            amount: 55000,
            status: TxStatus.successful,
            at: days(9, 9),
            title: 'To GTBank •••• 4821',
            reference: 'PO-9810'),
        WalletTx(
            id: 't_e6',
            kind: TxKind.earning,
            amount: 16000,
            status: TxStatus.successful,
            at: days(11, 16),
            title: 'AC servicing · Hauwa I.',
            reference: 'RJH-46980'),
      ];
    }
    return const [];
  }

  // ---------------------------------------------------------------- places

  static List<SavedPlace> placesFor(String? userId) {
    if (userId != chidinma) return const [];
    return const [
      SavedPlace(
          id: 'p_home',
          label: 'Home',
          area: 'Wuse 2',
          address: '12 Aminu Kano Crescent, near Banex Plaza'),
      SavedPlace(
          id: 'p_office',
          label: 'Office',
          area: 'Central Business District',
          address: 'Plot 1061, Herbert Macaulay Way'),
    ];
  }

  // ---------------------------------------------------------------- help

  static const faqs = [
    FaqItem(
        id: 'f1',
        topic: 'Getting started',
        question: 'Do I need an account to look around?',
        answer:
            'No. You can explore artisans, prices and jobs as a guest. We only ask for your phone number when you book, post a job or send a quote, and there is no password.'),
    FaqItem(
        id: 'f2',
        topic: 'Getting started',
        question: 'How do I sign up?',
        answer:
            'Enter your phone number, then the 6-digit code we text you (or send to WhatsApp), and your name. That\'s it. Artisans also pick their trades.'),
    FaqItem(
        id: 'f3',
        topic: 'Getting started',
        question: 'Where is RijHub available?',
        answer:
            'Across Abuja: the city and the Area Councils of Abaji, Abuja Municipal, Bwari, Gwagwalada, Kuje and Kwali. More cities are coming.'),
    FaqItem(
        id: 'f4',
        topic: 'Booking',
        question: 'How do I find and book an artisan?',
        answer:
            'On the home screen, tell RijHub what needs fixing: type it, send a photo or record a voice note. We show you what it usually costs and the top-rated artisans who are free near you. Pick one, choose a time and place, and confirm.'),
    FaqItem(
        id: 'f5',
        topic: 'Booking',
        question: 'Can I get several quotes instead?',
        answer:
            'Yes. Tap "Get quotes from all" in the conversation, or post a job from Bookings. Artisans near you send prices, and you compare their quotes, ratings and when they can come before you choose.'),
    FaqItem(
        id: 'f6',
        topic: 'Booking',
        question: 'How do I cancel or move a booking?',
        answer:
            'Open the booking and tap Reschedule or Cancel. If you cancel before the artisan sets off, you get your money back in full.'),
    FaqItem(
        id: 'f7',
        topic: 'Booking',
        question: 'What if the artisan does not show up?',
        answer:
            'You get a full refund, and we help you book someone else quickly. Tell us from the booking\'s help button.'),
    FaqItem(
        id: 'f8',
        topic: 'Booking',
        question: 'What is the start code?',
        answer:
            'A 4-digit code in your booking. Give it to the artisan when they arrive. It confirms the right person came and starts the job.'),
    FaqItem(
        id: 'f9',
        topic: 'Payments',
        question: 'When do I pay, and how is my money protected?',
        answer:
            'You pay when you book, and RijHub holds the money safely. The artisan gets it only after you confirm the job is done. If you don\'t respond within 48 hours of the artisan finishing, it is released automatically.'),
    FaqItem(
        id: 'f10',
        topic: 'Payments',
        question: 'Which payment methods can I use?',
        answer:
            'Cards (Visa, Mastercard and Verve), bank transfer and USSD, through our payment partner Paystack.'),
    FaqItem(
        id: 'f11',
        topic: 'Payments',
        question: 'What is the service fee?',
        answer:
            'A small fee shown before you confirm, which pays for payment protection and support. The artisan keeps their full price.'),
    FaqItem(
        id: 'f12',
        topic: 'Safety',
        question: 'How are artisans checked?',
        answer:
            'Artisans with the verified badge have matched their NIN to a live selfie. Reviews come only from clients who booked and paid through RijHub.'),
    FaqItem(
        id: 'f13',
        topic: 'Safety',
        question: 'How do I leave a review?',
        answer:
            'When you confirm a job is done, we ask how it went. You can also rate from the booking later.'),
    FaqItem(
        id: 'f14',
        topic: 'For artisans',
        question: 'How do I get jobs?',
        answer:
            'Create your free profile, add your services and prices and some photos of your work, and verify your ID. Then switch to Available to get booking requests, and quote on jobs posted near you.'),
    FaqItem(
        id: 'f15',
        topic: 'For artisans',
        question: 'How do I verify my ID?',
        answer:
            'Go to Profile, ID check. Enter your 11-digit NIN and take a quick selfie. Most checks finish in minutes.'),
    FaqItem(
        id: 'f16',
        topic: 'For artisans',
        question: 'How do I manage my services and prices?',
        answer:
            'Go to Profile, Services and prices. Add, change or remove a service any time; clients see your prices on your profile.'),
    FaqItem(
        id: 'f17',
        topic: 'For artisans',
        question: 'When do I get paid, and how do I withdraw?',
        answer:
            'As soon as the client confirms the job is done, the money moves to your wallet. Withdraw to your bank account any time from Profile, Wallet and payouts. It usually arrives within minutes.'),
    FaqItem(
        id: 'f18',
        topic: 'Your account',
        question: 'How do I change my area?',
        answer:
            'Tap the area at the top of the home screen and pick your neighbourhood.'),
    FaqItem(
        id: 'f19',
        topic: 'Your account',
        question: 'How do I edit my profile?',
        answer:
            'Go to Profile and tap Edit. You can change your photo, name and email there.'),
    FaqItem(
        id: 'f20',
        topic: 'Your account',
        question: 'I changed my phone number. What do I do?',
        answer:
            'Contact us from the Help centre with your old and new numbers, and we will move your account over after a quick check.'),
    FaqItem(
        id: 'f21',
        topic: 'Your account',
        question: 'I am not getting notifications',
        answer:
            'Check that notifications are on for RijHub in your phone\'s settings, and in Profile, Settings, Notifications. A weak connection can delay them.'),
    FaqItem(
        id: 'f22',
        topic: 'Your account',
        question: 'How do I switch between light and dark?',
        answer:
            'Go to Profile, Settings, Appearance. By default RijHub follows your phone.'),
    FaqItem(
        id: 'f23',
        topic: 'Your account',
        question: 'How do I delete my account?',
        answer:
            'Go to Profile and tap Delete account. This removes your profile and history for good.'),
    FaqItem(
        id: 't1',
        topic: 'Something not working',
        question: 'The app is blank or won\'t load',
        answer:
            'Check your connection, then close and reopen RijHub. If it still won\'t load, update the app from your app store.'),
    FaqItem(
        id: 't2',
        topic: 'Something not working',
        question: 'My code is not arriving',
        answer:
            'Wait a minute, check the number is right, then tap Send a new code. You can also get the code on WhatsApp.'),
    FaqItem(
        id: 't3',
        topic: 'Something not working',
        question: 'My payment failed',
        answer:
            'No money is taken for a failed payment. Try again, or another card or bank transfer. If you were charged and the booking did not appear, contact us with the reference.'),
  ];
}

class _Rule {
  const _Rule(
      this.categoryId, this.words, this.service, this.min, this.max, this.lead);

  final String categoryId;
  final List<String> words;
  final String service;
  final int min;
  final int max;
  final String lead;
}
