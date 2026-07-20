import 'dart:io';

import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/services/storage_service.dart';
import 'package:dating_app/data/models/profile_tags.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:dating_app/presentation/widgets/rently_icon.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key, required this.profile});
  final TenantProfile profile;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

// ─── Photo entry ──────────────────────────────────────────────────────────────

class _PhotoEntry {
  _PhotoEntry.remote(String url)
      : localPath = null,
        remoteUrl = url,
        isUploading = false;

  _PhotoEntry.local(String path)
      : localPath = path,
        remoteUrl = null,
        isUploading = true;

  final String? localPath;
  String? remoteUrl;
  bool isUploading;

  String get displayUrl => remoteUrl ?? localPath!;

  bool get isLocalOnly => remoteUrl == null && localPath != null;
}

// ─── State ────────────────────────────────────────────────────────────────────

class _EditProfileScreenState extends State<EditProfileScreen> {
  // Move-in buckets — reuse the LOCKED canonical contract (kMoveInBuckets) so
  // this editor and the settings sheet never diverge. Chips show the Hebrew
  // label ($2); we store the token ($1).

  // Occupation vocabulary — LOCKED to match the landlord eligibility criterion
  // UI + backend allowlist. Key (English) is what we store on
  // searchProfile.occupation; the Hebrew label is shown to the tenant. Order is
  // presentation-only.
  static const List<(String, String)> _occupationOptions = [
    ('hightech', 'הייטק'),
    ('healthcare', 'בריאות/רפואה'),
    ('education', 'חינוך/הוראה'),
    ('finance', 'פיננסים/בנקאות'),
    ('law', 'משפטים'),
    ('engineering', 'הנדסה'),
    ('selfemployed', 'עצמאי/ת'),
    ('public', 'שירות ציבורי'),
    ('retail', 'מסחר/שירות'),
    ('academia', 'אקדמיה'),
    ('student', 'סטודנט/ית'),
    ('other', 'אחר'),
  ];

  // Household type vocabulary — LOCKED to the gate's `household` allowlist. Store
  // the English key on searchProfile.household; show the Hebrew label.
  static const List<(String, String)> _householdOptions = [
    ('family', 'משפחה'),
    ('single', 'רווק/ה'),
    ('couple', 'זוג'),
    ('student', 'סטודנט/ית'),
  ];

  // Life-stage vocabulary — LOCKED to the gate's `lifeStage` allowlist. Note the
  // hyphen in 'young-professional' (backend key is exact).
  static const List<(String, String)> _lifeStageOptions = [
    ('student', 'סטודנט/ית'),
    ('young-professional', 'צעיר/ה מקצועי/ת'),
    ('family', 'משפחה'),
    ('senior', 'גיל הזהב'),
  ];

  static const List<double> _roomOptions = [
    1.0,
    1.5,
    2.0,
    2.5,
    3.0,
    3.5,
    4.0,
    4.5,
    5.0,
  ];

  final _storageService = StorageService();
  final _picker = ImagePicker();

  late final TextEditingController _nameCtrl;
  late final TextEditingController _bioCtrl;
  late final TextEditingController _incomeCtrl;
  late final TextEditingController _workAddressCtrl;
  late int _budget;
  late double _rooms;
  late String _moveIn;
  String? _occupation;
  // Eligibility attributes the per-listing gate can filter on. Null = unset.
  int? _numChildren;
  bool? _hasPets;
  bool? _hasCar;
  bool? _wfh;
  String? _household;
  String? _lifeStage;
  bool? _isOleh;
  int? _age;
  bool? _accessibilityNeed;
  bool? _smoker;
  bool? _hasGuarantor;
  int? _leaseMonths;
  bool? _incomeProofReady;
  late List<String> _details;
  late List<String> _dealBreakers;
  late List<_PhotoEntry> _photos;

  // Geocoded work location. Kept in sync with the address field on save; cleared
  // when the address is emptied. Null leaves the commute dimension off.
  double? _workLat;
  double? _workLon;

