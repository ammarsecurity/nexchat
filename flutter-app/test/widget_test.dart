import 'package:flutter_test/flutter_test.dart';
import 'package:nexchat/core/phone_validation.dart';
import 'package:nexchat/services/update_check.dart';

void main() {
  test('compareVersions', () {
    expect(compareVersions('1.0.16', '1.0.17'), -1);
    expect(compareVersions('1.1', '1.0.9'), 1);
    expect(compareVersions('1.0', '1.0.0'), 0);
  });

  test('validatePhone', () {
    expect(validatePhone('964', '7701234567').valid, isTrue);
    expect(validatePhone('964', '07701234567').errorKey, 'noLeadingZero');
    expect(validatePhone('966', '12').errorKey, 'sa');
  });
}
