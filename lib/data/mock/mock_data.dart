import 'dart:math' as math;

import '../catalog/trades.dart';
import '../geo/places.dart';
import '../models/models.dart';

/// Sample data for the redesign, set in Abuja. It stands in for the backend
/// until the new API exists, and drives the screenshots and demos.
///
/// Times are worked out from `now`, the moment the mock backend started
/// (`MockAccounts.startedAt`), so there is always a booking coming up and
/// jobs posted minutes ago, and they age as real ones would.
abstract final class MockData {
  /// The city RijHub launches in. As an area, it means all of it.
  static const city = 'Abuja';

  static const categories = Trades.all;

  /// Districts and neighbourhoods of Abuja, A to Z.
  static const areas = [
    'Apo',
    'Asokoro',
    'Bwari',
    'Central Business District',
    'Dakibiyu',
    'Dakwo',
    'Dawaki',
    'Dei-Dei',
    'Durumi',
    'Dutse',
    'Galadimawa',
    'Garki',
    'Gudu',
    'Guzape',
    'Gwagwalada',
    'Gwarinpa',
    'Idu',
    'Jabi',
    'Jahi',
    'Jikwoyi',
    'Kado',
    'Karmo',
    'Karu',
    'Katampe',
    'Kaura',
    'Kubwa',
    'Kuje',
    'Life Camp',
    'Lokogoma',
    'Lugbe',
    'Mabushi',
    'Maitama',
    'Mpape',
    'Nyanya',
    'Utako',
    'Wuse',
    'Wuse 2',
    'Wuye',
  ];

  /// Rough centres (latitude, longitude) of the areas, and of the places
  /// the samples are in, for distances. The city's is its centre.
  static const _places = <String, (double, double)>{
    city: (9.0550, 7.4900),
    'Apo': (8.9850, 7.5020),
    'Asokoro': (9.0430, 7.5250),
    'Bwari': (9.2820, 7.3790),
    'Central Business District': (9.0550, 7.4900),
    'Dakibiyu': (9.0530, 7.4130),
    'Dakwo': (8.9830, 7.4640),
    'Dawaki': (9.1230, 7.4300),
    'Dei-Dei': (9.1130, 7.2840),
    'Durumi': (9.0230, 7.4680),
    'Dutse': (9.1450, 7.3950),
    'Galadimawa': (8.9960, 7.4300),
    'Garki': (9.0330, 7.4880),
    'Garki Area 11': (9.0420, 7.4930),
    'Gudu': (9.0080, 7.4780),
    'Guzape': (9.0270, 7.5100),
    'Gwagwalada': (8.9430, 7.0830),
    'Gwarinpa': (9.1100, 7.4060),
    'Idu': (9.0250, 7.3480),
    'Jabi': (9.0660, 7.4230),
    'Jahi': (9.0930, 7.4380),
    'Jikwoyi': (9.0020, 7.5880),
    'Kado': (9.0860, 7.4230),
    'Karmo': (9.0640, 7.3570),
    'Karu': (9.0230, 7.5760),
    'Katampe': (9.1120, 7.4620),
    'Kaura': (8.9990, 7.4560),
    'Kubwa': (9.1560, 7.3280),
    'Kuje': (8.8790, 7.2290),
    'Life Camp': (9.0760, 7.4010),
    'Lokogoma': (8.9800, 7.4480),
    'Lugbe': (8.9760, 7.3800),
    'Mabushi': (9.0800, 7.4500),
    'Maitama': (9.0880, 7.4930),
    'Mpape': (9.1240, 7.4920),
    'Nyanya': (9.0110, 7.5640),
    'Utako': (9.0710, 7.4410),
    'Wuse': (9.0640, 7.4650),
    'Wuse 2': (9.0790, 7.4760),
    'Wuse Market': (9.0660, 7.4620),
    'Wuye': (9.0610, 7.4470),
  };

  /// How far, in km, something [offsetKm] from the middle of [place] is from
  /// the middle of [area]: straight-line, to 0.1 km. [offsetKm] alone when
  /// either place is unknown.
  static double kmFrom(String area, String place, double offsetKm) {
    final from = _places[area];
    final to = _places[place];
    if (from == null || to == null) return offsetKm;
    final (lat1, lng1) = from;
    final (lat2, lng2) = to;
    double radians(double degrees) => degrees * math.pi / 180;
    final x = radians(lng2 - lng1) * math.cos(radians((lat1 + lat2) / 2));
    final y = radians(lat2 - lat1);
    final between = 6371 * math.sqrt(x * x + y * y);
    final km = math.sqrt(between * between + offsetKm * offsetKm);
    return (km * 10).round() / 10;
  }

  /// A point about [km] from the middle of [area], in a direction set by
  /// [seed], so each sample sits in its own place on the map.
  static GeoPoint spot(String area, String seed, double km) {
    final angle =
        seed.codeUnits.fold<int>(0, (h, c) => h * 31 + c) % 360 * math.pi / 180;
    final r = km.clamp(0.3, 1.8);
    return AbujaPlaces.centreOf(area)
        .offset(r * math.cos(angle), r * math.sin(angle));
  }

  static const _avatars = 'assets/mock/avatars';
  static const _photos = 'assets/images/onboarding';

