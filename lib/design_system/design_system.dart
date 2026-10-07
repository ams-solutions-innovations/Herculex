/// The app's design system: tokens, theme and shared components.
///
/// One import gets a screen everything visual it should need:
///
/// ```dart
/// import 'package:herculex/design_system/design_system.dart';
/// ```
///
/// The three sub-barrels stay importable on their own for code that wants
/// only one layer — `tokens/tokens.dart` in particular, since domain and
/// data code occasionally needs a domain accent colour without pulling in
/// the whole widget library.
///
/// Nothing in here may import `package:herculex/features/...`. The dependency
/// runs one way: features build on the design system, never the reverse.
library;

export 'components/components.dart';
export 'theme/app_theme.dart';
export 'theme/colors.dart';
export 'theme/haptics.dart';
export 'theme/system_ui.dart';
export 'theme/theme_provider.dart';
export 'tokens/tokens.dart';
