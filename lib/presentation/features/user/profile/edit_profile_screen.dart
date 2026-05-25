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
  static const List<String> _moveInOptions = [
    'מיידי',
    'תוך חודש',
    '1-3 חודשים',
    '3-6 חודשים',
    'גמיש',
  ];

  final _storageService = StorageService();
  final _picker = ImagePicker();

  late final TextEditingController _nameCtrl;
  late final TextEditingController _bioCtrl;
  late int _budget;
  late double _rooms;
  late String _moveIn;
  late List<String> _details;
  late List<_PhotoEntry> _photos;

  bool _isSaving = false;
  int _currentPhotoPage = 0;
  final _pageCtrl = PageController();

  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    _nameCtrl = TextEditingController(text: p.name);
    _bioCtrl = TextEditingController(text: p.bio);
    _budget = p.budgetMax;
    _rooms = p.desiredRooms;
    _moveIn = p.moveInWindow.isNotEmpty ? p.moveInWindow : 'גמיש';
    _details = List<String>.from(p.importantDetails);
    _photos = p.photoUrls.map(_PhotoEntry.remote).toList();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _bioCtrl.dispose();
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
                      icon: IconsaxPlusBold.camera,
                      label: 'מצלמה',
                      onTap: () => _pickPhoto(ImageSource.camera),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _SourceButton(
                      icon: IconsaxPlusBold.gallery,
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
            if (newIndex > oldIndex) newIndex--;
            final item = _photos.removeAt(oldIndex);
            _photos.insert(newIndex, item);
          });
        },
      ),
    );
  }

  // ─── Details ────────────────────────────────────────────────────────────────

  void _addDetail() {
    showDialog<String>(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController();
        return AlertDialog(
          backgroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          title: const Text(
            'הוספת פרט',
            style:
                TextStyle(color: AppColors.navy, fontWeight: FontWeight.w900),
          ),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            textDirection: TextDirection.rtl,
            decoration: InputDecoration(
              hintText: 'לדוגמה: עם כלב, זוג…',
              filled: true,
              fillColor: AppColors.background,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.borderLight),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: AppColors.primary, width: 2),
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
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('הוספה'),
            ),
          ],
        );
      },
    ).then((value) {
      if (value != null && value.isNotEmpty) {
        HapticFeedback.selectionClick();
        setState(() => _details.add(value));
      }
    });
  }

  // ─── Save ───────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _showError('יש להזין שם');
      return;
    }

    setState(() => _isSaving = true);

    final urls = _photos.map((e) => e.displayUrl).toList();
    final updated = widget.profile.copyWith(
      name: name,
      bio: _bioCtrl.text.trim(),
      moveInWindow: _moveIn,
      budgetMax: _budget,
      desiredRooms: _rooms,
      photoUrls: urls,
      importantDetails: _details,
    );

    await context.read<DatingProvider>().updateTenantProfile(updated);

    if (!mounted) return;
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop();
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ─── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      backgroundColor: AppColors.background,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.35),
              shape: BoxShape.circle,
            ),
            child: const Icon(IconsaxPlusLinear.arrow_right,
                color: Colors.white, size: 20),
          ),
        ),
        title: const Text(
          'עריכת פרופיל',
          style: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: _isSaving
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    ),
                  )
                : TextButton(
                    onPressed: _save,
                    style: TextButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 8),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
                    ),
                    child: const Text(
                      'שמור',
                      style:
                          TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                    ),
                  ),
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          // Photo header
          SliverToBoxAdapter(child: _buildPhotoHeader()),
          // Form
          SliverPadding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, bottomPad + 32),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                const SizedBox(height: 16),
                _FormCard(
                  icon: IconsaxPlusBold.profile_circle,
                  title: 'פרטים אישיים',
                  child: Column(
                    children: [
                      _RentchField(
                        controller: _nameCtrl,
                        label: 'שם מלא',
                        icon: IconsaxPlusLinear.user,
                      ),
                      const SizedBox(height: 14),
                      _RentchField(
                        controller: _bioCtrl,
                        label: 'ספר/י על עצמך',
                        icon: IconsaxPlusLinear.message_text,
                        maxLines: 4,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _FormCard(
                  icon: IconsaxPlusBold.search_normal,
                  title: 'העדפות חיפוש',
                  child: Column(
                    children: [
                      _SliderRow(
                        label: 'תקציב מקסימלי',
                        displayValue: _fmtCurrency(_budget),
                        value: _budget.toDouble(),
                        min: 2000,
                        max: 20000,
                        divisions: 180,
                        onChanged: (v) =>
                            setState(() => _budget = (v / 100).round() * 100),
                      ),
                      const SizedBox(height: 10),
                      _SliderRow(
                        label: 'מספר חדרים',
                        displayValue: _rooms % 1 == 0
                            ? _rooms.toInt().toString()
                            : '$_rooms',
                        value: _rooms,
                        min: 1,
                        max: 6,
                        divisions: 10,
                        onChanged: (v) =>
                            setState(() => _rooms = (v * 2).round() / 2),
                      ),
                      const SizedBox(height: 14),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          'מועד כניסה',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _moveInOptions.map((opt) {
                          final selected = opt == _moveIn;
                          return GestureDetector(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() => _moveIn = opt);
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
                                opt,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color:
                                      selected ? Colors.white : AppColors.navy,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _FormCard(
                  icon: IconsaxPlusBold.info_circle,
                  title: 'פרטים לבעלי דירות',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_details.isNotEmpty) ...[
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _details.map((d) {
                            return _DetailTag(
                              label: d,
                              onRemove: () {
                                HapticFeedback.lightImpact();
                                setState(() => _details.remove(d));
                              },
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 10),
                      ],
                      GestureDetector(
                        onTap: _addDetail,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 9),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: AppColors.primary,
                              width: 1.5,
                            ),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(IconsaxPlusLinear.add,
                                  size: 14, color: AppColors.primary),
                              SizedBox(width: 5),
                              Text(
                                'הוסף פרט',
                                style: TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w700,
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
              ]),
            ),
          ),
        ],
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
                      colors: [AppColors.navy, Color(0xFF0D3D60)],
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 56),
                      Icon(
                        IconsaxPlusBold.profile_circle,
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
          const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xCC072946),
                    Colors.transparent,
                    Color(0xBB072946)
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
                        const Icon(IconsaxPlusBold.gallery,
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
                        Icon(IconsaxPlusBold.edit_2,
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
                    child: const Text(
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
                      color: Color(0xFF27AE60),
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
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(IconsaxPlusLinear.add, color: AppColors.primary, size: 20),
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
      child: Icon(
        IconsaxPlusBold.profile_circle,
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

// ─── Reusable form widgets ────────────────────────────────────────────────────

class _FormCard extends StatelessWidget {
  const _FormCard({
    required this.icon,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final String title;
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 17, color: AppColors.primary),
              const SizedBox(width: 7),
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
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _RentchField extends StatelessWidget {
  const _RentchField({
    required this.controller,
    required this.label,
    required this.icon,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      textDirection: TextDirection.rtl,
      style: const TextStyle(color: AppColors.navy, fontSize: 15),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(
            color: AppColors.textSecondary, fontWeight: FontWeight.w600),
        prefixIcon: Icon(icon, size: 18, color: AppColors.primary),
        filled: true,
        fillColor: AppColors.background,
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
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        alignLabelWithHint: maxLines > 1,
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
                    fontSize: 14,
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

class _DetailTag extends StatelessWidget {
  const _DetailTag({required this.label, required this.onRemove});

  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
                fontSize: 13),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onRemove,
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child:
                  const Icon(Icons.close, size: 11, color: AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }
}

String _fmtCurrency(int value) {
  final raw = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < raw.length; i++) {
    final remaining = raw.length - i;
    buffer.write(raw[i]);
    if (remaining > 1 && remaining % 3 == 1) buffer.write(',');
  }
  return '₪$buffer';
}
