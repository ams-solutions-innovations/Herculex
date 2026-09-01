import 'package:flutter/material.dart';

IconData getFastingStageIcon(String? icon) {
  switch (icon) {
    case 'restaurant':
      return Icons.restaurant_rounded;
    case 'battery_charging_full':
      return Icons.battery_charging_full_rounded;
    case 'trending_flat':
      return Icons.trending_flat_rounded;
    case 'hourglass_empty':
      return Icons.hourglass_empty_rounded;
    case 'spa':
      return Icons.spa_rounded;
    case 'balance':
      return Icons.balance_rounded;
    case 'bedtime':
      return Icons.bedtime_rounded;
    case 'bolt':
      return Icons.bolt_rounded;
    case 'autorenew':
      return Icons.autorenew_rounded;
    case 'local_fire_department':
      return Icons.local_fire_department_rounded;
    case 'favorite':
      return Icons.favorite_rounded;
    case 'swap_horiz':
      return Icons.swap_horiz_rounded;
    case 'whatshot':
      return Icons.whatshot_rounded;
    case 'health_and_safety':
      return Icons.health_and_safety_rounded;
    case 'fitness_center':
      return Icons.fitness_center_rounded;
    case 'stars':
      return Icons.stars_rounded;
    case 'build':
      return Icons.build_rounded;
    case 'recycling':
      return Icons.recycling_rounded;
    case 'insights':
      return Icons.insights_rounded;
    case 'psychology':
      return Icons.psychology_rounded;
    case 'cleaning_services':
      return Icons.cleaning_services_rounded;
    case 'workspace_premium':
      return Icons.workspace_premium_rounded;
    case 'electric_bolt':
      return Icons.electric_bolt_rounded;
    case 'shield':
      return Icons.shield_rounded;
    case 'military_tech':
      return Icons.military_tech_rounded;
    case 'dna':
      return Icons.fingerprint_rounded;
    case 'emoji_events':
      return Icons.emoji_events_rounded;
    default:
      return Icons.timelapse_rounded;
  }
}
