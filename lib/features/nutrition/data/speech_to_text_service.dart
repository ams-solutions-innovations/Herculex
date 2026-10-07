import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/app/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

class SttLanguageOption {
  final String localeId;
  final String name;
  final String flag;

  const SttLanguageOption({
    required this.localeId,
    required this.name,
    required this.flag,
  });
}

const kSupportedSttLanguages = [
  SttLanguageOption(localeId: 'sl_SI', name: 'Slovenščina', flag: '🇸🇮'),
  SttLanguageOption(localeId: 'en_US', name: 'English (US)', flag: '🇺🇸'),
  SttLanguageOption(localeId: 'en_GB', name: 'English (UK)', flag: '🇬🇧'),
  SttLanguageOption(localeId: 'de_DE', name: 'Deutsch', flag: '🇩🇪'),
  SttLanguageOption(localeId: 'it_IT', name: 'Italiano', flag: '🇮🇹'),
  SttLanguageOption(localeId: 'hr_HR', name: 'Hrvatski', flag: '🇭🇷'),
  SttLanguageOption(localeId: 'es_ES', name: 'Español', flag: '🇪🇸'),
  SttLanguageOption(localeId: 'fr_FR', name: 'Français', flag: '🇫🇷'),
];

final speechToTextServiceProvider = ChangeNotifierProvider<SpeechToTextService>(
  (ref) {
    final prefs = ref.watch(sharedPreferencesProvider);
    return SpeechToTextService(prefs);
  },
);

class SpeechToTextService extends ChangeNotifier {
  final SharedPreferences? _prefs;
  final SpeechToText _speech = SpeechToText();
  bool _isInitialized = false;
  bool _isListening = false;
  late String _selectedLocaleId;
  List<LocaleName> _locales = [];
  String? _lastError;

  static const String _prefKey = 'stt_selected_locale';

  SpeechToTextService([this._prefs]) {
    _selectedLocaleId = _prefs?.getString(_prefKey) ?? 'sl_SI';
  }

  bool get isInitialized => _isInitialized;
  bool get isListening => _isListening;
  String get selectedLocaleId => _selectedLocaleId;
  List<LocaleName> get locales => _locales;
  String? get lastError => _lastError;

  SttLanguageOption get selectedLanguageOption {
    final match = kSupportedSttLanguages.firstWhere(
      (opt) => opt.localeId.toLowerCase() == _selectedLocaleId.toLowerCase(),
      orElse: () {
        // Fallback or device custom
        final base = _selectedLocaleId.split('_').first.toLowerCase();
        return kSupportedSttLanguages.firstWhere(
          (opt) => opt.localeId.toLowerCase().startsWith(base),
          orElse: () => SttLanguageOption(
            localeId: _selectedLocaleId,
            name: _selectedLocaleId,
            flag: '🌐',
          ),
        );
      },
    );
    return match;
  }

  Future<bool> initialize() async {
    if (_isInitialized) return true;
    try {
      _isInitialized = await _speech.initialize(
        onError: (error) {
          _lastError = error.errorMsg;
          _isListening = false;
          notifyListeners();
        },
        onStatus: (status) {
          _isListening = status == 'listening';
          notifyListeners();
        },
      );
      if (_isInitialized) {
        _locales = await _speech.locales();
      }
      notifyListeners();
      return _isInitialized;
    } catch (e) {
      _lastError = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<void> setLocale(String localeId) async {
    _selectedLocaleId = localeId;
    await _prefs?.setString(_prefKey, localeId);
    notifyListeners();
  }

  Future<void> startListening({
    required Function(String text, bool isFinal) onResult,
    String? localeId,
  }) async {
    if (!_isInitialized) {
      final ok = await initialize();
      if (!ok) return;
    }

    final targetLocale = localeId ?? _selectedLocaleId;

    _lastError = null;
    try {
      await _speech.listen(
        onResult: (SpeechRecognitionResult result) {
          onResult(result.recognizedWords, result.finalResult);
        },
        listenOptions: SpeechListenOptions(
          localeId: targetLocale,
          partialResults: true,
          cancelOnError: true,
          listenMode: ListenMode.dictation,
        ),
      );
      _isListening = _speech.isListening;
      notifyListeners();
    } catch (e) {
      _lastError = e.toString();
      _isListening = false;
      notifyListeners();
    }
  }

  Future<void> stopListening() async {
    if (_isListening) {
      await _speech.stop();
      _isListening = false;
      notifyListeners();
    }
  }

  Future<void> cancelListening() async {
    if (_isListening) {
      await _speech.cancel();
      _isListening = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _speech.stop();
    super.dispose();
  }
}