  /// The sample accounts: a client and an artisan.
  static const _chidinma = 'u_chidinma';
  static const _emeka = 'u_emeka';

  /// Relay numbers for calls about a booking (see `Booking.counterpartPhone`).
  static const _relayEmeka = '+2347000000101';
  static const _relayChidinma = '+2347000000102';
  static const _relayFatima = '+2347000000103';
  static const _relayHauwa = '+2347000000104';

  /// Every listed artisan, best rated first (rating, then number of
  /// reviews), with distances from [area].
  static List<Artisan> artisansAt(DateTime now, {String area = city}) => [
        for (final artisan in _artisans(now))
          artisan.copyWith(
            distanceKm: kmFrom(area, artisan.area, artisan.distanceKm),
            location: spot(artisan.area, artisan.id, artisan.distanceKm),
          ),
      ]..sort(
          (a, b) => a.rating != b.rating
              ? b.rating.compareTo(a.rating)
              : b.reviewCount.compareTo(a.reviewCount),
        );

  /// Every listed artisan, as of now, with distances from the city centre.
  static List<Artisan> get artisans => artisansAt(DateTime.now());

  /// [days] after [now]'s date, at [hour]:[minute].
  static DateTime _dayAt(DateTime now, int days, int hour, [int minute = 0]) =>
      DateTime(now.year, now.month, now.day + days, hour, minute);

