import 'dart:convert';

import 'package:dating_app/data/models/panorama_tour.dart';
import 'package:dating_app/data/models/scanned_room.dart';
import 'package:latlong2/latlong.dart';

enum SearchSortOption {
  bestMatch,
  priceLowToHigh,
  priceHighToLow,
  newestEntry,
  biggestFirst,
}

enum ListingSourceFilter {
  any,
  privateOnly,
  agencyOnly,
}

enum MoveInFilter {
  any,
  immediate,
  within30Days,
  within90Days,
}

enum PropertyTransactionType { rent, sale }

enum TransactionTypeFilter { any, rent, sale }

enum PropertyMediaType { image, video }

enum PropertyTourStatus {
  none,
  captured,
  queued,
  uploading,
  processing,
  ready,
  failed,
}

class PropertyMedia {
  const PropertyMedia({
    required this.url,
    required this.type,
  });

  final String url;
  final PropertyMediaType type;

  bool get isImage => type == PropertyMediaType.image;
  bool get isVideo => type == PropertyMediaType.video;

  factory PropertyMedia.fromJson(Map<String, dynamic> json) {
    final rawType = json['type'] as String?;
    final url = json['url'] as String? ?? '';
    return PropertyMedia(
      url: url,
      type: rawType == 'video'
          ? PropertyMediaType.video
          : rawType == 'image'
              ? PropertyMediaType.image
              : _inferMediaType(url),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'url': url,
      'type': type.name,
    };
  }
}

