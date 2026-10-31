import 'dart:io';

import 'package:chair_ledger/book.dart';
import 'package:chair_ledger/main.dart';
import 'package:chair_ledger/schedule.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('private appointment book smoke screen', (tester) async {
    await tester.pumpWidget(const ChairLedgerApp());
    expect(find.text('Chair Ledger'), findsOneWidget);
    expect(
      find.text('Your private appointment book starts here.'),
      findsOneWidget,
    );
    expect(find.byType(MaterialApp), findsOneWidget);
  });

  for (final platform in [
    TargetPlatform.iOS,
    TargetPlatform.android,
    TargetPlatform.windows,
  ]) {
    testWidgets('editor uses native controls on $platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      final dir = Directory.systemTemp.createTempSync('chair-ledger-native-');
      final book = Book.open('${dir.path}/book.db');
      try {
        book.saveService(
          Service(id: 's', name: 'Cut', durationMinutes: 30, bufferMinutes: 10),
        );
        book.setWindows([
          WorkingWindow(weekday: 1, openMinute: 540, closeMinute: 1020),
        ]);
        await tester.pumpWidget(
          ChairLedgerApp(book: book, initialDate: DateTime(2026, 11, 2)),
        );
        await tester.tap(find.byKey(const Key('new-appointment-button')));
        await tester.pumpAndSettle();
        expect(
          find.byType(
            platform == TargetPlatform.iOS
                ? CupertinoTextField
                : platform == TargetPlatform.windows
                ? fluent.TextBox
                : TextField,
          ),
          findsWidgets,
        );
        expect(
          find.byType(
            platform == TargetPlatform.iOS
                ? CupertinoButton
                : platform == TargetPlatform.windows
                ? fluent.Button
                : TextButton,
          ),
          findsWidgets,
        );
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        book.close();
        dir.deleteSync(recursive: true);
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  for (final platform in [
    TargetPlatform.iOS,
    TargetPlatform.android,
    TargetPlatform.windows,
  ]) {
    testWidgets('native shell on $platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await tester.pumpWidget(const ChairLedgerApp());
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
        expect(
          find.byType(
            platform == TargetPlatform.iOS
                ? MaterialApp
                : platform == TargetPlatform.windows
                ? CupertinoApp
                : fluent.FluentApp,
          ),
          findsNothing,
        );
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
