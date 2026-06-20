import 'package:flutter/material.dart';

enum BrokerPropertyTemplate {
  rentlyClassic,
  acidHero,
  dashboardGlass,
  estateCard,
  galleryEditorial,
  cinematicGlass,
}

enum BrokerChatTemplate {
  rentlyClassic,
  softGlass,
  editorialLight,
  nightSuite,
}

extension BrokerPropertyTemplateLabels on BrokerPropertyTemplate {
  String get id => switch (this) {
        BrokerPropertyTemplate.rentlyClassic => 'rently_classic',
        BrokerPropertyTemplate.acidHero => 'acid_hero',
        BrokerPropertyTemplate.dashboardGlass => 'dashboard_glass',
        BrokerPropertyTemplate.estateCard => 'estate_card',
        BrokerPropertyTemplate.galleryEditorial => 'gallery_editorial',
        BrokerPropertyTemplate.cinematicGlass => 'cinematic_glass',
      };

  String get title => switch (this) {
        BrokerPropertyTemplate.rentlyClassic => 'Rently Classic',
        BrokerPropertyTemplate.acidHero => 'Aura Hero',
        BrokerPropertyTemplate.dashboardGlass => 'Market Board',
        BrokerPropertyTemplate.estateCard => 'Estate Card',
        BrokerPropertyTemplate.galleryEditorial => 'Gallery Editorial',
        BrokerPropertyTemplate.cinematicGlass => 'Cinematic Glass',
      };
}

extension BrokerChatTemplateLabels on BrokerChatTemplate {
  String get id => switch (this) {
        BrokerChatTemplate.rentlyClassic => 'rently_classic',
        BrokerChatTemplate.softGlass => 'soft_glass',
        BrokerChatTemplate.editorialLight => 'editorial_light',
        BrokerChatTemplate.nightSuite => 'night_suite',
      };

  String get title => switch (this) {
        BrokerChatTemplate.rentlyClassic => 'Rently',
        BrokerChatTemplate.softGlass => 'Glass',
        BrokerChatTemplate.editorialLight => 'Editorial',
        BrokerChatTemplate.nightSuite => 'Night',
      };
}

class BrokerBrandingConfig {
  const BrokerBrandingConfig({
    this.propertyTemplate = BrokerPropertyTemplate.galleryEditorial,
    this.chatTemplate = BrokerChatTemplate.softGlass,
    this.logoPath = '',
    this.primaryColorValue = 0xFF6C5CE7,
    this.secondaryColorValue = 0xFF111827,
    this.accentColorValue = 0xFFECFF74,
  });

  final BrokerPropertyTemplate propertyTemplate;
  final BrokerChatTemplate chatTemplate;
  final String logoPath;
  final int primaryColorValue;
  final int secondaryColorValue;
  final int accentColorValue;

  static const defaults = BrokerBrandingConfig();

  Color get primaryColor => Color(primaryColorValue);
  Color get secondaryColor => Color(secondaryColorValue);
  Color get accentColor => Color(accentColorValue);
  bool get hasLogo => logoPath.trim().isNotEmpty;

  BrokerBrandingConfig copyWith({
    BrokerPropertyTemplate? propertyTemplate,
    BrokerChatTemplate? chatTemplate,
    String? logoPath,
    int? primaryColorValue,
    int? secondaryColorValue,
    int? accentColorValue,
  }) {
    return BrokerBrandingConfig(
      propertyTemplate: propertyTemplate ?? this.propertyTemplate,
      chatTemplate: chatTemplate ?? this.chatTemplate,
      logoPath: logoPath ?? this.logoPath,
      primaryColorValue: primaryColorValue ?? this.primaryColorValue,
      secondaryColorValue: secondaryColorValue ?? this.secondaryColorValue,
      accentColorValue: accentColorValue ?? this.accentColorValue,
    );
  }

  factory BrokerBrandingConfig.fromJson(Object? rawValue) {
    if (rawValue is! Map) return defaults;
    final json = Map<String, dynamic>.from(rawValue);
    return BrokerBrandingConfig(
      propertyTemplate: _propertyTemplateFromId(
        json['propertyTemplate']?.toString(),
      ),
      chatTemplate: _chatTemplateFromId(json['chatTemplate']?.toString()),
      logoPath: json['logoPath']?.toString() ?? '',
      primaryColorValue: _parseColorValue(
        json['primaryColorValue'] ?? json['primaryColor'],
        defaults.primaryColorValue,
      ),
      secondaryColorValue: _parseColorValue(
        json['secondaryColorValue'] ?? json['secondaryColor'],
        defaults.secondaryColorValue,
      ),
      accentColorValue: _parseColorValue(
        json['accentColorValue'] ?? json['accentColor'],
        defaults.accentColorValue,
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'propertyTemplate': propertyTemplate.id,
      'chatTemplate': chatTemplate.id,
      'logoPath': logoPath,
      'primaryColorValue': primaryColorValue,
      'secondaryColorValue': secondaryColorValue,
      'accentColorValue': accentColorValue,
    };
  }

  static BrokerPropertyTemplate _propertyTemplateFromId(String? id) {
    for (final template in BrokerPropertyTemplate.values) {
      if (template.id == id) return template;
    }
    return defaults.propertyTemplate;
  }

  static BrokerChatTemplate _chatTemplateFromId(String? id) {
    for (final template in BrokerChatTemplate.values) {
      if (template.id == id) return template;
    }
    return defaults.chatTemplate;
  }

  static int _parseColorValue(Object? rawValue, int fallback) {
    if (rawValue is int) return rawValue;
    if (rawValue is Color) return rawValue.value;
    final raw = rawValue?.toString().trim();
    if (raw == null || raw.isEmpty) return fallback;
    final normalized = raw
        .replaceFirst('#', '')
        .replaceFirst(RegExp('^0x', caseSensitive: false), '');
    final withAlpha = normalized.length == 6 ? 'FF$normalized' : normalized;
    if (withAlpha.length != 8) return fallback;
    return int.tryParse(withAlpha, radix: 16) ?? fallback;
  }
}
