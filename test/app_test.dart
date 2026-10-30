import 'package:chair_ledger/main.dart';
import 'package:flutter/material.dart';
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
}
