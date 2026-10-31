import 'dart:io';

import 'package:chair_ledger/book.dart';
import 'package:chair_ledger/main.dart';
import 'package:chair_ledger/schedule.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late Book book;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('chair-ledger-ui-test-');
    book = Book.open('${directory.path}/book.db');
    book.saveService(
      Service(
        id: 'cut',
        name: 'Haircut',
        durationMinutes: 30,
        bufferMinutes: 10,
      ),
    );
    book.setWindows([
      for (var d = 1; d <= 7; d++)
        WorkingWindow(weekday: d, openMinute: 9 * 60, closeMinute: 17 * 60),
    ]);
  });

  tearDown(() {
    book.close();
    directory.deleteSync(recursive: true);
  });

  testWidgets('create appointment workflow and status update', (tester) async {
    await tester.pumpWidget(
      ChairLedgerApp(book: book, initialDate: DateTime(2026, 11, 2)),
    );
    await tester.pumpAndSettle();

    expect(find.text('No appointments yet'), findsOneWidget);

    // Tap New Appointment
    await tester.tap(find.byKey(const Key('new-appointment-button')));
    await tester.pumpAndSettle();

    // Fill form
    await tester.enterText(
      find.byKey(const Key('client-label-field')),
      'Sam Stylist',
    );
    await tester.enterText(
      find.byKey(const Key('note-field')),
      'Allergic to latex',
    );
    await tester.enterText(find.byKey(const Key('time-field')), '09:30');

    // Save
    await tester.tap(find.byKey(const Key('save-appointment-button')));
    await tester.pumpAndSettle();

    // Appears in list
    expect(book.appointments.length, 1);
    expect(find.textContaining('Sam Stylist'), findsOneWidget);
    expect(find.text('Haircut'), findsOneWidget);
    expect(find.text('booked'), findsOneWidget);

    // Mark complete
    await tester.tap(
      find.byKey(const Key('complete-appointment-button')).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('completed'), findsOneWidget);
  });

  testWidgets('conflict warning preserves user input', (tester) async {
    book.saveAppointment(
      Appointment(
        id: 'existing',
        serviceId: 'cut',
        startLocal: DateTime(2026, 11, 2, 10, 0),
        durationMinutes: 30,
        bufferMinutes: 10,
        clientLabel: 'Existing Client',
      ),
    );

    await tester.pumpWidget(
      ChairLedgerApp(book: book, initialDate: DateTime(2026, 11, 2)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('new-appointment-button')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('client-label-field')),
      'New Client',
    );
    await tester.enterText(
      find.byKey(const Key('note-field')),
      'Special color note',
    );
    await tester.enterText(find.byKey(const Key('time-field')), '10:15');

    // Attempt save - conflict!
    await tester.tap(find.byKey(const Key('save-appointment-button')));
    await tester.pumpAndSettle();

    // Conflict error shown
    expect(find.textContaining('conflict', findRichText: true), findsOneWidget);
    // User input NOT lost
    expect(find.text('New Client'), findsOneWidget);
    expect(find.text('Special color note'), findsOneWidget);

    // Adjust time to non-conflicting
    await tester.enterText(find.byKey(const Key('time-field')), '11:00');
    await tester.tap(find.byKey(const Key('save-appointment-button')));
    await tester.pumpAndSettle();

    expect(find.textContaining('New Client'), findsOneWidget);
    expect(find.textContaining('Existing Client'), findsOneWidget);
  });

  testWidgets('service and hours editor persists edits', (tester) async {
    await tester.pumpWidget(
      ChairLedgerApp(book: book, initialDate: DateTime(2026, 11, 2)),
    );
    await tester.pumpAndSettle();

    // Switch to Settings / Services tab
    await tester.tap(find.byKey(const Key('tab-services')));
    await tester.pumpAndSettle();

    expect(find.text('Haircut (30m + 10m buffer)'), findsOneWidget);

    // Add service
    await tester.tap(find.byKey(const Key('add-service-button')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('service-name-field')),
      'Color Treatment',
    );
    await tester.enterText(
      find.byKey(const Key('service-duration-field')),
      '60',
    );
    await tester.enterText(find.byKey(const Key('service-buffer-field')), '15');
    await tester.tap(find.byKey(const Key('save-service-button')));
    await tester.pumpAndSettle();

    expect(find.text('Color Treatment (60m + 15m buffer)'), findsOneWidget);
    expect(book.services.any((s) => s.name == 'Color Treatment'), isTrue);
  });
}
