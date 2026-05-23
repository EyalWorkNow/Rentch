import 'package:dating_app/data/models/rental_models.dart';
import 'package:flutter/material.dart';

class ProfileHeader extends StatelessWidget {
  const ProfileHeader({
    super.key,
    required this.profile,
    required this.onEditPressed,
  });

  final TenantProfile profile;
  final VoidCallback onEditPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 330,
      child: Stack(
        fit: StackFit.expand,
        children: [
          profile.photoUrl.isEmpty
              ? const ColoredBox(color: Color(0xFFEAF4EF))
              : Image.network(
                  profile.photoUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return const ColoredBox(color: Color(0xFFEAF4EF));
                  },
                ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.82),
                  Colors.black.withValues(alpha: 0.14),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 22,
            left: 22,
            right: 22,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(
                      Icons.payments_rounded,
                      size: 18,
                      color: Colors.white70,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'תקציב עד ${_formatCurrency(profile.budgetMax)} • ${profile.desiredRooms} חדרים',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Positioned(
            top: 44,
            left: 20,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onEditPressed,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(
                    Icons.edit_rounded,
                    color: Color(0xFF146C5A),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatCurrency(int value) {
  final raw = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < raw.length; i++) {
    final remaining = raw.length - i;
    buffer.write(raw[i]);
    if (remaining > 1 && remaining % 3 == 1) {
      buffer.write(',');
    }
  }
  return '₪$buffer';
}
