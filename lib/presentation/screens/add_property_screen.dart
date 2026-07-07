import 'dart:async';
import 'dart:ui' show PathMetric, ImageFilter;
import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/security/input_sanitizer.dart';
import 'package:dating_app/core/security/rate_limiter.dart';
import 'package:dating_app/core/security/security_config.dart';
import 'package:dating_app/core/services/israel_locations.dart';
import 'package:dating_app/core/services/legal_consent_service.dart';
import 'package:dating_app/core/services/property_3d_scan_service.dart';
import 'package:dating_app/core/services/scaniverse_asset_import_service.dart';
import 'package:dating_app/core/services/scaniverse_service.dart';
import 'package:dating_app/core/services/storage_service.dart';
import 'package:dating_app/data/models/broker_design_models.dart';
import 'package:dating_app/data/models/panorama_tour.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/presentation/features/panorama/panorama_capture_screen.dart';
import 'package:dating_app/presentation/features/pricing/fair_rent_hint.dart';
import 'package:dating_app/presentation/features/scan3d/room_scan_flow.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/presentation/widgets/safe_media.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:dating_app/core/search/geo_auto_tags.dart';
import 'package:dating_app/core/listing_score.dart';
import 'package:dating_app/core/finance/price_realism.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:dating_app/presentation/widgets/rently_icon.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:video_compress/video_compress.dart';

class _PropertyMediaDraft {
  _PropertyMediaDraft({
    String initialValue = '',
    this.type = PropertyMediaType.image,
  }) : controller = TextEditingController(text: initialValue);

  final TextEditingController controller;
  PropertyMediaType type;

  void dispose() => controller.dispose();
}

extension _PropertyMediaTypeUi on PropertyMediaType {
  String get label => this == PropertyMediaType.image ? 'תמונה' : 'וידאו';

  IconData get icon => this == PropertyMediaType.image
      ? IconsaxPlusLinear.image
      : IconsaxPlusLinear.video;
}

// Version is resolved from AppConfig so it stays in sync with
// LegalConsentService across the whole app — never hardcode it here.
final List<String> _propertyFeatureLabels = PropertyFeatureCatalog.allLabels;

// Upper bound for a one-time sale price (₪). Sale listings reuse `price` as the
// full asking price rather than a monthly rent, so they need a much wider range.
const int _kMaxSalePrice = 20000000; // 20M ₪

PropertyLegal _buildPropertyLegal({
  required bool acceptedTerms,
  required bool thirdPartyTransferAllowed,
  required bool commercialSaleAllowed,
  required bool aiTrainingAllowed,
  PropertyLegal? existing,
  String source = 'add_property_screen',
}) {
  if (!acceptedTerms) {
    // Preserve whatever was stored before without touching consent fields.
    return existing ??
        PropertyLegal(
          thirdPartyTransferAllowed: thirdPartyTransferAllowed,
          commercialSaleAllowed: commercialSaleAllowed,
          aiTrainingAllowed: aiTrainingAllowed,
        );
  }

  // User actively checked "I agree" — always stamp a fresh timestamp and the
  // current config version so LegalConsentService.hasValidConsent() passes.
  return LegalConsentService.instance.grantConsent(
    source: source,
    thirdPartyTransfer: thirdPartyTransferAllowed,
    commercialSale: commercialSaleAllowed,
    aiTraining: aiTrainingAllowed,
  );
}

class AddPropertyScreen extends StatefulWidget {
  const AddPropertyScreen({super.key, this.initialDraft});

  /// Optional pre-fill from Erik (the personal assistant): collected fields such
  /// as city / street / rooms / price / floor / size / condition / entryDate.
  /// The landlord just reviews, adds photos and publishes via the normal flow.
  final Map<String, dynamic>? initialDraft;

  @override
  State<AddPropertyScreen> createState() => _AddPropertyScreenState();
}

class _AddPropertyScreenState extends State<AddPropertyScreen> {
  static const _stepLabels = ['מיקום', 'פרטי הנכס', 'מאפיינים', 'מדיה'];

  final _pageCtrl = PageController();
  int _step = 0;

  final _cityCtrl = TextEditingController();
  final _neighborhoodCtrl = TextEditingController();
  final _streetCtrl = TextEditingController();
  final _streetNumCtrl = TextEditingController();
  final _floorCtrl = TextEditingController();
  final _totalFloorsCtrl = TextEditingController();
  final _sizeCtrl = TextEditingController();
  final _entryDateCtrl = TextEditingController();
  final List<_PropertyMediaDraft> _mediaDrafts = [_PropertyMediaDraft()];
  final _picker = ImagePicker();
  final _storageService = StorageService();
  final _scanService = Property3dScanService();
  final _scaniverseImportService = ScaniverseAssetImportService();
  final String _draftPropertyId =
      'custom-${DateTime.now().millisecondsSinceEpoch}';

  int _price = 5000;
  PropertyTransactionType _transactionType = PropertyTransactionType.rent;
  double _rooms = 3;
  String _propertyType = 'דירה';
  String _condition = 'תקין';
  String _designTemplate = '';
  int _designAccent = 0;
  // Kept on the model (preserved when editing) but no longer user-toggleable on
  // the add flow — the 'פרסום תיווך מאומת' switch was removed from the details step.
  final bool _agencyListing = false;
  final Set<String> _selectedFeatures = {};
  // Where the (broker) listing is advertised. Rently is ON by default — you're
  // publishing here; brokers can also mark other channels for their own tracking.
  final Set<String> _publishChannels = {'rently'};
  bool _isSaving = false;
  bool _isSubmittingTour = false;
  bool _isScanSubmitting = false;
  bool _isCapturingVerification = false;
  PropertyVirtualTour? _virtualTourDraft;
  PropertyVirtualTour? _scanTourDraft;
  PropertyModel3d? _model3dDraft;
  PropertyPanoramaTour? _panoramaTourDraft;
  List<ScannedRoom> _roomScans = const [];
  Timer? _scanPollTimer;

  // Opens the per-room 3D scan flow (the founder's primary path: high-quality
  // 3D captured one room at a time, linked together). Persists the resulting
  // rooms on the draft. NOTE: full multi-room persistence needs a model field —
  // see report. For now we keep the rooms in screen state and surface the first
  // viewable room through the existing _model3dDraft so a save still carries 3D.
  Future<void> _openRoomScan() async {
    final result = await RoomScanFlowScreen.open(
      context,
      propertyId: _draftPropertyId,
      initialRooms: _roomScans,
    );
    if (result == null || !mounted) return;
    setState(() {
      _roomScans = result;
      final firstViewable = result.firstWhere(
        (r) => r.hasViewableAsset,
        orElse: () => const ScannedRoom(name: ''),
      );
      if (firstViewable.hasViewableAsset) {
        _model3dDraft = (_model3dDraft ?? const PropertyModel3d()).copyWith(
          glbUrl: firstViewable.meshGlbUrl ?? '',
          plyUrl: firstViewable.splatUrl ?? '',
          scanDate: DateTime.now(),
        );
      } else if (result.isEmpty) {
        _model3dDraft = null;
      }
    });
  }

  Future<void> _createPanoramaTour() async {
    final result = await Navigator.of(context).push<PropertyPanoramaTour>(
      MaterialPageRoute(
        builder: (_) => PanoramaCaptureScreen(initial: _panoramaTourDraft),
      ),
    );
    if (result != null && mounted) {
      setState(() => _panoramaTourDraft = result.isEmpty ? null : result);
    }
  }
  int _scanPollCount = 0;
  bool _wantsVerifiedListing = false;
  String _verificationVideoUrl = '';
  DateTime? _verificationCapturedAt;
  bool _acceptedPropertyTerms = false;
  bool _thirdPartyTransferAllowed = false;
  bool _commercialSaleAllowed = false;
  bool _aiTrainingAllowed = false;

  @override
  void initState() {
    super.initState();
    _applyInitialDraft(widget.initialDraft);
  }

  // Pre-fill the form from Erik's collected draft so an older landlord only has
  // to review and add photos. All values are optional and defensively parsed.
  void _applyInitialDraft(Map<String, dynamic>? d) {
    if (d == null || d.isEmpty) return;
    String s(Object? v) => v == null ? '' : v.toString().trim();
    if (s(d['city']).isNotEmpty) _cityCtrl.text = s(d['city']);
    if (s(d['neighborhood']).isNotEmpty) {
      _neighborhoodCtrl.text = s(d['neighborhood']);
    }
    if (s(d['street']).isNotEmpty) _streetCtrl.text = s(d['street']);
    if (s(d['streetNumber']).isNotEmpty) {
      _streetNumCtrl.text = s(d['streetNumber']).replaceAll(RegExp(r'[^0-9]'), '');
    }
    if (s(d['floor']).isNotEmpty) _floorCtrl.text = s(d['floor']);
    if (s(d['totalFloors']).isNotEmpty) {
      _totalFloorsCtrl.text = s(d['totalFloors']);
    }
    if (s(d['sizeM2']).isNotEmpty) {
      _sizeCtrl.text = s(d['sizeM2']).replaceAll(RegExp(r'[^0-9]'), '');
    }
    if (s(d['entryDate']).isNotEmpty) _entryDateCtrl.text = s(d['entryDate']);
    final rooms = d['rooms'];
    if (rooms is num) _rooms = (rooms.toDouble() * 2).round() / 2;
    final price = d['price'];
    if (price is num && price > 0) _price = (price / 100).round() * 100;
    if (s(d['condition']).isNotEmpty) _condition = s(d['condition']);
  }

  @override
  void dispose() {
    _stopScanPolling();
    _pageCtrl.dispose();
    _cityCtrl.dispose();
    _neighborhoodCtrl.dispose();
    _streetCtrl.dispose();
    _streetNumCtrl.dispose();
    _floorCtrl.dispose();
    _totalFloorsCtrl.dispose();
    _sizeCtrl.dispose();
    _entryDateCtrl.dispose();
    for (final item in _mediaDrafts) {
      item.dispose();
    }
    super.dispose();
  }

