import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Status-bar icon style that follows the active theme.
///
/// `SystemUiOverlayStyle.light` means *light icons*, which are only legible on
/// a dark bar. Screens that hardcoded it left the status bar unreadable in
/// light mode.
SystemUiOverlayStyle overlayStyleFor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark;
