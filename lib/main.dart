import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

void main() => runApp(const ChairLedgerApp());

class ChairLedgerApp extends StatelessWidget {
  const ChairLedgerApp({super.key});

  @override
  Widget build(BuildContext context) {
    const title = 'Chair Ledger';
    const message = 'Your private appointment book starts here.';
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return const CupertinoApp(
        title: title,
        home: CupertinoPageScaffold(
          navigationBar: CupertinoNavigationBar(middle: Text(title)),
          child: SafeArea(child: Center(child: Text(message))),
        ),
      );
    }
    return const MaterialApp(
      title: title,
      home: Scaffold(
        appBar: null,
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: TextStyle(fontSize: 28)),
                Text(message),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