  void _startScanPolling() {
    _stopScanPolling();
    _scanPollCount = 0;
    _scanPollTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      final tour = _scanTourDraft;
      if (tour == null) { _stopScanPolling(); return; }
      if (tour.status == PropertyTourStatus.ready || tour.status == PropertyTourStatus.failed) {
        _stopScanPolling(); return;
      }
      _scanPollCount++;
      if (_scanPollCount > 20) {
        _stopScanPolling();
        if (!mounted) return;
        // Teleport's Gaussian-splat processing takes ~1 hour, far longer than
        // this in-screen poll — so keep it "processing" (not failed). The tour
        // is saved with the capture id and appears automatically once ready.
        final isTeleport = tour.provider == 'teleport';
        setState(() {
          _scanTourDraft = _scanTourDraft?.copyWith(
            status: isTeleport
                ? PropertyTourStatus.processing
                : PropertyTourStatus.failed,
            processingStage: isTeleport
                ? 'הסיור התלת־ממדי בעיבוד (בערך שעה). אפשר לשמור את הדירה — הוא יופיע אוטומטית כשיהיה מוכן.'
                : '',
            errorMessage: isTeleport
                ? ''
                : 'עיבוד הסריקה לקח יותר מדי זמן. נסה שוב מאוחר יותר.',
            updatedAt: DateTime.now().toUtc(),
          );
        });
        return;
      }
      try {
        final updated = await _scanService.refresh(tour);
        if (!mounted) { _stopScanPolling(); return; }
        setState(() => _scanTourDraft = updated);
        if (updated.status == PropertyTourStatus.ready || updated.status == PropertyTourStatus.failed) {
          _stopScanPolling();
        }
      } catch (e) {
        if (!mounted) { _stopScanPolling(); return; }
        if (_scanPollCount >= 20) {
          _stopScanPolling();
          setState(() {
            _scanTourDraft = _scanTourDraft?.copyWith(
              status: PropertyTourStatus.failed,
              errorMessage: 'שגיאה בבדיקת סטטוס הסריקה. נסה שוב.',
              updatedAt: DateTime.now().toUtc(),
            );
          });
        }
      }
    });
  }

  void _stopScanPolling() {
    _scanPollTimer?.cancel();
    _scanPollTimer = null;
  }

  bool _validateCurrentStep() {
    switch (_step) {
      case 0:
        final city = _cityCtrl.text.trim();
        final street = _streetCtrl.text.trim();
        if (city.isEmpty || street.isEmpty) return false;
        if (city.length < 2 || street.length < 2) return false;
        return true;
      case 1:
        final size = int.tryParse(_sizeCtrl.text.trim()) ?? 0;
        return size > 0 &&
            _price > 0 &&
            _rooms > 0;
      case 3:
        if (_wantsVerifiedListing) {
          return _verificationVideoUrl.isNotEmpty;
        }
        return _mediaDrafts.any((draft) => draft.controller.text.trim().isNotEmpty);
      default:
        return true;
    }
  }

  void _next() {
    if (!_validateCurrentStep()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(milliseconds: 2500),
          content: Text('יש למלא את השדות הנדרשים'),
          backgroundColor: AppColors.coral,
        ),
      );
      return;
    }
    if (_step < 3) {
      setState(() => _step++);
      _pageCtrl.nextPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeInOut,
      );
    } else {
      _save();
    }
  }

  void _prev() {
    if (_step > 0) {
      setState(() => _step--);
      _pageCtrl.previousPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeInOut,
      );
    } else {
      Navigator.of(context).pop();
    }
  }

  Future<void> _pickPropertyImage(ImageSource source) async {
    if (_wantsVerifiedListing) {
      _showMediaError('בדירה מאומתת אפשר לצלם רק וידאו אימות מתוך האפליקציה.');
      return;
    }
    try {
      final file = await _picker.pickImage(
        source: source,
        imageQuality: 86,
        maxWidth: 1800,
      );
      if (file == null) return;

      final localPath = await _storageService.saveImageLocally(
        file,
        folderName: 'property_photos',
      );
      final remoteUrl = await _storageService.uploadToCloud(localPath);
      if (remoteUrl == null || remoteUrl.isEmpty) {
        _showMediaError('שגיאה בהעלאת התמונה לשרת. בדוק את החיבור לאינטרנט ונסה שוב.');
        return;
      }
      _assignPickedMedia(remoteUrl, PropertyMediaType.image);
    } on StorageException catch (error) {
      _showMediaError(error.message);
    }
  }

  Future<void> _pickPropertyVideo(ImageSource source) async {
    if (_wantsVerifiedListing) {
      _showMediaError('בדירה מאומתת אפשר לצלם רק וידאו אימות מתוך האפליקציה.');
      return;
    }
    try {
      final file = await _picker.pickVideo(
        source: source,
        maxDuration: const Duration(seconds: 90),
      );
      if (file == null) return;

      final localPath = await _storageService.saveVideoLocally(
        file,
        folderName: 'property_videos',
      );
      final remoteUrl = await _storageService.uploadToCloud(localPath);
      if (remoteUrl == null || remoteUrl.isEmpty) {
        _showMediaError('שגיאה בהעלאת הוידאו לשרת. בדוק את החיבור לאינטרנט ונסה שוב.');
        return;
      }
      _assignPickedMedia(remoteUrl, PropertyMediaType.video);
    } on StorageException catch (error) {
      _showMediaError(error.message);
    }
  }

  Future<void> _pickScanVideo(ImageSource source) async {
    if (_wantsVerifiedListing) {
      _showMediaError(
          'בדירה מאומתת סריקות והעלאות ננעלות עד ביטול מצב האימות.');
      return;
    }
    // A successful 3D reconstruction depends entirely on capture quality — the
    // #1 cause of a failed Teleport scan is a video that's too fast/partial to
    // rebuild the room. Show the technique guide before recording.
    if (source == ImageSource.camera) {
      final proceed = await showScanCaptureGuide(context);
      if (proceed != true) return;
    }

    try {
      final file = await _picker.pickVideo(
        source: source,
        maxDuration: const Duration(seconds: 60),
      );
      if (file == null) return;

      final rawSize = await file.length();
      if (rawSize > 400 * 1024 * 1024) {
        _showMediaError(
          'הסרטון גדול מדי (${(rawSize / 1024 / 1024).toStringAsFixed(0)} MB). '
          'צלם סרטון קצר יותר של עד 60 שניות.',
        );
        return;
      }

      setState(() => _isScanSubmitting = true);
      // Teleport's 3D reconstruction requires an H.264 mp4; iOS records HEVC
      // .mov which fails processing. Transcode on-device first (fail-soft —
      // if it fails we upload the original rather than block the user).
      final mp4Path = await transcodeScanToMp4(file.path);
      final scanFile = mp4Path != null ? XFile(mp4Path) : file;
      final localPath = await _storageService.saveVideoLocally(
        scanFile,
        folderName: 'property_scan_videos',
      );
      final sizeBytes = await scanFile.length();
      final captured = _scanService.localCapture(
        propertyId: _draftPropertyId,
        localVideoPath: localPath,
        sizeBytes: sizeBytes,
      );

      if (!_scanService.isConfigured) {
        setState(() {
          _scanTourDraft = captured;
          _isScanSubmitting = false;
        });
        _showMediaError(
          'הסריקה נשמרה כטיוטה. שליחת הסריקה לעיבוד אינה זמינה כרגע.',
        );
        return;
      }

      setState(() {
        _scanTourDraft = captured.copyWith(
          status: PropertyTourStatus.uploading,
          updatedAt: DateTime.now().toUtc(),
        );
      });

      final submitted = await _scanService.submitScanVideo(
        propertyId: _draftPropertyId,
        title: _scanTitle(),
        localVideoPath: localPath,
      );

      if (!mounted) return;
      setState(() {
        _scanTourDraft = submitted;
        _isScanSubmitting = false;
      });
      if (submitted.status == PropertyTourStatus.processing ||
          submitted.status == PropertyTourStatus.queued) {
        _startScanPolling();
      }
    } on Property3dScanException catch (error) {
      if (!mounted) return;
      setState(() {
        _scanTourDraft = _scanTourDraft?.copyWith(
          status: PropertyTourStatus.captured,
          updatedAt: DateTime.now().toUtc(),
        );
        _isScanSubmitting = false;
      });
      _showMediaError(error.message);
    } on StorageException catch (error) {
      if (!mounted) return;
      setState(() => _isScanSubmitting = false);
      _showMediaError(error.message);
    } catch (error) {
      if (!mounted) return;
      setState(() => _isScanSubmitting = false);
      _showMediaError('סריקת ה־3D נכשלה: $error');
    }
  }

  Future<void> _linkScaniverseScan() async {
    final service = ScaniverseService.instance;
    if (!service.isConfigured) {
      _showMediaError(
        'ייבוא סריקות אינו זמין כרגע.',
      );
      return;
    }
    final scan = await showModalBottomSheet<ScaniverseScan>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const _ScaniversePickerSheet(),
    );
    if (scan == null || !mounted) return;
    setState(() {
      _scanTourDraft = service.tourFromScan(scan);
    });
  }

  Future<void> _importScaniverseAssets() async {
    if (_wantsVerifiedListing) {
      _showMediaError(
          'בדירה מאומתת סריקות והעלאות ננעלות עד ביטול מצב האימות.');
      return;
    }
    try {
      setState(() => _isScanSubmitting = true);
      final imported = await _scaniverseImportService.importExportedModel(
        propertyId: _draftPropertyId,
        title: _scanTitle(),
      );
      if (!mounted) return;
      setState(() {
        _scanTourDraft = imported.tour;
        _model3dDraft = imported.model3d;
        _isScanSubmitting = false;
      });
    } on ScaniverseAssetImportException catch (error) {
      if (!mounted) return;
      setState(() => _isScanSubmitting = false);
      _showMediaError(error.message);
    } on ScaniverseException catch (error) {
      if (!mounted) return;
      setState(() => _isScanSubmitting = false);
      _showMediaError(error.message);
    } catch (error) {
      if (!mounted) return;
      setState(() => _isScanSubmitting = false);
      _showMediaError('ייבוא מודל מ-Scaniverse נכשל: $error');
    }
  }

  Future<void> _captureVerificationVideo() async {
    try {
      setState(() => _isCapturingVerification = true);
      final file = await _picker.pickVideo(
        source: ImageSource.camera,
        maxDuration: const Duration(seconds: 90),
      );
      if (file == null) {
        if (mounted) setState(() => _isCapturingVerification = false);
        return;
      }

      final localPath = await _storageService.saveVideoLocally(
        file,
        folderName: 'property_verification_videos',
      );
      final remoteUrl = await _storageService.uploadToCloud(localPath);
      final videoUrl = remoteUrl ?? localPath;
      final capturedAt = DateTime.now().toUtc();
      if (!mounted) return;
      setState(() {
        _wantsVerifiedListing = true;
        _verificationVideoUrl = videoUrl;
        _verificationCapturedAt = capturedAt;
        _virtualTourDraft = null;
        _model3dDraft = null;
        _replaceMediaDraftsWithSingleVideo(videoUrl);
        _isCapturingVerification = false;
      });
    } on StorageException catch (error) {
      if (!mounted) return;
      setState(() => _isCapturingVerification = false);
      _showMediaError(error.message);
    } catch (error) {
      if (!mounted) return;
      setState(() => _isCapturingVerification = false);
      _showMediaError('צילום וידאו האימות נכשל: $error');
    }
  }

  String _scanTitle() {
    final city = _cityCtrl.text.trim();
    final street = _streetCtrl.text.trim();
    final parts = [
      if (street.isNotEmpty) street,
      if (city.isNotEmpty) city,
    ];
    return parts.isEmpty ? 'Rently apartment scan' : parts.join(', ');
  }

  void _assignPickedMedia(String path, PropertyMediaType type) {
    if (!mounted) return;
    if (_wantsVerifiedListing) {
      _showMediaError('בדירה מאומתת אי אפשר להוסיף מדיה ידנית או מהגלריה.');
      return;
    }
    final emptyIndex = _mediaDrafts.indexWhere(
      (draft) => draft.controller.text.trim().isEmpty,
    );
    if (emptyIndex != -1) {
      setState(() {
        _mediaDrafts[emptyIndex].controller.text = path;
        _mediaDrafts[emptyIndex].type = type;
      });
      return;
    }
    if (_mediaDrafts.length >= SecurityConfig.maxPropertyMediaItems) {
      _showMediaError(
        'אפשר לצרף עד ${SecurityConfig.maxPropertyMediaItems} פריטי מדיה.',
      );
      return;
    }
    setState(() {
      _mediaDrafts.add(_PropertyMediaDraft(initialValue: path, type: type));
    });
  }

  void _replaceMediaDraftsWithSingleVideo(String videoUrl) {
    for (final draft in _mediaDrafts) {
      draft.dispose();
    }
    _mediaDrafts
      ..clear()
      ..add(
        _PropertyMediaDraft(
          initialValue: videoUrl,
          type: PropertyMediaType.video,
        ),
      );
  }

  void _resetMediaDrafts() {
    for (final draft in _mediaDrafts) {
      draft.dispose();
    }
    _mediaDrafts
      ..clear()
      ..add(_PropertyMediaDraft());
  }

  void _setVerifiedListingMode(bool value) {
    setState(() {
      _wantsVerifiedListing = value;
      _verificationVideoUrl = '';
      _verificationCapturedAt = null;
      _virtualTourDraft = null;
      _scanTourDraft = null;
      _model3dDraft = null;
      _resetMediaDrafts();
    });
  }

  void _clearVerificationVideo() {
    setState(() {
      _verificationVideoUrl = '';
      _verificationCapturedAt = null;
      _resetMediaDrafts();
    });
  }

  void _showMediaError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(milliseconds: 2500),
        content: Text(message),
        backgroundColor: AppColors.coral,
      ),
    );
  }

  Future<void> _save() async {
    // SEC-rate: prevent property spam
    if (!RateLimiter.instance.allowPropertyAdd()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(milliseconds: 2500),
          content: Text('הוספת יותר מדי נכסים לאחרונה. נסה שוב מאוחר יותר.'),
          backgroundColor: AppColors.coral,
        ),
      );
      return;
    }

    if (!_acceptedPropertyTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(milliseconds: 2500),
          content:
              Text('יש לאשר את תנאי השימוש והצהרת הזכויות לפני פרסום נכס.'),
          backgroundColor: AppColors.coral,
        ),
      );
      return;
    }

    // SEC-2: Sanitize all text inputs before persistence
    final city = InputSanitizer.sanitizeAddress(_cityCtrl.text);
    final street = InputSanitizer.sanitizeAddress(_streetCtrl.text);
    final size = (int.tryParse(_sizeCtrl.text.trim()) ?? 0)
        .clamp(SecurityConfig.minSizeM2, SecurityConfig.maxSizeM2);

    if (city.isEmpty || street.isEmpty || size == 0) return;

    // Guideline 1.2: reject listings whose free-text fields contain
    // objectionable content before it is published.
    final freeText = [
      _cityCtrl.text,
      _streetCtrl.text,
      _neighborhoodCtrl.text,
      _floorCtrl.text,
      _entryDateCtrl.text,
    ].join(' ');
    if (InputSanitizer.containsObjectionableContent(freeText)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(milliseconds: 3000),
          content: Text('הטקסט מכיל תוכן לא הולם. אנא תקנו ונסו שוב.'),
          backgroundColor: AppColors.coral,
        ),
      );
      return;
    }

    final sanitizedVerificationVideoUrl =
        InputSanitizer.sanitizeMediaUrl(_verificationVideoUrl);
    if (_wantsVerifiedListing &&
        (sanitizedVerificationVideoUrl == null ||
            sanitizedVerificationVideoUrl.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(milliseconds: 2500),
          content:
              Text('כדי לפרסם דירה מאומתת צריך לצלם וידאו מתוך האפליקציה.'),
          backgroundColor: AppColors.coral,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final media = _wantsVerifiedListing
          ? [
              PropertyMedia(
                url: sanitizedVerificationVideoUrl!,
                type: PropertyMediaType.video,
              ),
            ]
          : _mediaDrafts
              .map((draft) {
                final sanitized =
                    InputSanitizer.sanitizeMediaUrl(draft.controller.text.trim());
                if (sanitized == null || sanitized.isEmpty) return null;
                return PropertyMedia(url: sanitized, type: draft.type);
              })
              .whereType<PropertyMedia>()
              .toList();
      final verification = _wantsVerifiedListing
          ? PropertyVerification.cameraVideo(
              videoUrl: sanitizedVerificationVideoUrl!,
              capturedAt: _verificationCapturedAt ?? DateTime.now().toUtc(),
            )
          : const PropertyVerification();
      // For a sale the price is a one-time total (reusing `price`), so it can be
      // far higher than a monthly rent — clamp it against the sale ceiling.
      final sanitizedPrice = _transactionType == PropertyTransactionType.sale
          ? _price.clamp(0, _kMaxSalePrice)
          : InputSanitizer.clampPrice(_price);
      final transactionType = _transactionType;
      final priceHistory = sanitizedPrice > 0
          ? [
              PropertyPricePoint(
                date: DateTime.now().toUtc(),
                price: sanitizedPrice,
                transactionType: transactionType,
              ),
            ]
          : const <PropertyPricePoint>[];
      final legal = _buildPropertyLegal(
        acceptedTerms: _acceptedPropertyTerms,
        thirdPartyTransferAllowed: _thirdPartyTransferAllowed,
        commercialSaleAllowed: _commercialSaleAllowed,
        aiTrainingAllowed: _aiTrainingAllowed,
      );

      double lat = 32.0853;
      double lon = 34.7818;
      bool geocodingFailed = false;
      try {
        final addressParts = <String>[
          if (street.isNotEmpty) street,
          if (_streetNumCtrl.text.trim().isNotEmpty) _streetNumCtrl.text.trim(),
          if (city.isNotEmpty) city,
          'ישראל',
        ];
        final locations = await locationFromAddress(addressParts.join(', '));
        if (locations.isNotEmpty) {
          lat = locations.first.latitude;
          lon = locations.first.longitude;
        } else {
          geocodingFailed = true;
        }
      } catch (_) {
        geocodingFailed = true;
      }
      if (geocodingFailed && kDebugMode) {
        debugPrint('Property geocoding failed for: $street, $city');
      }

      // Auto-complete VERIFIED geo tags (near sea / near park) the owner may have
      // missed — computed from the coordinates with strict thresholds, and still
      // removable like any other tag.
      _selectedFeatures.addAll(GeoAutoTags.compute(lat, lon));

      final property = RentalProperty(
        id: _draftPropertyId,
        sourceUrl: '',
        price: sanitizedPrice,
        rooms: InputSanitizer.clampRooms(_rooms),
        sizeM2: InputSanitizer.clampSize(size),
        floor: InputSanitizer.sanitizeText(_floorCtrl.text.trim(), maxLength: 10),
        totalFloors: InputSanitizer.sanitizeText(_totalFloorsCtrl.text.trim(),
            maxLength: 10),
        city: city,
        neighborhood: InputSanitizer.sanitizeAddress(_neighborhoodCtrl.text),
        street: street,
        streetNumber: int.tryParse(_streetNumCtrl.text.trim()) ?? -1,
        lat: lat,
        lon: lon,
        propertyType: _propertyType,
        entryDate: InputSanitizer.sanitizeText(_entryDateCtrl.text.trim(),
            maxLength: 20),
        condition: _condition,
        ownerName:
            context.read<DatingProvider>().tenantProfile?.name ?? 'בעל הדירה',
        agencyListing: _agencyListing,
        features: _selectedFeatures.toList(),
        publishChannels: _publishChannels.toList(),
        media: media,
        transactionType: transactionType,
        virtualTour: _scanTourDraft ?? _virtualTourDraft,
        model3d: _model3dDraft,
        panoramaTour: _panoramaTourDraft,
        legal: legal,
        priceHistory: priceHistory,
        verification: verification,
        designTemplate: _designTemplate,
        designAccent: _designAccent,
        createdAt: DateTime.now(),
      );

      // ANTI-BAIT: if the price is wildly off the market for this size + city
      // (a typo, or lead-bait), ask the owner to confirm or fix before it goes up.
      final realism = PriceRealism.check(property);
      if (realism.flag == PriceFlag.tooLow ||
          realism.flag == PriceFlag.tooHigh) {
        final proceed = await _confirmPriceRealism(realism);
        if (proceed != true) {
          if (mounted) setState(() => _isSaving = false);
          return; // back to the form to fix the price
        }
      }

      await context.read<DatingProvider>().addLandlordProperty(property);

      if (!mounted) return;
      // Auto-score the listing (our engine, verified signals) and show it back.
      final score = ListingScore.basic(property);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration: const Duration(seconds: 4),
        backgroundColor: AppColors.navy,
        content: Text('הדירה עלתה! ניקוד מודעה: $score/100 · '
            '${ListingScore.label(score)}'),
      ));
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration: const Duration(milliseconds: 3000),
        content: Text('שגיאה בשמירת הנכס. נסה שוב.'),
        backgroundColor: AppColors.coral,
      ));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<bool?> _confirmPriceRealism(
      ({PriceFlag flag, int fair, int expectedLow, int expectedHigh, double ratio})
          r) {
    final low = r.flag == PriceFlag.tooLow;
    String fmt(int v) => '₪${v.toString().replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},')}';
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(low ? 'המחיר נמוך מהרגיל 🤔' : 'המחיר גבוה מהרגיל 🤔'),
        content: Text(
          'המחיר שהזנת נראה ${low ? 'נמוך' : 'גבוה'} משמעותית מהשוק לגודל ולעיר '
          'הזו.\nטווח סביר: ${fmt(r.expectedLow)}–${fmt(r.expectedHigh)}.\n\n'
          'אולי נפלה טעות? אפשר לתקן, או להמשיך אם המחיר נכון.',
          style: const TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('חזרה לתיקון'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('המחיר נכון, המשך'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.navy,
          surfaceTintColor: Colors.transparent,
          leading: IconButton(
            icon: const RentlyIcon(IconsaxPlusLinear.arrow_right,
                color: Colors.white),
            onPressed: _prev,
          ),
          title: Text(
            _stepLabels[_step],
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(64),
            child: _StepIndicator(
              step: _step,
              total: 4,
              labels: _stepLabels,
            ),
          ),
        ),
        body: PageView(
          controller: _pageCtrl,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _StepLocation(
              cityCtrl: _cityCtrl,
              neighborhoodCtrl: _neighborhoodCtrl,
              streetCtrl: _streetCtrl,
              streetNumCtrl: _streetNumCtrl,
            ),
            _StepDetails(
              price: _price,
              transactionType: _transactionType,
              rooms: _rooms,
              cityCtrl: _cityCtrl,
              sizeCtrl: _sizeCtrl,
              floorCtrl: _floorCtrl,
              totalFloorsCtrl: _totalFloorsCtrl,
              entryDateCtrl: _entryDateCtrl,
              propertyType: _propertyType,
              condition: _condition,
              designTemplate: _designTemplate,
              designAccent: _designAccent,
              onTransactionTypeChanged: (v) => setState(() {
                _transactionType = v;
                // Keep the price within the sensible range for the new mode so a
                // 5,000 ₪ rent default doesn't read as a 5,000 ₪ sale.
                if (v == PropertyTransactionType.sale && _price < 100000) {
                  _price = 1500000;
                } else if (v == PropertyTransactionType.rent &&
                    _price > 50000) {
                  _price = 5000;
                }
              }),
              onPriceChanged: (v) =>
                  setState(() => _price = v.round()),
              onPriceSet: (v) => setState(() => _price = v),
              onRoomsChanged: (v) =>
                  setState(() => _rooms = (v * 2).round() / 2),
              onTypeChanged: (v) => setState(() => _propertyType = v!),
              onConditionChanged: (v) => setState(() => _condition = v!),
              onDesignTemplateChanged: (v) =>
                  setState(() => _designTemplate = v),
              onDesignAccentChanged: (v) => setState(() => _designAccent = v),
            ),
            _StepFeatures(
              allFeatures: _propertyFeatureLabels,
              selectedFeatures: _selectedFeatures,
              onToggle: (f) => setState(() {
                if (_selectedFeatures.contains(f)) {
                  _selectedFeatures.remove(f);
                } else {
                  _selectedFeatures.add(f);
                }
              }),
              publishChannels: _publishChannels,
              onChannelToggle: (c) => setState(() {
                if (_publishChannels.contains(c)) {
                  _publishChannels.remove(c);
                } else {
                  _publishChannels.add(c);
                }
              }),
            ),
            _StepPhotos(
              mediaDrafts: _mediaDrafts,
              virtualTourDraft: _virtualTourDraft,
              isSubmittingTour: _isSubmittingTour,
              scanTourDraft: _scanTourDraft,
              isScanSubmitting: _isScanSubmitting,
              isScanBackendConfigured: _scanService.isConfigured,
              wantsVerifiedListing: _wantsVerifiedListing,
              verificationVideoUrl: _verificationVideoUrl,
              verificationCapturedAt: _verificationCapturedAt,
              isCapturingVerification: _isCapturingVerification,
              onVerifiedListingChanged: _setVerifiedListingMode,
              onCaptureVerificationVideo: _captureVerificationVideo,
              onClearVerificationVideo: _clearVerificationVideo,
              onPickImageFromGallery: () =>
                  _pickPropertyImage(ImageSource.gallery),
              onPickImageFromCamera: () =>
                  _pickPropertyImage(ImageSource.camera),
              onPickVideoFromGallery: () =>
                  _pickPropertyVideo(ImageSource.gallery),
              onPickVideoFromCamera: () =>
                  _pickPropertyVideo(ImageSource.camera),
              onPickScanFromGallery: () => _pickScanVideo(ImageSource.gallery),
              onPickScanFromCamera: () => _pickScanVideo(ImageSource.camera),
              onOpenRoomScan: _openRoomScan,
              roomScanCount: _roomScans.length,
              onLinkScaniverse: ScaniverseService.instance.isConfigured
                  ? () => _linkScaniverseScan()
                  : null,
              onImportScaniverseAssets: _importScaniverseAssets,
              onClearVirtualTour: () => setState(() {
                _virtualTourDraft = null;
              }),
              onClearScan: () => setState(() {
                _scanTourDraft = null;
                _model3dDraft = null;
                _roomScans = const [];
              }),
              onCreatePanoramaTour: _createPanoramaTour,
              panoramaPointCount: _panoramaTourDraft?.length ?? 0,
              acceptedTerms: _acceptedPropertyTerms,
              onAcceptedTermsChanged: (value) =>
                  setState(() => _acceptedPropertyTerms = value),
              thirdPartyTransferAllowed: _thirdPartyTransferAllowed,
              onThirdPartyTransferChanged: (value) =>
                  setState(() => _thirdPartyTransferAllowed = value),
              commercialSaleAllowed: _commercialSaleAllowed,
              onCommercialSaleChanged: (value) =>
                  setState(() => _commercialSaleAllowed = value),
              aiTrainingAllowed: _aiTrainingAllowed,
              onAiTrainingChanged: (value) =>
                  setState(() => _aiTrainingAllowed = value),
              onAddMediaUrl: _assignPickedMedia,
              onRemoveMedia: (i) => setState(() {
                _mediaDrafts[i].dispose();
                _mediaDrafts.removeAt(i);
              }),
            ),
          ],
        ),
        bottomNavigationBar: _WizardNavBar(
          step: _step,
          total: 4,
          isLoading: _isSaving,
          onNext: _next,
          onPrev: _prev,
        ),
      ),
    );
  }
}

