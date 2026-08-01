import 'package:device_calendar/device_calendar.dart';
import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../../../data/local/database.dart';

class CalendarService {
  final AppDatabase _db;
  final DeviceCalendarPlugin _deviceCalendarPlugin = DeviceCalendarPlugin();

  CalendarService(this._db) {
    // Ensure timezone data is initialized
    tz.initializeTimeZones();
  }

  /// Request permissions to write events to the device calendar.
  Future<bool> requestPermissions() async {
    final permissionsGranted = await _deviceCalendarPlugin.hasPermissions();
    if (permissionsGranted.isSuccess && permissionsGranted.data == true) {
      return true;
    }
    final requestResult = await _deviceCalendarPlugin.requestPermissions();
    return requestResult.isSuccess && requestResult.data == true;
  }

  /// Export all planned/moved scheduled workouts to a dedicated device calendar.
  Future<bool> exportScheduleToCalendar() async {
    final hasPermission = await requestPermissions();
    if (!hasPermission) {
      return false;
    }

    try {
      // 1. Fetch scheduled workouts joined with program days
      final workouts = await _getScheduledWorkoutsWithDays();
      if (workouts.isEmpty) return true;

      // 2. Find or create custom calendar
      final String calendarId = await _findOrCreateHerculexCalendar();

      // 3. Clear/sync strategy: for simplicity and robust update, we create new events
      // for the future scheduled workouts.
      for (final item in workouts) {
        final date = DateTime.parse(item.workout.dateIso);
        
        // Skip dates in the past
        if (date.isBefore(DateTime.now().subtract(const Duration(days: 1)))) {
          continue;
        }

        final String dayName = item.dayName;
        final String emoji = _getEmojiForDay(dayName);
        final String title = "$emoji Herculex: $dayName Day";

        // Create the event (set as All Day for clean schedule placement)
        final tz.TZDateTime startDateTime = tz.TZDateTime.from(
          DateTime(date.year, date.month, date.day, 9, 0), // Default to 9:00 AM
          tz.local,
        );
        final tz.TZDateTime endDateTime = tz.TZDateTime.from(
          DateTime(date.year, date.month, date.day, 10, 30), // Default to 10:30 AM
          tz.local,
        );

        final event = Event(
          calendarId,
          title: title,
          start: startDateTime,
          end: endDateTime,
          description: "Programmed training session scheduled via your Herculex app.",
          allDay: false,
        );

        await _deviceCalendarPlugin.createOrUpdateEvent(event);
      }

      return true;
    } catch (e) {
      debugPrint("Calendar export error: $e");
      return false;
    }
  }

  /// Query scheduled workouts joined with ProgramDays from the local Drift DB.
  Future<List<ScheduledWorkoutWithDay>> _getScheduledWorkoutsWithDays() async {
    final query = _db.select(_db.scheduledWorkouts).join([
      innerJoin(
        _db.programDays,
        _db.programDays.id.equalsExp(_db.scheduledWorkouts.programDayId),
      ),
    ]);

    final rows = await query.get();
    return rows.map((row) {
      final workout = row.readTable(_db.scheduledWorkouts);
      final day = row.readTable(_db.programDays);
      return ScheduledWorkoutWithDay(workout: workout, dayName: day.name);
    }).toList();
  }

  /// Locates "Herculex Training" calendar, creating it if missing. Fallbacks to default if unavailable.
  Future<String> _findOrCreateHerculexCalendar() async {
    final calendarsResult = await _deviceCalendarPlugin.retrieveCalendars();
    if (calendarsResult.isSuccess && calendarsResult.data != null) {
      for (final cal in calendarsResult.data!) {
        if (cal.name == "Herculex Training") {
          return cal.id!;
        }
      }
    }

    // Try creating custom calendar
    final creationResult = await _deviceCalendarPlugin.createCalendar(
      "Herculex Training",
      calendarColor: Colors.deepPurple,
      localAccountName: "Herculex",
    );

    if (creationResult.isSuccess && creationResult.data != null) {
      return creationResult.data!;
    }

    // Fallback: Use the first writable calendar or primary calendar
    if (calendarsResult.isSuccess && calendarsResult.data != null && calendarsResult.data!.isNotEmpty) {
      final writable = calendarsResult.data!.firstWhere((c) => c.isReadOnly == false, orElse: () => calendarsResult.data!.first);
      return writable.id!;
    }

    throw Exception("No writable calendars found on device.");
  }

  /// Resolves target emoji depending on the program day's description name.
  String _getEmojiForDay(String dayName) {
    final name = dayName.toLowerCase();
    if (name.contains("leg") || name.contains("squat") || name.contains("lower") || name.contains("quad")) {
      return "🦵";
    }
    if (name.contains("push") || name.contains("chest") || name.contains("bench") || name.contains("shoulder") || name.contains("press")) {
      return "💪";
    }
    if (name.contains("pull") || name.contains("back") || name.contains("row") || name.contains("deadlift")) {
      return "🏋️";
    }
    if (name.contains("core") || name.contains("abs") || name.contains("cardio")) {
      return "🧘";
    }
    return "🗓️";
  }
}

class ScheduledWorkoutWithDay {
  final ScheduledWorkoutData workout;
  final String dayName;

  const ScheduledWorkoutWithDay({
    required this.workout,
    required this.dayName,
  });
}