  /// Each one's distanceKm here is how far they are from the middle of
  /// their own area.
  static List<Artisan> _artisans(DateTime now) => [
        Artisan(
          id: 'a_emeka',
          name: 'Emeka Nwosu',
          trade: 'AC technician',
          categoryId: 'ac',
          area: 'Wuse 2',
          distanceKm: 1.2,
          rating: 4.9,
          reviewCount: 128,
          jobsCompleted: 214,
          startingPrice: 8000,
          isVerified: true,
          isAvailableToday: true,
          replyMinutes: 10,
          photo: '$_avatars/emeka_ac.webp',
          coverPhoto: '$_photos/ac_technicians.webp',
          coverFocusX: -0.4,
          coverFocusY: -0.85,
        ),
        Artisan(
          id: 'a_ibrahim',
          name: 'Ibrahim Musa',
          trade: 'Electrician',
          categoryId: 'electrical',
          area: 'Garki',
          distanceKm: 1.0,
          rating: 4.9,
          reviewCount: 96,
          jobsCompleted: 167,
          startingPrice: 5000,
          isVerified: true,
          isAvailableToday: true,
          replyMinutes: 15,
          photo: '$_avatars/ibrahim_electrician.webp',
          coverPhoto: '$_photos/electrician.webp',
          coverFocusX: 0.35,
          coverFocusY: -0.55,
        ),
        Artisan(
          id: 'a_chinedu',
          name: 'Chinedu Eze',
          trade: 'Auto mechanic',
          categoryId: 'mechanic',
          area: 'Jabi',
          distanceKm: 1.4,
          rating: 4.8,
          reviewCount: 203,
          jobsCompleted: 342,
          startingPrice: 10000,
          isVerified: true,
          nextFreeAt: _dayAt(now, 1, 9),
          replyMinutes: 25,
          coverPhoto: '$_photos/mechanic.webp',
          coverFocusY: 0.1,
        ),
        Artisan(
          id: 'a_yusuf',
          name: 'Yusuf Abdullahi',
          trade: 'Plumber',
          categoryId: 'plumbing',
          area: 'Utako',
          distanceKm: 0.9,
          rating: 4.8,
          reviewCount: 74,
          jobsCompleted: 131,
          startingPrice: 5000,
          isVerified: true,
          isAvailableToday: true,
          replyMinutes: 8,
        ),
        Artisan(
          id: 'a_kunle',
          name: 'Kunle Adebayo',
          trade: 'Tailor',
          categoryId: 'tailoring',
          area: 'Wuse Market',
          distanceKm: 0.6,
          rating: 4.8,
          reviewCount: 61,
          jobsCompleted: 98,
          startingPrice: 6500,
          isVerified: true,
          isAvailableToday: true,
          replyMinutes: 20,
          photo: '$_avatars/kunle_tailor.webp',
          coverPhoto: '$_photos/tailor.webp',
          coverFocusX: 0.1,
          coverFocusY: -0.3,
        ),
        Artisan(
          id: 'a_blessing',
          name: 'Blessing Okoro',
          trade: 'Cleaner',
          categoryId: 'cleaning',
          area: 'Gwarinpa',
          distanceKm: 1.3,
          rating: 4.8,
          reviewCount: 52,
          jobsCompleted: 156,
          startingPrice: 15000,
          isVerified: true,
          isAvailableToday: true,
          replyMinutes: 12,
        ),
        Artisan(
          id: 'a_halima',
          name: 'Halima Sani',
          trade: 'Solar installer',
          categoryId: 'solar',
          area: 'Lugbe',
          distanceKm: 1.5,
          rating: 4.8,
          reviewCount: 33,
          jobsCompleted: 47,
          startingPrice: 20000,
          isVerified: true,
          nextFreeAt: _dayAt(now, 3, 10),
          replyMinutes: 60,
        ),
        Artisan(
          id: 'a_tunde',
          name: 'Tunde Bakare',
          trade: 'Generator technician',
          categoryId: 'generator',
          area: 'Kubwa',
          distanceKm: 1.6,
          rating: 4.7,
          reviewCount: 112,
          jobsCompleted: 240,
          startingPrice: 10000,
          isVerified: true,
          nextFreeAt: _dayAt(now, 1, 8),
          replyMinutes: 25,
        ),
        Artisan(
          id: 'a_daniel',
          name: 'Daniel Bassey',
          trade: 'Plumber',
          categoryId: 'plumbing',
          area: 'Kubwa',
          distanceKm: 1.8,
          rating: 4.7,
          reviewCount: 58,
          jobsCompleted: 102,
          startingPrice: 4500,
          isVerified: true,
          nextFreeAt: _dayAt(now, 2, 8, 30),
          replyMinutes: 18,
        ),
        Artisan(
          id: 'a_abubakar',
          name: 'Abubakar Garba',
          trade: 'Carpenter',
          categoryId: 'carpentry',
          area: 'Dutse',
          distanceKm: 1.2,
          rating: 4.7,
          reviewCount: 52,
          jobsCompleted: 88,
          startingPrice: 10000,
          isVerified: true,
          isAvailableToday: true,
          replyMinutes: 30,
        ),
        Artisan(
          id: 'a_musa',
          name: 'Musa Danjuma',
          trade: 'Gardener',
          categoryId: 'gardening',
          area: 'Maitama',
          distanceKm: 1.1,
          rating: 4.7,
          reviewCount: 44,
          jobsCompleted: 73,
          startingPrice: 7000,
          isVerified: true,
          nextFreeAt: _dayAt(now, 2, 8),
          replyMinutes: 45,
          photo: '$_avatars/musa_gardener.webp',
          coverPhoto: '$_photos/gardener.webp',
          coverFocusX: 0.1,
        ),
        Artisan(
          id: 'a_grace',
          name: 'Grace Effiong',
          trade: 'Painter',
          categoryId: 'painting',
          area: 'Life Camp',
          distanceKm: 1.4,
          rating: 4.7,
          reviewCount: 28,
          jobsCompleted: 41,
          startingPrice: 25000,
          isVerified: true,
          nextFreeAt: _dayAt(now, 1, 10),
          replyMinutes: 40,
        ),
        Artisan(
          id: 'a_ifeanyi',
          name: 'Ifeanyi Nnaji',
          trade: 'TV and decoder installer',
          categoryId: 'tv',
          area: 'Wuse',
          distanceKm: 0.8,
          rating: 4.6,
          reviewCount: 45,
          jobsCompleted: 120,
          startingPrice: 5000,
          isVerified: true,
          isAvailableToday: true,
          replyMinutes: 15,
        ),
        Artisan(
          id: 'a_samuel',
          name: 'Samuel Adeyemi',
          trade: 'AC technician',
          categoryId: 'ac',
          area: 'Garki',
          distanceKm: 2.1,
          rating: 4.6,
          reviewCount: 39,
          jobsCompleted: 58,
          startingPrice: 7000,
          isVerified: true,
          isAvailableToday: true,
          replyMinutes: 20,
        ),
        Artisan(
          id: 'a_aminu',
          name: 'Aminu Lawal',
          trade: 'Fumigator',
          categoryId: 'pest',
          area: 'Apo',
          distanceKm: 1.2,
          rating: 4.6,
          reviewCount: 31,
          jobsCompleted: 64,
          startingPrice: 15000,
          isVerified: true,
          isAvailableToday: true,
          replyMinutes: 35,
        ),
        // New on RijHub: ID check pending, too few requests for a reply time.
        Artisan(
          id: 'a_peter',
          name: 'Peter Udoh',
          trade: 'Electrician',
          categoryId: 'electrical',
          area: 'Lokogoma',
          distanceKm: 1.0,
          rating: 4.5,
          reviewCount: 21,
          jobsCompleted: 34,
          startingPrice: 4000,
          isAvailableToday: true,
        ),
        Artisan(
          id: 'a_aliyu',
          name: 'Aliyu Sani',
          trade: 'AC technician',
          categoryId: 'ac',
          area: 'Maitama',
          distanceKm: 0.8,
          rating: 4.7,
          reviewCount: 64,
          jobsCompleted: 102,
          startingPrice: 8500,
          isVerified: true,
          isAvailableToday: true,
          replyMinutes: 15,
        ),
        Artisan(
          id: 'a_david',
          name: 'David Okoro',
          trade: 'AC technician',
          categoryId: 'ac',
          area: 'Wuse',
          distanceKm: 0.9,
          rating: 4.6,
          reviewCount: 40,
          jobsCompleted: 77,
          startingPrice: 7000,
          isVerified: true,
          isAvailableToday: true,
          replyMinutes: 25,
        ),
        Artisan(
          id: 'a_bala',
          name: 'Bala Yakubu',
          trade: 'AC technician',
          categoryId: 'ac',
          area: 'Utako',
          distanceKm: 1.1,
          rating: 4.6,
          reviewCount: 33,
          jobsCompleted: 51,
          startingPrice: 6500,
          isVerified: true,
          isAvailableToday: false,
        ),
        Artisan(
          id: 'a_kelechi',
          name: 'Kelechi Obi',
          trade: 'Plumber',
          categoryId: 'plumbing',
          area: 'Wuse 2',
          distanceKm: 0.7,
          rating: 4.7,
          reviewCount: 52,
          jobsCompleted: 88,
          startingPrice: 5500,
          isVerified: true,
          isAvailableToday: true,
          replyMinutes: 12,
        ),
        Artisan(
          id: 'a_moses',
          name: 'Moses Danladi',
          trade: 'Electrician',
          categoryId: 'electrical',
          area: 'Wuse 2',
          distanceKm: 1.3,
          rating: 4.8,
          reviewCount: 71,
          jobsCompleted: 120,
          startingPrice: 5000,
          isVerified: true,
          isAvailableToday: true,
          replyMinutes: 8,
        ),
        Artisan(
          id: 'a_hadiza',
          name: 'Hadiza Umar',
          trade: 'Cleaner',
          categoryId: 'cleaning',
          area: 'Garki',
          distanceKm: 1.0,
          rating: 4.8,
          reviewCount: 58,
          jobsCompleted: 96,
          startingPrice: 14000,
          isVerified: true,
          isAvailableToday: true,
          replyMinutes: 20,
        ),
        Artisan(
          id: 'a_segun',
          name: 'Segun Ade',
          trade: 'Generator technician',
          categoryId: 'generator',
          area: 'Wuse',
          distanceKm: 1.4,
          rating: 4.7,
          reviewCount: 49,
          jobsCompleted: 83,
          startingPrice: 9000,
          isVerified: true,
          isAvailableToday: true,
          replyMinutes: 18,
        ),
      ];