// ─── Step Indicator ───────────────────────────────────────────────────────────

class _StepIndicator extends StatelessWidget {
  const _StepIndicator(
      {required this.step, required this.total, required this.labels});
  final int step;
  final int total;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
      child: Row(
        children: List.generate(total * 2 - 1, (i) {
          if (i.isOdd) {
            final lineIdx = i ~/ 2;
            return Expanded(
              child: Container(
                height: 2,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: lineIdx < step
                      ? AppColors.primary
                      : Colors.white.withValues(alpha: 0.28),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            );
          }
          final idx = i ~/ 2;
          final isActive = idx == step;
          final isDone = idx < step;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: isDone
                      ? AppColors.primary
                      : (isActive ? Colors.white : Colors.transparent),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isDone || isActive
                        ? AppColors.primary
                        : Colors.white.withValues(alpha: 0.45),
                    width: 2,
                  ),
                ),
                child: Center(
                  child: isDone
                      ? const Icon(Icons.check_rounded,
                          color: Colors.white, size: 14)
                      : Text(
                          '${idx + 1}',
                          style: TextStyle(
                            color: isActive
                                ? AppColors.navy
                                : Colors.white.withValues(alpha: 0.7),
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                labels[idx],
                style: TextStyle(
                  fontSize: 9,
                  color: isActive || isDone
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.5),
                  fontWeight: isActive ? FontWeight.w800 : FontWeight.w500,
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}

// ─── Wizard Nav Bar ───────────────────────────────────────────────────────────

// ─── Wizard Nav Bar ───────────────────────────────────────────────────────────

class _WizardNavBar extends StatelessWidget {
  const _WizardNavBar({
    required this.step,
    required this.total,
    required this.isLoading,
    required this.onNext,
    required this.onPrev,
    this.saveLabel,
  });
  final int step;
  final int total;
  final bool isLoading;
  final VoidCallback onNext;
  final VoidCallback onPrev;
  final String? saveLabel;

  @override
  Widget build(BuildContext context) {
    final isLast = step == total - 1;
    return Container(
      // Lift the submit/"הוספה" button ~15px higher above the home indicator
      // while staying SafeArea-aware (bottom inset is still added in).
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, 27 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(
          top: BorderSide(color: Color(0xFFF0F3F6), width: 1.5),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          if (step > 0) ...[
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onPrev,
                icon: const RentlyIcon(IconsaxPlusLinear.arrow_right, size: 16, color: AppColors.navy),
                label: const Text('חזרה'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.navy,
                  side: const BorderSide(color: Color(0xFFE2E8F0), width: 1.5),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            flex: step > 0 ? 2 : 1,
            child: FilledButton.icon(
              onPressed: isLoading ? null : onNext,
              icon: isLoading
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Icon(isLast ? IconsaxPlusLinear.add_square : null,
                      size: 16),
              label: Text(isLoading
                  ? 'שומר...'
                  : (isLast ? (saveLabel ?? 'פרסום הדירה') : 'הבא →')),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor:
                    AppColors.primary.withValues(alpha: 0.5),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Edit Property Footer ─────────────────────────────────────────────────────

class _EditPropertyFooter extends StatelessWidget {
  const _EditPropertyFooter({
    required this.step,
    required this.total,
    required this.isLoading,
    required this.onNext,
    required this.onPrev,
    required this.isActive,
    required this.onActiveChanged,
    required this.onDelete,
    required this.transactionType,
    this.saveLabel,
  });

  final int step;
  final int total;
  final bool isLoading;
  final VoidCallback onNext;
  final VoidCallback onPrev;
  final bool isActive;
  final ValueChanged<bool> onActiveChanged;
  final VoidCallback onDelete;
  final PropertyTransactionType transactionType;
  final String? saveLabel;

  @override
  Widget build(BuildContext context) {
    final isLast = step == total - 1;
    final isSale = transactionType == PropertyTransactionType.sale;
    final activeLabel = isSale ? 'עדיין למכירה' : 'עדיין להשכרה';
    final inactiveLabel = isSale ? 'לא למכירה / נמכר' : 'לא להשכרה / הושכר';

    return Container(
      // Lift the submit button ~15px higher (SafeArea-aware).
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, 27 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(
          top: BorderSide(color: Color(0xFFF0F3F6), width: 1.5),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Row 1: Active status Switch + Delete button
          Row(
            children: [
              Icon(
                isActive
                    ? Icons.check_circle_outline_rounded
                    : Icons.pause_circle_outline_rounded,
                color: isActive ? AppColors.success : AppColors.textSecondary,
                size: 20,
              ),
              const SizedBox(width: 6),
              Text(
                isActive ? activeLabel : inactiveLabel,
                style: TextStyle(
                  color: isActive ? AppColors.success : AppColors.textSecondary,
                  fontWeight: FontWeight.w800,
                  fontSize: 13.5,
                ),
              ),
              const SizedBox(width: 8),
              Theme(
                data: ThemeData(
                  useMaterial3: true,
                ).copyWith(
                  colorScheme: ColorScheme.fromSeed(seedColor: AppColors.success),
                ),
                child: Switch(
                  value: isActive,
                  onChanged: onActiveChanged,
                  activeThumbColor: AppColors.success,
                  activeTrackColor: AppColors.success.withValues(alpha: 0.2),
                  inactiveThumbColor: AppColors.textSecondary,
                  inactiveTrackColor: const Color(0xFFE2E8F0),
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: onDelete,
                icon: const RentlyIcon(IconsaxPlusLinear.trash,
                    color: AppColors.coral, size: 16),
                label: const Text(
                  'מחיקת נכס',
                  style: TextStyle(
                    color: AppColors.coral,
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Divider(color: Color(0xFFEDF2F7), height: 1, thickness: 1),
          const SizedBox(height: 10),
          // Row 2: Navigation buttons
          Row(
            children: [
              if (step > 0) ...[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onPrev,
                    icon: const RentlyIcon(IconsaxPlusLinear.arrow_right, size: 16, color: AppColors.navy),
                    label: const Text('חזרה'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.navy,
                      side: const BorderSide(color: Color(0xFFE2E8F0), width: 1.5),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                flex: step > 0 ? 2 : 1,
                child: FilledButton.icon(
                  onPressed: isLoading ? null : onNext,
                  icon: isLoading
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Icon(isLast ? IconsaxPlusLinear.add_square : null,
                          size: 16),
                  label: Text(isLoading
                      ? 'שומר...'
                      : (isLast ? (saveLabel ?? 'פרסום הדירה') : 'הבא →')),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor:
                        AppColors.primary.withValues(alpha: 0.5),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Step 1: Location ─────────────────────────────────────────────────────────

class _StepLocation extends StatefulWidget {
  const _StepLocation({
    required this.cityCtrl,
    required this.neighborhoodCtrl,
    required this.streetCtrl,
    required this.streetNumCtrl,
  });

  final TextEditingController cityCtrl;
  final TextEditingController neighborhoodCtrl;
  final TextEditingController streetCtrl;
  final TextEditingController streetNumCtrl;

  @override
  State<_StepLocation> createState() => _StepLocationState();
}

class _StepLocationState extends State<_StepLocation> {
  bool _isLoading = false;
  bool _locationsReady = false;

  @override
  void initState() {
    super.initState();
    // Lazy-load the bundled Israel cities/streets dataset once so the
    // autocomplete fields below can suggest as the landlord types.
    IsraelLocations.ensureLoaded().then((_) {
      if (mounted) setState(() => _locationsReady = true);
    });
  }

  /// Shows a clear Hebrew error. When [offerSettings] is true the snackbar
  /// gains a button that opens the OS app-settings page so an (older) user can
  /// grant the blocked permission without hunting through Settings themselves.
  void _showLocationError(String message, {bool offerSettings = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 5),
        content: Text(message),
        backgroundColor: AppColors.coral,
        action: offerSettings
            ? SnackBarAction(
                label: 'פתח הגדרות',
                textColor: Colors.white,
                onPressed: () => Geolocator.openAppSettings(),
              )
            : null,
      ),
    );
  }

  Future<void> _captureLocation() async {
    setState(() => _isLoading = true);
    try {
      final bool serviceEnabled =
          await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showLocationError(
          'שירותי המיקום כבויים. אנא הפעל את ה-GPS במכשיר ונסה שוב.',
          offerSettings: true,
        );
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        _showLocationError(
          'הרשאת המיקום נדחתה. ניתן להזין את הכתובת ידנית.',
        );
        return;
      }
      if (permission == LocationPermission.deniedForever) {
        _showLocationError(
          'הרשאות המיקום חסומות בהגדרות. פתח את ההגדרות כדי לאפשר גישה למיקום.',
          offerSettings: true,
        );
        return;
      }

      // Try a fresh fix first; a cold GPS start (especially indoors) can take
      // a while, so on timeout we fall back to the last known position rather
      // than dead-ending the user.
      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 20),
          ),
        );
      } on TimeoutException {
        position = await Geolocator.getLastKnownPosition();
      } catch (_) {
        position = await Geolocator.getLastKnownPosition();
      }

      if (position == null) {
        _showLocationError(
          'לא הצלחנו לקבל מיקום (ייתכן שאתה במקום סגור). נסה שוב בחוץ או הזן כתובת ידנית.',
        );
        return;
      }

      // Reverse-geocode to a human address. This can legitimately return
      // nothing (offline / unsupported region) — that is not a failure: we
      // still have valid coordinates, so we just ask the user to type the
      // street manually instead of throwing.
      List<Placemark> placemarks = const [];
      try {
        await setLocaleIdentifier('he_IL');
        placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );
      } catch (_) {
        placemarks = const [];
      }

      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        setState(() {
          widget.cityCtrl.text =
              place.locality ?? place.subAdministrativeArea ?? '';
          widget.neighborhoodCtrl.text = place.subLocality ?? '';
          widget.streetCtrl.text = place.thoroughfare ?? '';
          widget.streetNumCtrl.text = place.subThoroughfare ?? '';
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              duration: Duration(milliseconds: 2500),
              content: Text('המיקום זוהה והוזן בהצלחה!'),
              backgroundColor: AppColors.success,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              duration: const Duration(seconds: 4),
              content: const Text(
                'מצאנו את המיקום אך לא את הכתובת המדויקת. אנא הזן את הרחוב ידנית.',
              ),
              backgroundColor: AppColors.primary,
            ),
          );
        }
      }
    } catch (e) {
      _showLocationError('שגיאה בזיהוי המיקום. נסה שוב או הזן כתובת ידנית.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 130),
      children: [
        _SectionHint(
          icon: IconsaxPlusLinear.location,
          title: 'איפה נמצאת הדירה?',
          subtitle: 'מלא עיר ורחוב לפחות',
        ),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: _isLoading ? null : _captureLocation,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary.withValues(alpha: 0.1),
            foregroundColor: AppColors.primary,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: AppColors.primary, width: 1),
            ),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          icon: _isLoading
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primary,
                  ),
                )
              : const RentlyIcon(IconsaxPlusLinear.gps, size: 18),
          label: Text(
            _isLoading ? 'מזהה מיקום...' : 'זהה מיקום אוטומטית לפי ה-GPS',
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13.5,
            ),
          ),
        ),
        const SizedBox(height: 16),
        _FormCard(
          child: Column(
            children: [
              _AutocompleteField(
                ctrl: widget.cityCtrl,
                label: 'עיר *',
                icon: IconsaxPlusLinear.map,
                enabled: _locationsReady,
                optionsBuilder: (query) =>
                    IsraelLocations.searchCities(query, limit: 30),
                onSelected: (_) {
                  // A new city was picked — any previously typed street no longer
                  // belongs to it, so clear it and refresh the street suggestions.
                  widget.streetCtrl.clear();
                  setState(() {});
                },
              ),
              const SizedBox(height: 12),
              _Field(
                  ctrl: widget.neighborhoodCtrl,
                  label: 'שכונה (אופציונלי)',
                  icon: IconsaxPlusLinear.map_1),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: _AutocompleteField(
                      ctrl: widget.streetCtrl,
                      label: 'רחוב *',
                      icon: IconsaxPlusLinear.routing,
                      enabled: _locationsReady,
                      optionsBuilder: (query) => IsraelLocations.streetsOf(
                        widget.cityCtrl.text.trim(),
                        query: query,
                        limit: 30,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _Field(
                      ctrl: widget.streetNumCtrl,
                      label: 'מספר',
                      icon: IconsaxPlusLinear.hashtag,
                      numeric: true,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Rent / Sale toggle ───────────────────────────────────────────────────────

class _TransactionTypeToggle extends StatelessWidget {
  const _TransactionTypeToggle({
    required this.value,
    required this.onChanged,
  });

  final PropertyTransactionType value;
  final ValueChanged<PropertyTransactionType> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F3F6),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          _segment(
            label: 'להשכרה',
            icon: IconsaxPlusLinear.key,
            selected: value == PropertyTransactionType.rent,
            onTap: () => onChanged(PropertyTransactionType.rent),
          ),
          _segment(
            label: 'למכירה',
            icon: IconsaxPlusLinear.tag,
            selected: value == PropertyTransactionType.sale,
            onTap: () => onChanged(PropertyTransactionType.sale),
          ),
        ],
      ),
    );
  }

  Widget _segment({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              RentlyIcon(
                icon,
                size: 17,
                color: selected ? Colors.white : AppColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : AppColors.textSecondary,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Step 2: Property Details ─────────────────────────────────────────────────

class _StepDetails extends StatelessWidget {
  const _StepDetails({
    required this.price,
    required this.transactionType,
    required this.rooms,
    required this.cityCtrl,
    required this.sizeCtrl,
    required this.floorCtrl,
    required this.totalFloorsCtrl,
    required this.entryDateCtrl,
    required this.propertyType,
    required this.condition,
    required this.designTemplate,
    required this.designAccent,
    required this.onTransactionTypeChanged,
    required this.onPriceChanged,
    required this.onPriceSet,
    required this.onRoomsChanged,
    required this.onTypeChanged,
    required this.onConditionChanged,
    required this.onDesignTemplateChanged,
    required this.onDesignAccentChanged,
  });

  final int price;
  final PropertyTransactionType transactionType;
  final double rooms;
  final TextEditingController cityCtrl;
  final TextEditingController sizeCtrl;
  final TextEditingController floorCtrl;
  final TextEditingController totalFloorsCtrl;
  final TextEditingController entryDateCtrl;
  final String propertyType;
  final String condition;
  final String designTemplate;
  final int designAccent;
  final ValueChanged<PropertyTransactionType> onTransactionTypeChanged;
  final ValueChanged<double> onPriceChanged;
  // Sets the price directly to a specific value (e.g. the recommended rent).
  final ValueChanged<int> onPriceSet;
  final ValueChanged<double> onRoomsChanged;
  final ValueChanged<String?> onTypeChanged;
  final ValueChanged<String?> onConditionChanged;
  final ValueChanged<String> onDesignTemplateChanged;
  final ValueChanged<int> onDesignAccentChanged;

  @override
  Widget build(BuildContext context) {
    final isSale = transactionType == PropertyTransactionType.sale;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 130),
      children: [
        _SectionHint(
          icon: IconsaxPlusLinear.building,
          title: 'פרטי הנכס',
          subtitle: 'גודל הדירה הוא שדה חובה',
        ),
        const SizedBox(height: 16),
        _TransactionTypeToggle(
          value: transactionType,
          onChanged: onTransactionTypeChanged,
        ),
        const SizedBox(height: 16),
        _FormCard(
          child: Column(
            children: [
              _SliderWithEntry(
                // For a sale the price is a one-time total; for rent it's
                // monthly. Label + range follow the selected mode.
                label: isSale ? 'מחיר מבוקש (סה"כ)' : 'מחיר לחודש',
                value: price.toDouble(),
                min: 0,
                max: isSale ? _kMaxSalePrice.toDouble() : 50000,
                divisions: isSale ? 400 : 100,
                unitPrefix: '₪',
                onChanged: onPriceChanged,
              ),
              // Fair-rent guidance (rent only). Listens to the city/size fields
              // so the recommendation updates live as the landlord types; hides
              // itself whenever the market model can't price the listing.
              if (!isSale)
                ListenableBuilder(
                  listenable: Listenable.merge([cityCtrl, sizeCtrl]),
                  builder: (context, _) => FairRentHint(
                    city: cityCtrl.text,
                    sizeM2: int.tryParse(sizeCtrl.text.trim()) ?? 0,
                    rooms: rooms,
                    transactionType: transactionType,
                    typedPrice: price,
                    onUseRecommended: onPriceSet,
                  ),
                ),
              const SizedBox(height: 10),
              _SliderWithEntry(
                label: 'מספר חדרים',
                value: rooms,
                min: 0,
                max: 15,
                divisions: 30,
                unitSuffix: 'חד׳',
                allowDecimals: true,
                onChanged: onRoomsChanged,
              ),
              const SizedBox(height: 14),
              _Field(
                ctrl: sizeCtrl,
                label: 'גודל הנכס במ"ר *',
                icon: IconsaxPlusLinear.maximize_3,
                numeric: true,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _FloorDropdown(ctrl: floorCtrl),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _Field(
                      ctrl: totalFloorsCtrl,
                      label: 'סה"כ קומות',
                      icon: IconsaxPlusLinear.buildings,
                      numeric: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _DropdownRow(
                label: 'סוג נכס',
                value: propertyType,
                options: const [
                  'דירה',
                  'דירת גג',
                  'דירת גן',
                  'סטודיו',
                  'קוטג׳',
                  'בית פרטי',
                ],
                onChanged: onTypeChanged,
              ),
              const SizedBox(height: 10),
              _DropdownRow(
                label: 'מצב הנכס',
                value: condition,
                options: const ['חדש מקבלן', 'משופץ', 'תקין', 'ישן'],
                onChanged: onConditionChanged,
              ),
              const SizedBox(height: 12),
              _EntryDatePicker(ctrl: entryDateCtrl),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _DesignTemplatePicker(
          selectedTemplate: designTemplate,
          accent: designAccent,
          onTemplateChanged: onDesignTemplateChanged,
          onAccentChanged: onDesignAccentChanged,
        ),
      ],
    );
  }
}

// ─── Step 3: Features ─────────────────────────────────────────────────────────

class _StepFeatures extends StatelessWidget {
  const _StepFeatures({
    required this.allFeatures,
    required this.selectedFeatures,
    required this.onToggle,
    required this.publishChannels,
    required this.onChannelToggle,
  });
  final List<String> allFeatures;
  final Set<String> selectedFeatures;
  final ValueChanged<String> onToggle;
  final Set<String> publishChannels;
  final ValueChanged<String> onChannelToggle;

  IconData _getFeatureIcon(String label) {
    switch (label) {
      case 'מרפסת':
        return Icons.balcony;
      case 'חניה':
        return Icons.local_parking;
      case 'מחסן':
        return Icons.inventory_2_outlined;
      case 'מזגן':
        return Icons.ac_unit;
      case 'ממ"ד':
        return Icons.gpp_good_outlined;
      case 'מרפסת שמש':
        return Icons.wb_sunny_outlined;
      case 'גינה':
        return Icons.yard_outlined;
      case 'מעלית':
        return Icons.elevator;
      case 'ריהוט':
        return Icons.chair_outlined;
      case 'אינטרנט כלול':
        return Icons.wifi;
      case 'מטבח מאובזר':
        return Icons.countertops_outlined;
      case 'חיות מחמד מותר':
        return Icons.pets;
      case 'כביסה כלולה':
        return Icons.local_laundry_service_outlined;
      case 'שומר/אבטחה':
        return Icons.security;
      case 'נגישות לנכים':
        return Icons.accessible;
      case 'גג משותף':
        return Icons.roofing;
      case 'בריכה':
        return Icons.pool;
      case 'חדר כושר':
        return Icons.fitness_center;
      case 'סורגים':
        return Icons.grid_3x3;
      case 'משופצת':
        return Icons.build_circle_outlined;
      case 'מתאימה לשותפים':
        return Icons.group_outlined;
      case 'מקלט':
        return Icons.shield_outlined;
      case 'מרחב מוגן קומתי':
        return Icons.domain_disabled;
      case 'מרתף':
        return Icons.foundation;
      case 'חימום מרכזי':
        return Icons.local_fire_department_outlined;
      case 'מזגן בחדרי שינה':
        return Icons.bedroom_parent;
      case 'מכונת כביסה':
        return Icons.local_laundry_service;
      case 'מקרר':
        return Icons.kitchen;
      case 'תנור':
        return Icons.restaurant_outlined;
      case 'מדיח כלים':
        return Icons.dining_outlined;
      case 'בקרה חכמה בבית':
        return Icons.home;
      case 'חניה תת קרקעית':
        return Icons.terrain;
      case 'מערכת סאונד':
        return Icons.speaker_group_outlined;
      case 'כניסה פרטית':
        return Icons.meeting_room;
      default:
        return Icons.star_border;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 130),
      children: [
        _SectionHint(
          icon: IconsaxPlusLinear.star,
          title: 'מאפיינים ויתרונות',
          subtitle: 'בחר את כל המאפיינים הרלוונטיים',
        ),
        const SizedBox(height: 16),
        _FormCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (selectedFeatures.isNotEmpty)
                    Text(
                      '${selectedFeatures.length} נבחרו מתוך ${allFeatures.length}',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    )
                  else
                    Text(
                      'בחר מאפיינים (${allFeatures.length} אפשרויות)',
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  if (selectedFeatures.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${(selectedFeatures.length / allFeatures.length * 100).toStringAsFixed(0)}%',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 10,
                children: allFeatures.map((f) {
                  final selected = selectedFeatures.contains(f);
                  return GestureDetector(
                    onTap: () => onToggle(f),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 9),
                      decoration: BoxDecoration(
                        color:
                            selected ? AppColors.primary : AppColors.background,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: selected
                              ? AppColors.primary
                              : AppColors.borderLight,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _getFeatureIcon(f),
                            size: 16,
                            color: selected ? Colors.white : AppColors.textSecondary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            f,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color:
                                  selected ? Colors.white : AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _SectionHint(
          icon: IconsaxPlusLinear.export_3,
          title: 'ערוצי פרסום',
          subtitle: 'איפה הנכס מפורסם? (Rently מסומן כברירת מחדל)',
        ),
        const SizedBox(height: 12),
        _FormCard(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final ch in const [
                ('rently', 'Rently'),
                ('yad2', 'יד2'),
                ('madlan', 'מדלן'),
                ('facebook', 'פייסבוק'),
                ('komo', 'קומו'),
              ])
                FilterChip(
                  selected: publishChannels.contains(ch.$1),
                  onSelected: (_) => onChannelToggle(ch.$1),
                  label: Text(ch.$2),
                  labelStyle: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: publishChannels.contains(ch.$1)
                        ? Colors.white
                        : AppColors.textSecondary,
                  ),
                  selectedColor: AppColors.primary,
                  backgroundColor: AppColors.background,
                  checkmarkColor: Colors.white,
                  side: BorderSide(color: AppColors.borderLight),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Step 4: Photos ───────────────────────────────────────────────────────────

class _StepPhotos extends StatelessWidget {
  const _StepPhotos({
    required this.mediaDrafts,
    required this.virtualTourDraft,
    required this.isSubmittingTour,
    required this.scanTourDraft,
    required this.isScanSubmitting,
    required this.isScanBackendConfigured,
    required this.wantsVerifiedListing,
    required this.verificationVideoUrl,
    required this.verificationCapturedAt,
    required this.isCapturingVerification,
    required this.onVerifiedListingChanged,
    required this.onCaptureVerificationVideo,
    required this.onClearVerificationVideo,
    required this.onPickImageFromGallery,
    required this.onPickImageFromCamera,
    required this.onPickVideoFromGallery,
    required this.onPickVideoFromCamera,
    required this.onPickScanFromGallery,
    required this.onPickScanFromCamera,
    this.onOpenRoomScan,
    this.roomScanCount = 0,
    this.onLinkScaniverse,
    required this.onImportScaniverseAssets,
    required this.onClearVirtualTour,
    required this.onClearScan,
    this.onCreatePanoramaTour,
    this.panoramaPointCount = 0,
    required this.acceptedTerms,
    required this.onAcceptedTermsChanged,
    required this.thirdPartyTransferAllowed,
    required this.onThirdPartyTransferChanged,
    required this.commercialSaleAllowed,
    required this.onCommercialSaleChanged,
    required this.aiTrainingAllowed,
    required this.onAiTrainingChanged,
    required this.onAddMediaUrl,
    required this.onRemoveMedia,
  });
  final List<_PropertyMediaDraft> mediaDrafts;
  final PropertyVirtualTour? virtualTourDraft;
  final bool isSubmittingTour;
  final PropertyVirtualTour? scanTourDraft;
  final bool isScanSubmitting;
  final bool isScanBackendConfigured;
  final bool wantsVerifiedListing;
  final String verificationVideoUrl;
  final DateTime? verificationCapturedAt;
  final bool isCapturingVerification;
  final ValueChanged<bool> onVerifiedListingChanged;
  final VoidCallback onCaptureVerificationVideo;
  final VoidCallback onClearVerificationVideo;
  final VoidCallback onPickImageFromGallery;
  final VoidCallback onPickImageFromCamera;
  final VoidCallback onPickVideoFromGallery;
  final VoidCallback onPickVideoFromCamera;
  final VoidCallback onPickScanFromGallery;
  final VoidCallback onPickScanFromCamera;
  final VoidCallback? onOpenRoomScan;
  final int roomScanCount;
  final VoidCallback? onLinkScaniverse;
  final VoidCallback onImportScaniverseAssets;
  final VoidCallback onClearVirtualTour;
  final VoidCallback onClearScan;
  final VoidCallback? onCreatePanoramaTour;
  final int panoramaPointCount;
  final bool acceptedTerms;
  final ValueChanged<bool> onAcceptedTermsChanged;
  final bool thirdPartyTransferAllowed;
  final ValueChanged<bool> onThirdPartyTransferChanged;
  final bool commercialSaleAllowed;
  final ValueChanged<bool> onCommercialSaleChanged;
  final bool aiTrainingAllowed;
  final ValueChanged<bool> onAiTrainingChanged;
  final void Function(String url, PropertyMediaType type) onAddMediaUrl;
  final ValueChanged<int> onRemoveMedia;

  void _showMediaPickerSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      backgroundColor: Colors.white,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: AppColors.borderLight,
                    borderRadius: BorderRadius.circular(2.5),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'הוספת תמונה או סרטון',
                  style: TextStyle(
                    color: AppColors.navy,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 20),
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 2.2,
                  children: [
                    _PickerOptionButton(
                      icon: IconsaxPlusLinear.gallery,
                      label: 'תמונה מהגלריה',
                      onTap: () {
                        Navigator.pop(ctx);
                        onPickImageFromGallery();
                      },
                    ),
                    _PickerOptionButton(
                      icon: IconsaxPlusLinear.camera,
                      label: 'צלם תמונה',
                      onTap: () {
                        Navigator.pop(ctx);
                        onPickImageFromCamera();
                      },
                    ),
                    _PickerOptionButton(
                      icon: IconsaxPlusLinear.video,
                      label: 'וידאו מהגלריה',
                      onTap: () {
                        Navigator.pop(ctx);
                        onPickVideoFromGallery();
                      },
                    ),
                    _PickerOptionButton(
                      icon: IconsaxPlusLinear.video_play,
                      label: 'צלם וידאו',
                      onTap: () {
                        Navigator.pop(ctx);
                        onPickVideoFromCamera();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _PickerOptionButton(
                  icon: IconsaxPlusLinear.link,
                  label: 'הזן קישור ידנית (URL)',
                  isFullWidth: true,
                  onTap: () {
                    Navigator.pop(ctx);
                    _showUrlInputDialog(context);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showUrlInputDialog(BuildContext context) {
    final ctrl = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Text(
            'הוספת קישור למדיה',
            style: TextStyle(
              color: AppColors.navy,
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'הדבק כתובת URL של תמונה או וידאו',
              hintStyle:
                  const TextStyle(color: AppColors.textSecondary, fontSize: 13),
              filled: true,
              fillColor: AppColors.background,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.borderLight),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('ביטול',
                  style: TextStyle(color: AppColors.textSecondary)),
            ),
            FilledButton(
              onPressed: () {
                final url = ctrl.text.trim();
                if (url.isNotEmpty) {
                  final isVideo = url.toLowerCase().contains('.mp4') ||
                      url.toLowerCase().contains('.mov') ||
                      url.toLowerCase().contains('.avi') ||
                      url.toLowerCase().contains('.m3u8');
                  onAddMediaUrl(
                    url,
                    isVideo ? PropertyMediaType.video : PropertyMediaType.image,
                  );
                }
                Navigator.pop(ctx);
              },
              child: const Text('הוסף'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 130),
      children: [
        _SectionHint(
          icon: wantsVerifiedListing
              ? IconsaxPlusLinear.verify
              : IconsaxPlusLinear.gallery,
          title: wantsVerifiedListing ? 'דירה מאומתת' : 'תמונות וסרטונים',
          subtitle: wantsVerifiedListing
              ? 'אימות דורש צילום וידאו מתוך האפליקציה בלבד'
              : 'העלה תמונות וסרטונים המראים את הדירה במיטבה',
        ),
        const SizedBox(height: 16),
        _FormCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _VerifiedListingPanel(
                wantsVerifiedListing: wantsVerifiedListing,
                verificationVideoUrl: verificationVideoUrl,
                verificationCapturedAt: verificationCapturedAt,
                isCapturingVerification: isCapturingVerification,
                onChanged: onVerifiedListingChanged,
                onCaptureVideo: onCaptureVerificationVideo,
                onClearVideo: onClearVerificationVideo,
              ),
              if (wantsVerifiedListing) ...[
                const SizedBox(height: 16),
                const _VerifiedMediaLockNotice(),
              ] else ...[
                const SizedBox(height: 18),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 1.1,
                  ),
                  itemCount: mediaDrafts.length +
                      (mediaDrafts.length < 10 &&
                              (mediaDrafts.isEmpty ||
                                  mediaDrafts.last.controller.text
                                      .trim()
                                      .isNotEmpty)
                          ? 1
                          : 0),
                  itemBuilder: (context, i) {
                    if (i == mediaDrafts.length) {
                      return _MediaGridItem(
                        index: i,
                        draft: _PropertyMediaDraft(),
                        onRemove: () {},
                        onTapEmpty: () => _showMediaPickerSheet(context),
                      );
                    }
                    return _MediaGridItem(
                      index: i,
                      draft: mediaDrafts[i],
                      onRemove: () => onRemoveMedia(i),
                      onTapEmpty: () => _showMediaPickerSheet(context),
                    );
                  },
                ),
              ],
              // The per-room 3D scan tool is ALWAYS available, independent of
              // verified mode. "דירה מאומתת" only locks the PHOTO media (to force
              // an in-app verification video); it must NOT hide the separate 3D
              // room-scan tool. So _Scan3dPanel renders in BOTH verified and
              // non-verified states.
              const SizedBox(height: 18),
              const Divider(height: 1, color: AppColors.borderLight),
              const SizedBox(height: 16),
              // PRIMARY, RECOMMENDED apartment tour: the faithful 360° panorama
              // (built from real iPhone panoramas). Shown first + prominent.
              if (onCreatePanoramaTour != null) ...[
                _Panorama360Tile(
                  count: panoramaPointCount,
                  onTap: onCreatePanoramaTour!,
                ),
                const SizedBox(height: 16),
              ],
              // SECONDARY, "מתקדם" option: casual-video 3D Gaussian-splat scan.
              // Smaller, clearly labeled, after the recommended 360° tour.
              _Scan3dPanel(
                tour: scanTourDraft,
                isSubmitting: isScanSubmitting,
                isBackendConfigured: isScanBackendConfigured,
                onPickFromCamera: onPickScanFromCamera,
                onPickFromGallery: onPickScanFromGallery,
                onOpenRoomScan: onOpenRoomScan,
                roomScanCount: roomScanCount,
                onLinkScaniverse: onLinkScaniverse,
                onImportScaniverseAssets: onImportScaniverseAssets,
                onClear: onClearScan,
              ),
              const SizedBox(height: 16),
              _PropertyRightsPanel(
                acceptedTerms: acceptedTerms,
                onAcceptedTermsChanged: onAcceptedTermsChanged,
                thirdPartyTransferAllowed: thirdPartyTransferAllowed,
                onThirdPartyTransferChanged: onThirdPartyTransferChanged,
                commercialSaleAllowed: commercialSaleAllowed,
                onCommercialSaleChanged: onCommercialSaleChanged,
                aiTrainingAllowed: aiTrainingAllowed,
                onAiTrainingChanged: onAiTrainingChanged,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _VerifiedListingPanel extends StatelessWidget {
  const _VerifiedListingPanel({
    required this.wantsVerifiedListing,
    required this.verificationVideoUrl,
    required this.verificationCapturedAt,
    required this.isCapturingVerification,
    required this.onChanged,
    required this.onCaptureVideo,
    required this.onClearVideo,
  });

  final bool wantsVerifiedListing;
  final String verificationVideoUrl;
  final DateTime? verificationCapturedAt;
  final bool isCapturingVerification;
  final ValueChanged<bool> onChanged;
  final VoidCallback onCaptureVideo;
  final VoidCallback onClearVideo;

  @override
  Widget build(BuildContext context) {
    final hasVideo = verificationVideoUrl.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: RentlyIcon(
                  IconsaxPlusLinear.verify,
                  color: AppColors.primary,
                  size: 19,
                ),
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'פרסום דירה מאומתת',
                    style: TextStyle(
                      color: AppColors.navy,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  SizedBox(height: 3),
                  Text(
                    'דירה מאומתת היא דירה שצילמתם בה סרטון קצר ואמיתי מתוך '
                    'האפליקציה. ככה השוכרים יודעים שהדירה אמיתית — והיא מוצגת '
                    'ליותר אנשים ומופיעה גבוה יותר ברשימה.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12.5,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            Switch.adaptive(
              value: wantsVerifiedListing,
              onChanged: isCapturingVerification ? null : onChanged,
            ),
          ],
        ),
        if (wantsVerifiedListing) ...[
          const SizedBox(height: 14),
          Text(
            hasVideo
                ? 'וידאו האימות נשמר מתוך המצלמה של האפליקציה.'
                : 'כדי לאמת את הדירה צריך לצלם עכשיו וידאו קצר מתוך האפליקציה.',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          if (hasVideo)
            _VerificationVideoPreview(
              videoUrl: verificationVideoUrl,
              capturedAt: verificationCapturedAt,
              isCapturing: isCapturingVerification,
              onReplace: onCaptureVideo,
              onClear: onClearVideo,
            )
          else
            FilledButton.icon(
              onPressed: isCapturingVerification ? null : onCaptureVideo,
              icon: isCapturingVerification
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const RentlyIcon(IconsaxPlusLinear.video_play, size: 17),
              label: Text(
                isCapturingVerification ? 'פותח מצלמה...' : 'צלם וידאו אימות',
              ),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _VerificationVideoPreview extends StatelessWidget {
  const _VerificationVideoPreview({
    required this.videoUrl,
    required this.capturedAt,
    required this.isCapturing,
    required this.onReplace,
    required this.onClear,
  });

  final String videoUrl;
  final DateTime? capturedAt;
  final bool isCapturing;
  final VoidCallback onReplace;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final capturedLabel = capturedAt == null
        ? ''
        : capturedAt!.toLocal().toString().split('.').first;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFD),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE0EBF2)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 86,
              height: 64,
              child: SafeMedia(
                media: PropertyMedia(
                  url: videoUrl,
                  type: PropertyMediaType.video,
                ),
                fit: BoxFit.cover,
                videoMode: SafeVideoDisplayMode.iconOnly,
                fallback: Container(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  child: Center(
                    child: RentlyIcon(
                      IconsaxPlusLinear.video_tick,
                      color: AppColors.primary,
                      size: 24,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'וידאו אימות מוכן',
                  style: TextStyle(
                    color: AppColors.navy,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (capturedLabel.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    capturedLabel,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11.5,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: isCapturing ? null : onReplace,
                      icon:
                          const RentlyIcon(IconsaxPlusLinear.refresh, size: 14),
                      label: const Text('צלם מחדש'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.navy,
                        side: const BorderSide(color: AppColors.borderLight),
                        textStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: isCapturing ? null : onClear,
                      icon: const Icon(Icons.close, color: AppColors.coral),
                      tooltip: 'הסר וידאו אימות',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VerifiedMediaLockNotice extends StatelessWidget {
  const _VerifiedMediaLockNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RentlyIcon(
            IconsaxPlusLinear.lock,
            color: AppColors.primary,
            size: 18,
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'בפרסום מאומת אין העלאה מהגלריה, קישור URL, תמונות או וידאו קיים. וידאו האימות המצולם הוא המדיה היחידה של הדירה.',
              style: TextStyle(
                color: AppColors.navy,
                fontSize: 12.5,
                height: 1.35,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PropertyRightsPanel extends StatelessWidget {
  const _PropertyRightsPanel({
    required this.acceptedTerms,
    required this.onAcceptedTermsChanged,
    required this.thirdPartyTransferAllowed,
    required this.onThirdPartyTransferChanged,
    required this.commercialSaleAllowed,
    required this.onCommercialSaleChanged,
    required this.aiTrainingAllowed,
    required this.onAiTrainingChanged,
  });

  final bool acceptedTerms;
  final ValueChanged<bool> onAcceptedTermsChanged;
  final bool thirdPartyTransferAllowed;
  final ValueChanged<bool> onThirdPartyTransferChanged;
  final bool commercialSaleAllowed;
  final ValueChanged<bool> onCommercialSaleChanged;
  final bool aiTrainingAllowed;
  final ValueChanged<bool> onAiTrainingChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'זכויות שימוש והסכמה',
          style: TextStyle(
            color: AppColors.navy,
            fontSize: 15,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'אשר/י שהמדיה והמודל שייכים לך או הועלו ברשות, ובחר/י אילו שימושים מותרים.',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.borderLight),
          ),
          child: Column(
            children: [
              CheckboxListTile(
                value: acceptedTerms,
                onChanged: (value) => onAcceptedTermsChanged(value ?? false),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text(
                  'אני מאשר/ת תנאי שימוש, זכויות העלאה וחתימה דיגיטלית לנכס זה',
                  style: TextStyle(
                    color: AppColors.navy,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Divider(height: 1, color: AppColors.borderLight),
              SwitchListTile(
                value: thirdPartyTransferAllowed,
                onChanged: onThirdPartyTransferChanged,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                title: const Text('מותר להעביר את המידע לצד שלישי'),
              ),
              SwitchListTile(
                value: commercialSaleAllowed,
                onChanged: onCommercialSaleChanged,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                title: const Text('מותר שימוש מסחרי ומכירה עסקית של המידע'),
              ),
              SwitchListTile(
                value: aiTrainingAllowed,
                onChanged: onAiTrainingChanged,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                title: const Text('מותר שימוש לאימון מודלים ו-AI'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MediaGridItem extends StatelessWidget {
  const _MediaGridItem({
    required this.index,
    required this.draft,
    required this.onRemove,
    required this.onTapEmpty,
  });

  final int index;
  final _PropertyMediaDraft draft;
  final VoidCallback onRemove;
  final VoidCallback onTapEmpty;

  @override
  Widget build(BuildContext context) {
    final value = draft.controller.text.trim();
    final isEmpty = value.isEmpty;

    if (isEmpty) {
      return GestureDetector(
        onTap: onTapEmpty,
        child: CustomPaint(
          painter: _DashedRectPainter(
            color: AppColors.primary.withValues(alpha: 0.45),
            strokeWidth: 1.5,
            gap: 4.0,
            dashLength: 6.0,
            borderRadius: 16.0,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                RentlyIcon(
                  IconsaxPlusLinear.add_square,
                  color: AppColors.primary,
                  size: 26,
                ),
                SizedBox(height: 6),
                Text(
                  'הוסף מדיה',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        fit: StackFit.expand,
        children: [
          SafeMedia(
            media: PropertyMedia(url: value, type: draft.type),
            fit: BoxFit.cover,
            videoMode: SafeVideoDisplayMode.iconOnly,
            fallback: Container(
              color: AppColors.primaryLight2,
              child: Icon(draft.type.icon, color: AppColors.primary),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 28,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.45),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 6,
            left: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.navy.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                draft.type.label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          Positioned(
            top: 6,
            right: 6,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close,
                  size: 14,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PickerOptionButton extends StatelessWidget {
  const _PickerOptionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isFullWidth = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isFullWidth;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.background,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: 16,
            vertical: isFullWidth ? 14 : 12,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.borderLight),
          ),
          child: Row(
            mainAxisAlignment: isFullWidth
                ? MainAxisAlignment.center
                : MainAxisAlignment.start,
            children: [
              Icon(icon, color: AppColors.primary, size: 20),
              const SizedBox(width: 10),
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.navy,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashedRectPainter extends CustomPainter {
  _DashedRectPainter({
    required this.color,
    required this.strokeWidth,
    required this.gap,
    required this.dashLength,
    required this.borderRadius,
  });

  final Color color;
  final double strokeWidth;
  final double gap;
  final double dashLength;
  final double borderRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width, size.height),
        Radius.circular(borderRadius),
      ));

    final dashPath = Path();
    double distance = 0.0;
    for (final PathMetric measurePath in path.computeMetrics()) {
      while (distance < measurePath.length) {
        dashPath.addPath(
          measurePath.extractPath(distance, distance + dashLength),
          Offset.zero,
        );
        distance += dashLength + gap;
      }
      distance = 0.0;
    }

    canvas.drawPath(dashPath, paint);
  }

  @override
  bool shouldRepaint(covariant _DashedRectPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.gap != gap ||
        oldDelegate.dashLength != dashLength ||
        oldDelegate.borderRadius != borderRadius;
  }
}

class _Scan3dPanel extends StatelessWidget {
  const _Scan3dPanel({
    required this.tour,
    required this.isSubmitting,
    required this.isBackendConfigured,
    required this.onPickFromCamera,
    required this.onPickFromGallery,
    required this.onClear,
    this.onOpenRoomScan,
    this.roomScanCount = 0,
    this.onLinkScaniverse,
    this.onImportScaniverseAssets,
  });

  final PropertyVirtualTour? tour;
  final bool isSubmitting;
  final bool isBackendConfigured;
  final VoidCallback onPickFromCamera;
  final VoidCallback onPickFromGallery;
  final VoidCallback onClear;
  final VoidCallback? onOpenRoomScan;
  final int roomScanCount;
  final VoidCallback? onLinkScaniverse;
  final VoidCallback? onImportScaniverseAssets;

  @override
  Widget build(BuildContext context) {
    final currentTour = tour;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.navy.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.view_in_ar_rounded,
                color: AppColors.navy,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'סריקת תלת-מימד (מתקדם)',
                    style: TextStyle(
                      color: AppColors.navy,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  SizedBox(height: 3),
                  Text(
                    'דורש צילום תוך כדי הליכה לאט בחלל. '
                    '(לסיור נאמן ומומלץ השתמשו בסיור ה־360° למעלה.)',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12.5,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // PRIMARY path: per-room high-quality 3D scan, linked together.
        if (onOpenRoomScan != null) ...[
          _RoomScanEntry(
            roomScanCount: roomScanCount,
            onTap: onOpenRoomScan!,
          ),
          const SizedBox(height: 14),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: const [
            _ScanTip(
              icon: Icons.wb_sunny_rounded,
              label: 'אור חזק',
            ),
            _ScanTip(
              icon: Icons.home_work_rounded,
              label: 'חדר אחרי חדר',
            ),
            _ScanTip(
              icon: Icons.photo_camera_rounded,
              label: 'מכל הזוויות',
            ),
          ],
        ),
        if (currentTour != null) ...[
          const SizedBox(height: 18),
          _ScanStatusCard(
            tour: currentTour,
            isSubmitting: isSubmitting,
            isBackendConfigured: isBackendConfigured,
            onReplace: onPickFromCamera,
            onClear: onClear,
          ),
        ],
        // The old whole-apartment video→Teleport fallback was removed: Teleport
        // isn't configured (it returned "השרת לא זמין"). The per-room KIRI flow
        // above (which records a video per room) is the one working 3D path.
      ],
    );
  }
}

/// Big, primary entry to the per-room 3D scan flow. Shows how many rooms are
/// already scanned so an older user always knows where they stand.
class _RoomScanEntry extends StatelessWidget {
  const _RoomScanEntry({required this.roomScanCount, required this.onTap});

  final int roomScanCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final has = roomScanCount > 0;
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.navy, Color(0xFF1E3A8A)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: AppColors.navy.withValues(alpha: 0.18),
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Row(
              children: [
                const Icon(Icons.view_in_ar_rounded,
                    color: Colors.white, size: 26),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        has ? 'המשך סריקת חדרים' : 'התחל סריקת חדרים',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        has
                            ? '$roomScanCount חדרים נסרקו · אפשר להוסיף עוד'
                            : 'סורקים חדר-חדר באיכות גבוהה',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_left_rounded, color: Colors.white),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ScanTip extends StatelessWidget {
  const _ScanTip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppColors.primary, size: 14),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.navy,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanActions extends StatelessWidget {
  const _ScanActions({
    required this.isSubmitting,
    required this.onPickFromCamera,
    required this.onPickFromGallery,
    this.onLinkScaniverse,
    this.onImportScaniverseAssets,
  });

  final bool isSubmitting;
  final VoidCallback onPickFromCamera;
  final VoidCallback onPickFromGallery;
  final VoidCallback? onLinkScaniverse;
  final VoidCallback? onImportScaniverseAssets;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.navy, Color(0xFF1E3A8A)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.navy.withValues(alpha: 0.15),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: isSubmitting ? null : onPickFromCamera,
                    borderRadius: BorderRadius.circular(14),
                    child: Center(
                      child: isSubmitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                RentlyIcon(IconsaxPlusLinear.video_play,
                                    color: Colors.white, size: 18),
                                SizedBox(width: 8),
                                Text(
                                  'צלם סריקה',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.borderLight),
                  boxShadow: const [
                    BoxShadow(
                      color: AppColors.shadow,
                      blurRadius: 6,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: isSubmitting ? null : onPickFromGallery,
                    borderRadius: BorderRadius.circular(14),
                    child: const Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          RentlyIcon(IconsaxPlusLinear.video,
                              color: AppColors.navy, size: 18),
                          SizedBox(width: 8),
                          Text(
                            'בחר וידאו',
                            style: TextStyle(
                              color: AppColors.navy,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        // Scaniverse direct-link button — shown when API is configured
        if (onLinkScaniverse != null) ...[
          const SizedBox(height: 10),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: isSubmitting ? null : onLinkScaniverse,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.primaryLight2,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.view_in_ar_rounded,
                        color: AppColors.primary, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'קשר סריקה מ-Scaniverse',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
        if (onImportScaniverseAssets != null) ...[
          const SizedBox(height: 10),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: isSubmitting ? null : onImportScaniverseAssets,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFD6E3F0)),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      IconsaxPlusLinear.document_upload,
                      color: AppColors.navy,
                      size: 18,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'ייבא קבצי 3D מ-Scaniverse',
                      style: TextStyle(
                        color: AppColors.navy,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ScanStatusCard extends StatelessWidget {
  const _ScanStatusCard({
    required this.tour,
    required this.isSubmitting,
    required this.isBackendConfigured,
    required this.onReplace,
    required this.onClear,
  });

  final PropertyVirtualTour tour;
  final bool isSubmitting;
  final bool isBackendConfigured;
  final VoidCallback onReplace;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFD),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE0EBF2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_statusIcon, color: _statusColor, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _statusLabel,
                  style: const TextStyle(
                    color: AppColors.navy,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (tour.processingProgress != null)
                Text(
                  '${tour.processingProgress}%',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _detailLabel,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12.5,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: isSubmitting ? null : onReplace,
                  icon: const RentlyIcon(IconsaxPlusLinear.refresh, size: 16),
                  label: const Text('החלף סריקה'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.navy,
                    side: const BorderSide(color: AppColors.borderLight),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              IconButton(
                onPressed: isSubmitting ? null : onClear,
                icon: const Icon(Icons.close, color: AppColors.coral),
                tooltip: 'הסר סריקה',
              ),
            ],
          ),
        ],
      ),
    );
  }

  IconData get _statusIcon {
    if (tour.isReady) return IconsaxPlusLinear.tick_circle;
    if (tour.hasFailed) return IconsaxPlusLinear.close_circle;
    if (tour.needsBackendUpload) return IconsaxPlusLinear.document_upload;
    return IconsaxPlusLinear.cloud_change;
  }

  Color get _statusColor {
    if (tour.isReady) return AppColors.success;
    if (tour.hasFailed) return AppColors.coral;
    return AppColors.primary;
  }

  String get _statusLabel {
    if (tour.isReady) return 'סיור 3D מוכן לפרסום';
    if (tour.hasFailed) return 'העיבוד נכשל';
    if (tour.needsBackendUpload) return 'סריקה נשמרה וממתינה לעיבוד';
    if (tour.status == PropertyTourStatus.uploading) return 'מעלה וידאו לסריקה';
    return 'הסיור בעיבוד';
  }

  String get _detailLabel {
    if (tour.hasFailed && tour.errorMessage.isNotEmpty) {
      return tour.errorMessage;
    }
    if (tour.needsBackendUpload) {
      if (!isBackendConfigured) {
        return 'הווידאו נשמר במכשיר. כדי לשלוח לעיבוד יש לוודא שהגדרות השרת תקינות.';
      }
      return 'לחץ על ״החלף סריקה״ לנסות שוב (ייתכן שיש להתחבר תחילה לחשבון).';
    }
    if (tour.processingStage.isNotEmpty) {
      return 'שלב נוכחי: ${tour.processingStage}';
    }
    return 'הלקוחות יראו כפתור סיור רק כשה־viewer יהיה מוכן.';
  }
}

// ─── Shared widgets ───────────────────────────────────────────────────────────

class _SectionHint extends StatelessWidget {
  const _SectionHint(
      {required this.icon, required this.title, required this.subtitle});
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Center(child: Icon(icon, color: AppColors.primary, size: 22)),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: AppColors.navy)),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
            ],
          ),
        ),
      ],
    );
  }
}

class _FormCard extends StatelessWidget {
  const _FormCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderLight),
        boxShadow: const [
          BoxShadow(
              color: AppColors.shadow, blurRadius: 10, offset: Offset(0, 4)),
        ],
      ),
      child: child,
    );
  }
}

/// A text field with a suggestion dropdown backed by the bundled Israel
/// cities/streets dataset. Suggestions are advisory only — whatever the landlord
/// types is kept in [ctrl], so free text that matches nothing is still allowed
/// (nobody is blocked from submitting).
class _AutocompleteField extends StatelessWidget {
  const _AutocompleteField({
    required this.ctrl,
    required this.label,
    required this.icon,
    required this.optionsBuilder,
    this.enabled = true,
    this.onSelected,
  });

  final TextEditingController ctrl;
  final String label;
  final IconData icon;
  final List<String> Function(String query) optionsBuilder;
  final bool enabled;
  final ValueChanged<String>? onSelected;

  @override
  Widget build(BuildContext context) {
    return Autocomplete<String>(
      // Seed Autocomplete's internal controller with whatever is already in our
      // shared controller (e.g. GPS auto-fill or an Erik draft).
      initialValue: TextEditingValue(text: ctrl.text),
      optionsBuilder: (TextEditingValue value) {
        final query = value.text.trim();
        if (query.isEmpty) return const Iterable<String>.empty();
        return optionsBuilder(query);
      },
      onSelected: (selection) {
        ctrl.text = selection;
        onSelected?.call(selection);
      },
      fieldViewBuilder:
          (context, textController, focusNode, onFieldSubmitted) {
        return TextField(
          controller: textController,
          focusNode: focusNode,
          enabled: enabled,
          // Mirror every keystroke into the shared controller so free text the
          // user never "selected" from the list is still saved.
          onChanged: (v) => ctrl.text = v,
          onSubmitted: (_) => onFieldSubmitted(),
          style: const TextStyle(color: AppColors.navy, fontSize: 14),
          decoration: InputDecoration(
            labelText: label,
            labelStyle:
                const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            prefixIcon: Icon(icon, size: 16, color: AppColors.primary),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          ),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topRight,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(14),
            color: Colors.white,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240, maxWidth: 320),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final option = options.elementAt(index);
                  return InkWell(
                    onTap: () => onSelected(option),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      child: Text(
                        option,
                        style: const TextStyle(
                          color: AppColors.navy,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Floor-number selector as a drop-down menu (requested for older users instead
/// of free typing). Range: basement, ground floor, then 1…50. Writes the chosen
/// label straight into [ctrl] (kept as a string, same as before).
class _FloorDropdown extends StatelessWidget {
  const _FloorDropdown({required this.ctrl});

  final TextEditingController ctrl;

  static const List<String> _floors = [
    'מרתף',
    'קרקע',
    '1', '2', '3', '4', '5', '6', '7', '8', '9', '10',
    '11', '12', '13', '14', '15', '16', '17', '18', '19', '20',
    '21', '22', '23', '24', '25', '26', '27', '28', '29', '30',
    '31', '32', '33', '34', '35', '36', '37', '38', '39', '40',
    '41', '42', '43', '44', '45', '46', '47', '48', '49', '50',
  ];

  @override
  Widget build(BuildContext context) {
    final current = ctrl.text.trim();
    // A pre-filled value (GPS / Erik draft) might not be in the canonical list —
    // surface it as an extra option so it isn't silently dropped.
    final items = <String>[
      if (current.isNotEmpty && !_floors.contains(current)) current,
      ..._floors,
    ];
    return DropdownButtonFormField<String>(
      initialValue: current.isEmpty ? null : current,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'קומה',
        labelStyle:
            const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        // AppColors.primary is a mutable static — never put it inside a const
        // expression here (build-time invalid_constant even though it looks fine).
        prefixIcon: Icon(IconsaxPlusLinear.layer,
            size: 16, color: AppColors.primary),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      ),
      style: const TextStyle(
          color: AppColors.navy, fontWeight: FontWeight.w700, fontSize: 14),
      icon: const RentlyIcon(IconsaxPlusLinear.arrow_down,
          size: 16, color: AppColors.textSecondary),
      dropdownColor: Colors.white,
      borderRadius: BorderRadius.circular(16),
      items: items
          .map((f) => DropdownMenuItem(value: f, child: Text(f)))
          .toList(),
      onChanged: (v) => ctrl.text = v ?? '',
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.ctrl,
    required this.label,
    required this.icon,
    this.numeric = false,
  });
  final TextEditingController ctrl;
  final String label;
  final IconData icon;
  final bool numeric;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: ctrl,
      keyboardType: numeric ? TextInputType.number : TextInputType.text,
      inputFormatters:
          numeric ? [FilteringTextInputFormatter.digitsOnly] : null,
      style: const TextStyle(color: AppColors.navy, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle:
            const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        prefixIcon: Icon(icon, size: 16, color: AppColors.primary),
        // Inherit the global rounded, soft-filled InputDecorationTheme (no boxy
        // white border) so fields match the rounded cards around them.
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      ),
    );
  }
}

/// Read-only "entry date" field that opens a real date picker instead of asking
/// an (older) landlord to type a date by hand. Stores a clean dd/MM/yyyy string.
class _EntryDatePicker extends StatelessWidget {
  const _EntryDatePicker({required this.ctrl});
  final TextEditingController ctrl;

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final initial = _parse(ctrl.text) ?? today;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(today) ? today : initial,
      firstDate: today,
      lastDate: DateTime(now.year + 5),
      helpText: 'בחר תאריך כניסה',
    );
    if (picked != null) {
      ctrl.text =
          '${_two(picked.day)}/${_two(picked.month)}/${picked.year}';
    }
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  // Best-effort parse of a previously stored dd/MM/yyyy (or dd/MM) value.
  static DateTime? _parse(String s) {
    final parts = s.trim().split('/');
    if (parts.length < 2) return null;
    final d = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (d == null || m == null) return null;
    final y = parts.length >= 3
        ? (int.tryParse(parts[2]) ?? DateTime.now().year)
        : DateTime.now().year;
    return DateTime(y, m, d);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ctrl,
      builder: (context, _) {
        final hasValue = ctrl.text.trim().isNotEmpty;
        return InkWell(
          onTap: () => _pick(context),
          borderRadius: BorderRadius.circular(14),
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: 'תאריך כניסה',
              labelStyle: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13),
              prefixIcon: Icon(IconsaxPlusLinear.calendar,
                  size: 16, color: AppColors.primary),
              suffixIcon: const Icon(IconsaxPlusLinear.arrow_down_1,
                  size: 14, color: AppColors.textSecondary),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            ),
            child: Text(
              hasValue ? ctrl.text : 'בחר תאריך',
              style: TextStyle(
                color: hasValue ? AppColors.navy : AppColors.textSecondary,
                fontSize: 14,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Slider with a tappable numeric field so the value can be set by dragging OR
/// typed freely (precise amounts the slider's coarse steps can't reach). The
/// typed value is clamped to [min, max].
class _SliderWithEntry extends StatefulWidget {
  const _SliderWithEntry({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
    this.unitPrefix = '',
    this.unitSuffix = '',
    this.allowDecimals = false,
  });
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;
  final String unitPrefix;
  final String unitSuffix;
  final bool allowDecimals;

  @override
  State<_SliderWithEntry> createState() => _SliderWithEntryState();
}

class _SliderWithEntryState extends State<_SliderWithEntry> {
  late final TextEditingController _ctrl;
  final FocusNode _focus = FocusNode();

  String _fmt(double v) => widget.allowDecimals
      ? (v % 1 == 0 ? v.toInt().toString() : v.toString())
      : v.round().toString();

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: _fmt(widget.value));
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(covariant _SliderWithEntry old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && widget.value != old.value) {
      _ctrl.text = _fmt(widget.value);
    }
  }

  void _commit() {
    final parsed = double.tryParse(_ctrl.text.trim().replaceAll(',', ''));
    if (parsed == null) {
      _ctrl.text = _fmt(widget.value);
      return;
    }
    final clamped = parsed.clamp(widget.min, widget.max).toDouble();
    widget.onChanged(clamped);
    _ctrl.text = _fmt(clamped);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Text(widget.label,
                style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600)),
            const Spacer(),
            Container(
              constraints: const BoxConstraints(minWidth: 88, maxWidth: 150),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.35)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.unitPrefix.isNotEmpty)
                    Text(widget.unitPrefix,
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: AppColors.primary)),
                  Flexible(
                    child: TextField(
                      controller: _ctrl,
                      focusNode: _focus,
                      textAlign: TextAlign.center,
                      keyboardType: widget.allowDecimals
                          ? const TextInputType.numberWithOptions(decimal: true)
                          : TextInputType.number,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _commit(),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(widget.allowDecimals ? r'[0-9.]' : r'[0-9]'),
                        ),
                      ],
                      decoration: const InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: AppColors.primary),
                    ),
                  ),
                  if (widget.unitSuffix.isNotEmpty)
                    Text(' ${widget.unitSuffix}',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary)),
                ],
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: AppColors.primary,
            inactiveTrackColor: AppColors.borderLight,
            thumbColor: AppColors.primary,
            overlayColor: AppColors.primary.withValues(alpha: 0.15),
            trackHeight: 3,
          ),
          child: Slider(
            value: widget.value.clamp(widget.min, widget.max),
            min: widget.min,
            max: widget.max,
            divisions: widget.divisions,
            onChanged: (v) {
              if (_focus.hasFocus) _focus.unfocus();
              widget.onChanged(v);
            },
          ),
        ),
      ],
    );
  }
}

/// In-flow picker for the property page DESIGN: choose one of the 6 detail-page
/// templates + an optional accent colour, stored per-listing. Each listing can
/// look different without touching user-level broker branding.
class _DesignTemplatePicker extends StatelessWidget {
  const _DesignTemplatePicker({
    required this.selectedTemplate,
    required this.accent,
    required this.onTemplateChanged,
    required this.onAccentChanged,
  });

  final String selectedTemplate;
  final int accent;
  final ValueChanged<String> onTemplateChanged;
  final ValueChanged<int> onAccentChanged;

  static const _hebLabels = {
    'rently_classic': 'קלאסי',
    'acid_hero': 'אורה',
    'dashboard_glass': 'לוח שוק',
    'estate_card': 'כרטיס נכס',
    'gallery_editorial': 'גלריה',
    'cinematic_glass': 'קולנועי',
  };

  static const _defaultAccent = 0xFF13BEC9;

  static const _accentPresets = <int>[
    0xFF13BEC9,
    0xFF6C5CE7,
    0xFFECFF74,
    0xFFFF6B6B,
    0xFF2ECC71,
    0xFFFFA94D,
  ];

  static List<Color> _previewColors(String id) => switch (id) {
        'acid_hero' => const [Color(0xFF111827), Color(0xFFECFF74)],
        'dashboard_glass' => const [Color(0xFFEAF2F0), Color(0xFF13BEC9)],
        'estate_card' => const [Color(0xFFF5F6F8), Color(0xFF6C5CE7)],
        'gallery_editorial' => const [Colors.white, Color(0xFF111827)],
        'cinematic_glass' => const [Color(0xFF0B1220), Color(0xFF8B5CF6)],
        _ => const [Colors.white, Color(0xFF13BEC9)],
      };

  static BrokerPropertyTemplate _templateFromId(String id) {
    for (final t in BrokerPropertyTemplate.values) {
      if (t.id == id) return t;
    }
    return BrokerPropertyTemplate.rentlyClassic;
  }

  bool _isSelected(String id) {
    final effectiveTemplate = selectedTemplate.isEmpty ? 'rently_classic' : selectedTemplate;
    return effectiveTemplate == id;
  }

  @override
  Widget build(BuildContext context) {
    final templates = BrokerPropertyTemplate.values;
    final isMobile = MediaQuery.of(context).size.width < 600;
    final crossAxisCount = isMobile ? 2 : 3;

    return _FormCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(IconsaxPlusLinear.brush_4,
                  size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              const Text('עיצוב דף הדירה',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: AppColors.navy)),
            ],
          ),
          const SizedBox(height: 4),
          const Text('בחרו תבנית לדף הנכס וצבע מותאם אישית',
              style:
                  TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: crossAxisCount,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.85,
            children: [
              for (final t in templates)
                _TemplateChip(
                  label: _hebLabels[t.id] ?? t.title,
                  colors: _previewColors(t.id),
                  selected: _isSelected(t.id),
                  onTap: () => onTemplateChanged(t.id),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Icon(IconsaxPlusLinear.colorfilter, size: 16, color: AppColors.primary),
              const SizedBox(width: 8),
              const Text('צבע מותאם',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.navy)),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _AccentDot(
                value: _defaultAccent,
                selected: accent == _defaultAccent || accent == 0,
                onTap: () => onAccentChanged(_defaultAccent),
                label: 'ברירת מחדל',
              ),
              for (final c in _accentPresets.where((color) => color != _defaultAccent))
                _AccentDot(
                  value: c,
                  selected: accent == c,
                  onTap: () => onAccentChanged(c),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TemplateChip extends StatelessWidget {
  const _TemplateChip({
    required this.label,
    required this.colors,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final List<Color> colors;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected ? AppColors.primary : AppColors.borderLight,
                  width: selected ? 2.5 : 1.5,
                ),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: colors,
                ),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.15),
                          blurRadius: 10,
                          spreadRadius: 1,
                        ),
                      ]
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
              ),
              child: Stack(
                children: [
                  // Bottom accent bar
                  Positioned(
                    left: 10,
                    right: 10,
                    bottom: 10,
                    child: Container(
                      height: 7,
                      decoration: BoxDecoration(
                        color: colors.last.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(3.5),
                        boxShadow: [
                          BoxShadow(
                            color: colors.last.withValues(alpha: 0.3),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Check icon when selected
                  if (selected)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.4),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(3),
                        child: const Icon(Icons.check,
                            size: 14, color: Colors.white),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: selected ? AppColors.primary : AppColors.navy,
                height: 1.2,
              )),
        ],
      ),
    );
  }
}

class _AccentDot extends StatelessWidget {
  const _AccentDot({
    required this.value,
    required this.selected,
    required this.onTap,
    this.label = '',
  });

  final int value;
  final bool selected;
  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Color(value),
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? AppColors.primary : AppColors.borderLight,
                width: selected ? 2.4 : 1.5,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: Color(value).withValues(alpha: 0.3),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ]
                  : [],
            ),
            child: selected
                ? const Icon(Icons.check, size: 18, color: Colors.white)
                : null,
          ),
          if (label.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? AppColors.primary : AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

class _DropdownRow extends StatelessWidget {
  const _DropdownRow({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });
  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
        labelStyle:
            const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        // Inherit the global rounded soft-filled theme (no boxy white border).
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      ),
      style: const TextStyle(
          color: AppColors.navy, fontWeight: FontWeight.w700, fontSize: 14),
      icon: const RentlyIcon(IconsaxPlusLinear.arrow_down,
          size: 16, color: AppColors.textSecondary),
      dropdownColor: Colors.white,
      borderRadius: BorderRadius.circular(16),
      items: options
          .map((o) => DropdownMenuItem(value: o, child: Text(o)))
          .toList(),
      onChanged: onChanged,
    );
  }
}

// ─── Edit Property Screen ─────────────────────────────────────────────────────

class EditPropertyScreen extends StatefulWidget {
  const EditPropertyScreen({super.key, required this.property});

  final RentalProperty property;

  @override
  State<EditPropertyScreen> createState() => _EditPropertyScreenState();
}

class _EditPropertyScreenState extends State<EditPropertyScreen> {
  static const _stepLabels = ['מיקום', 'פרטי הנכס', 'מאפיינים', 'מדיה'];

  final _pageCtrl = PageController();
  int _step = 0;

  late final TextEditingController _cityCtrl;
  late final TextEditingController _neighborhoodCtrl;
  late final TextEditingController _streetCtrl;
  late final TextEditingController _streetNumCtrl;
  late final TextEditingController _floorCtrl;
  late final TextEditingController _totalFloorsCtrl;
  late final TextEditingController _sizeCtrl;
  late final TextEditingController _entryDateCtrl;
  late final List<_PropertyMediaDraft> _mediaDrafts;
  final _picker = ImagePicker();
  final _storageService = StorageService();
  final _scanService = Property3dScanService();
  final _scaniverseImportService = ScaniverseAssetImportService();

  late int _price;
  late PropertyTransactionType _transactionType;
  late double _rooms;
  late String _propertyType;
  late String _condition;
  late bool _agencyListing;
  late String _designTemplate;
  late int _designAccent;
  late final Set<String> _selectedFeatures;
  late final Set<String> _publishChannels;
  bool _isSaving = false;
  bool _isSubmittingTour = false;
  bool _isScanSubmitting = false;
  bool _isCapturingVerification = false;
  PropertyVirtualTour? _virtualTourDraft;
  PropertyVirtualTour? _scanTourDraft;
  PropertyModel3d? _model3dDraft;
  PropertyPanoramaTour? _panoramaTourDraft;
  List<ScannedRoom> _roomScans = const [];
  Timer? _scanPollTimer;

  // Opens the per-room 3D scan flow on the EDIT screen. Mirrors the add
  // screen's _openRoomScan: keeps the rooms in screen state and surfaces the
  // first viewable room through _model3dDraft so a save still carries 3D.
  Future<void> _openRoomScan() async {
    final result = await RoomScanFlowScreen.open(
      context,
      propertyId: widget.property.id,
      initialRooms: _roomScans,
    );
    if (result == null || !mounted) return;
    setState(() {
      _roomScans = result;
      final firstViewable = result.firstWhere(
        (r) => r.hasViewableAsset,
        orElse: () => const ScannedRoom(name: ''),
      );
      if (firstViewable.hasViewableAsset) {
        _model3dDraft = (_model3dDraft ?? const PropertyModel3d()).copyWith(
          glbUrl: firstViewable.meshGlbUrl ?? '',
          plyUrl: firstViewable.splatUrl ?? '',
          scanDate: DateTime.now(),
        );
      } else if (result.isEmpty) {
        _model3dDraft = null;
      }
    });
  }

  Future<void> _createPanoramaTour() async {
    final result = await Navigator.of(context).push<PropertyPanoramaTour>(
      MaterialPageRoute(
        builder: (_) => PanoramaCaptureScreen(initial: _panoramaTourDraft),
      ),
    );
    if (result != null && mounted) {
      setState(() => _panoramaTourDraft = result.isEmpty ? null : result);
    }
  }
  int _scanPollCount = 0;
  late bool _wantsVerifiedListing;
  late String _verificationVideoUrl;
  DateTime? _verificationCapturedAt;
  late bool _acceptedPropertyTerms;
  late bool _thirdPartyTransferAllowed;
  late bool _commercialSaleAllowed;
  late bool _aiTrainingAllowed;
  late bool _isActive;

  @override
  void initState() {
    super.initState();
    final p = widget.property;
    _cityCtrl = TextEditingController(text: p.city);
    _neighborhoodCtrl = TextEditingController(text: p.neighborhood);
    _streetCtrl = TextEditingController(text: p.street);
    _streetNumCtrl = TextEditingController(
        text: p.streetNumber > 0 ? '${p.streetNumber}' : '');
    _floorCtrl = TextEditingController(text: p.floor);
    _totalFloorsCtrl = TextEditingController(text: p.totalFloors);
    _sizeCtrl = TextEditingController(text: '${p.sizeM2}');
    _entryDateCtrl = TextEditingController(text: p.entryDate);
    _mediaDrafts = p.media.isNotEmpty
        ? p.media
            .map((item) => _PropertyMediaDraft(
                  initialValue: item.url,
                  type: item.type,
                ))
            .toList()
        : [_PropertyMediaDraft()];
    _price = p.price;
    _transactionType = p.transactionType;
    _rooms = p.rooms;
    _propertyType = p.propertyType;
    _condition = p.condition.isNotEmpty ? p.condition : 'תקין';
    _agencyListing = p.agencyListing;
    _designTemplate = p.designTemplate;
    _designAccent = p.designAccent;
    _selectedFeatures = Set<String>.from(p.features);
    _publishChannels = p.publishChannels.isEmpty
        ? <String>{'rently'}
        : Set<String>.from(p.publishChannels);
    _virtualTourDraft = p.virtualTour;
    _panoramaTourDraft = p.panoramaTour;
    _scanTourDraft = null;
    _model3dDraft = p.model3d;
    _wantsVerifiedListing = p.isVerifiedListing;
    _verificationVideoUrl = p.verification.videoUrl;
    _verificationCapturedAt = p.verification.capturedAt;
    // Show checkbox as checked only when consent exists AND version is current.
    // Stale consent (version mismatch) requires re-acceptance.
    _acceptedPropertyTerms =
        LegalConsentService.instance.hasValidConsent(p.legal);
    _thirdPartyTransferAllowed = p.legal.thirdPartyTransferAllowed;
    _commercialSaleAllowed = p.legal.commercialSaleAllowed;
    _aiTrainingAllowed = p.legal.aiTrainingAllowed;
    _isActive = p.isActive;
  }

  @override
  void dispose() {
    _stopScanPolling();
    _pageCtrl.dispose();
    _cityCtrl.dispose();
    _neighborhoodCtrl.dispose();
    _streetCtrl.dispose();
    _streetNumCtrl.dispose();
    _floorCtrl.dispose();
    _totalFloorsCtrl.dispose();
    _sizeCtrl.dispose();
    _entryDateCtrl.dispose();
    for (final item in _mediaDrafts) {
      item.dispose();
    }
    super.dispose();
  }

  void _startScanPolling() {
    _stopScanPolling();
    _scanPollCount = 0;
    _scanPollTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      final tour = _scanTourDraft;
      if (tour == null) { _stopScanPolling(); return; }
      if (tour.status == PropertyTourStatus.ready || tour.status == PropertyTourStatus.failed) {
        _stopScanPolling(); return;
      }
      _scanPollCount++;
      if (_scanPollCount > 20) {
        _stopScanPolling();
        if (!mounted) return;
        // Teleport's Gaussian-splat processing takes ~1 hour, far longer than
        // this in-screen poll — so keep it "processing" (not failed). The tour
        // is saved with the capture id and appears automatically once ready.
        final isTeleport = tour.provider == 'teleport';
        setState(() {
          _scanTourDraft = _scanTourDraft?.copyWith(
            status: isTeleport
                ? PropertyTourStatus.processing
                : PropertyTourStatus.failed,
            processingStage: isTeleport
                ? 'הסיור התלת־ממדי בעיבוד (בערך שעה). אפשר לשמור את הדירה — הוא יופיע אוטומטית כשיהיה מוכן.'
                : '',
            errorMessage: isTeleport
                ? ''
                : 'עיבוד הסריקה לקח יותר מדי זמן. נסה שוב מאוחר יותר.',
            updatedAt: DateTime.now().toUtc(),
          );
        });
        return;
      }
      try {
        final updated = await _scanService.refresh(tour);
        if (!mounted) { _stopScanPolling(); return; }
        setState(() => _scanTourDraft = updated);
        if (updated.status == PropertyTourStatus.ready || updated.status == PropertyTourStatus.failed) {
          _stopScanPolling();
        }
      } catch (e) {
        if (!mounted) { _stopScanPolling(); return; }
        if (_scanPollCount >= 20) {
          _stopScanPolling();
          setState(() {
            _scanTourDraft = _scanTourDraft?.copyWith(
              status: PropertyTourStatus.failed,
              errorMessage: 'שגיאה בבדיקת סטטוס הסריקה. נסה שוב.',
              updatedAt: DateTime.now().toUtc(),
            );
          });
        }
      }
    });
  }

  void _stopScanPolling() {
    _scanPollTimer?.cancel();
    _scanPollTimer = null;
  }

  bool _validateCurrentStep() {
    switch (_step) {
      case 0:
        final city = _cityCtrl.text.trim();
        final street = _streetCtrl.text.trim();
        if (city.isEmpty || street.isEmpty) return false;
        if (city.length < 2 || street.length < 2) return false;
        return true;
      case 1:
        final size = int.tryParse(_sizeCtrl.text.trim()) ?? 0;
        return size > 0 &&
            _price > 0 &&
            _rooms > 0;
      case 3:
        if (_wantsVerifiedListing) {
          return _verificationVideoUrl.isNotEmpty;
        }
        return _mediaDrafts.any((draft) => draft.controller.text.trim().isNotEmpty);
      default:
        return true;
    }
  }

  void _next() {
    if (!_validateCurrentStep()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(milliseconds: 2500),
          content: Text('יש למלא את השדות הנדרשים'),
          backgroundColor: AppColors.coral,
        ),
      );
      return;
    }
    if (_step < 3) {
      setState(() => _step++);
      _pageCtrl.nextPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeInOut,
      );
    } else {
      _save();
    }
  }

  void _prev() {
    if (_step > 0) {
      setState(() => _step--);
      _pageCtrl.previousPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeInOut,
      );
    } else {
      Navigator.of(context).pop();
    }
  }

  Future<void> _pickPropertyImage(ImageSource source) async {
    if (_wantsVerifiedListing) {
      _showMediaError('בדירה מאומתת אפשר לצלם רק וידאו אימות מתוך האפליקציה.');
      return;
    }
    try {
      final file = await _picker.pickImage(
        source: source,
        imageQuality: 86,
        maxWidth: 1800,
      );
      if (file == null) return;
      final localPath = await _storageService.saveImageLocally(
        file,
        folderName: 'property_photos',
      );
      final remoteUrl = await _storageService.uploadToCloud(localPath);
      _assignPickedMedia(remoteUrl ?? localPath, PropertyMediaType.image);
    } on StorageException catch (error) {
      _showMediaError(error.message);
    }
  }

  Future<void> _pickPropertyVideo(ImageSource source) async {
    if (_wantsVerifiedListing) {
      _showMediaError('בדירה מאומתת אפשר לצלם רק וידאו אימות מתוך האפליקציה.');
      return;
    }
    try {
      final file = await _picker.pickVideo(
        source: source,
        maxDuration: const Duration(seconds: 90),
      );
      if (file == null) return;
      final localPath = await _storageService.saveVideoLocally(
        file,
        folderName: 'property_videos',
      );
      final remoteUrl = await _storageService.uploadToCloud(localPath);
      _assignPickedMedia(remoteUrl ?? localPath, PropertyMediaType.video);
    } on StorageException catch (error) {
      _showMediaError(error.message);
    }
  }

  Future<void> _pickScanVideo(ImageSource source) async {
    if (_wantsVerifiedListing) {
      _showMediaError(
          'בדירה מאומתת סריקות והעלאות ננעלות עד ביטול מצב האימות.');
      return;
    }
    // A successful 3D reconstruction depends entirely on capture quality — the
    // #1 cause of a failed Teleport scan is a video that's too fast/partial to
    // rebuild the room. Show the technique guide before recording.
    if (source == ImageSource.camera) {
      final proceed = await showScanCaptureGuide(context);
      if (proceed != true) return;
    }

    try {
      final file = await _picker.pickVideo(
        source: source,
        maxDuration: const Duration(seconds: 60),
      );
      if (file == null) return;

      final rawSize = await file.length();
      if (rawSize > 400 * 1024 * 1024) {
        _showMediaError(
          'הסרטון גדול מדי (${(rawSize / 1024 / 1024).toStringAsFixed(0)} MB). '
          'צלם סרטון קצר יותר של עד 60 שניות.',
        );
        return;
      }

      setState(() => _isScanSubmitting = true);
      // Teleport's 3D reconstruction requires an H.264 mp4; iOS records HEVC
      // .mov which fails processing. Transcode on-device first (fail-soft —
      // if it fails we upload the original rather than block the user).
      final mp4Path = await transcodeScanToMp4(file.path);
      final scanFile = mp4Path != null ? XFile(mp4Path) : file;
      final localPath = await _storageService.saveVideoLocally(
        scanFile,
        folderName: 'property_scan_videos',
      );
      final sizeBytes = await scanFile.length();
      final captured = _scanService.localCapture(
        propertyId: widget.property.id,
        localVideoPath: localPath,
        sizeBytes: sizeBytes,
      );

      if (!_scanService.isConfigured) {
        setState(() {
          _scanTourDraft = captured;
          _isScanSubmitting = false;
        });
        _showMediaError(
          'הסריקה נשמרה כטיוטה. שליחת הסריקה לעיבוד אינה זמינה כרגע.',
        );
        return;
      }

      setState(() {
        _scanTourDraft = captured.copyWith(
          status: PropertyTourStatus.uploading,
          updatedAt: DateTime.now().toUtc(),
        );
      });

      final submitted = await _scanService.submitScanVideo(
        propertyId: widget.property.id,
        title: _scanTitle(),
        localVideoPath: localPath,
      );

      if (!mounted) return;
      setState(() {
        _scanTourDraft = submitted;
        _isScanSubmitting = false;
      });
      if (submitted.status == PropertyTourStatus.processing ||
          submitted.status == PropertyTourStatus.queued) {
        _startScanPolling();
      }
    } on Property3dScanException catch (error) {
      if (!mounted) return;
      setState(() {
        _scanTourDraft = _scanTourDraft?.copyWith(
          status: PropertyTourStatus.captured,
          updatedAt: DateTime.now().toUtc(),
        );
        _isScanSubmitting = false;
      });
      _showMediaError(error.message);
    } on StorageException catch (error) {
      if (!mounted) return;
      setState(() => _isScanSubmitting = false);
      _showMediaError(error.message);
    } catch (error) {
      if (!mounted) return;
      setState(() => _isScanSubmitting = false);
      _showMediaError('סריקת ה־3D נכשלה: $error');
    }
  }

  Future<void> _linkScaniverseScan() async {
    final service = ScaniverseService.instance;
    if (!service.isConfigured) {
      _showMediaError(
        'ייבוא סריקות אינו זמין כרגע.',
      );
      return;
    }
    final scan = await showModalBottomSheet<ScaniverseScan>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const _ScaniversePickerSheet(),
    );
    if (scan == null || !mounted) return;
    setState(() {
      _scanTourDraft = service.tourFromScan(scan);
    });
  }

  Future<void> _importScaniverseAssets() async {
    if (_wantsVerifiedListing) {
      _showMediaError(
          'בדירה מאומתת סריקות והעלאות ננעלות עד ביטול מצב האימות.');
      return;
    }
    try {
      setState(() => _isScanSubmitting = true);
      final imported = await _scaniverseImportService.importExportedModel(
        propertyId: widget.property.id,
        title: _scanTitle(),
      );
      if (!mounted) return;
      setState(() {
        _scanTourDraft = imported.tour;
        _model3dDraft = imported.model3d;
        _isScanSubmitting = false;
      });
    } on ScaniverseAssetImportException catch (error) {
      if (!mounted) return;
      setState(() => _isScanSubmitting = false);
      _showMediaError(error.message);
    } on ScaniverseException catch (error) {
      if (!mounted) return;
      setState(() => _isScanSubmitting = false);
      _showMediaError(error.message);
    } catch (error) {
      if (!mounted) return;
      setState(() => _isScanSubmitting = false);
      _showMediaError('ייבוא מודל מ-Scaniverse נכשל: $error');
    }
  }

  Future<void> _captureVerificationVideo() async {
    try {
      setState(() => _isCapturingVerification = true);
      final file = await _picker.pickVideo(
        source: ImageSource.camera,
        maxDuration: const Duration(seconds: 90),
      );
      if (file == null) {
        if (mounted) setState(() => _isCapturingVerification = false);
        return;
      }

      final localPath = await _storageService.saveVideoLocally(
        file,
        folderName: 'property_verification_videos',
      );
      final remoteUrl = await _storageService.uploadToCloud(localPath);
      final videoUrl = remoteUrl ?? localPath;
      final capturedAt = DateTime.now().toUtc();
      if (!mounted) return;
      setState(() {
        _wantsVerifiedListing = true;
        _verificationVideoUrl = videoUrl;
        _verificationCapturedAt = capturedAt;
        _virtualTourDraft = null;
        _model3dDraft = null;
        _replaceMediaDraftsWithSingleVideo(videoUrl);
        _isCapturingVerification = false;
      });
    } on StorageException catch (error) {
      if (!mounted) return;
      setState(() => _isCapturingVerification = false);
      _showMediaError(error.message);
    } catch (error) {
      if (!mounted) return;
      setState(() => _isCapturingVerification = false);
      _showMediaError('צילום וידאו האימות נכשל: $error');
    }
  }

  String _scanTitle() {
    final city = _cityCtrl.text.trim();
    final street = _streetCtrl.text.trim();
    final parts = [
      if (street.isNotEmpty) street,
      if (city.isNotEmpty) city,
    ];
    return parts.isEmpty ? 'Rently apartment scan' : parts.join(', ');
  }

  void _assignPickedMedia(String path, PropertyMediaType type) {
    if (!mounted) return;
    if (_wantsVerifiedListing) {
      _showMediaError('בדירה מאומתת אי אפשר להוסיף מדיה ידנית או מהגלריה.');
      return;
    }
    final emptyIndex = _mediaDrafts.indexWhere(
      (draft) => draft.controller.text.trim().isEmpty,
    );
    if (emptyIndex != -1) {
      setState(() {
        _mediaDrafts[emptyIndex].controller.text = path;
        _mediaDrafts[emptyIndex].type = type;
      });
      return;
    }
    if (_mediaDrafts.length >= SecurityConfig.maxPropertyMediaItems) {
      _showMediaError(
        'אפשר לצרף עד ${SecurityConfig.maxPropertyMediaItems} פריטי מדיה.',
      );
      return;
    }
    setState(() {
      _mediaDrafts.add(_PropertyMediaDraft(initialValue: path, type: type));
    });
  }

  void _replaceMediaDraftsWithSingleVideo(String videoUrl) {
    for (final draft in _mediaDrafts) {
      draft.dispose();
    }
    _mediaDrafts
      ..clear()
      ..add(
        _PropertyMediaDraft(
          initialValue: videoUrl,
          type: PropertyMediaType.video,
        ),
      );
  }

  void _resetMediaDrafts() {
    for (final draft in _mediaDrafts) {
      draft.dispose();
    }
    _mediaDrafts
      ..clear()
      ..add(_PropertyMediaDraft());
  }

  void _setVerifiedListingMode(bool value) {
    setState(() {
      _wantsVerifiedListing = value;
      _verificationVideoUrl = '';
      _verificationCapturedAt = null;
      _virtualTourDraft = null;
      _scanTourDraft = null;
      _model3dDraft = null;
      _resetMediaDrafts();
    });
  }

  void _clearVerificationVideo() {
    setState(() {
      _verificationVideoUrl = '';
      _verificationCapturedAt = null;
      _resetMediaDrafts();
    });
  }

  void _showMediaError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(milliseconds: 2500),
        content: Text(message),
        backgroundColor: AppColors.coral,
      ),
    );
  }

  Future<void> _save() async {
    final city = _cityCtrl.text.trim();
    final street = _streetCtrl.text.trim();
    final size = int.tryParse(_sizeCtrl.text.trim()) ?? 0;
    if (city.isEmpty || street.isEmpty || size == 0) return;

    if (!_acceptedPropertyTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(milliseconds: 2500),
          content:
              Text('יש לאשר את תנאי השימוש והצהרת הזכויות לפני שמירת הנכס.'),
          backgroundColor: AppColors.coral,
        ),
      );
      return;
    }

    final sanitizedVerificationVideoUrl =
        InputSanitizer.sanitizeMediaUrl(_verificationVideoUrl);
    if (_wantsVerifiedListing &&
        (sanitizedVerificationVideoUrl == null ||
            sanitizedVerificationVideoUrl.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(milliseconds: 2500),
          content:
              Text('כדי לשמור דירה מאומתת צריך לצלם וידאו מתוך האפליקציה.'),
          backgroundColor: AppColors.coral,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final media = _wantsVerifiedListing
          ? [
              PropertyMedia(
                url: sanitizedVerificationVideoUrl!,
                type: PropertyMediaType.video,
              ),
            ]
          : _mediaDrafts
              .map((draft) {
                final sanitized =
                    InputSanitizer.sanitizeMediaUrl(draft.controller.text.trim());
                if (sanitized == null || sanitized.isEmpty) return null;
                return PropertyMedia(url: sanitized, type: draft.type);
              })
              .whereType<PropertyMedia>()
              .toList();
      final verification = _wantsVerifiedListing
          ? PropertyVerification.cameraVideo(
              videoUrl: sanitizedVerificationVideoUrl!,
              capturedAt: _verificationCapturedAt ??
                  widget.property.verification.capturedAt ??
                  DateTime.now().toUtc(),
            )
          : const PropertyVerification();
      final transactionType = _transactionType;
      // Sale price is a one-time total, so it uses the wider sale ceiling.
      final sanitizedPrice = transactionType == PropertyTransactionType.sale
          ? _price.clamp(0, _kMaxSalePrice)
          : InputSanitizer.clampPrice(_price);
      final nextHistory = [
        ...widget.property.priceHistory,
        if (sanitizedPrice > 0 &&
            (widget.property.priceHistory.isEmpty ||
                widget.property.priceHistory.last.price != sanitizedPrice ||
                widget.property.priceHistory.last.transactionType !=
                    transactionType))
          PropertyPricePoint(
            date: DateTime.now().toUtc(),
            price: sanitizedPrice,
            transactionType: transactionType,
          ),
      ];
      final legal = _buildPropertyLegal(
        acceptedTerms: _acceptedPropertyTerms,
        thirdPartyTransferAllowed: _thirdPartyTransferAllowed,
        commercialSaleAllowed: _commercialSaleAllowed,
        aiTrainingAllowed: _aiTrainingAllowed,
        existing: widget.property.legal,
      );

      final updated = RentalProperty(
        id: widget.property.id,
        sourceUrl: widget.property.sourceUrl,
        price: sanitizedPrice,
        rooms: _rooms,
        sizeM2: size,
        floor: _floorCtrl.text.trim(),
        totalFloors: _totalFloorsCtrl.text.trim(),
        city: city,
        neighborhood: _neighborhoodCtrl.text.trim(),
        street: street,
        streetNumber: int.tryParse(_streetNumCtrl.text.trim()) ?? -1,
        lat: widget.property.lat,
        lon: widget.property.lon,
        propertyType: _propertyType,
        entryDate: _entryDateCtrl.text.trim(),
        condition: _condition,
        ownerName: widget.property.ownerName,
        agencyListing: _agencyListing,
        features: _selectedFeatures.toList(),
        publishChannels: _publishChannels.toList(),
        media: media,
        transactionType: transactionType,
        virtualTour: _scanTourDraft ?? _virtualTourDraft,
        model3d: _model3dDraft,
        panoramaTour: _panoramaTourDraft,
        legal: legal,
        priceHistory: nextHistory,
        marketSignals: widget.property.marketSignals,
        verification: verification,
        isActive: _isActive,
        designTemplate: _designTemplate,
        designAccent: _designAccent,
        createdAt: widget.property.createdAt,
      );

      await context.read<DatingProvider>().updateLandlordProperty(updated);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(milliseconds: 2500),
          content: Text('הנכס עודכן בהצלחה'),
          backgroundColor: Color(0xFF1B9C6A),
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration: const Duration(milliseconds: 3000),
        content: Text('שגיאה בעדכון הנכס. נסה שוב.'),
        backgroundColor: AppColors.coral,
      ));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const RentlyIcon(IconsaxPlusLinear.arrow_right,
              color: Colors.white),
          onPressed: _prev,
        ),
        title: Text(
          'עריכת נכס · ${_stepLabels[_step]}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: _StepIndicator(step: _step, total: 4, labels: _stepLabels),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView(
              controller: _pageCtrl,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _StepLocation(
                  cityCtrl: _cityCtrl,
                  neighborhoodCtrl: _neighborhoodCtrl,
                  streetCtrl: _streetCtrl,
                  streetNumCtrl: _streetNumCtrl,
                ),
                _StepDetails(
                  price: _price,
                  transactionType: _transactionType,
                  rooms: _rooms,
                  cityCtrl: _cityCtrl,
                  sizeCtrl: _sizeCtrl,
                  floorCtrl: _floorCtrl,
                  totalFloorsCtrl: _totalFloorsCtrl,
                  entryDateCtrl: _entryDateCtrl,
                  propertyType: _propertyType,
                  condition: _condition,
                  designTemplate: _designTemplate,
                  designAccent: _designAccent,
                  onTransactionTypeChanged: (v) => setState(() {
                    _transactionType = v;
                    if (v == PropertyTransactionType.sale && _price < 100000) {
                      _price = 1500000;
                    } else if (v == PropertyTransactionType.rent &&
                        _price > 50000) {
                      _price = 5000;
                    }
                  }),
                  onPriceChanged: (v) =>
                      setState(() => _price = v.round()),
                  onPriceSet: (v) => setState(() => _price = v),
                  onRoomsChanged: (v) =>
                      setState(() => _rooms = (v * 2).round() / 2),
                  onTypeChanged: (v) => setState(() => _propertyType = v!),
                  onConditionChanged: (v) => setState(() => _condition = v!),
                  onDesignTemplateChanged: (v) =>
                      setState(() => _designTemplate = v),
                  onDesignAccentChanged: (v) =>
                      setState(() => _designAccent = v),
                ),
                _StepFeatures(
                  allFeatures: _propertyFeatureLabels,
                  selectedFeatures: _selectedFeatures,
                  onToggle: (f) => setState(() {
                    if (_selectedFeatures.contains(f)) {
                      _selectedFeatures.remove(f);
                    } else {
                      _selectedFeatures.add(f);
                    }
                  }),
                  publishChannels: _publishChannels,
                  onChannelToggle: (c) => setState(() {
                    if (_publishChannels.contains(c)) {
                      _publishChannels.remove(c);
                    } else {
                      _publishChannels.add(c);
                    }
                  }),
                ),
                _StepPhotos(
                  mediaDrafts: _mediaDrafts,
                  virtualTourDraft: _virtualTourDraft,
                  isSubmittingTour: _isSubmittingTour,
                  scanTourDraft: _scanTourDraft,
                  isScanSubmitting: _isScanSubmitting,
                  isScanBackendConfigured: _scanService.isConfigured,
                  wantsVerifiedListing: _wantsVerifiedListing,
                  verificationVideoUrl: _verificationVideoUrl,
                  verificationCapturedAt: _verificationCapturedAt,
                  isCapturingVerification: _isCapturingVerification,
                  onVerifiedListingChanged: _setVerifiedListingMode,
                  onCaptureVerificationVideo: _captureVerificationVideo,
                  onClearVerificationVideo: _clearVerificationVideo,
                  onPickImageFromGallery: () =>
                      _pickPropertyImage(ImageSource.gallery),
                  onPickImageFromCamera: () =>
                      _pickPropertyImage(ImageSource.camera),
                  onPickVideoFromGallery: () =>
                      _pickPropertyVideo(ImageSource.gallery),
                  onPickVideoFromCamera: () =>
                      _pickPropertyVideo(ImageSource.camera),
                  onPickScanFromGallery: () =>
                      _pickScanVideo(ImageSource.gallery),
                  onPickScanFromCamera: () =>
                      _pickScanVideo(ImageSource.camera),
                  onOpenRoomScan: _openRoomScan,
                  roomScanCount: _roomScans.length,
                  onLinkScaniverse: ScaniverseService.instance.isConfigured
                      ? () => _linkScaniverseScan()
                      : null,
                  onImportScaniverseAssets: _importScaniverseAssets,
                  onClearVirtualTour: () => setState(() {
                    _virtualTourDraft = null;
                  }),
                  onClearScan: () => setState(() {
                    _scanTourDraft = null;
                    _model3dDraft = null;
                  }),
                  onCreatePanoramaTour: _createPanoramaTour,
                  panoramaPointCount: _panoramaTourDraft?.length ?? 0,
                  acceptedTerms: _acceptedPropertyTerms,
                  onAcceptedTermsChanged: (value) =>
                      setState(() => _acceptedPropertyTerms = value),
                  thirdPartyTransferAllowed: _thirdPartyTransferAllowed,
                  onThirdPartyTransferChanged: (value) =>
                      setState(() => _thirdPartyTransferAllowed = value),
                  commercialSaleAllowed: _commercialSaleAllowed,
                  onCommercialSaleChanged: (value) =>
                      setState(() => _commercialSaleAllowed = value),
                  aiTrainingAllowed: _aiTrainingAllowed,
                  onAiTrainingChanged: (value) =>
                      setState(() => _aiTrainingAllowed = value),
                  onAddMediaUrl: _assignPickedMedia,
                  onRemoveMedia: (i) => setState(() {
                    _mediaDrafts[i].dispose();
                    _mediaDrafts.removeAt(i);
                  }),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _EditPropertyFooter(
        step: _step,
        total: 4,
        isLoading: _isSaving,
        saveLabel: 'עדכון הנכס',
        onNext: _next,
        onPrev: _prev,
        isActive: _isActive,
        onActiveChanged: (value) => setState(() => _isActive = value),
        transactionType: widget.property.transactionType,
        onDelete: () async {
          final provider = context.read<DatingProvider>();
          final navigator = Navigator.of(context);
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22)),
              title: const Text(
                'הסרת נכס',
                style: TextStyle(
                    color: AppColors.navy,
                    fontWeight: FontWeight.w900),
              ),
              content: Text(
                'להסיר את "${widget.property.address}"?\nהפעולה אינה ניתנת לביטול.',
                style: const TextStyle(
                    color: AppColors.textSecondary, height: 1.4),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('ביטול',
                      style:
                          TextStyle(color: AppColors.textSecondary)),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.coral,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('הסר'),
                ),
              ],
            ),
          );
          if (confirmed == true) {
            await provider.removeLandlordProperty(widget.property.id);
            if (mounted) {
              navigator.pop();
            }
          }
        },
      ),
    );
  }
}

// ─── Scaniverse Scan Picker ───────────────────────────────────────────────────

class _ScaniversePickerSheet extends StatefulWidget {
  const _ScaniversePickerSheet();

  @override
  State<_ScaniversePickerSheet> createState() => _ScaniversePickerSheetState();
}

class _ScaniversePickerSheetState extends State<_ScaniversePickerSheet> {
  List<ScaniverseScan>? _scans;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final scans = await ScaniverseService.instance.listScans(limit: 30);
      if (mounted) {
        setState(() {
          _scans = scans;
          _loading = false;
        });
      }
    } on ScaniverseException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.45,
      maxChildSize: 0.92,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.borderLight,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight2,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.view_in_ar_rounded,
                      color: AppColors.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'בחר סריקה מ-Scaniverse',
                          style: TextStyle(
                            color: AppColors.navy,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          'סריקות מחשבון Niantic Spatial שלך',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Divider(height: 1, color: AppColors.borderLight),
            Expanded(child: _buildBody(scrollCtrl)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(ScrollController ctrl) {
    if (_loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppColors.primary),
            SizedBox(height: 12),
            Text(
              'טוען סריקות...',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: AppColors.coral, size: 40),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _loading = true;
                    _error = null;
                  });
                  _load();
                },
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('נסה שוב'),
              ),
            ],
          ),
        ),
      );
    }
    final scans = _scans ?? [];
    if (scans.isEmpty) {
      return const Center(
        child: Text(
          'לא נמצאו סריקות בחשבון Scaniverse.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }
    return ListView.separated(
      controller: ctrl,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      itemCount: scans.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _ScanTile(
        scan: scans[i],
        onTap: () => Navigator.pop(context, scans[i]),
      ),
    );
  }
}

class _ScanTile extends StatelessWidget {
  const _ScanTile({required this.scan, required this.onTap});
  final ScaniverseScan scan;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isReady = scan.isReady;
    final statusColor = isReady ? AppColors.success : AppColors.primary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isReady ? onTap : null,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isReady ? AppColors.borderLight : AppColors.borderLight,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.primaryLight2,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.view_in_ar_rounded,
                  color: AppColors.primary,
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      scan.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.navy,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            isReady ? 'מוכן' : 'בעיבוד',
                            style: TextStyle(
                              color: statusColor,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (scan.siteName.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Text(
                            scan.siteName,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (isReady)
                RentlyIcon(
                  IconsaxPlusLinear.arrow_left,
                  size: 16,
                  color: AppColors.primary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Transcodes a scan video to an H.264 mp4 for Teleport, which rejects the
/// HEVC/.mov files iOS records (they upload fine but fail reconstruction).
/// [VideoQuality.HighestQuality] preserves the detail the 3D pipeline needs.
/// Fail-soft: returns null so the caller uploads the original if transcoding
/// is unavailable rather than blocking the scan.
Future<String?> transcodeScanToMp4(String inputPath) async {
  try {
    final info = await VideoCompress.compressVideo(
      inputPath,
      quality: VideoQuality.HighestQuality,
      deleteOrigin: false,
      includeAudio: true,
    );
    final out = info?.path;
    if (out != null && out.trim().isNotEmpty) return out;
  } catch (error) {
    debugPrint('transcodeScanToMp4 failed: $error');
  }
  return null;
}

/// Pre-recording guide for a 3D apartment scan. Teleport's Gaussian-splat
/// reconstruction only succeeds on a steady, overlapping walkthrough that
/// covers the whole space — a quick pan or partial clip fails to rebuild and
/// comes back as a failed scan. Returns true when the user chooses to record.
Future<bool?> showScanCaptureGuide(BuildContext context) {
  const tips = <(IconData, String, String)>[
    (
      IconsaxPlusLinear.timer_1,
      'צלמו לאט ויציב',
      'הזיזו את הטלפון באיטיות וברציפות, בלי טלטולים — תנועה מהירה גורמת לטשטוש והסריקה נכשלת.',
    ),
    (
      IconsaxPlusLinear.rotate_left_1,
      'הקיפו כל חדר',
      'עברו סביב כל חדר וצלמו את הקירות, הפינות והרהיטים מכמה זוויות עם חפיפה ביניהן.',
    ),
    (
      IconsaxPlusLinear.sun_1,
      'תאורה טובה',
      'הדליקו אורות ופתחו וילונות. חדר חשוך או נגד-אור פוגע בשחזור התלת-ממדי.',
    ),
    (
      IconsaxPlusLinear.video,
      'כל הדירה, 30–60 שניות',
      'התחילו מהכניסה ועברו בין כל החללים ברצף אחד עד 60 שניות, בלי לדלג על חדרים.',
    ),
  ];
  return showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.white,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.borderLight,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'איך מצלמים סריקת 3D מוצלחת',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w900,
                color: AppColors.navy,
              ),
            ),
            const SizedBox(height: 14),
            for (final tip in tips)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(tip.$1, size: 19, color: AppColors.primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tip.$2,
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                              color: AppColors.navy,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            tip.$3,
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              fontSize: 12.5,
                              height: 1.45,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 4),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: () => Navigator.of(ctx).pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: const RentlyIcon(IconsaxPlusLinear.video, size: 18),
                label: const Text(
                  'הבנתי, התחל צילום',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                ),
              ),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text(
                'ביטול',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// ─── DIY 360° panorama-tour entry (Step Photos) ──────────────────────────────
class _Panorama360Tile extends StatelessWidget {
  const _Panorama360Tile({required this.count, required this.onTap});
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final has = count > 0;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [
              AppColors.primary,
              AppColors.primary.withValues(alpha: 0.78),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.28),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Stack(
          children: [
            // decorative 360 rings
            Positioned(
              right: -22,
              top: -22,
              child: Icon(IconsaxPlusLinear.global,
                  size: 120, color: Colors.white.withValues(alpha: 0.12)),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: const Icon(IconsaxPlusBold.camera,
                        color: Colors.white, size: 26),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Flexible(
                              child: Text('סיור 360° — מומלץ',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 16)),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.25),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: const Text('AR',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w900)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          has
                              ? '$count נקודות נוספו · הקש לעריכה או הוספה'
                              : 'הסיור המומלץ — נאמן למציאות. צילום מודרך כמו Street View',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.92),
                              fontSize: 12.5,
                              height: 1.3),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      has ? IconsaxPlusBold.tick_circle : IconsaxPlusBold.arrow_left_2,
                      color: AppColors.primary,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
