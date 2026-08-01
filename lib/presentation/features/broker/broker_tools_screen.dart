import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/presentation/features/broker/area_intel_screen.dart';
import 'package:dating_app/presentation/features/broker/broker_brochure_screen.dart';
import 'package:dating_app/presentation/features/broker/broker_clients_screen.dart';
import 'package:dating_app/presentation/features/broker/broker_cma_screen.dart';
import 'package:dating_app/presentation/features/broker/broker_commission_screen.dart';
import 'package:dating_app/presentation/features/broker/broker_exclusivity_screen.dart';
import 'package:dating_app/presentation/features/broker/broker_hot_matches_screen.dart';
import 'package:dating_app/presentation/features/broker/broker_owner_report_screen.dart';
import 'package:dating_app/presentation/features/broker/broker_pipeline_screen.dart';
import 'package:dating_app/presentation/features/broker/broker_viewings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

/// "כלי הסוכן" — one hub gathering all 10 broker (מתווך) tools in one place.
///
/// Brokers run the landlord flow but need their own toolbox. This screen is a
/// simple RTL grid of big, older-user-friendly tiles — each opens a dedicated
/// tool screen. Indigo brand accent (AppColors.primary is indigo for brokers).
class BrokerToolsScreen extends StatelessWidget {
  const BrokerToolsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // NOTE: AppColors.primary/primaryDark are MUTABLE statics (indigo for
    // brokers) — keep these out of any `const` constructor below.
    final tools = <_BrokerTool>[
      _BrokerTool(
        icon: IconsaxPlusLinear.profile_2user,
        color: AppColors.primary,
        title: 'פנקס לקוחות',
        subtitle: 'ניהול הלקוחות שלך + אילו נכסים מתאימים לכל אחד',
        builder: (_) => const BrokerClientsScreen(),
      ),
      _BrokerTool(
        icon: IconsaxPlusLinear.flash,
        color: AppColors.coral,
        title: 'התאמות חמות',
        subtitle: 'לקוחות שמחכים בדיוק לנכס שיש לך עכשיו',
        builder: (_) => const BrokerHotMatchesScreen(),
      ),
      _BrokerTool(
        icon: IconsaxPlusLinear.task_square,
        color: AppColors.superLike,
        title: 'פייפליין לידים',
        subtitle: 'כל הפניות במקום אחד — שום ליד לא נופל',
        builder: (_) => const BrokerPipelineScreen(),
      ),
      _BrokerTool(
        icon: IconsaxPlusLinear.calendar_1,
        color: AppColors.primaryDark,
        title: 'תיאום צפיות',
        subtitle: 'לקבוע ולעקוב אחרי צפיות בנכסים',
        builder: (_) => const BrokerViewingsScreen(),
      ),
      _BrokerTool(
        icon: IconsaxPlusLinear.chart_2,
        color: AppColors.success,
        title: 'ניתוח שוק (CMA)',
        subtitle: 'מחיר מומלץ לפי נכסים דומים באזור',
        builder: (_) => const BrokerCmaScreen(),
      ),
      _BrokerTool(
        icon: IconsaxPlusLinear.map_1,
        color: AppColors.primary,
        title: 'אינטליגנציית אזור',
        subtitle: 'כתובת → כל נתוני האזור + למי הוא הכי מתאים להשקעה',
        builder: (_) => const AreaIntelScreen(),
      ),
      _BrokerTool(
        icon: IconsaxPlusLinear.shield_tick,
        color: AppColors.warning,
        title: 'מעקב בלעדיות',
        subtitle: 'תוקף ההסכמים — שלא תחמיץ חידוש בלעדיות',
        builder: (_) => const BrokerExclusivityScreen(),
      ),
      _BrokerTool(
        icon: IconsaxPlusLinear.wallet_money,
        color: AppColors.primary,
        title: 'עמלות ופייפליין',
        subtitle: 'מעקב עמלות צפויות והכנסות מהעסקאות',
        builder: (_) => const BrokerCommissionScreen(),
      ),
      _BrokerTool(
        icon: IconsaxPlusLinear.document_text,
        color: AppColors.navy,
        title: 'דוח לבעל הנכס',
        subtitle: 'דוח מסודר על הפעילות לשליחה לבעל הנכס',
        builder: (_) => const BrokerOwnerReportScreen(),
      ),
      _BrokerTool(
        icon: IconsaxPlusLinear.gallery,
        color: AppColors.primaryDark,
        title: 'ברושור ממותג',
        subtitle: 'דף נכס יפה עם המיתוג שלך לשיתוף',
        builder: (_) => const BrokerBrochureScreen(),
      ),
    ];

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: AppColors.navy,
          elevation: 0,
          centerTitle: true,
          title: const Text(
            'כלי הסוכן',
            style: TextStyle(
              color: AppColors.navy,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          iconTheme: const IconThemeData(color: AppColors.navy),
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(1),
            child: Divider(color: AppColors.divider, height: 1, thickness: 1),
          ),
        ),
        body: SafeArea(
          top: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Short intro so the agent knows what this hub is for.
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.slate50,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.slate200),
                  ),
                  child: const Row(
                    children: [
                      Icon(IconsaxPlusLinear.briefcase,
                          color: Colors.black, size: 24),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'כל מה שצריך לניהול העסק שלך במקום אחד — לקוחות, '
                          'לידים, צפיות, עמלות ועוד. הקש על כלי כדי להתחיל.',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13.5,
                            height: 1.4,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                    childAspectRatio: 0.92,
                  ),
                  itemCount: tools.length,
                  itemBuilder: (context, i) => _BrokerToolTile(tool: tools[i]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BrokerTool {
  const _BrokerTool({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.builder,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final WidgetBuilder builder;
}

class _BrokerToolTile extends StatelessWidget {
  const _BrokerToolTile({required this.tool});

  final _BrokerTool tool;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        Navigator.of(context).push(
          MaterialPageRoute(builder: tool.builder),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.slate200, width: 1.2),
          boxShadow: [
            BoxShadow(
              color: AppColors.shadow.withValues(alpha: 0.05),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppColors.slate50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.slate200, width: 1.2),
              ),
              child: Icon(tool.icon, color: Colors.black, size: 26),
            ),
            const Spacer(),
            Text(
              tool.title,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              tool.subtitle,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                height: 1.3,
              ),
              maxLines: 3,
            ),
          ],
        ),
      ),
    );
  }
}
