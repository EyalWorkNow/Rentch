import 'package:dating_app/core/services/local_storage.dart';
import 'package:dating_app/core/services/rental_data_service.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  test('best match ranks soft near-misses by value, fit, and confidence',
      () async {
    final excellent = _property(
      id: 'excellent-near-budget',
      price: 6250,
      rooms: 3,
      sizeM2: 78,
      street: 'Market',
      streetNumber: 12,
      features: const ['parking', 'balcony', 'elevator'],
      mediaCount: 4,
      ownerName: 'Owner',
      url: 'https://example.com/excellent',
      entryDate: '2026-06-10',
    );
    final cheapButWeak = _property(
      id: 'cheap-but-weak',
      price: 5600,
      rooms: 3,
      sizeM2: 63,
      street: '',
      streetNumber: -1,
      features: const ['parking'],
      mediaCount: 0,
      ownerName: '',
      entryDate: '2026-06-12',
    );
    final missingDealBreaker = _property(
      id: 'missing-deal-breaker',
      price: 5200,
      rooms: 3,
      sizeM2: 70,
      features: const ['balcony', 'elevator'],
      mediaCount: 3,
      entryDate: '2026-06-08',
    );

    final provider = DatingProvider(
      rentalDataService: _FakeRentalDataService([
        excellent,
        cheapButWeak,
        missingDealBreaker,
        _property(id: 'market-1', price: 5900, sizeM2: 72),
        _property(id: 'market-2', price: 6100, sizeM2: 76),
        _property(id: 'market-3', price: 6400, sizeM2: 80),
        _property(id: 'market-4', price: 6600, sizeM2: 82),
      ]),
      localStorageService: _MemoryLocalStorageService(),
    );

    await provider.initialize();

    const filters = SearchFilters(
      query: '',
      minBudget: 600,
      maxBudget: 6000,
      minRooms: 3,
      maxRooms: 4,
      areaId: 'all_israel',
      requiredFeatures: {'parking'},
      preferredFeatures: {'balcony', 'elevator'},
      minSizeM2: 60,
      maxSizeM2: 90,
      propertyTypes: <String>{},
      preferredPropertyTypes: <String>{},
      conditions: <String>{},
      preferredConditions: <String>{},
      listingSource: ListingSourceFilter.any,
      minFloor: 0,
      moveInFilter: MoveInFilter.within30Days,
      sortBy: SearchSortOption.bestMatch,
      includeUnknownPriceListings: false,
      customAreaPolygon: <LatLng>[],
      city: 'Tel Aviv',
      transactionType: TransactionTypeFilter.rent,
    );

    await provider.updateFilters(filters);

    final rankedIds = provider.filteredProperties.map((p) => p.id).toList();
    expect(rankedIds, contains(excellent.id));
    expect(rankedIds, isNot(contains(missingDealBreaker.id)));
    expect(
      rankedIds.indexOf(excellent.id),
      lessThan(rankedIds.indexOf(cheapButWeak.id)),
    );
    expect(
      provider.matchScore(excellent),
      greaterThan(provider.matchScore(cheapButWeak)),
    );
    expect(provider.matchScore(missingDealBreaker), 0);

    await provider.updateFilters(
      filters.copyWith(sortBy: SearchSortOption.priceLowToHigh),
    );

    expect(
      provider.filteredProperties.map((p) => p.id),
      isNot(contains(excellent.id)),
    );

    provider.dispose();
  });

  test('listings without a real price stay hidden until explicitly included',
      () async {
    final provider = DatingProvider(
      rentalDataService: _FakeRentalDataService([
        _property(id: 'priced', price: 6200, sizeM2: 78),
        _property(id: 'missing-price', price: 0, sizeM2: 78),
      ]),
      localStorageService: _MemoryLocalStorageService(),
    );

    await provider.initialize();

    const filters = SearchFilters(
      query: '',
      minBudget: 600,
      maxBudget: 7000,
      minRooms: 0,
      maxRooms: 4,
      areaId: 'all_israel',
      requiredFeatures: <String>{},
      preferredFeatures: <String>{},
      minSizeM2: 0,
      maxSizeM2: 120,
      propertyTypes: <String>{},
      preferredPropertyTypes: <String>{},
      conditions: <String>{},
      preferredConditions: <String>{},
      listingSource: ListingSourceFilter.any,
      minFloor: 0,
      moveInFilter: MoveInFilter.any,
      sortBy: SearchSortOption.bestMatch,
      includeUnknownPriceListings: false,
      customAreaPolygon: <LatLng>[],
      city: '',
      transactionType: TransactionTypeFilter.rent,
    );

    await provider.updateFilters(filters);
    expect(
      provider.filteredProperties.map((p) => p.id),
      isNot(contains('missing-price')),
    );

    await provider.updateFilters(
      filters.copyWith(includeUnknownPriceListings: true),
    );
    expect(
      provider.filteredProperties.map((p) => p.id),
      contains('missing-price'),
    );

    provider.dispose();
  });

  test('listing source and move-in support preferred and required states',
      () async {
    final provider = DatingProvider(
      rentalDataService: _FakeRentalDataService([
        _property(
          id: 'private-fast',
          agencyListing: false,
          entryDate: '2026-06-12',
          price: 6200,
        ),
        _property(
          id: 'agency-fast',
          agencyListing: true,
          entryDate: '2026-06-11',
          price: 6200,
        ),
        _property(
          id: 'private-slow',
          agencyListing: false,
          entryDate: '2026-09-20',
          price: 6200,
        ),
      ]),
      localStorageService: _MemoryLocalStorageService(),
    );

    await provider.initialize();

    const preferredFilters = SearchFilters(
      query: '',
      minBudget: 600,
      maxBudget: 7000,
      minRooms: 0,
      maxRooms: 4,
      areaId: 'all_israel',
      requiredFeatures: <String>{},
      preferredFeatures: <String>{},
      minSizeM2: 0,
      maxSizeM2: 120,
      propertyTypes: <String>{},
      preferredPropertyTypes: <String>{},
      conditions: <String>{},
      preferredConditions: <String>{},
      listingSource: ListingSourceFilter.any,
      preferredListingSources: {ListingSourceFilter.privateOnly},
      minFloor: 0,
      moveInFilter: MoveInFilter.any,
      preferredMoveInFilters: {MoveInFilter.within30Days},
      sortBy: SearchSortOption.bestMatch,
      includeUnknownPriceListings: false,
      customAreaPolygon: <LatLng>[],
      city: '',
      transactionType: TransactionTypeFilter.rent,
    );

    await provider.updateFilters(preferredFilters);
    final preferredIds = provider.filteredProperties.map((p) => p.id).toList();
    expect(preferredIds, contains('agency-fast'));
    expect(
      preferredIds.indexOf('private-fast'),
      lessThan(preferredIds.indexOf('agency-fast')),
    );

    await provider.updateFilters(
      preferredFilters.copyWith(
        requiredListingSources: {ListingSourceFilter.privateOnly},
        preferredListingSources: const <ListingSourceFilter>{},
        requiredMoveInFilters: {MoveInFilter.within30Days},
        preferredMoveInFilters: const <MoveInFilter>{},
      ),
    );

    final requiredIds = provider.filteredProperties.map((p) => p.id).toList();
    expect(requiredIds, contains('private-fast'));
    expect(requiredIds, isNot(contains('agency-fast')));
    expect(requiredIds, isNot(contains('private-slow')));

    provider.dispose();
  });
}