  /// Open jobs, newest first, with distances from [area].
  static List<JobPost> jobs(DateTime now, {String area = city}) => [
        for (final job in _jobs(now))
          job.copyWith(
            distanceKm: kmFrom(area, job.area, job.distanceKm),
            location: spot(job.area, job.id, job.distanceKm),
          ),
      ]..sort((a, b) => b.postedAt.compareTo(a.postedAt));

  /// Each one's distanceKm here is how far it is from the middle of its
  /// own area.
  static List<JobPost> _jobs(DateTime now) {
    DateTime ago(int minutes) => now.subtract(Duration(minutes: minutes));
    return [
      JobPost(
        id: 'j_1',
        title: 'AC not cooling and leaking water',
        categoryId: 'ac',
        area: 'Garki Area 11',
        distanceKm: 0.6,
        postedAt: ago(12),
        budgetMin: 8000,
        budgetMax: 12000,
        isUrgent: true,
        description: 'Split unit in the sitting room. It blows warm air and '
            'water drips from the indoor unit onto the wall. Please come '
            'today if you can.',
        clientPhoneVerified: true,
        clientJobsPosted: 3,
      ),
      JobPost(
        id: 'j_9',
        title: 'Fix a leaking kitchen tap',
        categoryId: 'plumbing',
        area: 'Jahi',
        distanceKm: 0.7,
        postedAt: ago(18),
        budgetMin: 4000,
        budgetMax: 7000,
        description: 'The mixer tap drips all day and its base is loose. I '
            'can buy parts nearby if you tell me what to get.',
        clientPhoneVerified: true,
        clientJobsPosted: 2,
      ),
      JobPost(
        id: 'j_5',
        title: 'Socket sparking in the kitchen',
        categoryId: 'electrical',
        area: 'Wuse 2',
        distanceKm: 1.1,
        postedAt: ago(25),
        budgetMin: 5000,
        budgetMax: 8000,
        isUrgent: true,
        description: 'The socket behind the microwave sparks when anything '
            "is plugged in. I've switched that circuit off at the breaker "
            'for now.',
        clientPhoneVerified: true,
        clientJobsPosted: 2,
      ),
      JobPost(
        id: 'j_14',
        title: 'Satellite dish needs realigning',
        categoryId: 'tv',
        area: 'Wuye',
        distanceKm: 0.9,
        postedAt: ago(35),
        budgetMin: 5000,
        budgetMax: 8000,
        quoteCount: 1,
        description: "No signal since Tuesday's storm. The dish on the roof "
            'looks like it moved. There is a fixed ladder to the roof.',
        clientPhoneVerified: true,
        clientJobsPosted: 1,
      ),
      JobPost(
        id: 'j_2',
        title: 'Service two split AC units',
        categoryId: 'ac',
        area: 'Wuse 2',
        distanceKm: 0.8,
        postedAt: ago(40),
        budgetMin: 15000,
        budgetMax: 20000,
        quoteCount: 2,
        description: 'Two 1.5HP split units, last serviced in March. Washing, '
            'a gas check and a general look over. Third floor, no lift.',
        clientPhoneVerified: true,
        clientJobsPosted: 5,
      ),
      JobPost(
        id: 'j_10',
        title: 'Changeover switch keeps tripping',
        categoryId: 'electrical',
        area: 'Garki',
        distanceKm: 1.2,
        postedAt: ago(50),
        budgetMin: 8000,
        budgetMax: 15000,
        quoteCount: 1,
        description: 'When we switch over to the generator, the changeover '
            "trips the breaker. Please check it, and replace it if it's "
            'bad.',
        clientPhoneVerified: true,
        clientJobsPosted: 6,
      ),
      JobPost(
        id: 'j_6',
        title: "Generator won't start",
        categoryId: 'generator',
        area: 'Jabi',
        distanceKm: 1.0,
        postedAt: ago(60),
        quoteCount: 3,
        description: "7.5 kVA petrol generator. It cranks but hasn't started "
            'since the weekend, and the fuel is fresh.',
        clientPhoneVerified: true,
        clientJobsPosted: 4,
      ),
      JobPost(
        id: 'j_3',
        title: 'Install 1.5HP AC in a new flat',
        categoryId: 'ac',
        area: 'Gwarinpa',
        distanceKm: 1.5,
        postedAt: ago(120),
        quoteCount: 4,
        description: 'New 1.5HP split unit, still in the box. It needs '
            'mounting, about 3 m of piping and a socket close by.',
        clientPhoneVerified: true,
        clientJobsPosted: 1,
      ),
      JobPost(
        id: 'j_17',
        title: 'Generator service: oil, plugs and filter',
        categoryId: 'generator',
        area: 'Maitama',
        distanceKm: 0.9,
        postedAt: ago(150),
        budgetMin: 10000,
        budgetMax: 15000,
        quoteCount: 2,
        description: '8 kVA generator due for its service: oil change, plugs '
            'and air filter. I have the oil already.',
        clientPhoneVerified: true,
        clientJobsPosted: 3,
      ),
      JobPost(
        id: 'j_7',
        title: 'Unblock bathroom drain',
        categoryId: 'plumbing',
        area: 'Asokoro',
        distanceKm: 1.0,
        postedAt: ago(180),
        budgetMin: 6000,
        budgetMax: 10000,
        quoteCount: 2,
        description: "The shower drain is slow and smells. I've tried a "
            'plunger. Ground-floor flat.',
        clientPhoneVerified: true,
        clientJobsPosted: 2,
      ),
      JobPost(
        id: 'j_15',
        title: 'Car AC blowing hot air',
        categoryId: 'mechanic',
        area: 'Kubwa',
        distanceKm: 1.3,
        postedAt: ago(200),
        budgetMin: 15000,
        budgetMax: 25000,
        quoteCount: 1,
        description: 'Toyota Corolla 2012. The AC has blown hot air since last '
            'week. I can bring the car to you.',
        clientJobsPosted: 1,
      ),
      JobPost(
        id: 'j_8',
        title: 'Deep clean a 3-bedroom flat',
        categoryId: 'cleaning',
        area: 'Maitama',
        distanceKm: 1.2,
        postedAt: ago(240),
        budgetMin: 35000,
        budgetMax: 35000,
        quoteCount: 5,
        description: 'We move in on Saturday. Kitchen cabinets, bathrooms, '
            'windows and floors. There is water and a ladder on site.',
        clientPhoneVerified: true,
        clientJobsPosted: 1,
      ),
      JobPost(
        id: 'j_4',
        title: 'Gas refill for fridge and AC',
        categoryId: 'ac',
        area: 'Utako',
        distanceKm: 0.7,
        postedAt: ago(300),
        budgetMin: 25000,
        budgetMax: 25000,
        quoteCount: 1,
        description: 'The upright fridge stopped cooling last week, and the '
            'bedroom AC is weak. Both may need gas.',
        clientJobsPosted: 1,
      ),
      JobPost(
        id: 'j_11',
        title: 'Install an inverter and two batteries',
        categoryId: 'solar',
        area: 'Lokogoma',
        distanceKm: 1.1,
        postedAt: ago(360),
        budgetMin: 40000,
        budgetMax: 60000,
        quoteCount: 3,
        description: '3.5 kVA inverter and two 220Ah batteries, already '
            'bought. They need installing and wiring to the distribution '
            'board.',
        clientPhoneVerified: true,
        clientJobsPosted: 1,
      ),
      JobPost(
        id: 'j_16',
        title: 'Check the wiring before we move in',
        categoryId: 'electrical',
        area: 'Katampe',
        distanceKm: 1.4,
        postedAt: ago(420),
        budgetMin: 20000,
        budgetMax: 30000,
        quoteCount: 2,
        description: 'Four-bedroom duplex. Please check every socket, the '
            'distribution board and the earthing before we move in.',
        clientJobsPosted: 1,
      ),
      JobPost(
        id: 'j_12',
        title: 'Assemble a wardrobe and two beds',
        categoryId: 'carpentry',
        area: 'Life Camp',
        distanceKm: 1.0,
        postedAt: ago(26 * 60),
        budgetMin: 20000,
        budgetMax: 30000,
        quoteCount: 4,
        description: 'Flat-pack wardrobe and two bed frames, instructions '
            'included. Saturday morning suits us best.',
        clientPhoneVerified: true,
        clientJobsPosted: 3,
      ),
      JobPost(
        id: 'j_18',
        title: 'Fumigate a 3-bedroom flat',
        categoryId: 'pest',
        area: 'Apo',
        distanceKm: 1.3,
        postedAt: ago(28 * 60),
        budgetMin: 25000,
        budgetMax: 35000,
        quoteCount: 3,
        description: 'Cockroaches in the kitchen and bathrooms. We can be out '
            'of the flat for the day.',
        clientPhoneVerified: true,
        clientJobsPosted: 2,
      ),
      JobPost(
        id: 'j_13',
        title: 'Paint a 2-bedroom flat',
        categoryId: 'painting',
        area: 'Lugbe',
        distanceKm: 1.6,
        postedAt: ago(48 * 60),
        budgetMin: 120000,
        budgetMax: 180000,
        quoteCount: 6,
        description: "Walls and ceilings, emulsion. We haven't bought paint "
            'yet, so please quote with and without materials.',
        clientPhoneVerified: true,
        clientJobsPosted: 2,
      ),
    ];
  }

