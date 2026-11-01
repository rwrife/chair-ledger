import 'dart:io';

import 'package:chair_ledger/book.dart';
import 'package:chair_ledger/main.dart';
import 'package:chair_ledger/schedule.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final platform in [
    TargetPlatform.iOS,
    TargetPlatform.android,
    TargetPlatform.windows,
  ]) {
    for (final size in [
      const Size(390, 844),
      const Size(820, 1180),
      const Size(1440, 900),
    ]) {
      testWidgets('$platform agenda ${size.width}x${size.height}', (
        tester,
      ) async {
        final dir = Directory.systemTemp.createTempSync('chair-agenda-');
        final book = Book.open('${dir.path}/book.db');
        debugDefaultTargetPlatformOverride = platform;
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        try {
          book.saveService(
            Service(
              id: 's',
              name: 'Cut',
              durationMinutes: 30,
              bufferMinutes: 10,
            ),
          );
          book.setWindows([
            for (var d = 1; d <= 7; d++)
              WorkingWindow(weekday: d, openMinute: 540, closeMinute: 1020),
          ]);
          book.saveAppointment(
            Appointment(
              id: 'a',
              serviceId: 's',
              startLocal: DateTime(2026, 11, 2, 9),
              durationMinutes: 30,
              bufferMinutes: 10,
              clientLabel: 'Sam',
            ),
          );
          book.saveAppointment(
            Appointment(
              id: 'b',
              serviceId: 's',
              startLocal: DateTime(2026, 11, 4, 10),
              durationMinutes: 30,
              bufferMinutes: 10,
              clientLabel: 'Alex',
            ),
          );
          await tester.pumpWidget(
            ChairLedgerApp(book: book, initialDate: DateTime(2026, 11, 2)),
          );
          await tester.pumpAndSettle();
          expect(find.textContaining('Sam'), findsOneWidget);
          expect(find.textContaining('Alex'), findsNothing);
          expect(
            find.byType(
              platform == TargetPlatform.iOS
                  ? CupertinoApp
                  : platform == TargetPlatform.windows
                  ? fluent.FluentApp
                  : MaterialApp,
            ),
            findsOneWidget,
          );
          await tester.tap(find.byKey(const Key('toggle-view-button')));
          await tester.pumpAndSettle();
          expect(find.text('Week of 2026-11-02'), findsOneWidget);
          expect(find.textContaining('Alex'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.tap(find.byKey(const Key('select-appointment-a')));
          await tester.pumpAndSettle();
          expect(find.text('Client: Sam'), findsOneWidget);
          if (size.width >= 820) {
            expect(find.byType(VerticalDivider), findsOneWidget);
          }
          expect(tester.takeException(), isNull);
          await tester.tap(find.byKey(const Key('toggle-view-button')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('next-day-button')));
          await tester.pumpAndSettle();
          expect(find.text('2026-11-03'), findsOneWidget);
          expect(tester.takeException(), isNull);

          // Keyboard shortcut smoke: Ctrl+N triggers New appointment
          await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
          await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
          await tester.pumpAndSettle();
          expect(
            find.byKey(const Key('save-appointment-button')),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          book.close();
          dir.deleteSync(recursive: true);
          debugDefaultTargetPlatformOverride = null;
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        }
      });
    }
  }
}