class _FakeRentalDataService extends RentalDataService {
  _FakeRentalDataService(this.properties);

  final List<RentalProperty> properties;

  @override
  Future<PropertyPage> loadFirstPage({String areaId = 'all_israel'}) async {
    return PropertyPage(items: properties, hasMore: false);
  }

  @override
  TenantProfile createDefaultTenantProfile() {
    return const TenantProfile(
      id: 'tenant-test',
      name: 'Tenant',
      bio: '',
      photoUrls: <String>[],
      budgetMax: 6000,
      desiredRooms: 3,
      moveInWindow: 'within 30 days',
      importantDetails: <String>[],
    );
  }

  @override
  List<AppReview> createTenantReviews() => const [];

  @override
  List<AppReview> createPropertyReviews(RentalProperty property) {
    if (property.id == 'excellent-near-budget') {
      return const [
        AppReview(
          id: 'review-excellent',
          authorName: 'Previous tenant',
          rating: 5,
          text: 'Clear owner, maintained building, easy handover.',
        ),
      ];
    }
    return const [];
  }

  @override
  List<SearchArea> createSearchAreas() {
    return const [
      SearchArea(
        id: 'all_israel',
        name: 'All',
        center: LatLng(32.07, 34.78),
        polygon: [
          LatLng(31.7, 34.4),
          LatLng(31.7, 35.2),
          LatLng(32.4, 35.2),
          LatLng(32.4, 34.4),
        ],
      ),
    ];
  }
}

class _MemoryLocalStorageService extends LocalStorageService {
  Map<String, dynamic>? state;

  @override
  Future<Map<String, dynamic>?> loadAppState() async => state;

  @override
  Future<void> saveAppState(
    Map<String, dynamic> state, {
    bool syncRemote = true,
  }) async {
    this.state = Map<String, dynamic>.from(state);
  }

  @override
  Future<void> syncRemoteAppState(Map<String, dynamic> state) async {
    this.state = Map<String, dynamic>.from(state);
  }

  @override
  Future<void> clearAppState() async {
    state = null;
  }
}

RentalProperty _property({
  required String id,
  int price = 6000,
  double rooms = 3,
  int sizeM2 = 75,
  String street = 'Main',
  int streetNumber = 1,
  List<String> features = const ['parking'],
  int mediaCount = 2,
  String ownerName = 'Owner',
  String url = 'https://example.com/listing',
  String entryDate = '2026-06-15',
  bool agencyListing = false,
}) {
  return RentalProperty(
    id: id,
    url: url,
    price: price,
    rooms: rooms,
    sizeM2: sizeM2,
    floor: '3',
    totalFloors: '6',
    city: 'Tel Aviv',
    neighborhood: 'Center',
    street: street,
    streetNumber: streetNumber,
    lat: 32.08,
    lon: 34.78,
    propertyType: 'Apartment',
    entryDate: entryDate,
    condition: 'Renovated',
    ownerName: ownerName,
    agencyListing: agencyListing,
    features: features,
    media: [
      for (var i = 0; i < mediaCount; i++)
        PropertyMedia(
          url: 'https://example.com/$id-$i.jpg',
          type: PropertyMediaType.image,
        ),
    ],
  );
}
