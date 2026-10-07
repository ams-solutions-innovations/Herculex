import 'package:collection/collection.dart';
import 'package:device_calendar/device_calendar.dart';
import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:herculex/data/local/database.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class CalendarSyncResult {
  final bool success;
  final int pulledCount;
  final int pushedCount;
  final String? error;

  const CalendarSyncResult({
    required this.success,
    this.pulledCount = 0,
    this.pushedCount = 0,
    this.error,
  });
}

class CalendarService {
  final AppDatabase _db;
  final DeviceCalendarPlugin _deviceCalendarPlugin = DeviceCalendarPlugin();

  CalendarService(this._db) {
    _ensureTimezone();
  }

  Future<void> _ensureTimezone() async {
    try {
      tz.initializeTimeZones();
      final deviceTz = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(deviceTz.identifier));
    } catch (_) {}
  }

  /// Checks if calendar permissions are granted.
  Future<bool> hasPermissions() async {
    try {
      final permissionsGranted = await _deviceCalendarPlugin.hasPermissions();
      if (permissionsGranted.isSuccess && permissionsGranted.data == true) {
        return true;
      }
    } catch (_) {}

    try {
      final status = await Permission.calendarFullAccess.status;
      if (status.isGranted) return true;
      final writeOnly = await Permission.calendarWriteOnly.status;
      if (writeOnly.isGranted) return true;
    } catch (_) {}

    return false;
  }

  /// Request permissions to read and write events to the device calendar.
  Future<bool> requestPermissions() async {
    if (await hasPermissions()) {
      return true;
    }

    try {
      final requestResult = await _deviceCalendarPlugin.requestPermissions();
      if (requestResult.isSuccess && requestResult.data == true) {
        return true;
      }
    } catch (_) {}

    try {
      final status = await Permission.calendarFullAccess.request();
      if (status.isGranted) return true;
      final writeOnly = await Permission.calendarWriteOnly.request();
      if (writeOnly.isGranted) return true;
    } catch (_) {}

    return false;
  }

  /// Returns all writable calendars available on this device.
  Future<List<Calendar>> getWritableCalendars() async {
    final hasPerm = await requestPermissions();
    if (!hasPerm) return [];

    try {
      final calendarsResult = await _deviceCalendarPlugin.retrieveCalendars();
      if (calendarsResult.isSuccess && calendarsResult.data != null) {
        return calendarsResult.data!
            .where((c) => c.isReadOnly == false && c.id != null)
            .toList();
      }
    } catch (e) {
      debugPrint("CalendarService: retrieveCalendars failed: $e");
    }
    return [];
  }

  /// Locates "Herculex Training" calendar, creating it if missing. Fallbacks to Google / default calendar if unavailable.
  Future<String> findOrCreateHerculexCalendar() async {
    final calendarsResult = await _deviceCalendarPlugin.retrieveCalendars();
    final cals = (calendarsResult.isSuccess && calendarsResult.data != null)
        ? calendarsResult.data!
        : <Calendar>[];

    // 1. Check if "Herculex Training" calendar already exists and is writable
    for (final cal in cals) {
      if (cal.name == "Herculex Training" &&
          cal.isReadOnly == false &&
          cal.id != null) {
        return cal.id!;
      }
    }

    // 2. Look for an existing Google account or primary account
    Calendar? googleCal;
    for (final cal in cals) {
      if (cal.isReadOnly == false) {
        final isGoogle =
            (cal.accountType?.toLowerCase().contains('google') == true) ||
            (cal.accountName?.contains('@') == true);
        if (isGoogle) {
          googleCal = cal;
          break;
        }
      }
    }

    // 3. Try creating custom calendar "Herculex Training"
    try {
      final creationResult = await _deviceCalendarPlugin.createCalendar(
        "Herculex Training",
        calendarColor: Colors.deepPurple,
        localAccountName: googleCal?.accountName ?? "Herculex",
      );

      if (creationResult.isSuccess &&
          creationResult.data != null &&
          creationResult.data!.isNotEmpty) {
        return creationResult.data!;
      }
    } catch (e) {
      debugPrint("CalendarService: createCalendar failed: $e");
    }

    // 4. Fallback: If Google calendar exists and is writable, use it
    if (googleCal != null && googleCal.id != null) {
      return googleCal.id!;
    }

    // 5. Fallback: Default writable calendar
    final defaultCal = cals.firstWhereOrNull(
      (c) => c.isDefault == true && c.isReadOnly == false && c.id != null,
    );
    if (defaultCal != null) {
      return defaultCal.id!;
    }

    // 6. Fallback: Any writable calendar
    final anyWritable = cals.firstWhereOrNull(
      (c) => c.isReadOnly == false && c.id != null,
    );
    if (anyWritable != null) {
      return anyWritable.id!;
    }

    if (cals.isNotEmpty && cals.first.id != null) {
      return cals.first.id!;
    }

    throw Exception("No writable calendars found on device.");
  }

  /// Full 2-Way Sync between Herculex scheduled workouts and Google / Device Calendar.
  ///
  /// 1. Inbound: Pull changes made in Google Calendar (moved dates or changed times)
  ///    and apply them to local `scheduled_workouts`.
  /// 2. Outbound: Push local scheduled workouts, updates, and completion checkmarks
  ///    to Google Calendar.
  Future<CalendarSyncResult> syncTwoWay({String? calendarId}) async {
    final hasPerm = await requestPermissions();
    if (!hasPerm) {
      return const CalendarSyncResult(
        success: false,
        error: 'Calendar permission not granted',
      );
    }

    try {
      await _ensureTimezone();
      final String targetCalendarId =
          calendarId ?? await findOrCreateHerculexCalendar();

      final now = DateTime.now();
      final windowStart = now.subtract(const Duration(days: 30));
      final windowEnd = now.add(const Duration(days: 90));

      // 1. Retrieve all calendar events in the window
      final eventsResult = await _deviceCalendarPlugin.retrieveEvents(
        targetCalendarId,
        RetrieveEventsParams(startDate: windowStart, endDate: windowEnd),
      );

      final calendarEvents = eventsResult.isSuccess && eventsResult.data != null
          ? eventsResult.data!
          : <Event>[];

      // Map existing calendar events by their Herculex workout ID extracted from description
      final idRegex = RegExp(r'\[herculex_workout_id:(\d+)\]');
      final Map<int, Event> eventsByWorkoutId = {};

      for (final event in calendarEvents) {
        if (event.description != null) {
          final match = idRegex.firstMatch(event.description!);
          if (match != null) {
            final workoutId = int.tryParse(match.group(1)!);
            if (workoutId != null) {
              eventsByWorkoutId[workoutId] = event;
            }
          }
        }
      }

      final windowStartIso = DateFormat('yyyy-MM-dd').format(windowStart);
      final windowEndIso = DateFormat('yyyy-MM-dd').format(windowEnd);

      // 2. Fetch scheduled workouts from Herculex Drift DB
      final scheduledRows = await _getScheduledWorkoutsWithDaysInRange(
        windowStartIso,
        windowEndIso,
      );

      int pulledCount = 0;
      int pushedCount = 0;

      // 3. PHASE 1: INBOUND SYNC (Google Calendar -> Herculex)
      for (final item in scheduledRows) {
        final workout = item.workout;
        final existingEvent = eventsByWorkoutId[workout.id];

        if (existingEvent != null && existingEvent.start != null) {
          final eventStartLocal = existingEvent.start!.toLocal();
          final eventDateIso = DateFormat('yyyy-MM-dd').format(eventStartLocal);
          final eventStartMinutes =
              eventStartLocal.hour * 60 + eventStartLocal.minute;

          bool needsDbUpdate = false;
          String newDateIso = workout.dateIso;
          int? newStartMinutes = workout.startTimeMinutes;
          String newStatus = workout.status;

          // Check if date was changed in Google Calendar
          if (eventDateIso != workout.dateIso) {
            newDateIso = eventDateIso;
            if (workout.status == 'planned') {
              newStatus = 'moved';
            }
            needsDbUpdate = true;
          }

          // Check if start time was changed in Google Calendar (default 9:00 AM = 540 if null)
          final currentMinutes = workout.startTimeMinutes ?? 540;
          if ((eventStartMinutes - currentMinutes).abs() >= 1) {
            newStartMinutes = eventStartMinutes;
            needsDbUpdate = true;
          }

          if (needsDbUpdate) {
            await (_db.update(
              _db.scheduledWorkouts,
            )..where((tbl) => tbl.id.equals(workout.id))).write(
              ScheduledWorkoutsCompanion(
                dateIso: Value(newDateIso),
                startTimeMinutes: Value(newStartMinutes),
                status: Value(newStatus),
              ),
            );
            pulledCount++;
          }
        }
      }

      // Re-fetch after inbound changes
      final updatedScheduledRows = await _getScheduledWorkoutsWithDaysInRange(
        windowStartIso,
        windowEndIso,
      );

      // 4. PHASE 2: OUTBOUND SYNC (Herculex scheduled workouts -> Google Calendar)
      for (final item in updatedScheduledRows) {
        final workout = item.workout;
        final existingEvent = eventsByWorkoutId[workout.id];

        // If workout is skipped, delete event from calendar if it exists
        if (workout.status == 'skipped') {
          if (existingEvent != null && existingEvent.eventId != null) {
            await _deviceCalendarPlugin.deleteEvent(
              targetCalendarId,
              existingEvent.eventId!,
            );
          }
          continue;
        }

        final date = DateTime.tryParse(workout.dateIso) ?? now;
        final int startMin = workout.startTimeMinutes ?? 540; // Default 9:00 AM
        final int startHour = startMin ~/ 60;
        final int startMinute = startMin % 60;

        final startDateTime = tz.TZDateTime(
          tz.local,
          date.year,
          date.month,
          date.day,
          startHour,
          startMinute,
        );
        final endDateTime = startDateTime.add(const Duration(minutes: 90));

        final String dayName = item.dayName;
        final String title = calendarEventTitle(
          dayName,
          done: workout.status == 'done',
        );

        final String description =
            "Programmed training session scheduled via your Herculex app.\n[herculex_workout_id:${workout.id}]";

        if (existingEvent != null) {
          final eventStartLocal = existingEvent.start?.toLocal();
          final sameStart =
              eventStartLocal != null &&
              eventStartLocal.year == startDateTime.year &&
              eventStartLocal.month == startDateTime.month &&
              eventStartLocal.day == startDateTime.day &&
              eventStartLocal.hour == startDateTime.hour &&
              eventStartLocal.minute == startDateTime.minute;
          final sameTitle = existingEvent.title == title;

          if (!sameStart || !sameTitle) {
            existingEvent.title = title;
            existingEvent.start = startDateTime;
            existingEvent.end = endDateTime;
            existingEvent.description = description;
            final res = await _deviceCalendarPlugin.createOrUpdateEvent(
              existingEvent,
            );
            if (res?.isSuccess == true) {
              pushedCount++;
            }
          }
        } else {
          final newEvent = Event(
            targetCalendarId,
            title: title,
            start: startDateTime,
            end: endDateTime,
            description: description,
            allDay: false,
          );
          final res = await _deviceCalendarPlugin.createOrUpdateEvent(newEvent);
          if (res?.isSuccess == true) {
            pushedCount++;
          }
        }
      }

      // 5. PHASE 3: OUTBOUND SYNC FOR COMPLETED SESSIONS (even if unscheduled)
      final completedSessions =
          await (_db.select(_db.workoutSessions)..where(
                (t) =>
                    t.endedAt.isNotNull() &
                    t.startedAt.isBiggerOrEqualValue(windowStart) &
                    t.startedAt.isSmallerOrEqualValue(windowEnd),
              ))
              .get();

      final sessionRegex = RegExp(r'\[herculex_session_id:(\d+)\]');
      final Map<int, Event> eventsBySessionId = {};
      for (final event in calendarEvents) {
        if (event.description != null) {
          final match = sessionRegex.firstMatch(event.description!);
          if (match != null) {
            final sId = int.tryParse(match.group(1)!);
            if (sId != null) {
              eventsBySessionId[sId] = event;
            }
          }
        }
      }

      final scheduledSessionIds = updatedScheduledRows
          .map((r) => r.workout.completedSessionId)
          .whereType<int>()
          .toSet();

      for (final session in completedSessions) {
        if (scheduledSessionIds.contains(session.id)) {
          continue; // Already synced via scheduled workouts
        }

        final existingEvent = eventsBySessionId[session.id];
        final sessionStart = tz.TZDateTime.from(session.startedAt, tz.local);
        final sessionEnd = session.endedAt != null
            ? tz.TZDateTime.from(session.endedAt!, tz.local)
            : sessionStart.add(const Duration(minutes: 60));

        final sessionName = (session.name?.trim().isNotEmpty == true)
            ? session.name!.trim()
            : 'Workout';
        final title = calendarEventTitle(sessionName, done: true);
        final description =
            "Completed training session recorded in Herculex.\n[herculex_session_id:${session.id}]";

        if (existingEvent != null) {
          final eventStartLocal = existingEvent.start?.toLocal();
          final sameStart =
              eventStartLocal != null &&
              (eventStartLocal.difference(session.startedAt).inMinutes.abs() <
                  1);
          final sameTitle = existingEvent.title == title;

          if (!sameStart || !sameTitle) {
            existingEvent.title = title;
            existingEvent.start = sessionStart;
            existingEvent.end = sessionEnd;
            existingEvent.description = description;
            final res = await _deviceCalendarPlugin.createOrUpdateEvent(
              existingEvent,
            );
            if (res?.isSuccess == true) {
              pushedCount++;
            }
          }
        } else {
          final newEvent = Event(
            targetCalendarId,
            title: title,
            start: sessionStart,
            end: sessionEnd,
            description: description,
            allDay: false,
          );
          final res = await _deviceCalendarPlugin.createOrUpdateEvent(newEvent);
          if (res?.isSuccess == true) {
            pushedCount++;
          }
        }
      }

      return CalendarSyncResult(
        success: true,
        pulledCount: pulledCount,
        pushedCount: pushedCount,
      );
    } catch (e) {
      debugPrint("Calendar 2-way sync error: $e");
      return CalendarSyncResult(success: false, error: e.toString());
    }
  }

  /// Sync single workout immediately to device calendar (e.g. after move or complete).
  Future<bool> syncWorkoutNow(int workoutId, {String? targetCalendarId}) async {
    final hasPerm = await hasPermissions();
    if (!hasPerm) return false;

    try {
      await _ensureTimezone();
      final String calendarId =
          targetCalendarId ?? await findOrCreateHerculexCalendar();

      final query = _db.select(_db.scheduledWorkouts).join([
        leftOuterJoin(
          _db.programDays,
          _db.programDays.id.equalsExp(_db.scheduledWorkouts.programDayId),
        ),
      ])..where(_db.scheduledWorkouts.id.equals(workoutId));

      final rows = await query.get();
      if (rows.isEmpty) return false;

      final row = rows.first;
      final workout = row.readTable(_db.scheduledWorkouts);
      final day = row.readTableOrNull(_db.programDays);

      final date = DateTime.tryParse(workout.dateIso) ?? DateTime.now();
      final int startMin = workout.startTimeMinutes ?? 540;
      final int startHour = startMin ~/ 60;
      final int startMinute = startMin % 60;

      final startDateTime = tz.TZDateTime(
        tz.local,
        date.year,
        date.month,
        date.day,
        startHour,
        startMinute,
      );
      final endDateTime = startDateTime.add(const Duration(minutes: 90));

      final String dayName = day?.name ?? 'Workout';
      final String title = calendarEventTitle(
        dayName,
        done: workout.status == 'done',
      );
      final String description =
          "Programmed training session scheduled via your Herculex app.\n[herculex_workout_id:${workout.id}]";

      final eventsResult = await _deviceCalendarPlugin.retrieveEvents(
        calendarId,
        RetrieveEventsParams(
          startDate: date.subtract(const Duration(days: 3)),
          endDate: date.add(const Duration(days: 3)),
        ),
      );

      Event? targetEvent;
      if (eventsResult.isSuccess && eventsResult.data != null) {
        final idRegex = RegExp(r'\[herculex_workout_id:(\d+)\]');
        for (final event in eventsResult.data!) {
          if (event.description != null) {
            final match = idRegex.firstMatch(event.description!);
            if (match != null && match.group(1) == workoutId.toString()) {
              targetEvent = event;
              break;
            }
          }
        }
      }

      if (workout.status == 'skipped') {
        if (targetEvent != null && targetEvent.eventId != null) {
          await _deviceCalendarPlugin.deleteEvent(
            calendarId,
            targetEvent.eventId!,
          );
        }
        return true;
      }

      if (targetEvent != null) {
        targetEvent.title = title;
        targetEvent.start = startDateTime;
        targetEvent.end = endDateTime;
        targetEvent.description = description;
        final res = await _deviceCalendarPlugin.createOrUpdateEvent(
          targetEvent,
        );
        return res?.isSuccess == true;
      } else {
        final newEvent = Event(
          calendarId,
          title: title,
          start: startDateTime,
          end: endDateTime,
          description: description,
          allDay: false,
        );
        final res = await _deviceCalendarPlugin.createOrUpdateEvent(newEvent);
        return res?.isSuccess == true;
      }
    } catch (e) {
      debugPrint("Calendar single-workout sync error: $e");
      return false;
    }
  }

  /// Deletes corresponding workout event from device calendar when deleted in Herculex.
  Future<bool> deleteWorkoutFromCalendar(
    int workoutId, {
    String? targetCalendarId,
  }) async {
    final hasPerm = await hasPermissions();
    if (!hasPerm) return false;

    try {
      final String calendarId =
          targetCalendarId ?? await findOrCreateHerculexCalendar();

      final now = DateTime.now();
      final eventsResult = await _deviceCalendarPlugin.retrieveEvents(
        calendarId,
        RetrieveEventsParams(
          startDate: now.subtract(const Duration(days: 30)),
          endDate: now.add(const Duration(days: 90)),
        ),
      );

      if (eventsResult.isSuccess && eventsResult.data != null) {
        final idRegex = RegExp(r'\[herculex_workout_id:(\d+)\]');
        for (final event in eventsResult.data!) {
          if (event.description != null) {
            final match = idRegex.firstMatch(event.description!);
            if (match != null && match.group(1) == workoutId.toString()) {
              if (event.eventId != null) {
                final res = await _deviceCalendarPlugin.deleteEvent(
                  calendarId,
                  event.eventId!,
                );
                return res.isSuccess;
              }
            }
          }
        }
      }
      return true;
    } catch (e) {
      debugPrint("Calendar delete workout error: $e");
      return false;
    }
  }

  /// Backward-compatible export method.
  Future<bool> exportScheduleToCalendar() async {
    final result = await syncTwoWay();
    return result.success;
  }

  /// Query scheduled workouts joined with ProgramDays from the local Drift DB within date range.
  Future<List<ScheduledWorkoutWithDay>> _getScheduledWorkoutsWithDaysInRange(
    String startIso,
    String endIso,
  ) async {
    final query =
        _db.select(_db.scheduledWorkouts).join([
          leftOuterJoin(
            _db.programDays,
            _db.programDays.id.equalsExp(_db.scheduledWorkouts.programDayId),
          ),
        ])..where(
          _db.scheduledWorkouts.dateIso.isBiggerOrEqualValue(startIso) &
              _db.scheduledWorkouts.dateIso.isSmallerOrEqualValue(endIso),
        );

    final rows = await query.get();
    return rows.map((row) {
      final workout = row.readTable(_db.scheduledWorkouts);
      final day = row.readTableOrNull(_db.programDays);
      return ScheduledWorkoutWithDay(
        workout: workout,
        dayName: day?.name ?? 'Workout',
      );
    }).toList();
  }

  /// Resolves target emoji depending on the program day's description name.
  static String emojiForDay(String dayName) {
    final name = dayName.toLowerCase();
    if (name.contains("leg") ||
        name.contains("squat") ||
        name.contains("lower") ||
        name.contains("quad")) {
      return "🦵";
    }
    if (name.contains("push") ||
        name.contains("upper") ||
        name.contains("arm") ||
        name.contains("chest") ||
        name.contains("bench") ||
        name.contains("shoulder") ||
        name.contains("press")) {
      return "💪";
    }
    if (name.contains("pull") ||
        name.contains("back") ||
        name.contains("row") ||
        name.contains("deadlift")) {
      return "🏋️";
    }
    if (name.contains("core") ||
        name.contains("abs") ||
        name.contains("cardio")) {
      return "🧘";
    }
    return "🗓️";
  }
}

class ScheduledWorkoutWithDay {
  final ScheduledWorkoutData workout;
  final String dayName;

  const ScheduledWorkoutWithDay({required this.workout, required this.dayName});
}

/// Calendar event title for a workout: the session's own name and its emoji,
/// e.g. "Upper 💪" — short enough to read in a month view, with no app
/// prefix. A finished session gets a trailing ✅.
///
/// Events are matched by the `[herculex_workout_id:…]` marker in their
/// description, never by title, so the wording can change freely.
String calendarEventTitle(String name, {required bool done}) {
  final trimmed = name.trim().isEmpty ? 'Workout' : name.trim();
  final base = '$trimmed ${CalendarService.emojiForDay(trimmed)}';
  return done ? '$base ✅' : base;
}
