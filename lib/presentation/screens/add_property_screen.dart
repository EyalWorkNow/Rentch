import 'dart:ui' show PathMetric;
import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/security/input_sanitizer.dart';
import 'package:dating_app/core/security/rate_limiter.dart';
import 'package:dating_app/core/security/security_config.dart';
import 'package:dating_app/core/services/legal_consent_service.dart';
import 'package:dating_app/core/services/property_3d_scan_service.dart';
import 'package:dating_app/core/services/scaniverse_service.dart';
import 'package:dating_app/core/services/storage_service.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/presentation/widgets/safe_media.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:dating_app/presentation/widgets/rentch_icon.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

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
  const AddPropertyScreen({super.key});

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
  final String _draftPropertyId =
      'custom-${DateTime.now().millisecondsSinceEpoch}';

  int _price = 5000;
  double _rooms = 3;
  String _propertyType = 'דירה';
  String _condition = 'תקין';
  bool _agencyListing = false;
  final Set<String> _selectedFeatures = {};
  bool _isSaving = false;
  bool _isSubmittingTour = false;
  bool _isCapturingVerification = false;
  PropertyVirtualTour? _virtualTourDraft;
  bool _wantsVerifiedListing = false;
  String _verificationVideoUrl = '';
  DateTime? _verificationCapturedAt;
  bool _acceptedPropertyTerms = false;
  bool _thirdPartyTransferAllowed = false;
  bool _commercialSaleAllowed = false;
  bool _aiTrainingAllowed = false;

  @override
  void dispose() {
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

  bool _validateCurrentStep() {
    switch (_step) {
      case 0:
        return _cityCtrl.text.trim().isNotEmpty &&
            _streetCtrl.text.trim().isNotEmpty;
      case 1:
        return _sizeCtrl.text.trim().isNotEmpty;
      default:
        return true;
    }
  }

  void _next() {
    if (!_validateCurrentStep()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
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
      _assignPickedMedia(
        remoteUrl ?? localPath,
        PropertyMediaType.image,
      );
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
      _assignPickedMedia(
        remoteUrl ?? localPath,
        PropertyMediaType.video,
      );
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
    try {
      final file = await _picker.pickVideo(
        source: source,
        maxDuration: const Duration(seconds: 75),
      );
      if (file == null) return;

      setState(() => _isSubmittingTour = true);
      final localPath = await _storageService.saveVideoLocally(
        file,
        folderName: 'property_scan_videos',
      );
      final sizeBytes = await file.length();
      final captured = _scanService.localCapture(
        propertyId: _draftPropertyId,
        localVideoPath: localPath,
        sizeBytes: sizeBytes,
      );

      if (!_scanService.isConfigured) {
        setState(() {
          _virtualTourDraft = captured;
          _isSubmittingTour = false;
        });
        _showMediaError(
          'הסריקה נשמרה כטיוטה. כדי לשלוח לעיבוד צריך להגדיר RENTCH_3D_SCAN_PROXY_URL.',
        );
        return;
      }

      setState(() {
        _virtualTourDraft = captured.copyWith(
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
        _virtualTourDraft = submitted;
        _isSubmittingTour = false;
      });
    } on Property3dScanException catch (error) {
      if (!mounted) return;
      setState(() {
        _virtualTourDraft = _virtualTourDraft?.copyWith(
          status: PropertyTourStatus.failed,
          errorMessage: error.message,
          updatedAt: DateTime.now().toUtc(),
        );
        _isSubmittingTour = false;
      });
      _showMediaError(error.message);
    } on StorageException catch (error) {
      if (!mounted) return;
      setState(() => _isSubmittingTour = false);
      _showMediaError(error.message);
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSubmittingTour = false);
      _showMediaError('סריקת ה־3D נכשלה: $error');
    }
  }


  Future<void> _linkScaniverseScan() async {
    final service = ScaniverseService.instance;
    if (!service.isConfigured) {
      _showMediaError(
        'Scaniverse לא מוגדר. הפעל עם --dart-define=SPATIAL_API_KEY=<token>.',
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
    setState(() => _virtualTourDraft = service.tourFromScan(scan));
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
    return parts.isEmpty ? 'Rentch apartment scan' : parts.join(', ');
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
          content: Text('הוספת יותר מדי נכסים לאחרונה. נסה שוב מאוחר יותר.'),
          backgroundColor: AppColors.coral,
        ),
      );
      return;
    }

    if (!_acceptedPropertyTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
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

    final sanitizedVerificationVideoUrl =
        InputSanitizer.sanitizeMediaUrl(_verificationVideoUrl);
    if (_wantsVerifiedListing &&
        (sanitizedVerificationVideoUrl == null ||
            sanitizedVerificationVideoUrl.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('כדי לפרסם דירה מאומתת צריך לצלם וידאו מתוך האפליקציה.'),
          backgroundColor: AppColors.coral,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

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
    final sanitizedPrice = InputSanitizer.clampPrice(_price);
    final transactionType = PropertyTransactionType.rent;
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
      lat: 32.0853,
      lon: 34.7818,
      propertyType: _propertyType,
      entryDate: InputSanitizer.sanitizeText(_entryDateCtrl.text.trim(),
          maxLength: 20),
      condition: _condition,
      ownerName:
          context.read<DatingProvider>().tenantProfile?.name ?? 'בעל הדירה',
      agencyListing: _agencyListing,
      features: _selectedFeatures.toList(),
      media: media,
      transactionType: transactionType,
      virtualTour: _virtualTourDraft,
      legal: legal,
      priceHistory: priceHistory,
      verification: verification,
      createdAt: DateTime.now(),
    );

    await context.read<DatingProvider>().addLandlordProperty(property);

    if (!mounted) return;
    Navigator.of(context).pop();
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
            icon: const RentchIcon(IconsaxPlusLinear.arrow_right,
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
              rooms: _rooms,
              sizeCtrl: _sizeCtrl,
              floorCtrl: _floorCtrl,
              totalFloorsCtrl: _totalFloorsCtrl,
              entryDateCtrl: _entryDateCtrl,
              propertyType: _propertyType,
              condition: _condition,
              agencyListing: _agencyListing,
              onPriceChanged: (v) =>
                  setState(() => _price = (v / 100).round() * 100),
              onRoomsChanged: (v) =>
                  setState(() => _rooms = (v * 2).round() / 2),
              onTypeChanged: (v) => setState(() => _propertyType = v!),
              onConditionChanged: (v) => setState(() => _condition = v!),
              onAgencyChanged: (v) => setState(() => _agencyListing = v),
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
            ),
            _StepPhotos(
              mediaDrafts: _mediaDrafts,
              virtualTourDraft: _virtualTourDraft,
              isSubmittingTour: _isSubmittingTour,
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
              onLinkScaniverse: _linkScaniverseScan,
              onClearVirtualTour: () =>
                  setState(() => _virtualTourDraft = null),
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
        bottomSheet: _WizardNavBar(
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
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
              color: AppColors.shadow, blurRadius: 16, offset: Offset(0, -4))
        ],
      ),
      child: Row(
        children: [
          if (step > 0) ...[
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onPrev,
                icon: const RentchIcon(IconsaxPlusLinear.arrow_right, size: 16),
                label: const Text('חזרה'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.navy,
                  side: const BorderSide(color: AppColors.borderLight),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
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
                disabledBackgroundColor:
                    AppColors.primary.withValues(alpha: 0.5),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
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

  Future<void> _captureLocation() async {
    setState(() => _isLoading = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw 'שירותי המיקום כבויים במכשיר.';
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw 'הרשאת המיקום נדחתה.';
        }
      }
      if (permission == LocationPermission.deniedForever) {
        throw 'הרשאות המיקום חסומות לצמיתות בהגדרות המכשיר.';
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      await setLocaleIdentifier('he_IL');
      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

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
              content: Text('המיקום זוהה והוזן בהצלחה!'),
              backgroundColor: AppColors.success,
            ),
          );
        }
      } else {
        throw 'לא נמצאו נתוני כתובת עבור הקואורדינטות.';
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאה בזיהוי המיקום: $e'),
            backgroundColor: AppColors.coral,
          ),
        );
      }
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
              side: const BorderSide(color: AppColors.primary, width: 1),
            ),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          icon: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primary,
                  ),
                )
              : const RentchIcon(IconsaxPlusLinear.gps, size: 18),
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
              _Field(
                  ctrl: widget.cityCtrl,
                  label: 'עיר *',
                  icon: IconsaxPlusLinear.map),
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
                    child: _Field(
                        ctrl: widget.streetCtrl,
                        label: 'רחוב *',
                        icon: IconsaxPlusLinear.routing),
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

