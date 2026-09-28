import 'i18n/i18n.dart';

/// Port of utils/phoneValidation.js — length + real national prefix patterns.
class PhoneResult {
  const PhoneResult.valid(this.normalized)
      : valid = true,
        errorKey = null;
  const PhoneResult.invalid(this.errorKey)
      : valid = false,
        normalized = null;

  final bool valid;
  final String? errorKey;
  final String? normalized;

  String get message {
    if (errorKey == null) return '';
    final key = 'phoneValidation.$errorKey';
    final msg = t(key);
    return msg != key ? msg : errorKey!;
  }
}

class _PhoneRule {
  const _PhoneRule(this.min, this.max, this.errorKey, this.pattern);
  final int min;
  final int max;
  final String errorKey;
  /// Matches the national number (no country code, no leading 0).
  final RegExp pattern;
}

/// Dial-code → national mobile rules (prefix + length).
final _rules = <String, _PhoneRule>{
  // Iraq: Korek 75x · AsiaCell 77x · Zain 78x
  '964': _PhoneRule(10, 10, 'iq', RegExp(r'^7(5|7|8)\d{8}$')),
  // Saudi / UAE: mobile 5xxxxxxxx
  '966': _PhoneRule(9, 9, 'sa', RegExp(r'^5\d{8}$')),
  '971': _PhoneRule(9, 9, 'ae', RegExp(r'^5\d{8}$')),
  // Egypt: 10/11/12/15 + 8 digits
  '20': _PhoneRule(10, 10, 'eg', RegExp(r'^1[0125]\d{8}$')),
  // Jordan: 77/78/79
  '962': _PhoneRule(9, 9, 'jo', RegExp(r'^7[789]\d{7}$')),
  // Kuwait: 5/6/9
  '965': _PhoneRule(8, 8, 'kw', RegExp(r'^[569]\d{7}$')),
  // Qatar: 3/5/6/7
  '974': _PhoneRule(8, 8, 'qa', RegExp(r'^[3567]\d{7}$')),
  // Bahrain: 3xxxxxx
  '973': _PhoneRule(8, 8, 'bh', RegExp(r'^3\d{7}$')),
  // Oman: 7/9
  '968': _PhoneRule(8, 8, 'om', RegExp(r'^[79]\d{7}$')),
  // Yemen: 7xxxxxxxx
  '967': _PhoneRule(9, 9, 'ye', RegExp(r'^7\d{8}$')),
  // Syria: 9xxxxxxxx
  '963': _PhoneRule(9, 9, 'sy', RegExp(r'^9\d{8}$')),
  // Lebanon: 3/70/71/76/78/79…
  '961': _PhoneRule(7, 8, 'lb', RegExp(r'^(3\d{6}|7[01689]\d{6})$')),
  // Palestine: 59x
  '970': _PhoneRule(9, 9, 'ps', RegExp(r'^59\d{7}$')),
  // Libya: 9xxxxxxxx
  '218': _PhoneRule(9, 9, 'ly', RegExp(r'^9\d{8}$')),
  // Tunisia: 2/4/5/9
  '216': _PhoneRule(8, 8, 'tn', RegExp(r'^[2459]\d{7}$')),
  // Algeria: 5/6/7
  '213': _PhoneRule(9, 9, 'dz', RegExp(r'^[567]\d{8}$')),
  // Morocco: 6/7
  '212': _PhoneRule(9, 9, 'ma', RegExp(r'^[67]\d{8}$')),
  // Sudan: 9xxxxxxxx
  '249': _PhoneRule(9, 9, 'sd', RegExp(r'^9\d{8}$')),
  // US/Canada: NXXNXXXXXX — area code can't start with 0/1
  '1': _PhoneRule(10, 10, 'us', RegExp(r'^[2-9]\d{2}[2-9]\d{6}$')),
  // UK mobile: 7xxxxxxxxx
  '44': _PhoneRule(10, 10, 'gb', RegExp(r'^7\d{9}$')),
  // France mobile: 6/7
  '33': _PhoneRule(9, 9, 'fr', RegExp(r'^[67]\d{8}$')),
  // Germany mobile: 15/16/17…
  '49': _PhoneRule(10, 11, 'de', RegExp(r'^1[5-7]\d{8,9}$')),
  // Italy mobile: 3xxxxxxxx
  '39': _PhoneRule(9, 11, 'it', RegExp(r'^3\d{8,10}$')),
  // Turkey: 5xxxxxxxxx
  '90': _PhoneRule(10, 10, 'tr', RegExp(r'^5\d{9}$')),
  // India: starts 6-9
  '91': _PhoneRule(10, 10, 'in', RegExp(r'^[6-9]\d{9}$')),
  // Pakistan: 3xxxxxxxxx
  '92': _PhoneRule(10, 10, 'pk', RegExp(r'^3\d{9}$')),
  // Iran: 9xxxxxxxxx
  '98': _PhoneRule(10, 10, 'ir', RegExp(r'^9\d{9}$')),
  // China: 1xxxxxxxxxx
  '86': _PhoneRule(11, 11, 'cn', RegExp(r'^1\d{10}$')),
  // Japan mobile: 70/80/90
  '81': _PhoneRule(10, 10, 'jp', RegExp(r'^[789]0\d{8}$')),
  // Russia: 9xxxxxxxxx
  '7': _PhoneRule(10, 10, 'ru', RegExp(r'^9\d{9}$')),
  // Indonesia: 8xxxxxxxxx
  '62': _PhoneRule(9, 12, 'id', RegExp(r'^8\d{8,11}$')),
  // Nigeria: 7/8/9
  '234': _PhoneRule(10, 10, 'ng', RegExp(r'^[789]\d{9}$')),
  // South Africa: 6/7/8
  '27': _PhoneRule(9, 9, 'za', RegExp(r'^[678]\d{8}$')),
  // Kenya: 7xxxxxxxx / 1xxxxxxxx
  '254': _PhoneRule(9, 9, 'ke', RegExp(r'^[17]\d{8}$')),
  // Ethiopia: 9xxxxxxxx
  '251': _PhoneRule(9, 9, 'et', RegExp(r'^9\d{8}$')),
  // Bangladesh: 1xxxxxxxxx
  '880': _PhoneRule(10, 10, 'bd', RegExp(r'^1\d{9}$')),
  // Afghanistan: 7xxxxxxxx
  '93': _PhoneRule(9, 9, 'af', RegExp(r'^7\d{8}$')),
};

