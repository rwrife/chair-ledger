import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('icon assets and store description are wired honestly', () {
    final root = Directory.current;
    final sourceIcon = File('${root.path}/AppStore/icon.png');
    expect(
      sourceIcon.existsSync(),
      isTrue,
      reason: 'AppStore/icon.png missing',
    );
    final bytes = sourceIcon.readAsBytesSync();
    expect(bytes.length, greaterThan(100000));
    // PNG signature
    expect(
      bytes.sublist(0, 8),
      equals([137, 80, 78, 71, 13, 10, 26, 10]),
      reason: 'Source must be valid PNG',
    );

    // Verify Android launcher icons
    for (final density in ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi']) {
      final f = File(
        '${root.path}/android/app/src/main/res/mipmap-$density/ic_launcher.png',
      );
      expect(f.existsSync(), isTrue, reason: 'Missing Android $density icon');
      expect(f.lengthSync(), greaterThan(1000));
    }

    // Verify iOS asset catalog
    final iosCatalog = File(
      '${root.path}/ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json',
    );
    expect(iosCatalog.existsSync(), isTrue);
    final manifest =
        jsonDecode(iosCatalog.readAsStringSync()) as Map<String, dynamic>;
    final images = manifest['images'] as List<dynamic>;
    expect(images.length, equals(19));
    expect(images.any((entry) => entry['idiom'] == 'ios-marketing'), isTrue);
    for (final entry in images) {
      final filename = entry['filename'] as String;
      final f = File(
        '${root.path}/ios/Runner/Assets.xcassets/AppIcon.appiconset/$filename',
      );
      expect(f.existsSync(), isTrue, reason: 'Missing iOS icon $filename');
      expect(f.lengthSync(), greaterThan(1000));
    }

    // Verify Windows icon
    final winIcon = File('${root.path}/windows/runner/resources/app_icon.ico');
    expect(winIcon.existsSync(), isTrue);
    expect(winIcon.lengthSync(), greaterThan(10000));

    // Verify AppStore/description.txt
    final descFile = File('${root.path}/AppStore/description.txt');
    expect(descFile.existsSync(), isTrue);
    final desc = descFile.readAsStringSync();
    expect(
      desc.contains('planned'),
      isFalse,
      reason: 'Description should not call the app planned',
    );
    expect(desc.contains('offline appointment book'), isTrue);
    expect(desc.contains('solo stylists and barbers'), isTrue);
  });
}