  /// Open jobs posted this week across Abuja, by trade. They add up to 126.
  static const _jobsThisWeekInCity = {
    'ac': 46,
    'electrical': 22,
    'plumbing': 16,
    'generator': 13,
    'cleaning': 9,
    'solar': 5,
    'carpentry': 4,
    'painting': 3,
    'mechanic': 3,
    'tv': 2,
    'tailoring': 1,
    'gardening': 1,
    'pest': 1,
  };

  /// The same in or near one neighbourhood. They add up to 42.
  static const _jobsThisWeekInArea = {
    'ac': 18,
    'electrical': 7,
    'plumbing': 5,
    'generator': 4,
    'cleaning': 3,
    'solar': 1,
    'carpentry': 1,
    'painting': 1,
    'mechanic': 1,
    'tv': 1,
  };

  /// Of those, the ones posted today, across Abuja.
  static const _postedTodayInCity = {
    'ac': 13,
    'electrical': 6,
    'plumbing': 5,
    'generator': 4,
    'cleaning': 3,
    'solar': 1,
    'carpentry': 1,
    'painting': 1,
    'mechanic': 1,
    'tv': 1,
  };

  /// Of those, the ones posted today in or near one neighbourhood.
  static const _postedTodayInArea = {
    'ac': 5,
    'electrical': 2,
    'plumbing': 2,
    'generator': 1,
    'cleaning': 1,
    'painting': 1,
  };

