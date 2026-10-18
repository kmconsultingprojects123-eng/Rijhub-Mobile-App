import '../models/models.dart';

/// The trades RijHub serves, in the order to show them. A fixed list until
/// the backend serves it; `CatalogRepository.categories` returns the same.
abstract final class Trades {
  static const all = [
    ServiceCategory(
      id: 'ac',
      name: 'AC repair',
      iconKey: 'ac',
      artisanPlural: 'AC technicians',
    ),
    ServiceCategory(
      id: 'electrical',
      name: 'Electrical',
      iconKey: 'electrical',
      artisanPlural: 'Electricians',
    ),
    ServiceCategory(
      id: 'plumbing',
      name: 'Plumbing',
      iconKey: 'plumbing',
      artisanPlural: 'Plumbers',
    ),
    ServiceCategory(
      id: 'generator',
      name: 'Generator',
      iconKey: 'generator',
      artisanPlural: 'Generator technicians',
    ),
    ServiceCategory(
      id: 'cleaning',
      name: 'Cleaning',
      iconKey: 'cleaning',
      artisanPlural: 'Cleaners',
    ),
    ServiceCategory(
      id: 'mechanic',
      name: 'Auto repair',
      iconKey: 'mechanic',
      artisanPlural: 'Mechanics',
    ),
    ServiceCategory(
      id: 'solar',
      name: 'Solar',
      iconKey: 'solar',
      artisanPlural: 'Solar installers',
    ),
    ServiceCategory(
      id: 'carpentry',
      name: 'Carpentry',
      iconKey: 'carpentry',
      artisanPlural: 'Carpenters',
    ),
    ServiceCategory(
      id: 'painting',
      name: 'Painting',
      iconKey: 'painting',
      artisanPlural: 'Painters',
    ),
    ServiceCategory(
      id: 'tailoring',
      name: 'Tailoring',
      iconKey: 'tailoring',
      artisanPlural: 'Tailors',
    ),
    ServiceCategory(
      id: 'gardening',
      name: 'Gardening',
      iconKey: 'gardening',
      artisanPlural: 'Gardeners',
    ),
    ServiceCategory(
      id: 'moving',
      name: 'Moving',
      iconKey: 'moving',
      artisanPlural: 'Movers',
    ),
    ServiceCategory(
      id: 'pest',
      name: 'Pest control',
      iconKey: 'pest',
      artisanPlural: 'Fumigators',
    ),
    ServiceCategory(
      id: 'tv',
      name: 'TV & decoder',
      iconKey: 'tv',
      artisanPlural: 'TV technicians',
    ),
  ];

  static ServiceCategory byId(String id) =>
      all.firstWhere((c) => c.id == id, orElse: () => all.first);
}
