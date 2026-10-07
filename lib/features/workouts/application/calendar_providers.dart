import 'package:device_calendar/device_calendar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/features/workouts/application/workouts_providers.dart';
import 'package:herculex/features/workouts/domain/calendar_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kCalendarSyncEnabledKey = 'herculex_calendar_sync_enabled';
const _kCalendarIdKey = 'herculex_calendar_id';
const _kCalendarLastSyncKey = 'herculex_calendar_last_sync_timestamp';

/// Whether Google / Device Calendar 2-Way Sync is enabled.
final calendarSyncEnabledProvider =
    StateNotifierProvider<CalendarSyncEnabledNotifier, bool>((ref) {
      final prefs = ref.watch(sharedPreferencesProvider);
      return CalendarSyncEnabledNotifier(prefs);
    });

class CalendarSyncEnabledNotifier extends StateNotifier<bool> {
  final SharedPreferences _prefs;
  CalendarSyncEnabledNotifier(this._prefs)
    : super(_prefs.getBool(_kCalendarSyncEnabledKey) ?? false);

  Future<void> toggle(bool enabled) async {
    state = enabled;
    await _prefs.setBool(_kCalendarSyncEnabledKey, enabled);
  }
}

/// The selected device calendar ID (null = automatic "Herculex Training").
final selectedCalendarIdProvider =
    StateNotifierProvider<SelectedCalendarIdNotifier, String?>((ref) {
      final prefs = ref.watch(sharedPreferencesProvider);
      return SelectedCalendarIdNotifier(prefs);
    });

class SelectedCalendarIdNotifier extends StateNotifier<String?> {
  final SharedPreferences _prefs;
  SelectedCalendarIdNotifier(this._prefs)
    : super(_prefs.getString(_kCalendarIdKey));

  Future<void> setCalendarId(String? id) async {
    state = id;
    if (id == null) {
      await _prefs.remove(_kCalendarIdKey);
    } else {
      await _prefs.setString(_kCalendarIdKey, id);
    }
  }
}

/// Last timestamp when calendar sync completed.
final lastCalendarSyncTimestampProvider =
    StateNotifierProvider<LastCalendarSyncNotifier, DateTime?>((ref) {
      final prefs = ref.watch(sharedPreferencesProvider);
      return LastCalendarSyncNotifier(prefs);
    });

class LastCalendarSyncNotifier extends StateNotifier<DateTime?> {
  final SharedPreferences _prefs;
  LastCalendarSyncNotifier(this._prefs)
    : super(
        _prefs.getInt(_kCalendarLastSyncKey) != null
            ? DateTime.fromMillisecondsSinceEpoch(
                _prefs.getInt(_kCalendarLastSyncKey)!,
              )
            : null,
      );

  Future<void> recordSync() async {
    final now = DateTime.now();
    state = now;
    await _prefs.setInt(_kCalendarLastSyncKey, now.millisecondsSinceEpoch);
  }
}

/// Writable calendars available on device.
final availableCalendarsProvider = FutureProvider<List<Calendar>>((ref) async {
  final service = ref.watch(calendarServiceProvider);
  return service.getWritableCalendars();
});

/// State of 2-way sync action (idle, syncing, success, error)
enum CalendarSyncStateStatus { idle, syncing, success, error }

class CalendarSyncState {
  final CalendarSyncStateStatus status;
  final CalendarSyncResult? result;
  final String? error;

  const CalendarSyncState({
    this.status = CalendarSyncStateStatus.idle,
    this.result,
    this.error,
  });

  bool get isSyncing => status == CalendarSyncStateStatus.syncing;
}

final calendarSyncControllerProvider =
    StateNotifierProvider<CalendarSyncController, CalendarSyncState>((ref) {
      final service = ref.watch(calendarServiceProvider);
      final calendarId = ref.watch(selectedCalendarIdProvider);
      return CalendarSyncController(ref, service, calendarId);
    });

class CalendarSyncController extends StateNotifier<CalendarSyncState> {
  final Ref _ref;
  final CalendarService _service;
  final String? _calendarId;

  CalendarSyncController(this._ref, this._service, this._calendarId)
    : super(const CalendarSyncState());

  Future<CalendarSyncResult> syncNow() async {
    state = const CalendarSyncState(status: CalendarSyncStateStatus.syncing);
    final result = await _service.syncTwoWay(calendarId: _calendarId);

    if (result.success) {
      await _ref.read(lastCalendarSyncTimestampProvider.notifier).recordSync();
      state = CalendarSyncState(
        status: CalendarSyncStateStatus.success,
        result: result,
      );
    } else {
      state = CalendarSyncState(
        status: CalendarSyncStateStatus.error,
        error: result.error ?? 'Failed to sync calendar',
      );
    }
    return result;
  }
}