class PropertyVirtualTour {
  const PropertyVirtualTour({
    required this.id,
    required this.provider,
    required this.status,
    this.sourceVideoUrl = '',
    this.viewerUrl = '',
    this.downloadUrl = '',
    this.previewImageUrl = '',
    this.format = '',
    this.processingStage = '',
    this.processingProgress,
    this.qualityScore,
    this.sizeBytes,
    this.errorMessage = '',
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String provider;
  final PropertyTourStatus status;
  final String sourceVideoUrl;
  final String viewerUrl;
  final String downloadUrl;
  final String previewImageUrl;
  final String format;
  final String processingStage;
  final int? processingProgress;
  final double? qualityScore;
  final int? sizeBytes;
  final String errorMessage;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get hasSourceCapture => sourceVideoUrl.trim().isNotEmpty;
  bool get isReady =>
      status == PropertyTourStatus.ready && viewerUrl.trim().isNotEmpty;
  bool get isProcessing =>
      status == PropertyTourStatus.uploading ||
      status == PropertyTourStatus.queued ||
      status == PropertyTourStatus.processing;
  bool get needsBackendUpload => status == PropertyTourStatus.captured;
  bool get hasFailed => status == PropertyTourStatus.failed;

  PropertyVirtualTour copyWith({
    String? id,
    String? provider,
    PropertyTourStatus? status,
    String? sourceVideoUrl,
    String? viewerUrl,
    String? downloadUrl,
    String? previewImageUrl,
    String? format,
    String? processingStage,
    int? processingProgress,
    double? qualityScore,
    int? sizeBytes,
    String? errorMessage,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PropertyVirtualTour(
      id: id ?? this.id,
      provider: provider ?? this.provider,
      status: status ?? this.status,
      sourceVideoUrl: sourceVideoUrl ?? this.sourceVideoUrl,
      viewerUrl: viewerUrl ?? this.viewerUrl,
      downloadUrl: downloadUrl ?? this.downloadUrl,
      previewImageUrl: previewImageUrl ?? this.previewImageUrl,
      format: format ?? this.format,
      processingStage: processingStage ?? this.processingStage,
      processingProgress: processingProgress ?? this.processingProgress,
      qualityScore: qualityScore ?? this.qualityScore,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      errorMessage: errorMessage ?? this.errorMessage,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory PropertyVirtualTour.fromJson(Map<String, dynamic> json) {
    return PropertyVirtualTour(
      id: json['id']?.toString() ?? '',
      provider: json['provider']?.toString() ?? 'unknown',
      status: _parseTourStatus(json['status']),
      sourceVideoUrl: json['sourceVideoUrl']?.toString() ?? '',
      viewerUrl: json['viewerUrl']?.toString() ?? '',
      downloadUrl: json['downloadUrl']?.toString() ?? '',
      previewImageUrl: json['previewImageUrl']?.toString() ?? '',
      format: json['format']?.toString() ?? '',
      processingStage: json['processingStage']?.toString() ?? '',
      processingProgress: _optionalInt(json['processingProgress']),
      qualityScore: _optionalDouble(json['qualityScore']),
      sizeBytes: _optionalInt(json['sizeBytes']),
      errorMessage: json['errorMessage']?.toString() ?? '',
      createdAt: _optionalDate(json['createdAt']),
      updatedAt: _optionalDate(json['updatedAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'provider': provider,
      'status': status.name,
      'sourceVideoUrl': sourceVideoUrl,
      'viewerUrl': viewerUrl,
      'downloadUrl': downloadUrl,
      'previewImageUrl': previewImageUrl,
      'format': format,
      'processingStage': processingStage,
      'processingProgress': processingProgress,
      'qualityScore': qualityScore,
      'sizeBytes': sizeBytes,
      'errorMessage': errorMessage,
      'createdAt': createdAt?.toUtc().toIso8601String(),
      'updatedAt': updatedAt?.toUtc().toIso8601String(),
    };
  }
}

class PropertyFeatureDefinition {
  const PropertyFeatureDefinition({
    required this.key,
    required this.label,
    this.aliases = const [],
  });

  final String key;
  final String label;
  final List<String> aliases;
}

class PropertyFeatureSet {
  PropertyFeatureSet(Map<String, bool> values)
      : values = Map.unmodifiable(_completeFeatureFlags(values));

  final Map<String, bool> values;

  bool isEnabled(String key) => values[key] ?? false;

  List<String> get enabledLabels => _enabledFeatureLabels(values);

  Map<String, dynamic> toJson() => Map<String, bool>.from(values);

  factory PropertyFeatureSet.fromJson(
    Object? rawValue, {
    List<String> labelsFallback = const [],
  }) {
    final normalized = <String, bool>{};

    void enableFeature(String value) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return;
      final key = _featureKeyFor(trimmed) ?? trimmed;
      normalized[key] = true;
    }

    if (rawValue is List) {
      for (final item in rawValue.whereType<String>()) {
        enableFeature(item);
      }
    } else if (rawValue is Map) {
      for (final entry in rawValue.entries) {
        final key =
            _featureKeyFor(entry.key.toString()) ?? entry.key.toString();
        normalized[key] = _asBoolFlag(entry.value);
      }
    } else if (rawValue is String && rawValue.trim().isNotEmpty) {
      final parsed = _decodeJsonSafely(rawValue);
      return PropertyFeatureSet.fromJson(
        parsed,
        labelsFallback: labelsFallback,
      );
    }

    for (final label in labelsFallback) {
      enableFeature(label);
    }

    return PropertyFeatureSet(normalized);
  }
}

class PropertyFeatureCatalog {
  static List<String> get allLabels =>
      _propertyFeatureCatalog.map((item) => item.label).toList(growable: false);
}

class PropertyModel3d {
  const PropertyModel3d({
    this.viewerUrl = '',
    this.glbUrl = '',
    this.objUrl = '',
    this.mtlUrl = '',
    this.usdzUrl = '',
    this.spzUrl = '',
    this.plyUrl = '',
    this.ksplatUrl = '',
    this.textureFolder = '',
    this.assets = const [],
    this.rooms = const [],
    this.modelQualityScore,
    this.scanDate,
  });

  final String viewerUrl;
  final String glbUrl;
  final String objUrl;
  final String mtlUrl;
  final String usdzUrl;
  final String spzUrl;
  final String plyUrl;
  // Compact, fast-loading Gaussian splat produced by rentch-splat-convert from the
  // uploaded .ply/.spz — the client prefers this over the huge raw .ply.
  final String ksplatUrl;
  final String textureFolder;
  final List<PropertyModelAsset> assets;

  /// Per-room 3D captures (Option-1 room-switcher). When the landlord scans an
  /// apartment room-by-room, every viewable room lands here so the viewer can
  /// offer a room picker. The legacy single-scan urls (glbUrl/plyUrl/ksplatUrl)
  /// mirror the FIRST viewable room for back-compat with older readers.
  final List<ScannedRoom> rooms;

  final int? modelQualityScore;
  final DateTime? scanDate;

  /// Rooms that actually have a loadable mesh/splat (the ones worth showing).
  List<ScannedRoom> get viewableRooms =>
      rooms.where((r) => r.hasViewableAsset).toList(growable: false);

  bool get hasAnyAsset =>
      viewerUrl.trim().isNotEmpty ||
      glbUrl.trim().isNotEmpty ||
      objUrl.trim().isNotEmpty ||
      mtlUrl.trim().isNotEmpty ||
      usdzUrl.trim().isNotEmpty ||
      spzUrl.trim().isNotEmpty ||
      plyUrl.trim().isNotEmpty ||
      ksplatUrl.trim().isNotEmpty ||
      textureFolder.trim().isNotEmpty ||
      assets.isNotEmpty ||
      viewableRooms.isNotEmpty;

  PropertyModel3d copyWith({
    String? viewerUrl,
    String? glbUrl,
    String? objUrl,
    String? mtlUrl,
    String? usdzUrl,
    String? spzUrl,
    String? plyUrl,
    String? ksplatUrl,
    String? textureFolder,
    List<PropertyModelAsset>? assets,
    List<ScannedRoom>? rooms,
    int? modelQualityScore,
    DateTime? scanDate,
  }) {
    return PropertyModel3d(
      viewerUrl: viewerUrl ?? this.viewerUrl,
      glbUrl: glbUrl ?? this.glbUrl,
      objUrl: objUrl ?? this.objUrl,
      mtlUrl: mtlUrl ?? this.mtlUrl,
      usdzUrl: usdzUrl ?? this.usdzUrl,
      spzUrl: spzUrl ?? this.spzUrl,
      plyUrl: plyUrl ?? this.plyUrl,
      ksplatUrl: ksplatUrl ?? this.ksplatUrl,
      textureFolder: textureFolder ?? this.textureFolder,
      assets: assets ?? this.assets,
      rooms: rooms ?? this.rooms,
      modelQualityScore: modelQualityScore ?? this.modelQualityScore,
      scanDate: scanDate ?? this.scanDate,
    );
  }

  factory PropertyModel3d.fromJson(Map<String, dynamic> json) {
    final rawAssets = json['assets'] as List<dynamic>? ?? const [];
    final rawRooms = json['rooms'] as List<dynamic>? ?? const [];
    return PropertyModel3d(
      viewerUrl: json['viewerUrl']?.toString() ?? '',
      glbUrl: json['glbUrl']?.toString() ?? '',
      objUrl: json['objUrl']?.toString() ?? '',
      mtlUrl: json['mtlUrl']?.toString() ?? '',
      usdzUrl: json['usdzUrl']?.toString() ?? '',
      spzUrl: json['spzUrl']?.toString() ?? '',
      plyUrl: json['plyUrl']?.toString() ?? '',
      ksplatUrl: json['ksplatUrl']?.toString() ?? '',
      textureFolder: json['textureFolder']?.toString() ?? '',
      assets: rawAssets
          .whereType<Map>()
          .map((item) =>
              PropertyModelAsset.fromJson(Map<String, dynamic>.from(item)))
          .toList(growable: false),
      rooms: rawRooms
          .whereType<Map>()
          .map((item) => ScannedRoom.fromJson(Map<String, dynamic>.from(item)))
          .toList(growable: false),
      modelQualityScore: _optionalInt(json['modelQualityScore']),
      scanDate: _optionalDate(json['scanDate']),
    );
  }

  factory PropertyModel3d.fromVirtualTour(PropertyVirtualTour tour) {
    return PropertyModel3d(
      viewerUrl: tour.viewerUrl,
      glbUrl: tour.format.toLowerCase() == 'glb' ? tour.downloadUrl : '',
      modelQualityScore: tour.qualityScore?.round(),
      scanDate: tour.updatedAt ?? tour.createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'viewerUrl': viewerUrl,
      'glbUrl': glbUrl,
      'objUrl': objUrl,
      'mtlUrl': mtlUrl,
      'usdzUrl': usdzUrl,
      'spzUrl': spzUrl,
      'plyUrl': plyUrl,
      'ksplatUrl': ksplatUrl,
      'textureFolder': textureFolder,
      'assets': assets.map((item) => item.toJson()).toList(),
      'rooms': rooms.map((r) => r.toJson()).toList(),
      'modelQualityScore': modelQualityScore,
      'scanDate': scanDate == null ? null : _formatDateOnly(scanDate!),
    };
  }
}

class PropertyModelAsset {
  const PropertyModelAsset({
    required this.kind,
    required this.url,
    this.fileName = '',
    this.contentType = '',
    this.sizeBytes,
  });

  final String kind;
  final String url;
  final String fileName;
  final String contentType;
  final int? sizeBytes;

  factory PropertyModelAsset.fromJson(Map<String, dynamic> json) {
    return PropertyModelAsset(
      kind: json['kind']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      fileName: json['fileName']?.toString() ?? '',
      contentType: json['contentType']?.toString() ?? '',
      sizeBytes: _optionalInt(json['sizeBytes']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'kind': kind,
      'url': url,
      'fileName': fileName,
      'contentType': contentType,
      'sizeBytes': sizeBytes,
    };
  }
}

class PropertyLegal {
  const PropertyLegal({
    this.thirdPartyTransferAllowed = false,
    this.commercialSaleAllowed = false,
    this.aiTrainingAllowed = false,
    this.consentVersion = '',
    this.consentTimestamp,
    this.consentSource = '',
  });

  final bool thirdPartyTransferAllowed;
  final bool commercialSaleAllowed;
  final bool aiTrainingAllowed;
  final String consentVersion;
  final DateTime? consentTimestamp;
  final String consentSource;

  bool get hasConsent =>
      consentVersion.trim().isNotEmpty && consentTimestamp != null;

  PropertyLegal copyWith({
    bool? thirdPartyTransferAllowed,
    bool? commercialSaleAllowed,
    bool? aiTrainingAllowed,
    String? consentVersion,
    DateTime? consentTimestamp,
    String? consentSource,
  }) {
    return PropertyLegal(
      thirdPartyTransferAllowed:
          thirdPartyTransferAllowed ?? this.thirdPartyTransferAllowed,
      commercialSaleAllowed:
          commercialSaleAllowed ?? this.commercialSaleAllowed,
      aiTrainingAllowed: aiTrainingAllowed ?? this.aiTrainingAllowed,
      consentVersion: consentVersion ?? this.consentVersion,
      consentTimestamp: consentTimestamp ?? this.consentTimestamp,
      consentSource: consentSource ?? this.consentSource,
    );
  }

  factory PropertyLegal.fromJson(Map<String, dynamic> json) {
    return PropertyLegal(
      thirdPartyTransferAllowed: _asBoolFlag(json['thirdPartyTransferAllowed']),
      commercialSaleAllowed: _asBoolFlag(json['commercialSaleAllowed']),
      aiTrainingAllowed: _asBoolFlag(json['aiTrainingAllowed']),
      consentVersion: json['consentVersion']?.toString() ?? '',
      consentTimestamp: _optionalDate(json['consentTimestamp']),
      consentSource: json['consentSource']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'thirdPartyTransferAllowed': thirdPartyTransferAllowed,
      'commercialSaleAllowed': commercialSaleAllowed,
      'aiTrainingAllowed': aiTrainingAllowed,
      'consentVersion': consentVersion,
      'consentTimestamp': consentTimestamp?.toUtc().toIso8601String(),
      'consentSource': consentSource,
    };
  }
}

class PropertyPricePoint {
  const PropertyPricePoint({
    required this.date,
    required this.price,
    required this.transactionType,
  });

  final DateTime date;
  final int price;
  final PropertyTransactionType transactionType;

  factory PropertyPricePoint.fromJson(Map<String, dynamic> json) {
    return PropertyPricePoint(
      date:
          _optionalDate(json['date']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      price: _optionalInt(json['price']) ?? 0,
      transactionType: _parseTransactionType(json['transactionType']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'date': _formatDateOnly(date),
      'price': price,
      'transactionType': transactionType.name,
    };
  }
}

class PropertyMarketSignals {
  const PropertyMarketSignals({
    this.views = 0,
    this.likes = 0,
    this.saves = 0,
    this.skips = 0,
    this.contactRequests = 0,
    this.avgTimeIn3dSeconds = 0,
    this.liveViewers = 0,
    this.likesToday = 0,
    this.likesTodayDate = '',
    this.detailViews = 0,
    this.gallerySwipes = 0,
    this.avgDetailStaySeconds = 0,
    this.lastViewedAt,
  });

  final int views;
  final int likes;
  final int saves;
  final int skips;
  final int contactRequests;
  final int avgTimeIn3dSeconds;
  final int liveViewers;
  final int likesToday;
  final String likesTodayDate;
  final int detailViews;
  final int gallerySwipes;
  final int avgDetailStaySeconds;
  final DateTime? lastViewedAt;

  PropertyMarketSignals copyWith({
    int? views,
    int? likes,
    int? saves,
    int? skips,
    int? contactRequests,
    int? avgTimeIn3dSeconds,
    int? liveViewers,
    int? likesToday,
    String? likesTodayDate,
    int? detailViews,
    int? gallerySwipes,
    int? avgDetailStaySeconds,
    DateTime? lastViewedAt,
  }) {
    return PropertyMarketSignals(
      views: views ?? this.views,
      likes: likes ?? this.likes,
      saves: saves ?? this.saves,
      skips: skips ?? this.skips,
      contactRequests: contactRequests ?? this.contactRequests,
      avgTimeIn3dSeconds: avgTimeIn3dSeconds ?? this.avgTimeIn3dSeconds,
      liveViewers: liveViewers ?? this.liveViewers,
      likesToday: likesToday ?? this.likesToday,
      likesTodayDate: likesTodayDate ?? this.likesTodayDate,
      detailViews: detailViews ?? this.detailViews,
      gallerySwipes: gallerySwipes ?? this.gallerySwipes,
      avgDetailStaySeconds: avgDetailStaySeconds ?? this.avgDetailStaySeconds,
      lastViewedAt: lastViewedAt ?? this.lastViewedAt,
    );
  }

  factory PropertyMarketSignals.fromJson(Map<String, dynamic> json) {
    return PropertyMarketSignals(
      views: _optionalInt(json['views']) ?? 0,
      likes: _optionalInt(json['likes']) ?? 0,
      saves: _optionalInt(json['saves']) ?? 0,
      skips: _optionalInt(json['skips']) ?? 0,
      contactRequests: _optionalInt(json['contactRequests']) ?? 0,
      avgTimeIn3dSeconds: _optionalInt(json['avgTimeIn3dSeconds']) ?? 0,
      liveViewers: _optionalInt(json['liveViewers']) ?? 0,
      likesToday: _optionalInt(json['likesToday']) ?? 0,
      likesTodayDate: json['likesTodayDate']?.toString() ?? '',
      detailViews: _optionalInt(json['detailViews']) ?? 0,
      gallerySwipes: _optionalInt(json['gallerySwipes']) ?? 0,
      avgDetailStaySeconds: _optionalInt(json['avgDetailStaySeconds']) ?? 0,
      lastViewedAt: _optionalDate(json['lastViewedAt']),
    );
  }

  int likesTodayFor(DateTime now) {
    return likesTodayDate == _formatLocalDateOnly(now) ? likesToday : 0;
  }

  PropertyMarketSignals normalizedForToday(DateTime now) {
    final today = _formatLocalDateOnly(now);
    if (likesTodayDate == today) return this;
    return copyWith(likesToday: 0, likesTodayDate: today);
  }

  Map<String, dynamic> toJson() {
    return {
      'views': views,
      'likes': likes,
      'saves': saves,
      'skips': skips,
      'contactRequests': contactRequests,
      'avgTimeIn3dSeconds': avgTimeIn3dSeconds,
      'liveViewers': liveViewers,
      'likesToday': likesToday,
      'likesTodayDate': likesTodayDate,
      'detailViews': detailViews,
      'gallerySwipes': gallerySwipes,
      'avgDetailStaySeconds': avgDetailStaySeconds,
      'lastViewedAt': lastViewedAt?.toUtc().toIso8601String(),
    };
  }
}

class PropertyVerification {
  const PropertyVerification({
    this.verified = false,
    this.method = '',
    this.videoUrl = '',
    this.capturedAt,
  });

  static const cameraVideoMethod = 'camera_video';

  final bool verified;
  final String method;
  final String videoUrl;
  final DateTime? capturedAt;

  bool get hasCameraVideo =>
      method == cameraVideoMethod && videoUrl.trim().isNotEmpty;
  bool get isVerified => verified && hasCameraVideo;

  PropertyVerification copyWith({
    bool? verified,
    String? method,
    String? videoUrl,
    DateTime? capturedAt,
  }) {
    return PropertyVerification(
      verified: verified ?? this.verified,
      method: method ?? this.method,
      videoUrl: videoUrl ?? this.videoUrl,
      capturedAt: capturedAt ?? this.capturedAt,
    );
  }

  factory PropertyVerification.cameraVideo({
    required String videoUrl,
    required DateTime capturedAt,
  }) {
    return PropertyVerification(
      verified: true,
      method: cameraVideoMethod,
      videoUrl: videoUrl,
      capturedAt: capturedAt,
    );
  }

  factory PropertyVerification.fromJson(Map<String, dynamic> json) {
    final videoUrl = json['videoUrl']?.toString().trim() ??
        json['verificationVideoUrl']?.toString().trim() ??
        '';
    final method = json['method']?.toString().trim() ??
        json['verificationMethod']?.toString().trim() ??
        (videoUrl.isNotEmpty ? cameraVideoMethod : '');
    final verified = _asBoolFlag(
      json['verified'] ??
          json['verifiedListing'] ??
          json['isVerifiedListing'] ??
          false,
    );
    return PropertyVerification(
      verified: verified,
      method: method,
      videoUrl: videoUrl,
      capturedAt: _optionalDate(
        json['capturedAt'] ??
            json['verifiedAt'] ??
            json['verificationCapturedAt'],
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'verified': verified,
      'method': method,
      'videoUrl': videoUrl,
      'capturedAt': capturedAt?.toUtc().toIso8601String(),
    };
  }
}

class RentalProperty {
  RentalProperty({
    required this.id,
    String sourceUrl = '',
    String? url,
    this.ownerUserId = '',
    required this.price,
    required this.rooms,
    required this.sizeM2,
    required this.floor,
    required this.totalFloors,
    required this.city,
    required this.neighborhood,
    required this.street,
    required this.streetNumber,
    required this.lat,
    required this.lon,
    required this.propertyType,
    required this.entryDate,
    required this.condition,
    required this.ownerName,
    required this.agencyListing,
    required List<String> features,
    PropertyFeatureSet? featureFlags,
    List<String>? publishChannels,
    required this.media,
    this.transactionType = PropertyTransactionType.rent,
    this.virtualTour,
    PropertyModel3d? model3d,
    PropertyLegal? legal,
    List<PropertyPricePoint>? priceHistory,
    PropertyMarketSignals? marketSignals,
    PropertyVerification? verification,
    this.isActive = true,
    this.designTemplate = '',
    this.designAccent = 0,
    this.createdAt,
    this.panoramaTour,
  })  : sourceUrl = sourceUrl.isNotEmpty ? sourceUrl : (url ?? ''),
        featureFlags = featureFlags ?? PropertyFeatureSet.fromJson(features),
        model3d = _resolveModel3d(model3d, virtualTour),
        legal = legal ?? const PropertyLegal(),
        priceHistory = List.unmodifiable(
          _resolvePriceHistory(
            priceHistory,
            price: price,
            entryDate: entryDate,
            transactionType: transactionType,
          ),
        ),
        marketSignals = marketSignals ?? const PropertyMarketSignals(),
        verification = verification ?? const PropertyVerification(),
        features = List.unmodifiable(
          _resolveFeatureLabels(features, featureFlags),
        ),
        publishChannels =
            List.unmodifiable(publishChannels ?? const <String>[]);

  final String id;
  final String sourceUrl;
  final String ownerUserId;
  final int price;
  final double rooms;
  final int sizeM2;
  final String floor;
  final String totalFloors;
  final String city;
  final String neighborhood;
  final String street;
  final int streetNumber;
  final double lat;
  final double lon;
  final String propertyType;
  final String entryDate;
  final String condition;
  final String ownerName;
  final bool agencyListing;
  final List<String> features;
  final PropertyFeatureSet featureFlags;

  /// Where the (broker) listing is being advertised — e.g. ['rently','yad2',
  /// 'madlan','facebook']. Broker-facing tracking; empty for regular owners.
  final List<String> publishChannels;
  final List<PropertyMedia> media;
  final PropertyTransactionType transactionType;
  final PropertyVirtualTour? virtualTour;
  final PropertyModel3d? model3d;
  final PropertyLegal legal;
  final List<PropertyPricePoint> priceHistory;
  final PropertyMarketSignals marketSignals;
  final PropertyVerification verification;
  final bool isActive;

  /// Per-property page design: a `BrokerPropertyTemplate.id` chosen during
  /// listing creation (empty = default Rently layout), plus an optional accent
  /// colour (ARGB int, 0 = template default). Lets every listing pick its own
  /// detail-page look without depending on user-level broker branding.
  final String designTemplate;
  final int designAccent;
  final DateTime? createdAt;

  /// Optional DIY 360° walkthrough (Street-View-style panorama nodes). Distinct
  /// from [virtualTour]/[model3d] (heavy backend 3D reconstruction).
  final PropertyPanoramaTour? panoramaTour;

  bool get hasPanoramaTour => panoramaTour?.isNotEmpty ?? false;

  bool get hasCustomDesign => designTemplate.trim().isNotEmpty;

  String get url => sourceUrl;
  static const Duration newListingWindow = Duration(hours: 252);

  bool get isNewListing {
    final created = createdAt;
    if (created == null) return false;
    final age = DateTime.now().difference(created);
    return !age.isNegative && age <= newListingWindow;
  }

  PropertyMedia? get primaryMedia => media.isEmpty ? null : media.first;
  List<String> get mediaUrls => media.map((item) => item.url).toList();
  List<String> get imageUrls =>
      media.where((item) => item.isImage).map((item) => item.url).toList();
  List<String> get videoUrls =>
      media.where((item) => item.isVideo).map((item) => item.url).toList();
  bool get hasReadyVirtualTour => virtualTour?.isReady ?? false;
  bool get hasVirtualTour =>
      hasReadyVirtualTour || virtualTour?.isProcessing == true;
  bool get hasModel3d => model3d?.hasAnyAsset ?? false;
  bool get isVerifiedListing => verification.isVerified;
  String get imageUrl => imageUrls.isEmpty ? '' : imageUrls.first;
  LatLng get point => LatLng(lat, lon);
  int? get floorNumber => int.tryParse(floor);
  DateTime? get entryDateValue => DateTime.tryParse(entryDate);
  int? get pricePerSquareMeter => sizeM2 > 0 ? (price / sizeM2).round() : null;
  String get searchableText => [
        city,
        neighborhood,
        street,
        ownerName,
        propertyType,
        condition,
        if (isVerifiedListing) 'מאומת',
        transactionType == PropertyTransactionType.sale ? 'מכירה' : 'השכרה',
        ...features,
      ].join(' ').toLowerCase();

  String get address {
    final streetPart = streetNumber > 0 ? '$street $streetNumber' : street;
    return [
      if (streetPart.trim().isNotEmpty) streetPart.trim(),
      if (neighborhood.trim().isNotEmpty) neighborhood.trim(),
      city,
    ].join(', ');
  }

  String get priceLabel => '₪${_formatNumber(price)}';
  String get priceSuffixLabel =>
      transactionType == PropertyTransactionType.sale ? 'למכירה' : 'לחודש';
  String get transactionLabel =>
      transactionType == PropertyTransactionType.sale ? 'מכירה' : 'השכרה';
  String get roomsLabel =>
      rooms % 1 == 0 ? rooms.toInt().toString() : rooms.toString();

  RentalProperty copyWith({
    String? id,
    String? sourceUrl,
    String? url,
    String? ownerUserId,
    int? price,
    double? rooms,
    int? sizeM2,
    String? floor,
    String? totalFloors,
    String? city,
    String? neighborhood,
    String? street,
    int? streetNumber,
    double? lat,
    double? lon,
    String? propertyType,
    String? entryDate,
    String? condition,
    String? ownerName,
    bool? agencyListing,
    List<String>? features,
    List<String>? publishChannels,
    PropertyFeatureSet? featureFlags,
    List<PropertyMedia>? media,
    PropertyTransactionType? transactionType,
    PropertyVirtualTour? virtualTour,
    PropertyModel3d? model3d,
    PropertyLegal? legal,
    List<PropertyPricePoint>? priceHistory,
    PropertyMarketSignals? marketSignals,
    PropertyVerification? verification,
    bool? isActive,
    String? designTemplate,
    int? designAccent,
    DateTime? createdAt,
    PropertyPanoramaTour? panoramaTour,
  }) {
    return RentalProperty(
      id: id ?? this.id,
      sourceUrl: sourceUrl ?? url ?? this.sourceUrl,
      ownerUserId: ownerUserId ?? this.ownerUserId,
      price: price ?? this.price,
      rooms: rooms ?? this.rooms,
      sizeM2: sizeM2 ?? this.sizeM2,
      floor: floor ?? this.floor,
      totalFloors: totalFloors ?? this.totalFloors,
      city: city ?? this.city,
      neighborhood: neighborhood ?? this.neighborhood,
      street: street ?? this.street,
      streetNumber: streetNumber ?? this.streetNumber,
      lat: lat ?? this.lat,
      lon: lon ?? this.lon,
      propertyType: propertyType ?? this.propertyType,
      entryDate: entryDate ?? this.entryDate,
      condition: condition ?? this.condition,
      ownerName: ownerName ?? this.ownerName,
      agencyListing: agencyListing ?? this.agencyListing,
      features: features ?? this.features,
      publishChannels: publishChannels ?? this.publishChannels,
      featureFlags: featureFlags ?? this.featureFlags,
      media: media ?? this.media,
      transactionType: transactionType ?? this.transactionType,
      virtualTour: virtualTour ?? this.virtualTour,
      model3d: model3d ?? this.model3d,
      legal: legal ?? this.legal,
      priceHistory: priceHistory ?? this.priceHistory,
      marketSignals: marketSignals ?? this.marketSignals,
      verification: verification ?? this.verification,
      isActive: isActive ?? this.isActive,
      designTemplate: designTemplate ?? this.designTemplate,
      designAccent: designAccent ?? this.designAccent,
      createdAt: createdAt ?? this.createdAt,
      panoramaTour: panoramaTour ?? this.panoramaTour,
    );
  }

  factory RentalProperty.fromJson(Map<String, dynamic> json) {
    final mediaJson = json['media'] as List<dynamic>? ?? const [];
    final legacyImageUrls =
        List<String>.from(json['imageUrls'] as List<dynamic>? ?? const []);
    final legacyVideoUrls =
        List<String>.from(json['videoUrls'] as List<dynamic>? ?? const []);
    final media = mediaJson.isNotEmpty
        ? mediaJson
            .map((item) =>
                PropertyMedia.fromJson(Map<String, dynamic>.from(item as Map)))
            .toList()
        : [
            ...legacyImageUrls.map(
              (url) => PropertyMedia(
                url: url,
                type: PropertyMediaType.image,
              ),
            ),
            ...legacyVideoUrls.map(
              (url) => PropertyMedia(
                url: url,
                type: PropertyMediaType.video,
              ),
            ),
          ];
    final featureLabels = _decodeStringListValue(json['featureLabels']);
    final featureFlags = PropertyFeatureSet.fromJson(
      json['features'],
      labelsFallback: featureLabels,
    );
    final resolvedFeatures = featureLabels.isNotEmpty
        ? List<String>.from(featureLabels)
        : _decodeStringListValue(json['features']).isNotEmpty
            ? _decodeStringListValue(json['features'])
            : featureFlags.enabledLabels;
    final parsedPrice = _optionalInt(json['price']) ?? 0;
    final parsedEntryDate = json['entryDate'] as String? ?? '';
    final parsedTransactionType =
        _parseTransactionType(json['transactionType']);
    final parsedVirtualTour = _parseVirtualTour(json['virtualTour']);
    final parsedModel3d = _parseModel3d(json['model3d']);

    return RentalProperty(
      id: json['id'] as String,
      sourceUrl: json['sourceUrl']?.toString() ?? json['url']?.toString() ?? '',
      ownerUserId: json['ownerUserId']?.toString() ??
          json['ownerId']?.toString() ??
          json['landlordUserId']?.toString() ??
          '',
      price: parsedPrice,
      rooms: (json['rooms'] as num).toDouble(),
      sizeM2: json['sizeM2'] as int,
      floor: json['floor'] as String? ?? '',
      totalFloors: json['totalFloors'] as String? ?? '',
      city: json['city'] as String,
      neighborhood: json['neighborhood'] as String? ?? '',
      street: json['street'] as String? ?? '',
      streetNumber: json['streetNumber'] as int? ?? -1,
      lat: (json['lat'] as num).toDouble(),
      lon: (json['lon'] as num).toDouble(),
      propertyType: json['propertyType'] as String,
      entryDate: json['entryDate'] as String? ?? '',
      condition: json['condition'] as String? ?? '',
      ownerName: json['ownerName'] as String? ?? 'בעל הנכס',
      agencyListing: json['agencyListing'] as bool? ?? false,
      features: resolvedFeatures,
      publishChannels: _decodeStringListValue(json['publishChannels']),
      featureFlags: featureFlags,
      media: media,
      transactionType: parsedTransactionType,
      virtualTour: parsedVirtualTour,
      model3d: parsedModel3d,
      legal: _parsePropertyLegal(json['legal']) ?? const PropertyLegal(),
      priceHistory: _parsePriceHistory(
        json['priceHistory'],
        fallbackPrice: parsedPrice,
        fallbackEntryDate: parsedEntryDate,
        fallbackTransactionType: parsedTransactionType,
      ),
      marketSignals: _parseMarketSignals(json['marketSignals']) ??
          const PropertyMarketSignals(),
      verification: _parsePropertyVerification(json),
      isActive: json['isActive'] as bool? ?? true,
      designTemplate: json['designTemplate']?.toString() ?? '',
      designAccent: _optionalInt(json['designAccent']) ?? 0,
      createdAt: _optionalDate(
            json['createdAt'] ??
                json['postedAt'] ??
                json['uploadedAt'] ??
                json[r'$createdAt'],
          ) ??
          _generateDeterministicMockDate(json['id']?.toString() ?? ''),
      panoramaTour: PropertyPanoramaTour.fromJsonOrNull(json['panoramaTour']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sourceUrl': sourceUrl,
      'url': url,
      'ownerUserId': ownerUserId,
      'price': price,
      'rooms': rooms,
      'sizeM2': sizeM2,
      'floor': floor,
      'totalFloors': totalFloors,
      'city': city,
      'neighborhood': neighborhood,
      'street': street,
      'streetNumber': streetNumber,
      'lat': lat,
      'lon': lon,
      'propertyType': propertyType,
      'entryDate': entryDate,
      'condition': condition,
      'ownerName': ownerName,
      'agencyListing': agencyListing,
      'features': featureFlags.toJson(),
      'publishChannels': publishChannels,
      'featureLabels': features,
      'media': media.map((item) => item.toJson()).toList(),
      'imageUrls': imageUrls,
      'videoUrls': videoUrls,
      'transactionType': transactionType.name,
      'virtualTour': virtualTour?.toJson(),
      'model3d': model3d?.toJson(),
      'legal': legal.toJson(),
      'priceHistory': priceHistory.map((item) => item.toJson()).toList(),
      'marketSignals': marketSignals.toJson(),
      'verification': verification.toJson(),
      'verifiedListing': isVerifiedListing,
      'verificationMethod': verification.method,
      'verificationVideoUrl': verification.videoUrl,
      'verifiedAt': verification.capturedAt?.toUtc().toIso8601String(),
      'isActive': isActive,
      'designTemplate': designTemplate,
      'designAccent': designAccent,
      'createdAt': createdAt?.toUtc().toIso8601String(),
      if (panoramaTour != null) 'panoramaTour': panoramaTour!.toJson(),
    };
  }
}

class TenantProfile {
  const TenantProfile({
    required this.id,
    required this.name,
    required this.bio,
    required this.photoUrls,
    required this.budgetMax,
    required this.desiredRooms,
    required this.moveInWindow,
    required this.importantDetails,
    this.dealBreakers = const [],
    this.monthlyIncome,
    this.workLat,
    this.workLon,
  });

  final String id;
  final String name;
  final String bio;
  final List<String> photoUrls;
  final int budgetMax;
  final double desiredRooms;
  final String moveInWindow;
  final List<String> importantDetails;

  /// Subset of profile preferences the user flagged as non-negotiable. The
  /// matching algorithm treats a missing counterpart on the other side as a
  /// heavy penalty (effectively excluding the match) rather than just a lost
  /// bonus. Defaults to empty for backward compatibility with stored profiles.
  final List<String> dealBreakers;

  /// Gross monthly income in ₪, used by the affordability strip to assess
  /// rent-to-income fit. Optional — null hides the ratio band. Back-compat: not
  /// required, defaults to null, and old stored profiles load fine without it.
  final int? monthlyIncome;

  /// Tenant's work location (geocoded from a typed address). Feeds the optional
  /// "מרחק מהעבודה" commute dimension in the recommendation scorecard. Both must
  /// be present for a commute estimate; null leaves behaviour unchanged.
  final double? workLat;
  final double? workLon;

  String get photoUrl => photoUrls.isEmpty ? '' : photoUrls.first;

  TenantProfile copyWith({
    String? id,
    String? name,
    String? bio,
    List<String>? photoUrls,
    int? budgetMax,
    double? desiredRooms,
    String? moveInWindow,
    List<String>? importantDetails,
    List<String>? dealBreakers,
    int? monthlyIncome,
    double? workLat,
    double? workLon,
  }) {
    return TenantProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      bio: bio ?? this.bio,
      photoUrls: photoUrls ?? this.photoUrls,
      budgetMax: budgetMax ?? this.budgetMax,
      desiredRooms: desiredRooms ?? this.desiredRooms,
      moveInWindow: moveInWindow ?? this.moveInWindow,
      importantDetails: importantDetails ?? this.importantDetails,
      dealBreakers: dealBreakers ?? this.dealBreakers,
      monthlyIncome: monthlyIncome ?? this.monthlyIncome,
      workLat: workLat ?? this.workLat,
      workLon: workLon ?? this.workLon,
    );
  }

  factory TenantProfile.fromJson(Map<String, dynamic> json) {
    return TenantProfile(
      id: json['id'] as String,
      name: json['name'] as String,
      bio: json['bio'] as String,
      photoUrls:
          List<String>.from(json['photoUrls'] as List<dynamic>? ?? const []),
      budgetMax: json['budgetMax'] as int,
      desiredRooms: (json['desiredRooms'] as num).toDouble(),
      moveInWindow: json['moveInWindow'] as String,
      importantDetails: List<String>.from(
        json['importantDetails'] as List<dynamic>? ?? const [],
      ),
      dealBreakers: List<String>.from(
        json['dealBreakers'] as List<dynamic>? ?? const [],
      ),
      monthlyIncome: _optionalInt(json['monthlyIncome']),
      workLat: _optionalDouble(json['workLat']),
      workLon: _optionalDouble(json['workLon']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'bio': bio,
      'photoUrls': photoUrls,
      'budgetMax': budgetMax,
      'desiredRooms': desiredRooms,
      'moveInWindow': moveInWindow,
      'importantDetails': importantDetails,
      'dealBreakers': dealBreakers,
      // Optional fields are only written when set, so existing stored profiles
      // and downstream consumers that don't know them stay byte-for-byte same.
      if (monthlyIncome != null) 'monthlyIncome': monthlyIncome,
      if (workLat != null) 'workLat': workLat,
      if (workLon != null) 'workLon': workLon,
    };
  }
}

class SearchArea {
  const SearchArea({
    required this.id,
    required this.name,
    required this.center,
    required this.polygon,
  });

  final String id;
  final String name;
  final LatLng center;
  final List<LatLng> polygon;
  List<List<LatLng>> get polygons => splitCustomAreaPolygons(polygon);

  factory SearchArea.custom({
    required List<LatLng> polygon,
    String id = 'custom_area',
    String name = 'אזור שסומן ידנית',
  }) {
    final rawPolygon = polygon.isEmpty
        ? const [LatLng(32.07, 34.78)]
        : List<LatLng>.from(polygon);
    final actualPoints = splitCustomAreaPolygons(rawPolygon)
        .expand((segment) => segment)
        .toList();
    final safePolygon =
        actualPoints.isEmpty ? const [LatLng(32.07, 34.78)] : actualPoints;
    final avgLat =
        safePolygon.fold<double>(0, (sum, point) => sum + point.latitude) /
            safePolygon.length;
    final avgLon =
        safePolygon.fold<double>(0, (sum, point) => sum + point.longitude) /
            safePolygon.length;
    return SearchArea(
      id: id,
      name: name,
      center: LatLng(avgLat, avgLon),
      polygon: rawPolygon,
    );
  }

  bool contains(LatLng point) {
    for (final polygon in polygons) {
      if (polygon.length < 3) continue;
      var inside = false;
      for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
        final xi = polygon[i].longitude;
        final yi = polygon[i].latitude;
        final xj = polygon[j].longitude;
        final yj = polygon[j].latitude;
        final intersects = ((yi > point.latitude) != (yj > point.latitude)) &&
            (point.longitude <
                (xj - xi) * (point.latitude - yi) / (yj - yi + 0.0) + xi);
        if (intersects) {
          inside = !inside;
        }
      }
      if (inside) {
        return true;
      }
    }
    return false;
  }
}

const LatLng customAreaPolygonSeparator = LatLng(91, 181);

bool isCustomAreaPolygonSeparator(LatLng point) {
  return point.latitude == customAreaPolygonSeparator.latitude &&
      point.longitude == customAreaPolygonSeparator.longitude;
}

List<List<LatLng>> splitCustomAreaPolygons(List<LatLng> points) {
  final polygons = <List<LatLng>>[];
  var current = <LatLng>[];
  for (final point in points) {
    if (isCustomAreaPolygonSeparator(point)) {
      if (current.isNotEmpty) {
        polygons.add(current);
        current = <LatLng>[];
      }
      continue;
    }
    current.add(point);
  }
  if (current.isNotEmpty) {
    polygons.add(current);
  }
  return polygons;
}

List<LatLng> joinCustomAreaPolygons(List<List<LatLng>> polygons) {
  final encoded = <LatLng>[];
  for (final polygon in polygons) {
    if (polygon.isEmpty) continue;
    if (encoded.isNotEmpty) {
      encoded.add(customAreaPolygonSeparator);
    }
    encoded.addAll(polygon);
  }
  return encoded;
}

enum FilterPriority { none, preferred, required }

class SearchFilters {
  const SearchFilters({
    required this.query,
    required this.minBudget,
    required this.maxBudget,
    required this.minRooms,
    required this.maxRooms,
    required this.areaId,
    required this.requiredFeatures,
    required this.preferredFeatures,
    required this.minSizeM2,
    required this.maxSizeM2,
    required this.propertyTypes,
    required this.preferredPropertyTypes,
    required this.conditions,
    required this.preferredConditions,
    required this.listingSource,
    this.requiredListingSources = const <ListingSourceFilter>{},
    this.preferredListingSources = const <ListingSourceFilter>{},
    required this.minFloor,
    required this.moveInFilter,
    this.requiredMoveInFilters = const <MoveInFilter>{},
    this.preferredMoveInFilters = const <MoveInFilter>{},
    required this.sortBy,
    required this.includeUnknownPriceListings,
    required this.customAreaPolygon,
    this.city = '',
    this.transactionType = TransactionTypeFilter.any,
    this.strictMaxBudget = false,
  });

  final String query;
  final int minBudget;
  final int maxBudget;
  final double minRooms;
  final double maxRooms;
  final String areaId;

  /// Must-have tags. Properties missing any of these are excluded entirely.
  final Set<String> requiredFeatures;

  /// Nice-to-have preferences. Boost score proportionally.
  final Set<String> preferredFeatures;
  final int minSizeM2;
  final int maxSizeM2;

  /// Must-have property types.
  final Set<String> propertyTypes;

  /// Nice-to-have property types.
  final Set<String> preferredPropertyTypes;

  /// Must-have conditions.
  final Set<String> conditions;

  /// Nice-to-have conditions.
  final Set<String> preferredConditions;

  /// Legacy single-select fallback. Prefer [requiredListingSources] and
  /// [preferredListingSources] for new state.
  final ListingSourceFilter listingSource;
  final Set<ListingSourceFilter> requiredListingSources;
  final Set<ListingSourceFilter> preferredListingSources;
  final int minFloor;

  /// Legacy single-select fallback. Prefer [requiredMoveInFilters] and
  /// [preferredMoveInFilters] for new state.
  final MoveInFilter moveInFilter;
  final Set<MoveInFilter> requiredMoveInFilters;
  final Set<MoveInFilter> preferredMoveInFilters;
  final SearchSortOption sortBy;
  final bool includeUnknownPriceListings;
  final List<LatLng> customAreaPolygon;
  final String city;
  final TransactionTypeFilter transactionType;

  /// When true, [maxBudget] is a HARD ceiling even in best-match mode (set by an
  /// explicit typed "עד X" search). Transient — deliberately not persisted, so a
  /// slider budget keeps the soft near-miss behaviour the deck is built around.
  final bool strictMaxBudget;

  bool get hasQuery => query.trim().isNotEmpty;
  bool get hasCustomArea => splitCustomAreaPolygons(customAreaPolygon)
      .any((polygon) => polygon.length >= 3);

  FilterPriority featureState(String feature) {
    return _priorityState(
      value: feature,
      requiredValues: requiredFeatures,
      preferredValues: preferredFeatures,
    );
  }

  FilterPriority propertyTypeState(String propertyType) {
    return _priorityState(
      value: propertyType,
      requiredValues: propertyTypes,
      preferredValues: preferredPropertyTypes,
    );
  }

  FilterPriority conditionState(String condition) {
    return _priorityState(
      value: condition,
      requiredValues: conditions,
      preferredValues: preferredConditions,
    );
  }

  FilterPriority listingSourceState(ListingSourceFilter source) {
    return _priorityState(
      value: source,
      requiredValues: requiredListingSources,
      preferredValues: preferredListingSources,
    );
  }

  FilterPriority moveInState(MoveInFilter filter) {
    return _priorityState(
      value: filter,
      requiredValues: requiredMoveInFilters,
      preferredValues: preferredMoveInFilters,
    );
  }

  SearchFilters setFeatureState(String feature, FilterPriority state) {
    final updated = _applyPriorityState(
      value: feature,
      state: state,
      requiredValues: requiredFeatures,
      preferredValues: preferredFeatures,
    );
    return copyWith(
      requiredFeatures: updated.requiredValues,
      preferredFeatures: updated.preferredValues,
    );
  }

  SearchFilters setPropertyTypeState(
      String propertyType, FilterPriority state) {
    final updated = _applyPriorityState(
      value: propertyType,
      state: state,
      requiredValues: propertyTypes,
      preferredValues: preferredPropertyTypes,
    );
    return copyWith(
      propertyTypes: updated.requiredValues,
      preferredPropertyTypes: updated.preferredValues,
    );
  }

  SearchFilters setConditionState(String condition, FilterPriority state) {
    final updated = _applyPriorityState(
      value: condition,
      state: state,
      requiredValues: conditions,
      preferredValues: preferredConditions,
    );
    return copyWith(
      conditions: updated.requiredValues,
      preferredConditions: updated.preferredValues,
    );
  }

  SearchFilters setListingSourceState(
    ListingSourceFilter source,
    FilterPriority state,
  ) {
    final updated = _applyPriorityState(
      value: source,
      state: state,
      requiredValues: requiredListingSources,
      preferredValues: preferredListingSources,
    );
    return copyWith(
      requiredListingSources: updated.requiredValues,
      preferredListingSources: updated.preferredValues,
      listingSource: ListingSourceFilter.any,
    );
  }

  SearchFilters setMoveInState(MoveInFilter filter, FilterPriority state) {
    final updated = _applyPriorityState(
      value: filter,
      state: state,
      requiredValues: requiredMoveInFilters,
      preferredValues: preferredMoveInFilters,
    );
    return copyWith(
      requiredMoveInFilters: updated.requiredValues,
      preferredMoveInFilters: updated.preferredValues,
      moveInFilter: MoveInFilter.any,
    );
  }

  SearchFilters copyWith({
    String? query,
    int? minBudget,
    int? maxBudget,
    double? minRooms,
    double? maxRooms,
    String? areaId,
    Set<String>? requiredFeatures,
    Set<String>? preferredFeatures,
    int? minSizeM2,
    int? maxSizeM2,
    Set<String>? propertyTypes,
    Set<String>? preferredPropertyTypes,
    Set<String>? conditions,
    Set<String>? preferredConditions,
    ListingSourceFilter? listingSource,
    Set<ListingSourceFilter>? requiredListingSources,
    Set<ListingSourceFilter>? preferredListingSources,
    int? minFloor,
    MoveInFilter? moveInFilter,
    Set<MoveInFilter>? requiredMoveInFilters,
    Set<MoveInFilter>? preferredMoveInFilters,
    SearchSortOption? sortBy,
    bool? includeUnknownPriceListings,
    List<LatLng>? customAreaPolygon,
    String? city,
    TransactionTypeFilter? transactionType,
    bool? strictMaxBudget,
  }) {
    return SearchFilters(
      query: query ?? this.query,
      minBudget: minBudget ?? this.minBudget,
      maxBudget: maxBudget ?? this.maxBudget,
      minRooms: minRooms ?? this.minRooms,
      maxRooms: maxRooms ?? this.maxRooms,
      areaId: areaId ?? this.areaId,
      requiredFeatures: requiredFeatures ?? this.requiredFeatures,
      preferredFeatures: preferredFeatures ?? this.preferredFeatures,
      minSizeM2: minSizeM2 ?? this.minSizeM2,
      maxSizeM2: maxSizeM2 ?? this.maxSizeM2,
      propertyTypes: propertyTypes ?? this.propertyTypes,
      preferredPropertyTypes:
          preferredPropertyTypes ?? this.preferredPropertyTypes,
      conditions: conditions ?? this.conditions,
      preferredConditions: preferredConditions ?? this.preferredConditions,
      listingSource: listingSource ?? this.listingSource,
      requiredListingSources:
          requiredListingSources ?? this.requiredListingSources,
      preferredListingSources:
          preferredListingSources ?? this.preferredListingSources,
      minFloor: minFloor ?? this.minFloor,
      moveInFilter: moveInFilter ?? this.moveInFilter,
      requiredMoveInFilters:
          requiredMoveInFilters ?? this.requiredMoveInFilters,
      preferredMoveInFilters:
          preferredMoveInFilters ?? this.preferredMoveInFilters,
      sortBy: sortBy ?? this.sortBy,
      includeUnknownPriceListings:
          includeUnknownPriceListings ?? this.includeUnknownPriceListings,
      customAreaPolygon: customAreaPolygon ?? this.customAreaPolygon,
      city: city ?? this.city,
      transactionType: transactionType ?? this.transactionType,
      strictMaxBudget: strictMaxBudget ?? this.strictMaxBudget,
    );
  }

  factory SearchFilters.fromJson(Map<String, dynamic> json) {
    final customAreaJson =
        json['customAreaPolygon'] as List<dynamic>? ?? const [];
    return SearchFilters(
      query: json['query'] as String? ?? '',
      minBudget: json['minBudget'] as int? ?? 600,
      maxBudget: json['maxBudget'] as int? ?? 2000000000,
      minRooms: (json['minRooms'] as num? ?? 0).toDouble(),
      maxRooms: (json['maxRooms'] as num? ?? 10).toDouble(),
      areaId: json['areaId'] as String? ?? 'all_israel',
      requiredFeatures: Set<String>.from(
        json['requiredFeatures'] as List<dynamic>? ?? const [],
      ),
      preferredFeatures: Set<String>.from(
        json['preferredFeatures'] as List<dynamic>? ?? const [],
      ),
      minSizeM2: json['minSizeM2'] as int? ?? 0,
      maxSizeM2: json['maxSizeM2'] as int? ?? 1000000,
      propertyTypes: Set<String>.from(
        json['propertyTypes'] as List<dynamic>? ?? const [],
      ),
      preferredPropertyTypes: Set<String>.from(
        json['preferredPropertyTypes'] as List<dynamic>? ?? const [],
      ),
      conditions: Set<String>.from(
        json['conditions'] as List<dynamic>? ?? const [],
      ),
      preferredConditions: Set<String>.from(
        json['preferredConditions'] as List<dynamic>? ?? const [],
      ),
      listingSource: ListingSourceFilter.values.byName(
        json['listingSource'] as String? ?? ListingSourceFilter.any.name,
      ),
      requiredListingSources: Set<ListingSourceFilter>.from(
        (json['requiredListingSources'] as List<dynamic>? ?? const []).map(
          (value) => ListingSourceFilter.values.byName(value as String),
        ),
      ),
      preferredListingSources: Set<ListingSourceFilter>.from(
        (json['preferredListingSources'] as List<dynamic>? ?? const []).map(
          (value) => ListingSourceFilter.values.byName(value as String),
        ),
      ),
      minFloor: json['minFloor'] as int? ?? 0,
      moveInFilter: MoveInFilter.values.byName(
        json['moveInFilter'] as String? ?? MoveInFilter.any.name,
      ),
      requiredMoveInFilters: Set<MoveInFilter>.from(
        (json['requiredMoveInFilters'] as List<dynamic>? ?? const []).map(
          (value) => MoveInFilter.values.byName(value as String),
        ),
      ),
      preferredMoveInFilters: Set<MoveInFilter>.from(
        (json['preferredMoveInFilters'] as List<dynamic>? ?? const []).map(
          (value) => MoveInFilter.values.byName(value as String),
        ),
      ),
      sortBy: SearchSortOption.values.byName(
        json['sortBy'] as String? ?? SearchSortOption.bestMatch.name,
      ),
      includeUnknownPriceListings:
          json['includeUnknownPriceListings'] as bool? ?? false,
      customAreaPolygon: customAreaJson
          .whereType<Map>()
          .map(
            (item) => LatLng(
              (item['lat'] as num).toDouble(),
              (item['lng'] as num).toDouble(),
            ),
          )
          .toList(),
      city: json['city'] as String? ?? '',
      transactionType: TransactionTypeFilter.values.byName(
        json['transactionType'] as String? ?? TransactionTypeFilter.any.name,
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'query': query,
      'minBudget': minBudget,
      'maxBudget': maxBudget,
      'minRooms': minRooms,
      'maxRooms': maxRooms,
      'areaId': areaId,
      'requiredFeatures': requiredFeatures.toList(),
      'preferredFeatures': preferredFeatures.toList(),
      'minSizeM2': minSizeM2,
      'maxSizeM2': maxSizeM2,
      'propertyTypes': propertyTypes.toList(),
      'preferredPropertyTypes': preferredPropertyTypes.toList(),
      'conditions': conditions.toList(),
      'preferredConditions': preferredConditions.toList(),
      'listingSource': listingSource.name,
      'requiredListingSources':
          requiredListingSources.map((source) => source.name).toList(),
      'preferredListingSources':
          preferredListingSources.map((source) => source.name).toList(),
      'minFloor': minFloor,
      'moveInFilter': moveInFilter.name,
      'requiredMoveInFilters':
          requiredMoveInFilters.map((filter) => filter.name).toList(),
      'preferredMoveInFilters':
          preferredMoveInFilters.map((filter) => filter.name).toList(),
      'sortBy': sortBy.name,
      'includeUnknownPriceListings': includeUnknownPriceListings,
      'customAreaPolygon': customAreaPolygon
          .map((point) => {'lat': point.latitude, 'lng': point.longitude})
          .toList(),
      'city': city,
      'transactionType': transactionType.name,
    };
  }
}

FilterPriority _priorityState<T>({
  required T value,
  required Set<T> requiredValues,
  required Set<T> preferredValues,
}) {
  if (requiredValues.contains(value)) return FilterPriority.required;
  if (preferredValues.contains(value)) return FilterPriority.preferred;
  return FilterPriority.none;
}

({
  Set<T> requiredValues,
  Set<T> preferredValues,
}) _applyPriorityState<T>({
  required T value,
  required FilterPriority state,
  required Set<T> requiredValues,
  required Set<T> preferredValues,
}) {
  final nextRequired = {...requiredValues}..remove(value);
  final nextPreferred = {...preferredValues}..remove(value);
  switch (state) {
    case FilterPriority.none:
      break;
    case FilterPriority.preferred:
      nextPreferred.add(value);
    case FilterPriority.required:
      nextRequired.add(value);
  }
  return (
    requiredValues: nextRequired,
    preferredValues: nextPreferred,
  );
}

class AppReview {
  const AppReview({
    required this.id,
    required this.authorName,
    required this.rating,
    required this.text,
  });

  final String id;
  final String authorName;
  final int rating;
  final String text;

  factory AppReview.fromJson(Map<String, dynamic> json) {
    return AppReview(
      id: json['id'] as String,
      authorName: json['authorName'] as String,
      rating: json['rating'] as int,
      text: json['text'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'authorName': authorName,
      'rating': rating,
      'text': text,
    };
  }
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.sender,
    required this.text,
    required this.createdAt,
  });

  final String id;
  final String sender;
  final String text;
  final DateTime createdAt;

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String,
      sender: json['sender'] as String,
      text: json['text'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sender': sender,
      'text': text,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}

class RentalMatch {
  const RentalMatch({
    required this.id,
    required this.propertyId,
    required this.createdAt,
    required this.messages,
    required this.contractSent,
    required this.ownerSigned,
    required this.tenantSigned,
    this.isRequest = false,
  });

  final String id;
  final String propertyId;
  final DateTime createdAt;
  final List<ChatMessage> messages;
  final bool contractSent;
  final bool ownerSigned;
  final bool tenantSigned;

  /// A one-sided "request to message" — someone with no mutual like reached out.
  /// Lives in the "מבקשים לשלוח הודעה" section until accepted/replied to.
  final bool isRequest;

  RentalMatch copyWith({
    List<ChatMessage>? messages,
    bool? contractSent,
    bool? ownerSigned,
    bool? tenantSigned,
    bool? isRequest,
  }) {
    return RentalMatch(
      id: id,
      propertyId: propertyId,
      createdAt: createdAt,
      messages: messages ?? this.messages,
      contractSent: contractSent ?? this.contractSent,
      ownerSigned: ownerSigned ?? this.ownerSigned,
      tenantSigned: tenantSigned ?? this.tenantSigned,
      isRequest: isRequest ?? this.isRequest,
    );
  }

  factory RentalMatch.fromJson(Map<String, dynamic> json) {
    return RentalMatch(
      id: json['id'] as String,
      propertyId: json['propertyId'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      messages: (json['messages'] as List<dynamic>? ?? const [])
          .map((item) =>
              ChatMessage.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList(),
      contractSent: json['contractSent'] as bool? ?? false,
      ownerSigned: json['ownerSigned'] as bool? ?? false,
      tenantSigned: json['tenantSigned'] as bool? ?? false,
      isRequest: json['isRequest'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'propertyId': propertyId,
      'createdAt': createdAt.toIso8601String(),
      'messages': messages.map((message) => message.toJson()).toList(),
      'contractSent': contractSent,
      'ownerSigned': ownerSigned,
      'tenantSigned': tenantSigned,
      'isRequest': isRequest,
    };
  }
}

String _formatNumber(int value) {
  final raw = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < raw.length; i++) {
    final remaining = raw.length - i;
    buffer.write(raw[i]);
    if (remaining > 1 && remaining % 3 == 1) {
      buffer.write(',');
    }
  }
  return buffer.toString();
}

String _formatDateOnly(DateTime value) {
  final utc = value.toUtc();
  final month = utc.month.toString().padLeft(2, '0');
  final day = utc.day.toString().padLeft(2, '0');
  return '${utc.year}-$month-$day';
}

String _formatLocalDateOnly(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '${value.year}-$month-$day';
}

PropertyMediaType _inferMediaType(String url) {
  final normalized = url.split('?').first.toLowerCase();
  if (normalized.endsWith('.mp4') ||
      normalized.endsWith('.mov') ||
      normalized.endsWith('.m4v') ||
      normalized.endsWith('.webm')) {
    return PropertyMediaType.video;
  }
  return PropertyMediaType.image;
}

const List<PropertyFeatureDefinition> _propertyFeatureCatalog = [
  PropertyFeatureDefinition(
    key: 'balcony',
    label: 'מרפסת',
    aliases: ['balcony'],
  ),
  PropertyFeatureDefinition(
    key: 'parking',
    label: 'חניה',
    aliases: ['parking'],
  ),
  PropertyFeatureDefinition(
    key: 'storage',
    label: 'מחסן',
    aliases: ['storeroom', 'storage'],
  ),
  PropertyFeatureDefinition(
    key: 'airConditioning',
    label: 'מזגן',
    aliases: ['air_conditioning'],
  ),
  PropertyFeatureDefinition(
    key: 'mamad',
    label: 'ממ"ד',
    aliases: ['ממ״ד', 'safe_room'],
  ),
  PropertyFeatureDefinition(
    key: 'sunBalcony',
    label: 'מרפסת שמש',
  ),
  PropertyFeatureDefinition(
    key: 'garden',
    label: 'גינה',
  ),
  PropertyFeatureDefinition(
    key: 'elevator',
    label: 'מעלית',
    aliases: ['elevator'],
  ),
  PropertyFeatureDefinition(
    key: 'furnished',
    label: 'ריהוט',
    aliases: ['מרוהטת', 'מרוהט', 'furnished'],
  ),
  PropertyFeatureDefinition(
    key: 'internetIncluded',
    label: 'אינטרנט כלול',
  ),
  PropertyFeatureDefinition(
    key: 'equippedKitchen',
    label: 'מטבח מאובזר',
  ),
  PropertyFeatureDefinition(
    key: 'petsAllowed',
    label: 'חיות מחמד מותר',
    aliases: ['חיות מחמד', 'pets_allowed'],
  ),
  PropertyFeatureDefinition(
    key: 'laundryIncluded',
    label: 'כביסה כלולה',
  ),
  PropertyFeatureDefinition(
    key: 'security',
    label: 'שומר/אבטחה',
  ),
  PropertyFeatureDefinition(
    key: 'accessible',
    label: 'נגישות לנכים',
    aliases: ['גישה לנכים', 'handicapped_access'],
  ),
  PropertyFeatureDefinition(
    key: 'sharedRoof',
    label: 'גג משותף',
  ),
  PropertyFeatureDefinition(
    key: 'pool',
    label: 'בריכה',
  ),
  PropertyFeatureDefinition(
    key: 'gym',
    label: 'חדר כושר',
  ),
  PropertyFeatureDefinition(
    key: 'bars',
    label: 'סורגים',
    aliases: ['bars'],
  ),
  PropertyFeatureDefinition(
    key: 'renovated',
    label: 'משופצת',
    aliases: ['renovated'],
  ),
  PropertyFeatureDefinition(
    key: 'roommates',
    label: 'מתאימה לשותפים',
    aliases: ['for_roommates'],
  ),
  PropertyFeatureDefinition(
    key: 'bombShelter',
    label: 'מקלט',
    aliases: ['bomb_shelter'],
  ),
  PropertyFeatureDefinition(
    key: 'safeFloorSpace',
    label: 'מרחב מוגן קומתי',
    aliases: ['floor_level_shelter'],
  ),
  PropertyFeatureDefinition(
    key: 'basement',
    label: 'מרתף',
    aliases: ['cellar', 'basement'],
  ),
  PropertyFeatureDefinition(
    key: 'centralHeating',
    label: 'חימום מרכזי',
    aliases: ['heating', 'central_heating'],
  ),
  PropertyFeatureDefinition(
    key: 'bedroomAc',
    label: 'מזגן בחדרי שינה',
    aliases: ['bedroom_ac', 'air_conditioning_bedrooms'],
  ),
  PropertyFeatureDefinition(
    key: 'washingMachine',
    label: 'מכונת כביסה',
    aliases: ['washing_machine'],
  ),
  PropertyFeatureDefinition(
    key: 'refrigerator',
    label: 'מקרר',
    aliases: ['fridge', 'refrigerator'],
  ),
  PropertyFeatureDefinition(
    key: 'oven',
    label: 'תנור',
    aliases: ['oven', 'stove'],
  ),
  PropertyFeatureDefinition(
    key: 'dishwasher',
    label: 'מדיח כלים',
    aliases: ['dishwasher', 'dish_washer'],
  ),
  PropertyFeatureDefinition(
    key: 'smartHome',
    label: 'בקרה חכמה בבית',
    aliases: ['smart_home', 'home_automation'],
  ),
  PropertyFeatureDefinition(
    key: 'undergroundParking',
    label: 'חניה תת קרקעית',
    aliases: ['underground_parking', 'basement_parking'],
  ),
  PropertyFeatureDefinition(
    key: 'soundSystem',
    label: 'מערכת סאונד',
    aliases: ['sound_system', 'audio_system'],
  ),
  PropertyFeatureDefinition(
    key: 'privateEntrance',
    label: 'כניסה פרטית',
    aliases: ['private_entrance'],
  ),
  PropertyFeatureDefinition(
    key: 'cctv',
    label: 'מצלמות אבטחה',
    aliases: ['cctv', 'security_camera', 'camera'],
  ),
  PropertyFeatureDefinition(
    key: 'alarmSystem',
    label: 'מערכת אזעקה',
    aliases: ['alarm', 'alarm_system', 'security_system'],
  ),
  PropertyFeatureDefinition(
    key: 'intercom',
    label: 'אינטרקום',
    aliases: ['intercom', 'buzzer', 'video_intercom'],
  ),
  PropertyFeatureDefinition(
    key: 'electricity',
    label: 'חשמל כלול',
    aliases: ['electricity', 'utilities_included'],
  ),
  PropertyFeatureDefinition(
    key: 'water',
    label: 'מים כלולים',
    aliases: ['water', 'water_included'],
  ),
  PropertyFeatureDefinition(
    key: 'naturalLight',
    label: 'אור טבעי',
    aliases: ['natural_light', 'sunlight', 'bright'],
  ),
  PropertyFeatureDefinition(
    key: 'quietArea',
    label: 'אזור שקט',
    aliases: ['quiet', 'quiet_area', 'peaceful'],
  ),
  PropertyFeatureDefinition(
    key: 'petFriendly',
    label: 'מתאים לחיות מחמד',
    aliases: ['pet_friendly', 'pets_allowed', 'animals'],
  ),
  PropertyFeatureDefinition(
    key: 'parking',
    label: 'חניה מוצמדת',
    aliases: ['covered_parking', 'parking_spot'],
  ),
  PropertyFeatureDefinition(
    key: 'secureEntrance',
    label: 'כניסה מאובטחת',
    aliases: ['secure_entrance', 'gated', 'gated_community'],
  ),
  PropertyFeatureDefinition(
    key: 'publicTransport',
    label: 'קרוב לתחבורה ציבורית',
    aliases: ['public_transport', 'bus', 'train', 'transit'],
  ),
  PropertyFeatureDefinition(
    key: 'furnished',
    label: 'ריהוט אופציונלי',
    aliases: ['optional_furniture', 'furniture_negotiable'],
  ),
  // Geo-derived (auto-tagged on upload from verified coordinates).
  PropertyFeatureDefinition(
    key: 'nearSea',
    label: 'קרוב לים',
    aliases: ['near_sea', 'sea', 'beach', 'קרוב לחוף'],
  ),
  PropertyFeatureDefinition(
    key: 'nearPark',
    label: 'קרוב לפארק',
    aliases: ['near_park', 'park', 'garden', 'קרוב לגן', 'גן ציבורי'],
  ),
];

final Map<String, PropertyFeatureDefinition> _featureDefinitionByKey = {
  for (final item in _propertyFeatureCatalog) item.key: item,
};

final Map<String, String> _featureAliasLookup = {
  for (final item in _propertyFeatureCatalog) ...{
    _normalizeFeatureToken(item.key): item.key,
    _normalizeFeatureToken(item.label): item.key,
    for (final alias in item.aliases) _normalizeFeatureToken(alias): item.key,
  },
};

String _normalizeFeatureToken(String value) {
  return value
      .trim()
      .toLowerCase()
      .replaceAll('״', '"')
      .replaceAll("'", '')
      .replaceAll('"', '');
}

String? _featureKeyFor(String value) {
  return _featureAliasLookup[_normalizeFeatureToken(value)];
}

Map<String, bool> _completeFeatureFlags(Map<String, bool> values) {
  final completed = <String, bool>{
    for (final item in _propertyFeatureCatalog) item.key: false,
  };
  for (final entry in values.entries) {
    completed[entry.key] = entry.value;
  }
  return completed;
}

List<String> _enabledFeatureLabels(Map<String, bool> values) {
  final labels = <String>[];
  final seen = <String>{};

  for (final item in _propertyFeatureCatalog) {
    if (values[item.key] == true && seen.add(item.label)) {
      labels.add(item.label);
    }
  }

  for (final entry in values.entries) {
    if (entry.value != true || _featureDefinitionByKey.containsKey(entry.key)) {
      continue;
    }
    final label = entry.key.trim();
    if (label.isNotEmpty && seen.add(label)) {
      labels.add(label);
    }
  }

  return labels;
}

List<String> _resolveFeatureLabels(
  List<String> features,
  PropertyFeatureSet? featureFlags,
) {
  final labels = <String>[];
  final seen = <String>{};

  for (final feature in features) {
    final trimmed = feature.trim();
    if (trimmed.isNotEmpty && seen.add(trimmed)) {
      labels.add(trimmed);
    }
  }

  if (labels.isEmpty && featureFlags != null) {
    for (final label in featureFlags.enabledLabels) {
      if (seen.add(label)) labels.add(label);
    }
  }

  return labels;
}

List<String> _decodeStringListValue(Object? rawValue) {
  if (rawValue is List) {
    return rawValue.whereType<String>().map((item) => item.trim()).where(
      (item) {
        return item.isNotEmpty;
      },
    ).toList();
  }
  if (rawValue is String && rawValue.trim().isNotEmpty) {
    final parsed = _decodeJsonSafely(rawValue);
    if (parsed is List) {
      return _decodeStringListValue(parsed);
    }
  }
  return const [];
}

PropertyModel3d? _resolveModel3d(
  PropertyModel3d? model3d,
  PropertyVirtualTour? virtualTour,
) {
  if (model3d != null && model3d.hasAnyAsset) return model3d;
  if (virtualTour == null) return model3d;
  final derived = PropertyModel3d.fromVirtualTour(virtualTour);
  return derived.hasAnyAsset ? derived : model3d;
}

List<PropertyPricePoint> _resolvePriceHistory(
  List<PropertyPricePoint>? priceHistory, {
  required int price,
  required String entryDate,
  required PropertyTransactionType transactionType,
}) {
  if (priceHistory != null && priceHistory.isNotEmpty) {
    return List<PropertyPricePoint>.from(priceHistory);
  }
  if (price <= 0) return const [];
  final parsedDate = DateTime.tryParse(entryDate);
  if (parsedDate == null) return const [];
  return [
    PropertyPricePoint(
      date: parsedDate,
      price: price,
      transactionType: transactionType,
    ),
  ];
}

PropertyTransactionType _parseTransactionType(Object? value) {
  final normalized = value?.toString().trim().toLowerCase();
  return switch (normalized) {
    'sale' || 'sell' || 'for_sale' => PropertyTransactionType.sale,
    _ => PropertyTransactionType.rent,
  };
}

Object? _decodeJsonSafely(String rawValue) {
  try {
    return jsonDecode(rawValue);
  } catch (_) {
    return null;
  }
}

PropertyTourStatus _parseTourStatus(Object? value) {
  final normalized = value?.toString().trim().toLowerCase();
  return switch (normalized) {
    'captured' ||
    'capture_ready' ||
    'pending_upload' =>
      PropertyTourStatus.captured,
    'queued' || 'created' || 'pending' => PropertyTourStatus.queued,
    'uploading' => PropertyTourStatus.uploading,
    'processing' || 'training' || 'running' => PropertyTourStatus.processing,
    'ready' || 'complete' || 'completed' => PropertyTourStatus.ready,
    'failed' || 'error' => PropertyTourStatus.failed,
    _ => PropertyTourStatus.none,
  };
}

PropertyVirtualTour? _parseVirtualTour(Object? value) {
  if (value == null) return null;
  if (value is Map<String, dynamic>) {
    final tour = PropertyVirtualTour.fromJson(value);
    return tour.status == PropertyTourStatus.none && tour.viewerUrl.isEmpty
        ? null
        : tour;
  }
  if (value is Map) {
    final tour = PropertyVirtualTour.fromJson(Map<String, dynamic>.from(value));
    return tour.status == PropertyTourStatus.none && tour.viewerUrl.isEmpty
        ? null
        : tour;
  }
  return null;
}

PropertyModel3d? _parseModel3d(Object? value) {
  if (value == null) return null;
  if (value is Map<String, dynamic>) {
    final model = PropertyModel3d.fromJson(value);
    return model.hasAnyAsset ? model : null;
  }
  if (value is Map) {
    final model = PropertyModel3d.fromJson(Map<String, dynamic>.from(value));
    return model.hasAnyAsset ? model : null;
  }
  if (value is String && value.trim().isNotEmpty) {
    final decoded = _decodeJsonSafely(value);
    return _parseModel3d(decoded);
  }
  return null;
}

PropertyLegal? _parsePropertyLegal(Object? value) {
  if (value == null) return null;
  if (value is Map<String, dynamic>) {
    return PropertyLegal.fromJson(value);
  }
  if (value is Map) {
    return PropertyLegal.fromJson(Map<String, dynamic>.from(value));
  }
  if (value is String && value.trim().isNotEmpty) {
    final decoded = _decodeJsonSafely(value);
    return _parsePropertyLegal(decoded);
  }
  return null;
}

List<PropertyPricePoint> _parsePriceHistory(
  Object? value, {
  required int fallbackPrice,
  required String fallbackEntryDate,
  required PropertyTransactionType fallbackTransactionType,
}) {
  if (value is List) {
    final items = value
        .whereType<Map>()
        .map((item) =>
            PropertyPricePoint.fromJson(Map<String, dynamic>.from(item)))
        .where((item) => item.price > 0)
        .toList();
    if (items.isNotEmpty) return items;
  }
  if (value is String && value.trim().isNotEmpty) {
    final decoded = _decodeJsonSafely(value);
    return _parsePriceHistory(
      decoded,
      fallbackPrice: fallbackPrice,
      fallbackEntryDate: fallbackEntryDate,
      fallbackTransactionType: fallbackTransactionType,
    );
  }
  return _resolvePriceHistory(
    null,
    price: fallbackPrice,
    entryDate: fallbackEntryDate,
    transactionType: fallbackTransactionType,
  );
}

PropertyMarketSignals? _parseMarketSignals(Object? value) {
  if (value == null) return null;
  if (value is Map<String, dynamic>) {
    return PropertyMarketSignals.fromJson(value);
  }
  if (value is Map) {
    return PropertyMarketSignals.fromJson(Map<String, dynamic>.from(value));
  }
  if (value is String && value.trim().isNotEmpty) {
    final decoded = _decodeJsonSafely(value);
    return _parseMarketSignals(decoded);
  }
  return null;
}

PropertyVerification _parsePropertyVerification(Map<String, dynamic> json) {
  final raw = json['verification'];
  PropertyVerification parsed = const PropertyVerification();
  if (raw is Map<String, dynamic>) {
    parsed = PropertyVerification.fromJson(raw);
  } else if (raw is Map) {
    parsed = PropertyVerification.fromJson(Map<String, dynamic>.from(raw));
  } else if (raw is String && raw.trim().isNotEmpty) {
    final decoded = _decodeJsonSafely(raw);
    if (decoded is Map<String, dynamic>) {
      parsed = PropertyVerification.fromJson(decoded);
    } else if (decoded is Map) {
      parsed = PropertyVerification.fromJson(
        Map<String, dynamic>.from(decoded),
      );
    }
  }

  final flatVideoUrl =
      json['verificationVideoUrl']?.toString().trim().isNotEmpty == true
          ? json['verificationVideoUrl']!.toString().trim()
          : json['verifiedVideoUrl']?.toString().trim() ?? '';
  final flatMethod = json['verificationMethod']?.toString().trim() ?? '';
  final flatCapturedAt = _optionalDate(
    json['verifiedAt'] ?? json['verificationCapturedAt'],
  );
  final hasFlatVerification = _asBoolFlag(
    json['verifiedListing'] ??
        json['isVerifiedListing'] ??
        json['verified'] ??
        false,
  );

  final hasStructuredVerification =
      parsed.videoUrl.isNotEmpty || parsed.method.isNotEmpty || parsed.verified;
  if (hasStructuredVerification) {
    return parsed.copyWith(
      verified: parsed.verified || hasFlatVerification,
      method: parsed.method.isNotEmpty
          ? parsed.method
          : (flatMethod.isNotEmpty
              ? flatMethod
              : (flatVideoUrl.isNotEmpty
                  ? PropertyVerification.cameraVideoMethod
                  : parsed.method)),
      videoUrl: parsed.videoUrl.isNotEmpty ? parsed.videoUrl : flatVideoUrl,
      capturedAt: parsed.capturedAt ?? flatCapturedAt,
    );
  }

  if (!hasFlatVerification && flatVideoUrl.isEmpty) {
    return parsed;
  }

  return PropertyVerification(
    verified: hasFlatVerification,
    method: flatMethod.isNotEmpty
        ? flatMethod
        : (flatVideoUrl.isNotEmpty
            ? PropertyVerification.cameraVideoMethod
            : parsed.method),
    videoUrl: flatVideoUrl,
    capturedAt: flatCapturedAt,
  );
}

int? _optionalInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

double? _optionalDouble(Object? value) {
  if (value == null) return null;
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

DateTime? _optionalDate(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  return DateTime.tryParse(value.toString());
}

DateTime _generateDeterministicMockDate(String id) {
  final hash = id.hashCode.abs();
  // Distribute the listing age between 0 and 29 days.
  // If hash % 30 < 8, age is < 8 days, which is within the 10.5 days window.
  final daysAgo = hash % 30;
  final hoursAgo = hash % 24;
  return DateTime.now().subtract(Duration(days: daysAgo, hours: hoursAgo));
}

bool _asBoolFlag(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  final normalized = value?.toString().trim().toLowerCase();
  return normalized == 'true' || normalized == '1' || normalized == 'yes';
}
