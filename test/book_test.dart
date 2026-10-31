import 'dart:io';

import 'package:chair_ledger/book.dart';
import 'package:chair_ledger/schedule.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late String file;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('chair-ledger-test-');
    file = '${directory.path}/book.db';
  });
  tearDown(() => directory.deleteSync(recursive: true));

  final cut = Service(
    id: 'cut',
    name: 'Cut',
    durationMinutes: 30,
    bufferMinutes: 10,
  );
  final hours = [
    WorkingWindow(weekday: DateTime.monday, openMinute: 540, closeMinute: 1020),
  ];
  Appointment at(
    int minute, {
    String id = 'a',
    BookingStatus status = BookingStatus.booked,
  }) => Appointment.forService(
    id: id,
    service: cut,
    startLocal: DateTime(2026, 11, 2, 9).add(Duration(minutes: minute)),
  );

  test('committed rows survive restart; edits keep snapshot and metadata', () {
    final book = Book.open(file);
    book.saveService(cut);
    book.setWindows(hours);
    book.saveAppointment(
      Appointment(
        id: 'a',
        serviceId: 'cut',
        startLocal: DateTime(2026, 11, 2, 9),
        durationMinutes: 30,
        bufferMinutes: 10,
        clientLabel: 'A',
        note: 'private',
      ),
    );
    book.close();
    final reopened = Book.open(file);
    expect(reopened.services.single.name, 'Cut');
    expect(reopened.windows.single.openMinute, 540);
    expect(reopened.appointments.single.clientLabel, 'A');
    expect(reopened.appointments.single.note, 'private');
    reopened.saveService(
      Service(id: 'cut', name: 'Trim', durationMinutes: 60, bufferMinutes: 0),
    );
    expect(reopened.appointments.single.durationMinutes, 30);
    reopened.setStatus('a', BookingStatus.completed);
    expect(reopened.appointments.single.status, BookingStatus.completed);
    reopened.close();
  });

  test('bad slot and unknown service leave old rows intact', () {
    final book = Book.open(file);
    book.saveService(cut);
    book.setWindows(hours);
    book.saveAppointment(at(0));
    expect(
      () => book.saveAppointment(at(10, id: 'b')),
      throwsA(
        isA<SlotRejected>().having(
          (e) => e.reason,
          'reason',
          SlotError.conflict,
        ),
      ),
    );
    expect(
      () => book.saveAppointment(at(-10)),
      throwsA(
        isA<SlotRejected>().having(
          (e) => e.reason,
          'reason',
          SlotError.outsideHours,
        ),
      ),
    );
    expect(book.appointments.single.startMinute, 540);
    expect(
      () => book.saveAppointment(
        Appointment(
          id: 'c',
          serviceId: 'missing',
          startLocal: DateTime(2026, 11, 2, 12),
          durationMinutes: 10,
          bufferMinutes: 0,
        ),
      ),
      throwsArgumentError,
    );
    expect(book.appointments.map((a) => a.id).toList(), ['a']);
    book.setStatus('a', BookingStatus.cancelled);
    book.saveAppointment(at(10, id: 'b'));
    expect(book.appointments.length, 2);
    expect(
      () => book.setStatus('a', BookingStatus.booked),
      throwsA(
        isA<SlotRejected>().having(
          (e) => e.reason,
          'reason',
          SlotError.conflict,
        ),
      ),
    );
    expect(book.appointments.first.status, BookingStatus.cancelled);
    book.close();
  });

  test('window edit rejects existing bookings without partial write', () {
    final book = Book.open(file);
    book.saveService(cut);
    book.setWindows(hours);
    book.saveAppointment(at(0));
    expect(
      () => book.setWindows([
        WorkingWindow(weekday: 1, openMinute: 600, closeMinute: 1020),
      ]),
      throwsA(isA<SlotRejected>()),
    );
    expect(book.windows.single.openMinute, 540);
    expect(
      () => book.setWindows([
        WorkingWindow(weekday: 1, openMinute: 540, closeMinute: 600),
        WorkingWindow(weekday: 1, openMinute: 590, closeMinute: 700),
      ]),
      throwsArgumentError,
    );
    book.close();
  });

  test('malformed stored data and unsupported schema fail closed', () {
    File(file).writeAsStringSync('not sqlite');
    expect(() => Book.open(file), throwsException);
    File(file).deleteSync();
    final book = Book.open(file);
    book.close();
    final db = Book.open(file);
    expect(
      () => db.setStatus('absent', BookingStatus.cancelled),
      throwsArgumentError,
    );
    db.close();
  });
}
