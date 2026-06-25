// ═════════════════════════════════════════════════════════════════════════════
// RecommendationExplainer — client for POST /assistant/explain.
//
// FROZEN INTERFACE between the backend LLM explainer (A3) and the transparency
// UI (A4). The deterministic engine has already CHOSEN and produced a Scorecard
// per property (fit, dimension breakdown, real stats, persona reasons). This
// sends those Scorecards + the persona to the LLM, which writes the natural-
// language "why this one, by the numbers" per property and a persona-level
// "how I chose these" — grounded strictly in the supplied figures, never invented.
//
// Returns null on any failure so the UI degrades to the engine's own reasons.
// A3 fills the implementation; this stub keeps the app compiling for A4.
// ═════════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dating_app/core/config/app_config.dart';
import 'package:dating_app/core/search/engine/scorecard.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// The LLM's data-grounded explanation for a batch of recommendations.
class RecommendationExplanation {
  const RecommendationExplanation({
    required this.howIChose,
    required this.perProperty,
  });

  /// Persona-level summary: how the assistant weighed the data + persona to pick
  /// these, in warm Hebrew (e.g. "התמקדתי בתמורה למחיר ובקרבה לרכבת כי…").
  final String howIChose;

  /// propertyId → one short, number-grounded Hebrew reason for THAT property.
  final Map<String, String> perProperty;

  Map<String, dynamic> toJson() =>
      {'howIChose': howIChose, 'perProperty': perProperty};

  factory RecommendationExplanation.fromJson(Map<String, dynamic> j) {
    // The backend's frozen contract returns per-property text under `reasons`
    // (propertyId → reason). Accept `perProperty` too for forward-compat.
    final raw = (j['reasons'] as Map?) ?? (j['perProperty'] as Map?) ?? const {};
    return RecommendationExplanation(
      howIChose: j['howIChose']?.toString() ?? '',
      perProperty: <String, String>{
        for (final e in raw.entries)
          if (e.value != null && e.value.toString().trim().isNotEmpty)
            e.key.toString(): e.value.toString(),
      },
    );
  }
}

class RecommendationExplainer {
  const RecommendationExplainer._();

  static const Duration _timeout = Duration(seconds: 20);

  /// POST /assistant/explain — send Scorecards + persona, get NL explanations.
  /// [properties] and [cards] are index-aligned (cards[i] explains properties[i]).
  /// Returns null on failure; callers must fall back to the engine reasons.
  static Future<RecommendationExplanation?> explain({
    required List<RentalProperty> properties,
    required List<Scorecard> cards,
    required List<String> persona,
    required String querySummary,
  }) async {
    if (AppConfig.awsApiGatewayUrl.trim().isEmpty) return null;
    if (cards.isEmpty) return null;

    // Build the frozen request contract: scorecards = each card.toJson() merged
    // with its property id (index-aligned with [properties]).
    final scorecards = <Map<String, dynamic>>[];
    for (var i = 0; i < cards.length && i < properties.length; i++) {
      scorecards.add({
        'propertyId': properties[i].id,
        ...cards[i].toJson(),
      });
    }
    if (scorecards.isEmpty) return null;

    final client = HttpClient();
    try {
      final request =
          await client.openUrl('POST', _resolve('/assistant/explain')).timeout(_timeout);
      request.headers.contentType = ContentType.json;
      // Same auth mechanism AssistantService uses: optional x-api-key + a
      // Firebase ID token as a Bearer header.
      final apiKey = AppConfig.awsApiKey.trim();
      if (apiKey.isNotEmpty) request.headers.add('x-api-key', apiKey);
      try {
        final token = await FirebaseAuth.instance.currentUser?.getIdToken();
        if (token != null && token.isNotEmpty) {
          request.headers.add(HttpHeaders.authorizationHeader, 'Bearer $token');
        }
      } catch (_) {}
      request.write(jsonEncode({
        'persona': persona,
        'query': querySummary,
        'scorecards': scorecards,
      }));
      final response = await request.close().timeout(_timeout);
      final raw = await utf8.decoder.bind(response).join().timeout(_timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final decoded = jsonDecode(raw);
      final data = decoded is Map && decoded['data'] is Map
          ? Map<String, dynamic>.from(decoded['data'] as Map)
          : Map<String, dynamic>.from(decoded as Map);
      return RecommendationExplanation.fromJson(data);
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// Builds an absolute endpoint URL from the gateway base — mirrors the path
  /// joining AssistantService uses (no double slashes, base path preserved).
  static Uri _resolve(String path) {
    final base = Uri.parse(AppConfig.awsApiGatewayUrl.trim());
    final normalized = path.startsWith('/') ? path.substring(1) : path;
    return base.replace(
      path: [
        base.path.replaceFirst(RegExp(r'/$'), ''),
        normalized,
      ].where((p) => p.isNotEmpty).join('/'),
    );
  }
}