  /// What most budgets fall between, by trade, in naira.
  static const _typicalBudgets = <String, (int, int)>{
    'ac': (8000, 15000),
    'electrical': (3000, 10000),
    'plumbing': (5000, 12000),
    'generator': (10000, 25000),
    'cleaning': (15000, 40000),
    'solar': (30000, 80000),
    'carpentry': (10000, 35000),
    'painting': (60000, 180000),
    'mechanic': (10000, 30000),
    'tv': (5000, 12000),
    'tailoring': (6000, 20000),
    'gardening': (7000, 15000),
    'pest': (20000, 35000),
    'moving': (30000, 80000),
  };

  /// Across every trade.
  static const _typicalBudgetOverall = (5000, 20000);

  /// Fewer open jobs than this says too little about budgets.
  static const _fewestForBudgets = 3;

  /// Demand in [area] (null or the city for all of Abuja), for one trade
  /// or all.
  static JobDemand demand({String? area, String? categoryId}) {
    final wholeCity = area == null || area == city;
    int count(Map<String, int> byTrade) => categoryId == null
        ? byTrade.values.fold(0, (sum, n) => sum + n)
        : byTrade[categoryId] ?? 0;
    final open = count(wholeCity ? _jobsThisWeekInCity : _jobsThisWeekInArea);
    final budgets = open < _fewestForBudgets
        ? null
        : categoryId == null
            ? _typicalBudgetOverall
            : _typicalBudgets[categoryId];
    return JobDemand(
      openThisWeek: open,
      postedToday: count(wholeCity ? _postedTodayInCity : _postedTodayInArea),
      typicalBudgetMin: budgets?.$1,
      typicalBudgetMax: budgets?.$2,
    );
  }

