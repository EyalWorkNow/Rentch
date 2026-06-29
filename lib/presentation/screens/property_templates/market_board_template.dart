part of '../property_detail_screen.dart';

/// Market Board (a.k.a. `dashboardGlass`) — a translucent glass card holding the
/// top bar, hero media, address + like button, price, two market-metric tiles
/// (views / saves) and a facts wrap, followed by the shared full-parity block.
///
/// Self-contained, designer-owned unit. The metric tile [_MarketMetricCard] and
/// the [_compactNumber] formatter are exclusive to this layout and live here.
class _MarketBoardTemplate extends StatelessWidget {
  const _MarketBoardTemplate({
    required this.property,
    required this.branding,
    required this.controller,
    required this.currentPage,
    required this.onPageChanged,
    required this.reviews,
    required this.hasVirtualTour,
    required this.isLandlordPreview,
    required this.onBackTap,
    required this.onShareTap,
    required this.onLike,
    required this.onTour,
  });

  final RentalProperty property;
  final BrokerBrandingConfig branding;
  final PageController controller;
  final int currentPage;
  final ValueChanged<int> onPageChanged;
  final List<AppReview> reviews;
  final bool hasVirtualTour;
  final bool isLandlordPreview;
  final VoidCallback onBackTap;
  final VoidCallback onShareTap;
  final VoidCallback onLike;
  final VoidCallback onTour;

  @override
  Widget build(BuildContext context) {
    final signals = property.marketSignals;
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              18,
              MediaQuery.of(context).padding.top + 12,
              18,
              124,
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.64),
                    borderRadius: BorderRadius.circular(28),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.7)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _TemplateTopBar(
                        branding: branding,
                        title: '',
                        dark: false,
                        onBackTap: onBackTap,
                        onShareTap: onShareTap,
                      ),
                      const SizedBox(height: 18),
                      _TemplateHeroMedia(
                        property: property,
                        controller: controller,
                        currentPage: currentPage,
                        onPageChanged: onPageChanged,
                        height: 250,
                        radius: 18,
                      ),
                      const SizedBox(height: 18),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              property.address,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: branding.secondaryColor,
                                fontSize: 25,
                                fontWeight: FontWeight.w900,
                                height: 1.04,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          _RoundTemplateButton(
                            icon: IconsaxPlusLinear.heart,
                            onTap: onLike,
                            color: branding.primaryColor,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${property.priceLabel} · ${property.priceSuffixLabel}',
                        style: TextStyle(
                          color:
                              branding.secondaryColor.withValues(alpha: 0.58),
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _MarketMetricCard(
                              icon: IconsaxPlusLinear.eye,
                              label: 'צפיות',
                              value: _compactNumber(
                                signals.views + signals.detailViews,
                              ),
                              branding: branding,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _MarketMetricCard(
                              icon: IconsaxPlusLinear.heart,
                              label: 'שמירות',
                              value: _compactNumber(signals.saves),
                              branding: branding,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _TemplateFactsWrap(
                          property: property, branding: branding),
                    ],
                  ),
                ),
                const SizedBox(height: 26),
                _ParitySections(
                  property: property,
                  branding: branding,
                  controller: controller,
                  reviews: reviews,
                  hasVirtualTour: hasVirtualTour,
                  isLandlordPreview: isLandlordPreview,
                  onShareTap: onShareTap,
                  onTour: onTour,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _MarketMetricCard extends StatelessWidget {
  const _MarketMetricCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.branding,
  });

  final IconData icon;
  final String label;
  final String value;
  final BrokerBrandingConfig branding;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 126,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.64)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: branding.secondaryColor.withValues(alpha: 0.48)),
          const Spacer(),
          Text(
            label,
            style: TextStyle(
              color: branding.secondaryColor.withValues(alpha: 0.65),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: branding.secondaryColor,
              fontSize: 30,
              fontWeight: FontWeight.w900,
              height: 0.95,
            ),
          ),
        ],
      ),
    );
  }
}

String _compactNumber(int value) {
  if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
  if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}K';
  return value.toString();
}
