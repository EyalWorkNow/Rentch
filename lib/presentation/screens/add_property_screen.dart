import 'dart:io';

import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/services/storage_service.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

class AddPropertyScreen extends StatefulWidget {
  const AddPropertyScreen({super.key});

  @override
  State<AddPropertyScreen> createState() => _AddPropertyScreenState();
}

class _AddPropertyScreenState extends State<AddPropertyScreen> {
  static const _stepLabels = ['מיקום', 'פרטי הנכס', 'מאפיינים', 'תמונות'];

  static const _allFeatures = [
    'מרפסת',
    'חניה',
    'מחסן',
    'מזגן',
    'ממ"ד',
    'מרפסת שמש',
    'גינה',
    'מעלית',
    'ריהוט',
    'אינטרנט כלול',
    'מטבח מאובזר',
    'חיות מחמד מותר',
    'כביסה כלולה',
    'שומר/אבטחה',
    'נגישות לנכים',
    'גג משותף',
    'בריכה',
    'חדר כושר',
  ];

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
  final List<TextEditingController> _imageCtrlList = [TextEditingController()];
  final _picker = ImagePicker();
  final _storageService = StorageService();

  int _price = 5000;
  double _rooms = 3;
  String _propertyType = 'דירה';
  String _condition = 'תקין';
  bool _agencyListing = false;
  final Set<String> _selectedFeatures = {};
  bool _isSaving = false;

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
    for (final c in _imageCtrlList) {
      c.dispose();
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
    final imagePath = remoteUrl ?? localPath;
    if (!mounted) return;

    setState(() {
      final emptyIndex =
          _imageCtrlList.indexWhere((ctrl) => ctrl.text.trim().isEmpty);
      if (emptyIndex == -1 && _imageCtrlList.length < 6) {
        _imageCtrlList.add(TextEditingController(text: imagePath));
      } else if (emptyIndex != -1) {
        _imageCtrlList[emptyIndex].text = imagePath;
      }
    });
  }

