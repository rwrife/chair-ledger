import 'dart:convert';
import 'dart:io';

import 'package:chair_ledger/book.dart';
import 'package:chair_ledger/main.dart';
import 'package:chair_ledger/schedule.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  late Book book;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('chair-ledger-export-');
    book = Book.open('${dir.path}/book.db');
    book.saveService(
      Service(id: 'cut', name: '=Cut', durationMinutes: 30, bufferMinutes: 10),
    );
    book.setWindows([
      WorkingWindow(weekday: 1, openMinute: 540, closeMinute: 1020),
    ]);
    book.saveAppointment(
      Appointment(
        id: 'one',
        serviceId: 'cut',
        startLocal: DateTime(2026, 11, 2, 9),
        durationMinutes: 30,
        bufferMinutes: 10,
        clientLabel: '+Private',
        note: 'sensitive',
      ),
    );
  });
  tearDown(() {
    book.close();
    dir.deleteSync(recursive: true);
  });

  test('versioned round trip and explicit replacement', () {
    final backup = book.exportJson();
    final preview = previewBackup(backup);
    expect(preview.summary, '1 services, 1 working windows, 1 appointments');
    book.saveService(
      Service(id: 'new', name: 'New', durationMinutes: 15, bufferMinutes: 0),
    );
    expect(book.services.length, 2); // preview does not mutate book
    book.restore(preview);
    expect(book.services.length, 1);
    expect(book.appointments.single.note, 'sensitive');
    expect(jsonDecode(book.exportJson())['version'], 1);
  });

  test(
    'malformed, duplicate, unknown, conflict and bad time reject before write',
    () {
      final unchanged = book.exportJson();
      final original = jsonDecode(unchanged) as Map<String, dynamic>;
      expect(() => previewBackup('{'), throwsFormatException);
      expect(() => previewBackup('{"version":2}'), throwsFormatException);
      expect(() => previewBackup('{"version":1}'), throwsFormatException);
      for (final broken in [
        {
          ...original,
          'services': [...original['services'], original['services'][0]],
        },
        {
          ...original,
          'appointments': [
            ...original['appointments'],
            original['appointments'][0],
          ],
        },
        {
          ...original,
          'appointments': [
            {...original['appointments'][0], 'serviceId': 'absent'},
          ],
        },
        {
          ...original,
          'appointments': [
            {
              ...original['appointments'][0],
              'startLocal': '2026-11-02T08:00:00.000',
            },
          ],
        },
        {
          ...original,
          'appointments': [
            original['appointments'][0],
            {
              ...original['appointments'][0],
              'id': 'two',
              'startLocal': '2026-11-02T09:15:00.000',
            },
          ],
        },
        {
          ...original,
          'appointments': [
            {
              ...original['appointments'][0],
              'startLocal': '2026-02-30T09:00:00.000',
            },
          ],
        },
      ]) {
        expect(() => previewBackup(jsonEncode(broken)), throwsException);
        expect(book.exportJson(), unchanged);
      }
    },
  );

  test('restart and valid restore preserve book after invalid backup', () {
    final before = book.exportJson();
    final preview = previewBackup(before);
    book.close();
    final db = File('${dir.path}/book.db');
    expect(db.existsSync(), isTrue);
    book = Book.open(db.path);
    expect(() => previewBackup('{"version":2}'), throwsFormatException);
    expect(book.exportJson(), before);
    book.restore(preview);
    expect(book.exportJson(), before);
  });

  test(
    'CSV defaults to redaction, neutralizes spreadsheet formulas everywhere',
    () {
      final redacted = dailyScheduleCsv(
        book,
        DateTime(2026, 11, 2),
        redactNames: true,
      );
      expect(redacted, contains("'\u003dCut"));
      expect(redacted, contains('Private client'));
      expect(redacted, isNot(contains('+Private')));
      expect(redacted, isNot(contains('sensitive')));
      final explicit = dailyScheduleCsv(
        book,
        DateTime(2026, 11, 2),
        redactNames: false,
      );
      expect(explicit, contains("'+Private"));
      expect(explicit, isNot(contains('sensitive')));
    },
  );

  testWidgets('export screen defaults to redaction and allows opt-in', (
    tester,
  ) async {
    await tester.pumpWidget(ChairLedgerApp(book: book));
    await tester.tap(find.byKey(const Key('tab-export')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('export-backup-button')), findsOneWidget);
    expect(find.byKey(const Key('export-csv-button')), findsOneWidget);
    expect(find.text('Client names: redacted (change)'), findsOneWidget);
    await tester.tap(find.byKey(const Key('redact-names-button')));
    await tester.pumpAndSettle();
    expect(find.text('Client names: included (change)'), findsOneWidget);
  });
}
