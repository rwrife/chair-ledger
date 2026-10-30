import 'package:chair_ledger/schedule.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final service = Service(
    id: 'cut',
    name: 'Cut',
    durationMinutes: 30,
    bufferMinutes: 10,
  );
  final monday = DateTime(2026, 11, 2, 9);
  final hours = [
    WorkingWindow(
      weekday: DateTime.monday,
      openMinute: 9 * 60,
      closeMinute: 17 * 60,
    ),
  ];
  Appointment at(
    int minutes, {
    String id = 'a',
    Service? using,
    BookingStatus status = BookingStatus.booked,
  }) => Appointment(
    id: id,
    serviceId: 'cut',
    startLocal: monday.add(Duration(minutes: minutes)),
    durationMinutes: (using ?? service).durationMinutes,
    bufferMinutes: (using ?? service).bufferMinutes,
    status: status,
  );

  test('half-open adjacency, snapshot, buffer and status', () {
    final first = Appointment.forService(
      id: 'a',
      service: service,
      startLocal: monday,
    );
    expect(first.endMinute, 580);
    expect(validateSlot(at(40, id: 'b'), hours, [first]), isNull);
    expect(validateSlot(at(39, id: 'b'), hours, [first]), SlotError.conflict);
    expect(validateSlot(at(30, id: 'b'), hours, [first]), SlotError.conflict);
    expect(
      validateSlot(at(10, id: 'b'), hours, [
        at(0, status: BookingStatus.completed),
      ]),
      SlotError.conflict,
    );
    expect(
      validateSlot(at(10, id: 'b'), hours, [
        at(0, status: BookingStatus.cancelled),
      ]),
      isNull,
    );
    expect(
      validateSlot(at(10, id: 'a'), hours, [first]),
      SlotError.duplicateId,
    );
    final changedService = Service(
      id: 'cut',
      name: 'Cut',
      durationMinutes: 90,
      bufferMinutes: 0,
    );
    expect(first.durationMinutes, 30);
    expect(
      Appointment.forService(
        id: 'b',
        service: changedService,
        startLocal: monday,
      ).durationMinutes,
      90,
    );
  });

  test('bounds, breaks, midnight and bad inputs', () {
    expect(validateSlot(at(-1), hours, []), SlotError.outsideHours);
    expect(validateSlot(at(7 * 60 + 31), hours, []), SlotError.outsideHours);
    expect(validateSlot(at(0), hours, []), isNull);
    expect(validateSlot(at(7 * 60 + 21), hours, []), SlotError.outsideHours);
    final closing = [
      WorkingWindow(weekday: DateTime.monday, openMinute: 0, closeMinute: 1440),
    ];
    expect(
      validateSlot(at(14 * 60 + 30), closing, []),
      SlotError.crossesMidnight,
    );
    final split = [
      WorkingWindow(
        weekday: DateTime.monday,
        openMinute: 540,
        closeMinute: 720,
      ),
      WorkingWindow(
        weekday: DateTime.monday,
        openMinute: 780,
        closeMinute: 1020,
      ),
    ];
    expect(validateSlot(at(180), split, []), SlotError.outsideHours);
    expect(
      () => Service(id: '', name: 'X', durationMinutes: 1, bufferMinutes: 0),
      throwsArgumentError,
    );
    expect(
      () => WorkingWindow(weekday: 8, openMinute: 0, closeMinute: 1),
      throwsArgumentError,
    );
    expect(
      () => Appointment(
        id: 'x',
        serviceId: 'x',
        startLocal: monday,
        durationMinutes: -1,
        bufferMinutes: 0,
      ),
      throwsArgumentError,
    );
    expect(
      validateSlot(
        Appointment(
          id: 'x',
          serviceId: 'cut',
          startLocal: DateTime.utc(2026, 11, 2, 9),
          durationMinutes: 30,
          bufferMinutes: 0,
        ),
        hours,
        [],
      ),
      SlotError.invalidLocalTime,
    );
  });

  test('DST fold, gap and crossing under a zone with these transitions', () {
    final spring = DateTime(2026, 3, 8, 1, 30);
    final fall = DateTime(2026, 11, 1, 1, 30);
    // Windows runners use their host zone. Run with TZ=America/New_York
    // on Linux to execute the transition branch.
    if (spring.timeZoneOffset == DateTime(2026, 3, 8, 3, 30).timeZoneOffset &&
        fall.timeZoneOffset == DateTime(2026, 11, 1, 2, 30).timeZoneOffset) {
      return;
    }
    expect(isUniqueLocalMinute(fall), isFalse);
    expect(
      isUniqueLocalMinute(DateTime(2026, 3, 8, 2, 30)),
      isTrue,
      reason: 'DateTime normalizes skipped wall minute: parseLocalMinute rejects original input',
    );
    expect(() => parseLocalMinute(2026, 3, 8, 2, 30), throwsFormatException);
    expect(() => parseLocalMinute(2026, 11, 1, 1, 30), throwsFormatException);
    final crossing = Appointment(
      id: 'x',
      serviceId: 'cut',
      startLocal: spring,
      durationMinutes: 90,
      bufferMinutes: 0,
    );
    final sunday = [
      WorkingWindow(weekday: DateTime.sunday, openMinute: 0, closeMinute: 1440),
    ];
    expect(validateSlot(crossing, sunday, []), SlotError.invalidLocalTime);
  });
}
