export 'package:herculex/features/profile/presentation/dream_physique_priorities_view.dart';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/app/router/routes.dart';

@Deprecated('Use DreamPhysiquePrioritiesView with AppRoutes.dreamPhysiquePriorities instead')
class DreamPhysiquePrioritiesSheet {
  static Future<bool?> show(BuildContext context) {
    return context.push<bool>(AppRoutes.dreamPhysiquePriorities);
  }
}
