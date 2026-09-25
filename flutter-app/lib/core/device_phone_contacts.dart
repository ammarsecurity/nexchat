import 'phone_validation.dart';
import '../data/countries.dart';

/// عنصر من سجل هاتف الجهاز بعد التطبيع.
class DevicePhoneContact {
  const DevicePhoneContact({required this.displayName, required this.phones});
  final String displayName;
  /// أرقام كاملة مرشّحة للمطابقة (مثل 9647712345678).
  final List<String> phones;
}

/// يحوّل رقم جهاز خام إلى مجموعة صيغ محتملة للمطابقة مع Users.PhoneNumber.
Set<String> candidatePhonesFromDevice(String raw, {String? defaultDialCode}) {
  final out = <String>{};
  var digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return out;

  // إزالة أصفار البداية الزائدة للأرقام الدولية الطويلة
  while (digits.length > 11 && digits.startsWith('00')) {
    digits = digits.substring(2);
  }

  if (digits.length >= 10 && digits.length <= 15 && !digits.startsWith('0')) {
    out.add(digits);
  }

  final dial = (defaultDialCode ?? '').replaceAll(RegExp(r'\D'), '');
  if (digits.startsWith('0')) {
    final national = normalizeNationalNumber(digits);
    if (dial.isNotEmpty && national.isNotEmpty) {
      out.add('$dial$national');
    }
  } else if (dial.isNotEmpty && digits.length >= 7 && digits.length <= 11 && !digits.startsWith(dial)) {
    // رقم محلي بدون مفتاح
    out.add('$dial$digits');
  }

  // جرّب مطابقة مفاتيح الدول المعروفة إن بدأ الرقم بها
  for (final c in countries) {
    final code = c.dialCode;
    if (digits.startsWith(code) && digits.length > code.length + 6) {
      out.add(digits);
    }
  }

  return out.where((p) => p.length >= 8 && p.length <= 15).toSet();
}
