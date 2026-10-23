import 'package:flutter/material.dart';

class OnboardingFeature {
  const OnboardingFeature({
    required this.icon,
    required this.iconBackground,
    required this.iconColor,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final Color iconBackground;
  final Color iconColor;
  final String title;
  final String description;
}

class OnboardingPage {
  const OnboardingPage({
    required this.image,
    this.badge,
    required this.title,
    required this.description,
    required this.features,
  });

  final String image;
  final String? badge;
  final String title;
  final String description;
  final List<OnboardingFeature> features;
}
