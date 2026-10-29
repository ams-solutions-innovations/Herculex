import 'dart:collection';
import 'package:device_calendar/device_calendar.dart';
import 'package:drift/drift.dart' as drift;
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/workouts/domain/calendar_service.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;

import 'support/test_database.dart';

class FakeCalendar implements DeviceCalendarPlugin {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  final events = <Event>[];
  bool failRead = false;
  int creates = 0;

  @override
  Future<Result<bool>> hasPermissions() async => Result<bool>()..data = true;

  @override
  Future<Result<UnmodifiableListView<Event>>> retrieveEvents(
    String? calendarId, [
    RetrieveEventsParams? params,
  ]) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    if (failRead) return Result<UnmodifiableListView<Event>>();
    return Result<UnmodifiableListView<Event>>()
      ..data = UnmodifiableListView(
        events
            .where(
              (e) =>
                  e.start!.isAfter(params!.startDate!) &&
                  e.start!.isBefore(params.endDate!),
            )
            .toList(),
      );
  }

  @override
  Future<Result<String>?> createOrUpdateEvent(Event? event) async {
    if (event!.eventId == null) {
      event.eventId = 'event-${++creates}';
      events.add(event);
    }
    return Result<String>()..data = event.eventId;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late FakeCalendar calendar;
  late CalendarService service;
  late int workoutId;

  setUp(() async {
    db = await openTestDatabase();
    calendar = FakeCalendar();
    service = CalendarService(db, deviceCalendarPlugin: calendar);
    workoutId = await db
        .into(db.scheduledWorkouts)
        .insert(
          ScheduledWorkoutsCompanion.insert(
            dateIso: DateFormat('yyyy-MM-dd').format(DateTime.now()),
          ),
        );
  });
  tearDown(() async => db.close());

  test('overlapping full and individual syncs create only one event', () async {
    final results = await Future.wait([
      service.syncTwoWay(calendarId: 'cal').then((r) => r.success),
      service.syncWorkoutNow(workoutId, targetCalendarId: 'cal'),
      service.syncTwoWay(calendarId: 'cal').then((r) => r.success),
    ]);
    expect(results, everyElement(isTrue));
    expect(calendar.events, hasLength(1));
    expect(calendar.creates, 1);
  });

  test('failed calendar read cannot create duplicate events', () async {
    calendar.failRead = true;
    expect((await service.syncTwoWay(calendarId: 'cal')).success, isFalse);
    expect(
      await service.syncWorkoutNow(workoutId, targetCalendarId: 'cal'),
      isFalse,
    );
    expect(calendar.events, isEmpty);
  });

  test('moving a workout by weeks updates its existing event', () async {
    final oldDate = DateTime.now().subtract(const Duration(days: 20));
    calendar.events.add(
      Event(
        'cal',
        eventId: 'old',
        title: 'Workout 🗓️',
        description: '[herculex_workout_id:$workoutId]',
        start: tz.TZDateTime.from(oldDate, tz.local),
        end: tz.TZDateTime.from(
          oldDate.add(const Duration(minutes: 90)),
          tz.local,
        ),
      ),
    );
    expect(
      await service.syncWorkoutNow(workoutId, targetCalendarId: 'cal'),
      isTrue,
    );
    expect(calendar.events, hasLength(1));
    expect(calendar.creates, 0);
    expect(
      DateFormat('yyyy-MM-dd').format(calendar.events.single.start!),
      DateFormat('yyyy-MM-dd').format(DateTime.now()),
    );
  });
}