// ─── Step 2: Property Details ─────────────────────────────────────────────────

class _StepDetails extends StatelessWidget {
  const _StepDetails({
    required this.price,
    required this.rooms,
    required this.sizeCtrl,
    required this.floorCtrl,
    required this.totalFloorsCtrl,
    required this.entryDateCtrl,
    required this.propertyType,
    required this.condition,
    required this.agencyListing,
    required this.onPriceChanged,
    required this.onRoomsChanged,
    required this.onTypeChanged,
    required this.onConditionChanged,
    required this.onAgencyChanged,
  });

  final int price;
  final double rooms;
  final TextEditingController sizeCtrl;
  final TextEditingController floorCtrl;
  final TextEditingController totalFloorsCtrl;
  final TextEditingController entryDateCtrl;
  final String propertyType;
  final String condition;
  final bool agencyListing;
  final ValueChanged<double> onPriceChanged;
  final ValueChanged<double> onRoomsChanged;
  final ValueChanged<String?> onTypeChanged;
  final ValueChanged<String?> onConditionChanged;
  final ValueChanged<bool> onAgencyChanged;

  @override
  Widget build(BuildContext context) {
    final roomsLabel = rooms % 1 == 0 ? rooms.toInt().toString() : '$rooms';
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 130),
      children: [
        _SectionHint(
          icon: IconsaxPlusLinear.building,
          title: 'פרטי הנכס',
          subtitle: 'גודל הדירה הוא שדה חובה',
        ),
        const SizedBox(height: 16),
        _FormCard(
          child: Column(
            children: [
              _SliderRow(
                label: 'מחיר לחודש',
                displayValue: _fmtPrice(price),
                value: price.toDouble(),
                min: 1000,
                max: 25000,
                divisions: 240,
                onChanged: onPriceChanged,
              ),
              const SizedBox(height: 10),
              _SliderRow(
                label: 'מספר חדרים',
                displayValue: roomsLabel,
                value: rooms,
                min: 1,
                max: 6,
                divisions: 10,
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
                    child: _Field(
                      ctrl: floorCtrl,
                      label: 'קומה',
                      icon: IconsaxPlusLinear.layer,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _Field(
                      ctrl: totalFloorsCtrl,
                      label: 'סה"כ קומות',
                      icon: IconsaxPlusLinear.buildings,
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
              _Field(
                ctrl: entryDateCtrl,
                label: 'תאריך כניסה (לדוגמה: 01/09)',
                icon: IconsaxPlusLinear.calendar,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text(
                    'פרסום תיווך מאומת',
                    style: TextStyle(
                        color: AppColors.navy,
                        fontWeight: FontWeight.w700,
                        fontSize: 14),
                  ),
                  const Spacer(),
                  Switch.adaptive(
                    value: agencyListing,
                    onChanged: onAgencyChanged,
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

// ─── Step 3: Features ─────────────────────────────────────────────────────────

class _StepFeatures extends StatelessWidget {
  const _StepFeatures({
    required this.allFeatures,
    required this.selectedFeatures,
    required this.onToggle,
  });
  final List<String> allFeatures;
  final Set<String> selectedFeatures;
  final ValueChanged<String> onToggle;

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
              if (selectedFeatures.isNotEmpty) ...[
                Text(
                  '${selectedFeatures.length} נבחרו',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Wrap(
                spacing: 8,
                runSpacing: 8,
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
                      child: Text(
                        f,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color:
                              selected ? Colors.white : AppColors.textSecondary,
                        ),
                      ),
                    ),
                  );
                }).toList(),
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
    required this.onLinkScaniverse,
    required this.onClearVirtualTour,
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
  final VoidCallback onLinkScaniverse;
  final VoidCallback onClearVirtualTour;
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
                const SizedBox(height: 18),
                const Divider(height: 1, color: AppColors.borderLight),
                const SizedBox(height: 16),
                _Scan3dPanel(
                  tour: virtualTourDraft,
                  isSubmitting: isSubmittingTour,
                  isBackendConfigured: isScanBackendConfigured,
                  onPickFromCamera: onPickScanFromCamera,
                  onPickFromGallery: onPickScanFromGallery,
                  onClear: onClearVirtualTour,
                  onLinkScaniverse: onLinkScaniverse,
                ),
              ],
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
              child: const Center(
                child: RentchIcon(
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
                    'דירה מאומתת מקבלת ניקוד גבוה יותר באלגוריתם.',
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
                  : const RentchIcon(IconsaxPlusLinear.video_play, size: 17),
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
                  child: const Center(
                    child: RentchIcon(
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
                          const RentchIcon(IconsaxPlusLinear.refresh, size: 14),
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
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RentchIcon(
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
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                RentchIcon(
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
    this.onLinkScaniverse,
  });

  final PropertyVirtualTour? tour;
  final bool isSubmitting;
  final bool isBackendConfigured;
  final VoidCallback onPickFromCamera;
  final VoidCallback onPickFromGallery;
  final VoidCallback onClear;
  final VoidCallback? onLinkScaniverse;

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
              width: 44,
              height: 44,
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
              child: const Icon(
                Icons.view_in_ar_rounded,
                color: Colors.white,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'סריקת 3D לדירה',
                    style: TextStyle(
                      color: AppColors.navy,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  SizedBox(height: 3),
                  Text(
                    'וידאו קצר ויציב הופך לסיור אינטראקטיבי קל לטעינה.',
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
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: const [
            _ScanTip(
              icon: Icons.access_time_filled_rounded,
              label: '45-75 שניות',
            ),
            _ScanTip(
              icon: Icons.wb_sunny_rounded,
              label: 'אור חזק',
            ),
            _ScanTip(
              icon: Icons.slow_motion_video_rounded,
              label: 'תנועה איטית',
            ),
            _ScanTip(
              icon: Icons.home_work_rounded,
              label: 'מעבר בכל חדר',
            ),
          ],
        ),
        const SizedBox(height: 18),
        if (currentTour == null)
          _ScanActions(
            isSubmitting: isSubmitting,
            onPickFromCamera: onPickFromCamera,
            onPickFromGallery: onPickFromGallery,
            onLinkScaniverse: onLinkScaniverse,
          )
        else
          _ScanStatusCard(
            tour: currentTour,
            isSubmitting: isSubmitting,
            isBackendConfigured: isBackendConfigured,
            onReplace: onPickFromCamera,
            onClear: onClear,
          ),
      ],
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
  });

  final bool isSubmitting;
  final VoidCallback onPickFromCamera;
  final VoidCallback onPickFromGallery;
  final VoidCallback? onLinkScaniverse;

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
                                RentchIcon(IconsaxPlusLinear.video_play,
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
                          RentchIcon(IconsaxPlusLinear.video,
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
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                ),
                child: const Row(
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
                  style: const TextStyle(
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
                  icon: const RentchIcon(IconsaxPlusLinear.refresh, size: 16),
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
    if (tour.needsBackendUpload && !isBackendConfigured) {
      return 'הווידאו נשמר במכשיר. אחרי חיבור proxy עם API key, הוא יישלח לעיבוד בענן.';
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
        filled: true,
        fillColor: AppColors.background,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.borderLight),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.borderLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.displayValue,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });
  final String label;
  final String displayValue;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600)),
            const Spacer(),
            Text(displayValue,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: AppColors.primary)),
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
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
      ],
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
        filled: true,
        fillColor: AppColors.background,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.borderLight),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.borderLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
      ),
      style: const TextStyle(
          color: AppColors.navy, fontWeight: FontWeight.w700, fontSize: 14),
      icon: const RentchIcon(IconsaxPlusLinear.arrow_down,
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

String _fmtPrice(int value) {
  final raw = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < raw.length; i++) {
    final remaining = raw.length - i;
    buffer.write(raw[i]);
    if (remaining > 1 && remaining % 3 == 1) buffer.write(',');
  }
  return '₪$buffer';
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

  late int _price;
  late double _rooms;
  late String _propertyType;
  late String _condition;
  late bool _agencyListing;
  late final Set<String> _selectedFeatures;
  bool _isSaving = false;
  bool _isSubmittingTour = false;
  bool _isCapturingVerification = false;
  PropertyVirtualTour? _virtualTourDraft;
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
    _rooms = p.rooms;
    _propertyType = p.propertyType;
    _condition = p.condition.isNotEmpty ? p.condition : 'תקין';
    _agencyListing = p.agencyListing;
    _selectedFeatures = Set<String>.from(p.features);
    _virtualTourDraft = p.virtualTour;
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

  bool _validateCurrentStep() {
    switch (_step) {
      case 0:
        return _cityCtrl.text.trim().isNotEmpty &&
            _streetCtrl.text.trim().isNotEmpty;
      case 1:
        return _sizeCtrl.text.trim().isNotEmpty;
      default:
        return true;
    }
  }

  void _next() {
    if (!_validateCurrentStep()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
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
    try {
      final file = await _picker.pickVideo(
        source: source,
        maxDuration: const Duration(seconds: 75),
      );
      if (file == null) return;

      setState(() => _isSubmittingTour = true);
      final localPath = await _storageService.saveVideoLocally(
        file,
        folderName: 'property_scan_videos',
      );
      final sizeBytes = await file.length();
      final captured = _scanService.localCapture(
        propertyId: widget.property.id,
        localVideoPath: localPath,
        sizeBytes: sizeBytes,
      );

      if (!_scanService.isConfigured) {
        setState(() {
          _virtualTourDraft = captured;
          _isSubmittingTour = false;
        });
        _showMediaError(
          'הסריקה נשמרה כטיוטה. כדי לשלוח לעיבוד צריך להגדיר RENTCH_3D_SCAN_PROXY_URL.',
        );
        return;
      }

      setState(() {
        _virtualTourDraft = captured.copyWith(
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
        _virtualTourDraft = submitted;
        _isSubmittingTour = false;
      });
    } on Property3dScanException catch (error) {
      if (!mounted) return;
      setState(() {
        _virtualTourDraft = _virtualTourDraft?.copyWith(
          status: PropertyTourStatus.failed,
          errorMessage: error.message,
          updatedAt: DateTime.now().toUtc(),
        );
        _isSubmittingTour = false;
      });
      _showMediaError(error.message);
    } on StorageException catch (error) {
      if (!mounted) return;
      setState(() => _isSubmittingTour = false);
      _showMediaError(error.message);
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSubmittingTour = false);
      _showMediaError('סריקת ה־3D נכשלה: $error');
    }
  }

  Future<void> _linkScaniverseScan() async {
    final service = ScaniverseService.instance;
    if (!service.isConfigured) {
      _showMediaError(
        'Scaniverse לא מוגדר. הפעל עם --dart-define=SPATIAL_API_KEY=<token>.',
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
    setState(() => _virtualTourDraft = service.tourFromScan(scan));
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
    return parts.isEmpty ? 'Rentch apartment scan' : parts.join(', ');
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
          content:
              Text('כדי לשמור דירה מאומתת צריך לצלם וידאו מתוך האפליקציה.'),
          backgroundColor: AppColors.coral,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

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
    final sanitizedPrice = InputSanitizer.clampPrice(_price);
    final transactionType = widget.property.transactionType;
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
      media: media,
      transactionType: transactionType,
      virtualTour: _virtualTourDraft,
      legal: legal,
      priceHistory: nextHistory,
      marketSignals: widget.property.marketSignals,
      verification: verification,
      isActive: _isActive,
      createdAt: widget.property.createdAt,
    );

    await context.read<DatingProvider>().updateLandlordProperty(updated);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('הנכס עודכן בהצלחה'),
        backgroundColor: Color(0xFF1B9C6A),
      ),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const RentchIcon(IconsaxPlusLinear.arrow_right,
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
                  rooms: _rooms,
                  sizeCtrl: _sizeCtrl,
                  floorCtrl: _floorCtrl,
                  totalFloorsCtrl: _totalFloorsCtrl,
                  entryDateCtrl: _entryDateCtrl,
                  propertyType: _propertyType,
                  condition: _condition,
                  agencyListing: _agencyListing,
                  onPriceChanged: (v) =>
                      setState(() => _price = (v / 100).round() * 100),
                  onRoomsChanged: (v) =>
                      setState(() => _rooms = (v * 2).round() / 2),
                  onTypeChanged: (v) => setState(() => _propertyType = v!),
                  onConditionChanged: (v) => setState(() => _condition = v!),
                  onAgencyChanged: (v) => setState(() => _agencyListing = v),
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
                ),
                _StepPhotos(
                  mediaDrafts: _mediaDrafts,
                  virtualTourDraft: _virtualTourDraft,
                  isSubmittingTour: _isSubmittingTour,
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
                  onLinkScaniverse: _linkScaniverseScan,
                  onClearVirtualTour: () =>
                      setState(() => _virtualTourDraft = null),
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
          // Action bar at bottom: active status toggle and delete button
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(
                  top: BorderSide(color: AppColors.borderLight, width: 1)),
            ),
            child: Row(
              children: [
                Icon(
                  _isActive
                      ? Icons.check_circle_outline_rounded
                      : Icons.pause_circle_outline_rounded,
                  color:
                      _isActive ? AppColors.success : AppColors.textSecondary,
                  size: 20,
                ),
                const SizedBox(width: 6),
                Text(
                  _isActive ? 'סטטוס: פעיל' : 'סטטוס: לא פעיל',
                  style: TextStyle(
                    color:
                        _isActive ? AppColors.success : AppColors.textSecondary,
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(width: 8),
                Switch(
                  value: _isActive,
                  onChanged: (value) => setState(() => _isActive = value),
                  activeThumbColor: AppColors.success,
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () async {
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
                  icon: const RentchIcon(IconsaxPlusLinear.trash,
                      color: AppColors.coral, size: 16),
                  label: const Text(
                    'מחיקת נכס',
                    style: TextStyle(
                      color: AppColors.coral,
                      fontWeight: FontWeight.w800,
                      fontSize: 13.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 72 + MediaQuery.of(context).padding.bottom),
        ],
      ),
      bottomSheet: _WizardNavBar(
        step: _step,
        total: 4,
        isLoading: _isSaving,
        saveLabel: 'עדכון הנכס',
        onNext: _next,
        onPrev: _prev,
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
      if (mounted) setState(() { _scans = scans; _loading = false; });
    } on ScaniverseException catch (e) {
      if (mounted) setState(() { _error = e.message; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
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
                    child: const Icon(
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
      return const Center(
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
                  setState(() { _loading = true; _error = null; });
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
                child: const Icon(
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
                        if (scan.createdAt != null) ...[
                          const SizedBox(width: 6),
                          Text(
                            '${scan.createdAt!.day}.${scan.createdAt!.month}.${scan.createdAt!.year}',
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
                const RentchIcon(
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
