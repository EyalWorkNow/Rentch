import 'package:dating_app/core/config/app_config.dart';
import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/presentation/screens/property_detail_screen.dart';
import 'package:dating_app/presentation/widgets/rently_icon.dart';
import 'package:dating_app/presentation/widgets/safe_media.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// Public-facing "all listings by this landlord/agent" page. Reached by tapping
/// an owner's name on a property, or from the landlord's own profile ("share my
/// listings"). Pure in-app page — the shared link is a deep link that resolves
/// once the app's URL scheme is wired up.
class OwnerListingsScreen extends StatelessWidget {
  const OwnerListingsScreen({
    super.key,
    required this.ownerUserId,
    required this.ownerName,
    this.isSelf = false,
  });

  final String ownerUserId;
  final String ownerName;
  final bool isSelf;

  // Share the working public share link (same format as the property share
  // sheet): the backend /p/<id> page opens the app (rently://) or falls back to
  // the store. The old https://rently.app/owner/<id> URL was dead (no such host).
  String _shareLink() {
    final id = ownerUserId.trim().isNotEmpty
        ? ownerUserId.trim()
        : Uri.encodeComponent(ownerName.trim());
    return '${AppConfig.publicShareBaseUrl}/p/$id';
  }

  String _shareMessage() =>
      'הדירות של $ownerName ב-Rently 🏠\n${_shareLink()}';

  Future<void> _share(BuildContext context) async {
    final wa = Uri.parse(
        'https://wa.me/?text=${Uri.encodeComponent(_shareMessage())}');
    if (await canLaunchUrl(wa)) {
      await launchUrl(wa, mode: LaunchMode.externalApplication);
      return;
    }
    await Clipboard.setData(ClipboardData(text: _shareMessage()));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      duration: Duration(milliseconds: 2500),
      content: Text('הקישור לדירות שלך הועתק — אפשר לשלוח לכל אחד'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Consumer<DatingProvider>(
        builder: (context, provider, _) {
          final listings = _ownerListings(provider);
          final profile = ownerUserId.trim().isNotEmpty
              ? provider.getCachedProfile(ownerUserId.trim())
              : null;
          final isAgency =
              listings.any((p) => p.agencyListing) || provider.isBroker && isSelf;

          return Scaffold(
            backgroundColor: AppColors.slate50,
            appBar: AppBar(
              backgroundColor: AppColors.slate50,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              title: Text(
                isSelf ? 'הדירות שלי' : 'הדירות של $ownerName',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              iconTheme: const IconThemeData(color: AppColors.textPrimary),
              actions: [
                IconButton(
                  tooltip: 'שתף את דף הדירות',
                  onPressed: () => _share(context),
                  icon: const RentlyIcon(IconsaxPlusLinear.export_2,
                      color: AppColors.textPrimary, size: 22),
                ),
              ],
            ),
            body: SafeArea(
              top: false,
              child: CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                    sliver: SliverToBoxAdapter(
                      child: _OwnerHeader(
                        name: profile?.name.isNotEmpty == true
                            ? profile!.name
                            : ownerName,
                        isAgency: isAgency,
                        count: listings.length,
                        onShare: () => _share(context),
                      ),
                    ),
                  ),
                  if (listings.isEmpty)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.only(top: 60),
                        child: Center(
                          child: Text(
                            'אין דירות פעילות כרגע',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
                      sliver: SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 0.74,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, i) =>
                              _OwnerListingCard(property: listings[i]),
                          childCount: listings.length,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  List<RentalProperty> _ownerListings(DatingProvider provider) {
    if (isSelf) return provider.myProperties;
    final id = ownerUserId.trim();
    final name = ownerName.trim();
    return provider.allProperties.where((p) {
      if (id.isNotEmpty && p.ownerUserId.trim() == id) return true;
      if (name.isNotEmpty && p.ownerName.trim() == name) return true;
      return false;
    }).toList();
  }
}

class _OwnerHeader extends StatelessWidget {
  const _OwnerHeader({
    required this.name,
    required this.isAgency,
    required this.count,
    required this.onShare,
  });

  final String name;
  final bool isAgency;
  final int count;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.slate200),
      ),
      child: Row(
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isAgency
                    ? [AppColors.tealBrand, AppColors.tealDark]
                    : [AppColors.slate600, AppColors.inkSoft],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                initial,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${isAgency ? 'מתווך נדל״ן' : 'בעל נכס פרטי'} · $count דירות',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: isAgency
                        ? AppColors.tealBrand
                        : AppColors.slate500,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onShare,
            icon: RentlyIcon(IconsaxPlusLinear.link_1,
                color: AppColors.primary, size: 22),
          ),
        ],
      ),
    );
  }
}

class _OwnerListingCard extends StatelessWidget {
  const _OwnerListingCard({required this.property});

  final RentalProperty property;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PropertyDetailScreen(property: property),
          ),
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.slate200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 1.4,
                child: SafeMedia(
                  media: property.primaryMedia,
                  fallback: Container(color: AppColors.slate200),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${property.priceLabel} ${property.priceSuffixLabel}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.ink,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        property.address,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.slate500,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${property.roomsLabel} חד׳ · ${property.sizeM2} מ״ר',
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
            ],
          ),
        ),
      ),
    );
  }
}
