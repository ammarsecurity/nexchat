import 'i18n/i18n.dart';

/// Port of utils/phoneValidation.js.
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

const _rules = <String, (int, int, String)>{
  '964': (10, 10, 'iq'), '966': (9, 9, 'sa'), '20': (9, 10, 'eg'), '971': (9, 9, 'ae'),
  '962': (9, 9, 'jo'), '965': (8, 8, 'kw'), '974': (8, 8, 'qa'), '973': (8, 8, 'bh'),
  '968': (8, 8, 'om'), '967': (9, 9, 'ye'), '963': (9, 9, 'sy'), '961': (8, 8, 'lb'),
  '970': (9, 9, 'ps'), '218': (9, 9, 'ly'), '216': (8, 8, 'tn'), '213': (9, 9, 'dz'),
  '212': (9, 9, 'ma'), '249': (9, 9, 'sd'), '1': (10, 10, 'us'), '44': (10, 10, 'gb'),
  '33': (9, 9, 'fr'), '49': (10, 11, 'de'), '39': (9, 11, 'it'), '90': (10, 10, 'tr'),
  '91': (10, 10, 'in'), '92': (10, 10, 'pk'), '98': (10, 10, 'ir'), '86': (11, 11, 'cn'),
  '81': (10, 10, 'jp'), '7': (10, 10, 'ru'), '62': (9, 12, 'id'), '234': (10, 10, 'ng'),
  '27': (9, 9, 'za'), '254': (9, 9, 'ke'), '251': (9, 9, 'et'), '880': (10, 10, 'bd'),
  '93': (9, 9, 'af'),
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
    if (national.length < rule.$1 || national.length > rule.$2) return PhoneResult.invalid(rule.$3);
  } else if (national.length < 7 || national.length > 15) {
    return const PhoneResult.invalid('generic');
  }
  return PhoneResult.valid(national);
}