  /// Typical prices in Abuja, the most asked-about first, as worked out at
  /// the start of [now]'s month.
  static List<PriceGuideItem> priceGuide(DateTime now) {
    final updatedOn = DateTime(now.year, now.month);
    return [
      PriceGuideItem(
        problem: 'AC servicing (1 unit)',
        categoryId: 'ac',
        minPrice: 8000,
        maxPrice: 12000,
        updatedOn: updatedOn,
      ),
      PriceGuideItem(
        problem: 'Generator servicing (up to 10 kVA)',
        categoryId: 'generator',
        minPrice: 10000,
        maxPrice: 18000,
        updatedOn: updatedOn,
      ),
      PriceGuideItem(
        problem: 'Socket or switch replacement',
        categoryId: 'electrical',
        minPrice: 3000,
        maxPrice: 6000,
        updatedOn: updatedOn,
      ),
      PriceGuideItem(
        problem: 'Sink or toilet leak',
        categoryId: 'plumbing',
        minPrice: 5000,
        maxPrice: 10000,
        updatedOn: updatedOn,
      ),
      PriceGuideItem(
        problem: 'Deep cleaning (2-bedroom flat)',
        categoryId: 'cleaning',
        minPrice: 25000,
        maxPrice: 40000,
        updatedOn: updatedOn,
      ),
      // The rest of the API's guide (app/catalog.py PRICE_GUIDE): every trade.
      PriceGuideItem(
        problem: 'Gas top-up (1 unit)',
        categoryId: 'ac',
        minPrice: 12000,
        maxPrice: 18000,
        updatedOn: updatedOn,
      ),
      PriceGuideItem(
        problem: 'Inverter and battery check',
        categoryId: 'solar',
        minPrice: 15000,
        maxPrice: 40000,
        updatedOn: updatedOn,
      ),
      PriceGuideItem(
        problem: 'Paint one room (labour)',
        categoryId: 'painting',
        minPrice: 25000,
        maxPrice: 80000,
        updatedOn: updatedOn,
      ),
      PriceGuideItem(
        problem: 'Car repair',
        categoryId: 'mechanic',
        minPrice: 10000,
        maxPrice: 30000,
        updatedOn: updatedOn,
      ),
      PriceGuideItem(
        problem: 'Door, lock or furniture repair',
        categoryId: 'carpentry',
        minPrice: 8000,
        maxPrice: 25000,
        updatedOn: updatedOn,
      ),
      PriceGuideItem(
        problem: 'Sewing or altering clothes',
        categoryId: 'tailoring',
        minPrice: 6500,
        maxPrice: 25000,
        updatedOn: updatedOn,
      ),
      PriceGuideItem(
        problem: 'Lawn and hedge care',
        categoryId: 'gardening',
        minPrice: 4000,
        maxPrice: 12000,
        updatedOn: updatedOn,
      ),
      PriceGuideItem(
        problem: 'Moving help',
        categoryId: 'moving',
        minPrice: 20000,
        maxPrice: 60000,
        updatedOn: updatedOn,
      ),
      PriceGuideItem(
        problem: 'Home fumigation',
        categoryId: 'pest',
        minPrice: 15000,
        maxPrice: 35000,
        updatedOn: updatedOn,
      ),
      PriceGuideItem(
        problem: 'TV mounting or decoder setup',
        categoryId: 'tv',
        minPrice: 5000,
        maxPrice: 15000,
        updatedOn: updatedOn,
      ),
    ];
  }

  /// When the sample day's first booking starts: on the quarter hour, at
  /// least 70 minutes after [now], so one is always coming up.
  static DateTime firstBookingAt(DateTime now) {
    final soon = now.add(const Duration(minutes: 70));
    final secondsIntoHour = soon.minute * 60 + soon.second;
    final quarters = (secondsIntoHour + 899) ~/ 900;
    return DateTime(soon.year, soon.month, soon.day, soon.hour, quarters * 15);
  }

  /// The upcoming bookings of account [userId], seen as [role]. Only the
  /// sample accounts have any; new accounts start with none.
  static List<Booking> bookingsFor(
    String? userId,
    UserRole role,
    DateTime now,
  ) =>
      switch ((userId, role)) {
        (_chidinma, UserRole.client) => clientBookings(now),
        (_emeka, UserRole.artisan) => artisanBookings(now),
        _ => const [],
      };

  /// The sample client's: Emeka is coming to service her AC.
  static List<Booking> clientBookings(DateTime now) => [
        Booking(
          id: 'b_1',
          serviceName: 'AC servicing',
          categoryId: 'ac',
          scheduledAt: firstBookingAt(now),
          status: BookingStatus.confirmed,
          counterpartName: 'Emeka Nwosu',
          counterpartPhoto: '$_avatars/emeka_ac.webp',
          counterpartPhone: _relayEmeka,
          area: 'Wuse 2',
          price: 12000,
          fee: 600,
          startCode: '4829',
          landmark: 'near Banex Plaza',
          artisanId: 'a_emeka',
          conversationId: 'c_emeka',
          payment: PaymentState.held,
          notes: "My bedroom AC is not cooling and it's dripping water.",
        ),
      ];

  /// The sample artisan's: the same AC job, another later today, and one
  /// tomorrow. He doesn't get the start code; the client gives it to him.
  static List<Booking> artisanBookings(DateTime now) {
    final first = firstBookingAt(now);
    return [
      Booking(
        id: 'b_1',
        serviceName: 'AC servicing',
        categoryId: 'ac',
        scheduledAt: first,
        status: BookingStatus.confirmed,
        counterpartName: 'Chidinma Okafor',
        counterpartPhone: _relayChidinma,
        payment: PaymentState.held,
        area: 'Wuse 2',
        price: 12000,
        landmark: 'near Banex Plaza',
        distanceKm: 3.1,
      ),
      Booking(
        id: 'b_2',
        serviceName: 'Changeover switch repair',
        categoryId: 'electrical',
        scheduledAt: first.add(const Duration(hours: 2, minutes: 30)),
        status: BookingStatus.confirmed,
        counterpartName: 'Fatima Bello',
        counterpartPhone: _relayFatima,
        payment: PaymentState.held,
        area: 'Jabi',
        price: 15000,
        landmark: 'behind Jabi Lake Mall',
        distanceKm: 6.4,
      ),
      Booking(
        id: 'b_3',
        serviceName: 'Service three split units',
        categoryId: 'ac',
        scheduledAt: _dayAt(now, 1, 10),
        status: BookingStatus.confirmed,
        counterpartName: 'Hauwa Ibrahim',
        counterpartPhone: _relayHauwa,
        payment: PaymentState.held,
        area: 'Maitama',
        price: 30000,
        landmark: 'near Transcorp Hilton',
        distanceKm: 2.6,
      ),
    ];
  }