  bool _isSaving = false;
  int _currentPhotoPage = 0;
  final _pageCtrl = PageController();

  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    _nameCtrl = TextEditingController(text: p.name);
    _bioCtrl = TextEditingController(text: p.bio);
    _incomeCtrl = TextEditingController(
      text: p.monthlyIncome == null ? '' : p.monthlyIncome.toString(),
    );
    // We persist only the geocoded coords (not the typed string), so on reopen
    // the field starts empty but the stored coords remain unless re-edited.
    _workAddressCtrl = TextEditingController();
    _workLat = p.workLat;
    _workLon = p.workLon;
    _budget = p.budgetMax;
    _rooms = p.desiredRooms;
    _moveIn = moveInBucketOf(p.moveInWindow);
    // Pre-fill occupation from the saved profile; only keep it if it's a known
    // vocabulary key (guards against stale/legacy values).
    _occupation = _occupationOptions.any((o) => o.$1 == p.occupation)
        ? p.occupation
        : null;
    _numChildren = p.numChildren;
    _hasPets = p.hasPets;
    _hasCar = p.hasCar;
    _wfh = p.wfh;
    // Keep the stored key only if it's a known vocabulary value.
    _household = _householdOptions.any((o) => o.$1 == p.household)
        ? p.household
        : null;
    _lifeStage = _lifeStageOptions.any((o) => o.$1 == p.lifeStage)
        ? p.lifeStage
        : null;
    _isOleh = p.isOleh;
    _age = p.age;
    _accessibilityNeed = p.accessibilityNeed;
    _smoker = p.smoker;
    _hasGuarantor = p.hasGuarantor;
    _leaseMonths = p.leaseMonths;
    _incomeProofReady = p.incomeProofReady;
    _details = List<String>.from(p.importantDetails);
    _dealBreakers = List<String>.from(p.dealBreakers);
    _photos = p.photoUrls.map(_PhotoEntry.remote).toList();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _bioCtrl.dispose();
    _incomeCtrl.dispose();
    _workAddressCtrl.dispose();
    _pageCtrl.dispose();
    super.dispose();
  }

  // ─── Photo management ───────────────────────────────────────────────────────

  Future<void> _pickPhoto(ImageSource source) async {
    Navigator.of(context).pop(); // close bottom sheet
    final file = await _picker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1200,
    );
    if (file == null) return;

    final localPath = await _storageService.saveImageLocally(file);
    final entry = _PhotoEntry.local(localPath);
    setState(() => _photos.add(entry));

    // Upload in background
    final remoteUrl = await _storageService.uploadToCloud(localPath);
    if (!mounted) return;
    setState(() {
      entry.remoteUrl = remoteUrl;
      entry.isUploading = false;
    });
  }

  void _showPhotoPicker() {
    HapticFeedback.selectionClick();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: AppColors.borderLight,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const Text(
                'הוספת תמונה',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: AppColors.navy,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: _SourceButton(
                      icon: IconsaxPlusLinear.camera,
                      label: 'מצלמה',
                      onTap: () => _pickPhoto(ImageSource.camera),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _SourceButton(
                      icon: IconsaxPlusLinear.gallery,
                      label: 'גלריה',
                      onTap: () => _pickPhoto(ImageSource.gallery),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _openPhotoManager() {
    HapticFeedback.selectionClick();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _PhotoManagerSheet(
        photos: _photos,
        onAdd: _showPhotoPicker,
        onRemove: (entry) {
          HapticFeedback.lightImpact();
          setState(() {
            _photos.remove(entry);
            if (_currentPhotoPage >= _photos.length && _currentPhotoPage > 0) {
              _currentPhotoPage = _photos.length - 1;
              _pageCtrl.jumpToPage(_currentPhotoPage);
            }
          });
          if (entry.remoteUrl != null) {
            _storageService.deleteFromCloud(entry.remoteUrl!);
          }
        },
        onReorder: (oldIndex, newIndex) {
          setState(() {
            final item = _photos.removeAt(oldIndex);
            _photos.insert(newIndex, item);
          });
        },
      ),
    );
  }

  // ─── Details ────────────────────────────────────────────────────────────────

  void _toggleDealBreaker(String tag) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_dealBreakers.contains(tag)) {
        _dealBreakers.remove(tag);
      } else {
        _dealBreakers.add(tag);
      }
    });
  }

  void _openTagPicker() {
    HapticFeedback.selectionClick();
    final isLandlord = context.read<DatingProvider>().isLandlord;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _TagPickerSheet(
        isLandlord: isLandlord,
        selected: _details,
        dealBreakers: _dealBreakers,
        onToggleTag: (tag) {
          HapticFeedback.selectionClick();
          setState(() {
            if (_details.contains(tag)) {
              _details.remove(tag);
              _dealBreakers.remove(tag);
            } else {
              _details.add(tag);
            }
          });
        },
        onToggleDealBreaker: _toggleDealBreaker,
      ),
    );
  }

  // ─── Save ───────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _showError('יש להזין שם');
      return;
    }

    setState(() => _isSaving = true);

    // Income (tenant only): parse digits; empty clears it.
    final incomeDigits = _incomeCtrl.text.replaceAll(RegExp(r'[^0-9]'), '');
    final monthlyIncome = incomeDigits.isEmpty ? null : int.tryParse(incomeDigits);

    // Work address (tenant only): geocode the typed address into coords for the
    // commute dimension. Empty field clears any stored coords; a typed address
    // that fails to geocode keeps the previous coords (best-effort, never blocks).
    final workAddress = _workAddressCtrl.text.trim();
    if (workAddress.isEmpty) {
      _workLat = null;
      _workLon = null;
    } else {
      try {
        final locations = await locationFromAddress(workAddress);
        if (locations.isNotEmpty) {
          _workLat = locations.first.latitude;
          _workLon = locations.first.longitude;
        }
      } catch (_) {/* keep previous coords on geocode failure */}
    }

    final urls = _photos.map((e) => e.displayUrl).toList();
    final updated = widget.profile.copyWith(
      name: name,
      bio: _bioCtrl.text.trim(),
      moveInWindow: _moveIn,
      budgetMax: _budget,
      desiredRooms: _rooms,
      photoUrls: urls,
      importantDetails: _details,
      dealBreakers:
          _dealBreakers.where((tag) => _details.contains(tag)).toList(),
      monthlyIncome: monthlyIncome,
      workLat: _workLat,
      workLon: _workLon,
      occupation: _occupation,
      numChildren: _numChildren,
      hasPets: _hasPets,
      hasCar: _hasCar,
      wfh: _wfh,
      household: _household,
      lifeStage: _lifeStage,
      isOleh: _isOleh,
      age: _age,
      accessibilityNeed: _accessibilityNeed,
      smoker: _smoker,
      hasGuarantor: _hasGuarantor,
      leaseMonths: _leaseMonths,
      incomeProofReady: _incomeProofReady,
    );

    if (!mounted) return;
    await context.read<DatingProvider>().updateTenantProfile(updated);

    if (!mounted) return;
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop();
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(milliseconds: 2500),
      content: Text(msg),
    ));
  }

  InputDecoration _fieldDecoration({
    required String hint,
    required IconData icon,
    String? suffixText,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(
          color: AppColors.textSecondary, fontWeight: FontWeight.w500),
      suffixText: suffixText,
      suffixIcon:
          RentlyIcon(icon, size: 18, color: AppColors.primary),
      filled: true,
      fillColor: AppColors.background,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.borderLight),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.borderLight),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: AppColors.primary, width: 2),
      ),
    );
  }

  // ─── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isLandlord = context.read<DatingProvider>().isLandlord;
    return Scaffold(
      backgroundColor: AppColors.background,
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: _isSaving
            ? Center(
                child: CircularProgressIndicator(color: AppColors.primary))
            : SizedBox(
                height: 54,
                width: double.infinity,
                child: FilledButton(
                  onPressed: _isSaving ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18)),
                  ),
                  child: const Text(
                    'שמור שינויים',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: CustomScrollView(
          slivers: [
            // ── Photo header with floating buttons ──────────────────────
            SliverToBoxAdapter(
              child: Stack(
                children: [
                  _buildPhotoHeader(),
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8.0, vertical: 8.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                                color: Colors.white),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                          if (!_isSaving)
                            TextButton(
                              onPressed: _save,
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.white,
                              ),
                              child: const Text(
                                'שמור',
                                style: TextStyle(
                                    fontWeight: FontWeight.w800, fontSize: 14),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Form sections ────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Column(
                  children: [
                    const SizedBox(height: 8),

                    // 1. Personal details
                    _FormSection(
                      title: 'פרטים אישיים',
                      icon: IconsaxPlusLinear.profile_circle,
                      child: Column(
                        children: [
                          // Name field
                          TextField(
                            controller: _nameCtrl,
                            textDirection: TextDirection.rtl,
                            style: const TextStyle(
                                color: AppColors.navy, fontSize: 15),
                            decoration: InputDecoration(
                              labelText: isLandlord ? 'שם מלא / שם העסק' : 'שם מלא',
                              hintText: isLandlord ? 'שם פרטי ומשפחה או שם העסק' : 'שם וכינוי',
                              labelStyle: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w600),
                              suffixIcon: RentlyIcon(
                                  IconsaxPlusLinear.profile_circle,
                                  size: 18,
                                  color: AppColors.primary),
                              filled: true,
                              fillColor: AppColors.background,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 14),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(
                                    color: AppColors.borderLight),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(
                                    color: AppColors.borderLight),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(
                                    color: AppColors.primary, width: 2),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          // Bio field
                          TextField(
                            controller: _bioCtrl,
                            maxLines: 4,
                            minLines: 3,
                            textDirection: TextDirection.rtl,
                            style: const TextStyle(
                                color: AppColors.navy, fontSize: 15),
                            decoration: InputDecoration(
                              labelText: isLandlord ? 'עליי / על הנכסים' : 'עליי',
                              hintText: isLandlord ? 'תאר/י את עצמך או את הדירות שלך לשוכרים פוטנציאליים...' : 'תאר/י את עצמך לבעלי דירות...',
                              alignLabelWithHint: true,
                              labelStyle: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w600),
                              filled: true,
                              fillColor: AppColors.background,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 14),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(
                                    color: AppColors.borderLight),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(
                                    color: AppColors.borderLight),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(
                                    color: AppColors.primary, width: 2),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    if (!isLandlord) ...[
                    // 2. Apartment preferences
                    _FormSection(
                      title: 'העדפות דירה',
                      icon: IconsaxPlusLinear.building,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Budget pill badge
                          Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 18, vertical: 8),
                              decoration: BoxDecoration(
                                color:
                                    AppColors.primary.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                'תקציב מקסימאלי: ₪${_budget.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}',
                                style: TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 18,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              activeTrackColor: AppColors.primary,
                              inactiveTrackColor: AppColors.borderLight,
                              thumbColor: AppColors.primary,
                              overlayColor:
                                  AppColors.primary.withValues(alpha: 0.15),
                              trackHeight: 3,
                            ),
                            child: Slider(
                              value: _budget.toDouble().clamp(3000, 15000),
                              min: 3000,
                              max: 15000,
                              divisions: 120,
                              onChanged: (v) => setState(
                                  () => _budget = (v / 100).round() * 100),
                            ),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: const [
                              Text('₪3,000',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary,
                                      fontWeight: FontWeight.w600)),
                              Text('₪15,000',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary,
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                          const SizedBox(height: 20),

                          // Rooms label
                          const Text(
                            'מספר חדרים',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 10),

                          // Rooms selector
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: _roomOptions.map((r) {
                                final selected = _rooms == r;
                                final label = r % 1 == 0
                                    ? r.toInt().toString()
                                    : r.toString();
                                return GestureDetector(
                                  onTap: () {
                                    HapticFeedback.selectionClick();
                                    setState(() => _rooms = r);
                                  },
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 180),
                                    width: 44,
                                    height: 36,
                                    margin: const EdgeInsets.only(left: 8),
                                    decoration: BoxDecoration(
                                      color: selected
                                          ? AppColors.primary
                                          : Colors.white,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: selected
                                            ? AppColors.primary
                                            : AppColors.borderLight,
                                      ),
                                    ),
                                    child: Center(
                                      child: Text(
                                        label,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: selected
                                              ? Colors.white
                                              : AppColors.textSecondary,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                          const SizedBox(height: 20),

                          // Move-in label
                          const Text(
                            'מועד כניסה',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 10),

                          // Move-in chips
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: kMoveInBuckets.map((bucket) {
                              final selected = bucket.$1 == _moveIn;
                              return GestureDetector(
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  setState(() => _moveIn = bucket.$1);
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 180),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? AppColors.primary
                                        : AppColors.background,
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                      color: selected
                                          ? AppColors.primary
                                          : AppColors.borderLight,
                                    ),
                                  ),
                                  child: Text(
                                    bucket.$2,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: selected
                                          ? Colors.white
                                          : AppColors.navy,
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 22),

                          // Monthly income — drives the affordability strip on
                          // each listing. Optional; left blank hides the band.
                          const Text(
                            'הכנסה חודשית (ברוטו)',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _incomeCtrl,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            textDirection: TextDirection.rtl,
                            style: const TextStyle(
                                color: AppColors.navy, fontSize: 15),
                            decoration: _fieldDecoration(
                              hint: 'לדוגמה: 12000',
                              icon: IconsaxPlusLinear.wallet_money,
                              suffixText: '₪',
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'נשתמש בזה רק כדי לחשב עבורך אם השכירות נוחה לתקציב. לא מוצג לבעלי הדירות.',
                            style: TextStyle(
                              fontSize: 11.5,
                              height: 1.4,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign: TextAlign.right,
                          ),
                          const SizedBox(height: 18),

                          // Work address — geocoded into coords to show "מרחק
                          // מהעבודה" in the match breakdown. Optional.
                          const Text(
                            'כתובת מקום העבודה',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _workAddressCtrl,
                            textDirection: TextDirection.rtl,
                            style: const TextStyle(
                                color: AppColors.navy, fontSize: 15),
                            decoration: _fieldDecoration(
                              hint: _workLat != null
                                  ? 'מיקום עבודה נשמר — הקלד/י לעדכון'
                                  : 'רחוב, עיר',
                              icon: IconsaxPlusLinear.location,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'נחשב לפי זה את המרחק מהעבודה לכל דירה בהסבר "למה ההתאמה הזו".',
                            style: TextStyle(
                              fontSize: 11.5,
                              height: 1.4,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign: TextAlign.right,
                          ),
                          const SizedBox(height: 20),

                          // Occupation — the tenant's work field. Some listings
                          // are gated by a landlord occupation criterion; picking
                          // one here lets those listings surface for the tenant.
                          const Text(
                            'עיסוק / תחום עבודה',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _occupationOptions.map((opt) {
                              final selected = opt.$1 == _occupation;
                              return GestureDetector(
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  setState(() => _occupation = opt.$1);
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 180),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? AppColors.primary
                                        : AppColors.background,
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                      color: selected
                                          ? AppColors.primary
                                          : AppColors.borderLight,
                                    ),
                                  ),
                                  child: Text(
                                    opt.$2,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: selected
                                          ? Colors.white
                                          : AppColors.navy,
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'עוזר לנו להתאים דירות שבעל הדירה ייעד לתחום עיסוק מסוים.',
                            style: TextStyle(
                              fontSize: 11.5,
                              height: 1.4,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign: TextAlign.right,
                          ),
                          const SizedBox(height: 20),

                          // Number of children — some listings are gated on
                          // household size. Chips 0..5+; null leaves it unset.
                          const Text(
                            'מספר ילדים',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: List.generate(6, (i) {
                              final selected = _numChildren == i;
                              final label = i == 5 ? '5+' : i.toString();
                              return GestureDetector(
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  setState(() =>
                                      _numChildren = selected ? null : i);
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 180),
                                  width: 44,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? AppColors.primary
                                        : AppColors.background,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: selected
                                          ? AppColors.primary
                                          : AppColors.borderLight,
                                    ),
                                  ),
                                  child: Center(
                                    child: Text(
                                      label,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: selected
                                            ? Colors.white
                                            : AppColors.textSecondary,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ),
                          const SizedBox(height: 20),

                          // Pet + car — כן/לא toggles. Pushed to the eligibility
                          // gate (car is inverted to `carFree` on the backend).
                          _YesNoRow(
                            label: 'יש חיית מחמד?',
                            value: _hasPets,
                            onChanged: (v) {
                              HapticFeedback.selectionClick();
                              setState(() => _hasPets = v);
                            },
                          ),
                          const SizedBox(height: 14),
                          _YesNoRow(
                            label: 'יש רכב?',
                            value: _hasCar,
                            onChanged: (v) {
                              HapticFeedback.selectionClick();
                              setState(() => _hasCar = v);
                            },
                          ),
                          const SizedBox(height: 14),

                          // Remote work — 1:1 to the gate's `wfh` criterion.
                          _YesNoRow(
                            label: 'עובד/ת מרחוק?',
                            value: _wfh,
                            onChanged: (v) {
                              HapticFeedback.selectionClick();
                              setState(() => _wfh = v);
                            },
                          ),
                          const SizedBox(height: 14),

                          // New immigrant — 1:1 to the gate's `isOleh` criterion.
                          _YesNoRow(
                            label: 'עולה חדש/ה?',
                            value: _isOleh,
                            onChanged: (v) {
                              HapticFeedback.selectionClick();
                              setState(() => _isOleh = v);
                            },
                          ),
                          const SizedBox(height: 14),

                          // Accessibility — 1:1 to the gate's `accessibilityNeed`.
                          _YesNoRow(
                            label: 'צריך/ה נגישות?',
                            value: _accessibilityNeed,
                            onChanged: (v) {
                              HapticFeedback.selectionClick();
                              setState(() => _accessibilityNeed = v);
                            },
                          ),
                          const SizedBox(height: 14),

                          // Smoking — snapshotted so the landlord's "מעשן" filter
                          // can act on it.
                          _YesNoRow(
                            label: 'מעשן/ת?',
                            value: _smoker,
                            onChanged: (v) {
                              HapticFeedback.selectionClick();
                              setState(() => _smoker = v);
                            },
                          ),
                          const SizedBox(height: 14),

                          // Guarantor — backs the landlord's "ערבות" filter.
                          _YesNoRow(
                            label: 'יש ערב/ערבות?',
                            value: _hasGuarantor,
                            onChanged: (v) {
                              HapticFeedback.selectionClick();
                              setState(() => _hasGuarantor = v);
                            },
                          ),
                          const SizedBox(height: 14),

                          // Income proof — backs the "אסמכתאות הכנסה" filter.
                          _YesNoRow(
                            label: 'אישור הכנסה מוכן?',
                            value: _incomeProofReady,
                            onChanged: (v) {
                              HapticFeedback.selectionClick();
                              setState(() => _incomeProofReady = v);
                            },
                          ),
                          const SizedBox(height: 20),

                          // Desired lease length (months) — backs the landlord's
                          // "משך שכירות מבוקש" filter. Chips; tap again to clear.
                          const Text(
                            'משך שכירות מבוקש (חודשים)',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: const <int>[6, 12, 24, 36].map((m) {
                              final selected = _leaseMonths == m;
                              return GestureDetector(
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  setState(() =>
                                      _leaseMonths = selected ? null : m);
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 180),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? AppColors.primary
                                        : AppColors.background,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: selected
                                          ? AppColors.primary
                                          : AppColors.borderLight,
                                    ),
                                  ),
                                  child: Text(
                                    '$m',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: selected
                                          ? Colors.white
                                          : AppColors.textSecondary,
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 20),

                          // Household type — chips storing the English key.
                          const Text(
                            'סוג משק בית',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _householdOptions.map((opt) {
                              final selected = opt.$1 == _household;
                              return GestureDetector(
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  setState(() =>
                                      _household = selected ? null : opt.$1);
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 180),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? AppColors.primary
                                        : AppColors.background,
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                      color: selected
                                          ? AppColors.primary
                                          : AppColors.borderLight,
                                    ),
                                  ),
                                  child: Text(
                                    opt.$2,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: selected
                                          ? Colors.white
                                          : AppColors.navy,
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 20),

                          // Life stage — chips storing the English key
                          // ('young-professional' keeps its hyphen).
                          const Text(
                            'שלב חיים',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _lifeStageOptions.map((opt) {
                              final selected = opt.$1 == _lifeStage;
                              return GestureDetector(
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  setState(() =>
                                      _lifeStage = selected ? null : opt.$1);
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 180),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? AppColors.primary
                                        : AppColors.background,
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                      color: selected
                                          ? AppColors.primary
                                          : AppColors.borderLight,
                                    ),
                                  ),
                                  child: Text(
                                    opt.$2,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: selected
                                          ? Colors.white
                                          : AppColors.navy,
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 20),

                          // Age — stepper; backs minAge/maxAge on the gate.
                          Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'גיל',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: AppColors.textSecondary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  textAlign: TextAlign.right,
                                ),
                              ),
                              const SizedBox(width: 10),
                              _AgeStepper(
                                value: _age,
                                min: 18,
                                max: 99,
                                onChanged: (v) {
                                  HapticFeedback.selectionClick();
                                  setState(() => _age = v);
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],

                    // 3. Important details / tags for landlords/seekers
                    _FormSection(
                      title: isLandlord ? 'תגיות לשוכרים' : 'תגיות לבעלי דירות',
                      icon: IconsaxPlusLinear.tag,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'בחר/י תגיות שמתארות אותך והעדפותיך. סמן/י תגית כ"דיל ברייקר" כדי שנציג התאמות שעונות עליה בלבד.',
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.5,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign: TextAlign.right,
                          ),
                          const SizedBox(height: 14),
                          if (_details.isNotEmpty) ...[
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: _details.map((d) {
                                final tag = ProfileTagCatalog.tagFor(d,
                                    isLandlord: isLandlord);
                                return _DetailTag(
                                  label: d,
                                  isDealBreaker: _dealBreakers.contains(d),
                                  canBeDealBreaker: tag?.canBeDealBreaker ?? false,
                                  onToggleDealBreaker: () =>
                                      _toggleDealBreaker(d),
                                  onRemove: () {
                                    HapticFeedback.lightImpact();
                                    setState(() {
                                      _details.remove(d);
                                      _dealBreakers.remove(d);
                                    });
                                  },
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 12),
                          ],
                          FilledButton.icon(
                            onPressed: _openTagPicker,
                            style: FilledButton.styleFrom(
                              backgroundColor:
                                  AppColors.primary.withValues(alpha: 0.12),
                              foregroundColor: AppColors.primary,
                              elevation: 0,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(999),
                              ),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 9),
                            ),
                            icon: const RentlyIcon(IconsaxPlusLinear.add,
                                size: 14),
                            label: Text(
                              _details.isEmpty ? 'הוסף תגיות' : 'ערוך תגיות',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Photo header ────────────────────────────────────────────────────────────

  Widget _buildPhotoHeader() {
    final hasPhotos = _photos.isNotEmpty;
    return SizedBox(
      height: 340,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Photo carousel or placeholder
          hasPhotos
              ? PageView.builder(
                  controller: _pageCtrl,
                  itemCount: _photos.length,
                  onPageChanged: (i) => setState(() => _currentPhotoPage = i),
                  itemBuilder: (_, i) {
                    final entry = _photos[i];
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        _ProfilePhotoWidget(url: entry.displayUrl),
                        if (entry.isUploading)
                          Container(
                            color: Colors.black.withValues(alpha: 0.35),
                            child: const Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircularProgressIndicator(
                                      color: Colors.white),
                                  SizedBox(height: 10),
                                  Text('מעלה תמונה…',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                )
              : Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.navy, AppColors.navyMid],
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 56),
                      RentlyIcon(
                        IconsaxPlusLinear.profile_circle,
                        size: 72,
                        color: AppColors.primary.withValues(alpha: 0.6),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'אין תמונות עדיין',
                        style: TextStyle(
                            color: Colors.white70, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),

          // Gradient overlay (wrapped in IgnorePointer)
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.navy.withValues(alpha: 0.80),
                    Colors.transparent,
                    AppColors.navy.withValues(alpha: 0.73),
                  ],
                  stops: [0.0, 0.45, 1.0],
                ),
              ),
            ),
          ),

          // Dot indicators (wrapped in IgnorePointer)
          if (_photos.length > 1)
            Positioned(
              bottom: 64,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_photos.length, (i) {
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: _currentPhotoPage == i ? 20 : 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: _currentPhotoPage == i
                            ? AppColors.primary
                            : Colors.white.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    );
                  }),
                ),
              ),
            ),

          // Bottom bar: photo count + edit button
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (hasPhotos)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const RentlyIcon(IconsaxPlusLinear.gallery,
                            size: 13, color: Colors.white),
                        const SizedBox(width: 5),
                        Text(
                          '${_photos.length} תמונות',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                const Spacer(),
                // Manage photos
                GestureDetector(
                  onTap: _openPhotoManager,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.4),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        RentlyIcon(IconsaxPlusLinear.edit_2,
                            size: 14, color: Colors.white),
                        SizedBox(width: 6),
                        Text(
                          'ניהול תמונות',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Form section card ────────────────────────────────────────────────────────

class _FormSection extends StatelessWidget {
  const _FormSection({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderLight),
        boxShadow: const [
          BoxShadow(
              color: AppColors.shadow, blurRadius: 12, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 16, color: AppColors.primary),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: AppColors.navy,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

// ─── Photo manager bottom sheet ───────────────────────────────────────────────

class _PhotoManagerSheet extends StatefulWidget {
  const _PhotoManagerSheet({
    required this.photos,
    required this.onAdd,
    required this.onRemove,
    required this.onReorder,
  });

  final List<_PhotoEntry> photos;
  final VoidCallback onAdd;
  final void Function(_PhotoEntry) onRemove;
  final void Function(int, int) onReorder;

  @override
  State<_PhotoManagerSheet> createState() => _PhotoManagerSheetState();
}

class _PhotoManagerSheetState extends State<_PhotoManagerSheet> {
  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      minChildSize: 0.4,
      expand: false,
      builder: (ctx, scrollCtrl) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Handle
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.borderLight,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Row(
                  children: [
                    const Text(
                      'תמונות פרופיל',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: AppColors.navy,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${widget.photos.length}/6 תמונות',
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: AppColors.borderLight),
              Expanded(
                child: ReorderableListView.builder(
                  scrollController: scrollCtrl,
                  padding: const EdgeInsets.all(16),
                  proxyDecorator: (child, index, animation) => child,
                  onReorderItem: (oldIndex, newIndex) {
                    setState(() => widget.onReorder(oldIndex, newIndex));
                  },
                  itemCount:
                      widget.photos.length + (widget.photos.length < 6 ? 1 : 0),
                  itemBuilder: (ctx, i) {
                    // Add button cell
                    if (i == widget.photos.length) {
                      return _AddPhotoCell(
                        key: const ValueKey('add'),
                        onTap: () {
                          Navigator.of(context).pop();
                          widget.onAdd();
                        },
                      );
                    }
                    final entry = widget.photos[i];
                    return _PhotoCell(
                      key: ValueKey(entry.displayUrl),
                      entry: entry,
                      isMain: i == 0,
                      onRemove: () {
                        widget.onRemove(entry);
                        setState(() {});
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PhotoCell extends StatelessWidget {
  const _PhotoCell({
    super.key,
    required this.entry,
    required this.isMain,
    required this.onRemove,
  });

  final _PhotoEntry entry;
  final bool isMain;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      height: 80,
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isMain ? AppColors.primary : AppColors.borderLight,
          width: isMain ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          // Drag handle
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 10),
            child: Icon(Icons.drag_handle_rounded,
                color: AppColors.textSecondary, size: 20),
          ),
          // Photo thumbnail
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 60,
              height: 60,
              child: _ProfilePhotoWidget(url: entry.displayUrl),
            ),
          ),
          const SizedBox(width: 12),
          // Label
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isMain)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'תמונה ראשית',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                if (entry.isUploading)
                  const Text(
                    'מעלה…',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  )
                else if (entry.remoteUrl != null)
                  const Text(
                    'נשמרה בענן',
                    style: TextStyle(
                      color: AppColors.success,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                else
                  const Text(
                    'מקומית בלבד',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
          // Remove button
          GestureDetector(
            onTap: onRemove,
            child: Container(
              margin: const EdgeInsets.only(left: 8, right: 12),
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.coral.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close_rounded,
                  size: 16, color: AppColors.coral),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddPhotoCell extends StatelessWidget {
  const _AddPhotoCell({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      key: key,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        height: 80,
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.3),
            width: 1.5,
            strokeAlign: BorderSide.strokeAlignInside,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            RentlyIcon(IconsaxPlusLinear.add,
                color: AppColors.primary, size: 20),
            SizedBox(width: 8),
            Text(
              'הוספת תמונה',
              style: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Photo display widget (handles local path + network URL) ─────────────────

class _ProfilePhotoWidget extends StatelessWidget {
  const _ProfilePhotoWidget({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) return _fallback();
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

  Widget _fallback() {
    return Container(
      color: AppColors.navy,
      child: RentlyIcon(
        IconsaxPlusLinear.profile_circle,
        color: AppColors.primary.withValues(alpha: 0.5),
        size: 40,
      ),
    );
  }
}

// ─── Source picker button ─────────────────────────────────────────────────────

class _SourceButton extends StatelessWidget {
  const _SourceButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Column(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: AppColors.primary, size: 22),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.navy,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Yes/No selector row (RTL) ────────────────────────────────────────────────

class _YesNoRow extends StatelessWidget {
  const _YesNoRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool? value; // null = unset
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.right,
          ),
        ),
        const SizedBox(width: 10),
        // Tapping the already-selected option clears it back to unset.
        _chip('כן', value == true, () => onChanged(value == true ? null : true)),
        const SizedBox(width: 8),
        _chip('לא', value == false,
            () => onChanged(value == false ? null : false)),
      ],
    );
  }

  Widget _chip(String text, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.background,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.borderLight,
          ),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : AppColors.navy,
          ),
        ),
      ),
    );
  }
}

// ─── Age stepper ──────────────────────────────────────────────────────────────

class _AgeStepper extends StatelessWidget {
  const _AgeStepper({
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final int? value; // null = unset
  final int min;
  final int max;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final v = value;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Decrement: below min clears back to unset.
        _btn('−', () {
          if (v == null) return;
          onChanged(v <= min ? null : v - 1);
        }),
        const SizedBox(width: 10),
        SizedBox(
          width: 44,
          child: Text(
            v == null ? '—' : v.toString(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.navy,
            ),
          ),
        ),
        const SizedBox(width: 10),
        // Increment: from unset starts at min.
        _btn('+', () {
          if (v == null) {
            onChanged(min);
          } else if (v < max) {
            onChanged(v + 1);
          }
        }),
      ],
    );
  }

  Widget _btn(String text, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Center(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.navy,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Detail tag chip ──────────────────────────────────────────────────────────

class _DetailTag extends StatelessWidget {
  const _DetailTag({
    required this.label,
    required this.onRemove,
    this.isDealBreaker = false,
    this.canBeDealBreaker = false,
    this.onToggleDealBreaker,
  });

  final String label;
  final VoidCallback onRemove;
  final bool isDealBreaker;
  final bool canBeDealBreaker;
  final VoidCallback? onToggleDealBreaker;

  @override
  Widget build(BuildContext context) {
    final accent = isDealBreaker ? AppColors.coral : AppColors.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Deal-breaker flag toggle (only for eligible tags).
          if (canBeDealBreaker && onToggleDealBreaker != null) ...[
            GestureDetector(
              onTap: onToggleDealBreaker,
              child: Icon(
                isDealBreaker
                    ? Icons.gpp_maybe_rounded
                    : Icons.shield_outlined,
                size: 15,
                color: accent,
              ),
            ),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
                color: accent, fontWeight: FontWeight.w700, fontSize: 13),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onRemove,
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.close, size: 11, color: accent),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Searchable tag picker bottom sheet ───────────────────────────────────────

class _TagPickerSheet extends StatefulWidget {
  const _TagPickerSheet({
    required this.isLandlord,
    required this.selected,
    required this.dealBreakers,
    required this.onToggleTag,
    required this.onToggleDealBreaker,
  });

  final bool isLandlord;
  final List<String> selected;
  final List<String> dealBreakers;
  final void Function(String tag) onToggleTag;
  final void Function(String tag) onToggleDealBreaker;

  @override
  State<_TagPickerSheet> createState() => _TagPickerSheetState();
}

class _TagPickerSheetState extends State<_TagPickerSheet> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categories =
        ProfileTagCatalog.forRole(isLandlord: widget.isLandlord);
    final query = _query.trim();
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (ctx, scrollCtrl) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.borderLight,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'בחירת תגיות',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: AppColors.navy,
                    ),
                  ),
                ),
              ),
              // Search box
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: TextField(
                  controller: _searchCtrl,
                  textDirection: TextDirection.rtl,
                  onChanged: (v) => setState(() => _query = v),
                  style: const TextStyle(color: AppColors.navy, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'חיפוש תגית…',
                    prefixIcon: const Icon(IconsaxPlusLinear.search_normal_1,
                        size: 18, color: AppColors.textSecondary),
                    isDense: true,
                    filled: true,
                    fillColor: AppColors.background,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: AppColors.borderLight),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: AppColors.borderLight),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide:
                          BorderSide(color: AppColors.primary, width: 2),
                    ),
                  ),
                ),
              ),
              const Divider(height: 1, color: AppColors.borderLight),
              Expanded(
                child: ListView(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  children: [
                    for (final category in categories)
                      ..._buildCategory(category, query),
                    if (categories.every((c) =>
                        _matchingTags(c, query).isEmpty))
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: Text(
                          'לא נמצאו תגיות תואמות',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    child: Text(
                      'סיום (${widget.selected.length})',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<ProfileTag> _matchingTags(ProfileTagCategory category, String query) {
    if (query.isEmpty) return category.tags;
    return category.tags
        .where((tag) => tag.label.contains(query))
        .toList();
  }

  List<Widget> _buildCategory(ProfileTagCategory category, String query) {
    final tags = _matchingTags(category, query);
    if (tags.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(2, 8, 2, 10),
        child: Text(
          category.title,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w900,
            color: AppColors.navy,
          ),
        ),
      ),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: tags.map(_buildChip).toList(),
      ),
      const SizedBox(height: 14),
    ];
  }

  // The selection lists are owned by the parent; toggling there mutates the
  // shared list, so we also rebuild this sheet to reflect the new state.
  void _toggleTag(String tag) {
    widget.onToggleTag(tag);
    setState(() {});
  }

  void _toggleDeal(String tag) {
    widget.onToggleDealBreaker(tag);
    setState(() {});
  }

  Widget _buildChip(ProfileTag tag) {
    final selected = widget.selected.contains(tag.label);
    final isDeal = widget.dealBreakers.contains(tag.label);
    final accent = isDeal ? AppColors.coral : AppColors.primary;
    return GestureDetector(
      onTap: () => _toggleTag(tag.label),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.12) : AppColors.background,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? accent : AppColors.borderLight,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              selected ? Icons.check_circle_rounded : Icons.add_circle_outline,
              size: 15,
              color: selected ? accent : AppColors.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              tag.label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: selected ? accent : AppColors.navy,
              ),
            ),
            // Inline deal-breaker toggle, only once the tag is selected.
            if (selected && tag.canBeDealBreaker) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => _toggleDeal(tag.label),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: isDeal
                        ? AppColors.coral
                        : AppColors.coral.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'דיל ברייקר',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: isDeal ? Colors.white : AppColors.coral,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
