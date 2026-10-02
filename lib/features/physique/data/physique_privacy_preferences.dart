import 'package:shared_preferences/shared_preferences.dart';

/// Remembers the accepted physique-photo consent version and the last blur
/// choice. Holds no photo data.
class PhysiquePrivacyPreferences {
  PhysiquePrivacyPreferences(this._prefs);

  static const String consentKey = 'herculex.physique.consent_version.v1';
  static const String blurKey = 'herculex.physique.blur_faces.v1';

  final SharedPreferences _prefs;

  String? get acceptedConsentVersion => _prefs.getString(consentKey);

  Future<void> acceptConsent(String version) =>
      _prefs.setString(consentKey, version);

  bool hasAcceptedConsent(String requiredVersion) =>
      acceptedConsentVersion == requiredVersion;

  bool get blurFaces => _prefs.getBool(blurKey) ?? false;

  Future<void> setBlurFaces(bool value) => _prefs.setBool(blurKey, value);
}