String normalizeNationalNumber(String phone) {
  var digits = phone.replaceAll(RegExp(r'\D'), '');
  while (digits.length > 1 && digits.startsWith('0')) {
    digits = digits.substring(1);
  }
  return digits;
}

PhoneResult validatePhone(String countryCode, String phone) {
  final code = countryCode.trim().replaceFirst(RegExp(r'^\+\s*'), '').replaceAll(RegExp(r'\s'), '');
  if (code.isEmpty || code.length > 4) return const PhoneResult.invalid('invalidCountryCode');
  final digits = phone.replaceAll(RegExp(r'\D'), '');
  if (digits.length > 1 && digits.startsWith('0')) return const PhoneResult.invalid('noLeadingZero');
  final national = normalizeNationalNumber(phone);
  if (national.isEmpty) return const PhoneResult.invalid('required');
  if (!RegExp(r'^\d+$').hasMatch(national)) return const PhoneResult.invalid('digitsOnly');
  if ((code + national).length > 20) return const PhoneResult.invalid('tooLong');

  final rule = _rules[code];
  if (rule != null) {
    if (national.length < rule.min || national.length > rule.max || !rule.pattern.hasMatch(national)) {
      return PhoneResult.invalid(rule.errorKey);
    }
  } else if (national.length < 7 || national.length > 15) {
    return const PhoneResult.invalid('generic');
  }
  return PhoneResult.valid(national);
}