  Future<void> _save() async {
    final city = _cityCtrl.text.trim();
    final street = _streetCtrl.text.trim();
    final size = int.tryParse(_sizeCtrl.text.trim()) ?? 0;

    if (city.isEmpty || street.isEmpty || size == 0) return;

    setState(() => _isSaving = true);

    final imageUrls = _imageCtrlList
        .map((c) => c.text.trim())
        .where((u) => u.isNotEmpty)
        .toList();

    final property = RentalProperty(
      id: 'custom-${DateTime.now().millisecondsSinceEpoch}',
      url: '',
      price: _price,
      rooms: _rooms,
      sizeM2: size,
      floor: _floorCtrl.text.trim(),
      totalFloors: _totalFloorsCtrl.text.trim(),
      city: city,
      neighborhood: _neighborhoodCtrl.text.trim(),
      street: street,
      streetNumber: int.tryParse(_streetNumCtrl.text.trim()) ?? -1,
      lat: 32.0853,
      lon: 34.7818,
      propertyType: _propertyType,
      entryDate: _entryDateCtrl.text.trim(),
      condition: _condition,
      ownerName:
          context.read<DatingProvider>().tenantProfile?.name ?? 'בעל הדירה',
      agencyListing: _agencyListing,
      features: _selectedFeatures.toList(),
      imageUrls: imageUrls,
    );

    await context.read<DatingProvider>().addLandlordProperty(property);

    if (!mounted) return;
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
          icon: const Icon(IconsaxPlusLinear.arrow_right, color: Colors.white),
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
            onRoomsChanged: (v) => setState(() => _rooms = (v * 2).round() / 2),
            onTypeChanged: (v) => setState(() => _propertyType = v!),
            onConditionChanged: (v) => setState(() => _condition = v!),
            onAgencyChanged: (v) => setState(() => _agencyListing = v),
          ),
          _StepFeatures(
            allFeatures: _allFeatures,
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
            imageCtrlList: _imageCtrlList,
            onPickFromGallery: () => _pickPropertyImage(ImageSource.gallery),
            onPickFromCamera: () => _pickPropertyImage(ImageSource.camera),
            onAddImage: () =>
                setState(() => _imageCtrlList.add(TextEditingController())),
            onRemoveImage: (i) => setState(() {
              _imageCtrlList[i].dispose();
              _imageCtrlList.removeAt(i);
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
                icon: const Icon(IconsaxPlusLinear.arrow_right, size: 16),
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
                  : Icon(isLast ? IconsaxPlusBold.add_square : null, size: 16),
              label: Text(
                  isLoading
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

class _StepLocation extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 130),
      children: [
        _SectionHint(
          icon: IconsaxPlusBold.location,
          title: 'איפה נמצאת הדירה?',
          subtitle: 'מלא עיר ורחוב לפחות',
        ),
        const SizedBox(height: 16),
        _FormCard(
          child: Column(
            children: [
              _Field(
                  ctrl: cityCtrl, label: 'עיר *', icon: IconsaxPlusLinear.map),
              const SizedBox(height: 12),
              _Field(
                  ctrl: neighborhoodCtrl,
                  label: 'שכונה (אופציונלי)',
                  icon: IconsaxPlusLinear.map_1),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: _Field(
                        ctrl: streetCtrl,
                        label: 'רחוב *',
                        icon: IconsaxPlusLinear.routing),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _Field(
                      ctrl: streetNumCtrl,
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
          icon: IconsaxPlusBold.building,
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
              Row(
                children: [
                  Expanded(
                    child: _Field(
                      ctrl: sizeCtrl,
                      label: 'גודל (מ"ר) *',
                      icon: IconsaxPlusLinear.maximize_3,
                      numeric: true,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _Field(
                        ctrl: floorCtrl,
                        label: 'קומה',
                        icon: IconsaxPlusLinear.layer),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _Field(
                        ctrl: totalFloorsCtrl,
                        label: 'סה"כ קומות',
                        icon: IconsaxPlusLinear.buildings),
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
                    activeThumbColor: AppColors.primary,
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
          icon: IconsaxPlusBold.star,
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
    required this.imageCtrlList,
    required this.onPickFromGallery,
    required this.onPickFromCamera,
    required this.onAddImage,
    required this.onRemoveImage,
  });
  final List<TextEditingController> imageCtrlList;
  final VoidCallback onPickFromGallery;
  final VoidCallback onPickFromCamera;
  final VoidCallback onAddImage;
  final ValueChanged<int> onRemoveImage;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 130),
      children: [
        _SectionHint(
          icon: IconsaxPlusBold.gallery,
          title: 'תמונות הדירה',
          subtitle: 'אפשר להעלות תמונה מהמכשיר או להדביק קישור',
        ),
        const SizedBox(height: 16),
        _FormCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onPickFromGallery,
                      icon: const Icon(IconsaxPlusBold.gallery, size: 17),
                      label: const Text('בחר מהגלריה'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onPickFromCamera,
                      icon: const Icon(IconsaxPlusLinear.camera, size: 17),
                      label: const Text('צלם עכשיו'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.navy,
                        side: const BorderSide(color: AppColors.borderLight),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _PhotoPreviewStrip(imageCtrlList: imageCtrlList),
              const SizedBox(height: 14),
              ...imageCtrlList.asMap().entries.map((e) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: _Field(
                          ctrl: e.value,
                          label: 'תמונה ${e.key + 1} - קישור או נתיב קובץ',
                          icon: IconsaxPlusLinear.image,
                        ),
                      ),
                      if (e.key > 0) ...[
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => onRemoveImage(e.key),
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: AppColors.coral.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.close,
                                size: 18, color: AppColors.coral),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }),
              if (imageCtrlList.length < 6)
                GestureDetector(
                  onTap: onAddImage,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.primary),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(IconsaxPlusLinear.add,
                            size: 14, color: AppColors.primary),
                        SizedBox(width: 5),
                        Text(
                          'הוסף תמונה',
                          style: TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700,
                              fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PhotoPreviewStrip extends StatelessWidget {
  const _PhotoPreviewStrip({required this.imageCtrlList});

  final List<TextEditingController> imageCtrlList;

  @override
  Widget build(BuildContext context) {
    final images = imageCtrlList
        .map((ctrl) => ctrl.text.trim())
        .where((url) => url.isNotEmpty)
        .toList();
    if (images.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: const Row(
          children: [
            Icon(IconsaxPlusLinear.image, color: AppColors.textSecondary),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'תמונה טובה מעלה אמון ומבליטה את הדירה בסוויפים.',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12.5,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: images.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) => ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            width: 112,
            height: 92,
            child: _PropertyImagePreview(url: images[i]),
          ),
        ),
      ),
    );
  }
}

class _PropertyImagePreview extends StatelessWidget {
  const _PropertyImagePreview({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    if (url.startsWith('/') || url.startsWith('file://')) {
      final path = url.startsWith('file://') ? url.substring(7) : url;
      return Image.file(
        File(path),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _fallback(),
      );
    }
    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => _fallback(),
    );
  }

  Widget _fallback() => Container(
        color: AppColors.primaryLight2,
        child: const Icon(
          IconsaxPlusBold.building,
          color: AppColors.primary,
        ),
      );
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
    return Row(
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600)),
        const Spacer(),
        DropdownButton<String>(
          value: value,
          underline: const SizedBox.shrink(),
          style: const TextStyle(
              color: AppColors.navy, fontWeight: FontWeight.w700, fontSize: 14),
          items: options
              .map((o) => DropdownMenuItem(value: o, child: Text(o)))
              .toList(),
          onChanged: onChanged,
        ),
      ],
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
  static const _stepLabels = ['מיקום', 'פרטי הנכס', 'מאפיינים', 'תמונות'];

  static const _allFeatures = [
    'מרפסת', 'חניה', 'מחסן', 'מזגן', 'ממ"ד', 'מרפסת שמש', 'גינה', 'מעלית',
    'ריהוט', 'אינטרנט כלול', 'מטבח מאובזר', 'חיות מחמד מותר', 'כביסה כלולה',
    'שומר/אבטחה', 'נגישות לנכים', 'גג משותף', 'בריכה', 'חדר כושר',
  ];

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
  late final List<TextEditingController> _imageCtrlList;
  final _picker = ImagePicker();
  final _storageService = StorageService();

  late int _price;
  late double _rooms;
  late String _propertyType;
  late String _condition;
  late bool _agencyListing;
  late final Set<String> _selectedFeatures;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final p = widget.property;
    _cityCtrl = TextEditingController(text: p.city);
    _neighborhoodCtrl = TextEditingController(text: p.neighborhood);
    _streetCtrl = TextEditingController(text: p.street);
    _streetNumCtrl =
        TextEditingController(text: p.streetNumber > 0 ? '${p.streetNumber}' : '');
    _floorCtrl = TextEditingController(text: p.floor);
    _totalFloorsCtrl = TextEditingController(text: p.totalFloors);
    _sizeCtrl = TextEditingController(text: '${p.sizeM2}');
    _entryDateCtrl = TextEditingController(text: p.entryDate);
    _imageCtrlList = p.imageUrls.isNotEmpty
        ? p.imageUrls.map((u) => TextEditingController(text: u)).toList()
        : [TextEditingController()];
    _price = p.price;
    _rooms = p.rooms;
    _propertyType = p.propertyType;
    _condition = p.condition.isNotEmpty ? p.condition : 'תקין';
    _agencyListing = p.agencyListing;
    _selectedFeatures = Set<String>.from(p.features);
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
    for (final c in _imageCtrlList) {
      c.dispose();
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
    final file = await _picker.pickImage(
      source: source,
      imageQuality: 86,
      maxWidth: 1800,
    );
    if (file == null) return;
    final localPath =
        await _storageService.saveImageLocally(file, folderName: 'property_photos');
    final remoteUrl = await _storageService.uploadToCloud(localPath);
    final imagePath = remoteUrl ?? localPath;
    if (!mounted) return;
    setState(() {
      final emptyIndex =
          _imageCtrlList.indexWhere((ctrl) => ctrl.text.trim().isEmpty);
      if (emptyIndex == -1 && _imageCtrlList.length < 6) {
        _imageCtrlList.add(TextEditingController(text: imagePath));
      } else if (emptyIndex != -1) {
        _imageCtrlList[emptyIndex].text = imagePath;
      }
    });
  }

  Future<void> _save() async {
    final city = _cityCtrl.text.trim();
    final street = _streetCtrl.text.trim();
    final size = int.tryParse(_sizeCtrl.text.trim()) ?? 0;
    if (city.isEmpty || street.isEmpty || size == 0) return;

    setState(() => _isSaving = true);

    final imageUrls = _imageCtrlList
        .map((c) => c.text.trim())
        .where((u) => u.isNotEmpty)
        .toList();

    final updated = RentalProperty(
      id: widget.property.id,
      url: widget.property.url,
      price: _price,
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
      imageUrls: imageUrls,
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
          icon: const Icon(IconsaxPlusLinear.arrow_right, color: Colors.white),
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
            onRoomsChanged: (v) => setState(() => _rooms = (v * 2).round() / 2),
            onTypeChanged: (v) => setState(() => _propertyType = v!),
            onConditionChanged: (v) => setState(() => _condition = v!),
            onAgencyChanged: (v) => setState(() => _agencyListing = v),
          ),
          _StepFeatures(
            allFeatures: _allFeatures,
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
            imageCtrlList: _imageCtrlList,
            onPickFromGallery: () => _pickPropertyImage(ImageSource.gallery),
            onPickFromCamera: () => _pickPropertyImage(ImageSource.camera),
            onAddImage: () =>
                setState(() => _imageCtrlList.add(TextEditingController())),
            onRemoveImage: (i) => setState(() {
              _imageCtrlList[i].dispose();
              _imageCtrlList.removeAt(i);
            }),
          ),
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
