import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:noria_checkout/noria_checkout.dart';

void main() {
  test('noriaCheckoutSdkVersion matches pubspec.yaml', () {
    final String pubspec = File('pubspec.yaml').readAsStringSync();
    final RegExpMatch? match = RegExp(
      r'^version:\s*(\S+)',
      multiLine: true,
    ).firstMatch(pubspec);
    expect(match, isNotNull, reason: 'pubspec.yaml must declare a version');
    expect(noriaCheckoutSdkVersion, match!.group(1));
  });

  test('CHANGELOG.md documents the current version', () {
    final String changelog = File('CHANGELOG.md').readAsStringSync();
    expect(changelog, contains('## [$noriaCheckoutSdkVersion]'));
  });
}