  /// Requests waiting for account [userId], made at [now]: the sample
  /// artisan has one, to answer within 14 minutes, for a two-hour window
  /// that starts on the hour, one to two hours from now. That leaves time
  /// to finish the first booking, which starts 70 to 85 minutes from now
  /// in the same area.
  static List<DirectRequest> requestsFor(String? userId, DateTime now) {
    if (userId != _emeka) return const [];
    final start = DateTime(now.year, now.month, now.day, now.hour + 2);
    return [
      DirectRequest(
        id: 'r_1',
        clientName: 'Ngozi A.',
        serviceName: 'Socket repair',
        categoryId: 'electrical',
        area: 'Wuse 2',
        window: TimeWindow(
          start: start,
          end: start.add(const Duration(hours: 2)),
        ),
        price: 6000,
        expiresAt: now.add(const Duration(minutes: 14)),
        message:
            "Two sockets in my kitchen are sparking. I've switched them off at the board for now.",
        photos: const ['$_photos/electrician.webp'],
        voiceNote: const VoiceNote(
          path: 'mock://ngozi',
          duration: Duration(seconds: 12),
          heard:
              'The one near the fridge is the worst. It makes a noise when I plug anything in.',
        ),
        distanceKm: 0.9,
        landmark: 'off Aminu Kano Crescent',
      ),
    ];
  }

  /// Artisans account [userId] has hired before, with distances from
  /// [area]: the sample client had Yusuf fix a leak three weeks ago and
  /// rated him 5. (Her upcoming booking is with Emeka, so the two
  /// relationships show side by side.)
  static List<HiredArtisan> hiredBeforeBy(
    String? userId,
    DateTime now, {
    String area = city,
  }) {
    if (userId != _chidinma) return const [];
    final yusuf =
        artisansAt(now, area: area).firstWhere((a) => a.id == 'a_yusuf');
    return [
      HiredArtisan(
        artisan: yusuf,
        serviceName: 'Kitchen sink leak',
        lastHiredOn: _dayAt(now, -21, 0),
        yourRating: 5,
      ),
    ];
  }

  /// The dashboard of artisan [user]: the sample one for the sample
  /// artisan, and a first-run one for anyone else: off, nothing earned,
  /// and the server's four setup steps to do (services/artisans.py
  /// setup_steps), the first two holding back bookings.
  static ArtisanDashboard dashboardFor(AppUser? user) {
    if (user?.id == _emeka) return dashboard;
    return const ArtisanDashboard(
      isAvailable: false,
      earningsThisWeek: 0,
      earningsLastWeek: 0,
      availableBalance: 0,
      jobsThisWeek: 0,
      rating: 0,
      reviewCount: 0,
      responseRate: 0,
      setupSteps: [
        SetupStep(
          id: 'services',
          label: 'Add your services and prices',
          done: false,
          reason: 'Clients book from your prices',
          effort: '2 minutes',
          blocksBookings: true,
        ),
        SetupStep(
          id: 'identity',
          label: 'Check your ID',
          done: false,
          reason: 'Clients only book ID-checked artisans',
          effort: '2 minutes',
          blocksBookings: true,
        ),
        SetupStep(
          id: 'work_photos',
          label: 'Add photos of your work',
          done: false,
          reason: 'Clients can see what you do before they book',
          effort: '1 minute',
        ),
        SetupStep(
          id: 'payout',
          label: 'Add your bank account',
          done: false,
          reason: 'So we can pay you for finished jobs',
          effort: '1 minute',
        ),
      ],
    );
  }

  /// The sample artisan's dashboard.
  static const dashboard = ArtisanDashboard(
    isAvailable: true,
    earningsThisWeek: 86500,
    earningsLastWeek: 72000,
    availableBalance: 54000,
    earnedToDate: 1284500,
    jobsThisWeek: 6,
    rating: 4.9,
    reviewCount: 128,
    responseRate: 96,
    setupSteps: [
      SetupStep(id: 'identity', label: 'Verify your identity', done: true),
      SetupStep(id: 'services', label: 'Add services and prices', done: true),
      SetupStep(id: 'area', label: 'Set your work area', done: true),
      SetupStep(
        id: 'work_photos',
        label: 'Add photos of your work',
        done: false,
        reason: 'Clients can see what you do before they book.',
      ),
    ],
  );

  /// Accounts that already exist, keyed by E.164 phone number.
  static const existingUsers = {
    '+2348031234567': AppUser(
      id: _chidinma,
      firstName: 'Chidinma',
      lastName: 'Okafor',
      phone: '+2348031234567',
      role: UserRole.client,
      email: 'chidinma@example.com',
      homeArea: 'Wuse 2',
    ),
    '+2348059876543': AppUser(
      id: _emeka,
      firstName: 'Emeka',
      lastName: 'Nwosu',
      phone: '+2348059876543',
      role: UserRole.artisan,
      homeArea: 'Wuse 2',
      photo: '$_avatars/emeka_ac.webp',
      tradeIds: ['ac', 'electrical'],
    ),
  };

  static AppUser sampleUser(UserRole role) =>
      existingUsers.values.firstWhere((u) => u.role == role);
}
