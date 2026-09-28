/**
 * التحقق من صحة أرقام الهواتف حسب الدولة (طول + بادئة جوال حقيقية).
 * يطابق قواعد الباك اند / Flutter.
 */
const RULES = {
  '964': { min: 10, max: 10, errorKey: 'iq', pattern: /^7(5|7|8)\d{8}$/ },
  '966': { min: 9, max: 9, errorKey: 'sa', pattern: /^5\d{8}$/ },
  '20': { min: 10, max: 10, errorKey: 'eg', pattern: /^1[0125]\d{8}$/ },
  '971': { min: 9, max: 9, errorKey: 'ae', pattern: /^5\d{8}$/ },
  '962': { min: 9, max: 9, errorKey: 'jo', pattern: /^7[789]\d{7}$/ },
  '965': { min: 8, max: 8, errorKey: 'kw', pattern: /^[569]\d{7}$/ },
  '974': { min: 8, max: 8, errorKey: 'qa', pattern: /^[3567]\d{7}$/ },
  '973': { min: 8, max: 8, errorKey: 'bh', pattern: /^3\d{7}$/ },
  '968': { min: 8, max: 8, errorKey: 'om', pattern: /^[79]\d{7}$/ },
  '967': { min: 9, max: 9, errorKey: 'ye', pattern: /^7\d{8}$/ },
  '963': { min: 9, max: 9, errorKey: 'sy', pattern: /^9\d{8}$/ },
  '961': { min: 7, max: 8, errorKey: 'lb', pattern: /^(3\d{6}|7[01689]\d{6})$/ },
  '970': { min: 9, max: 9, errorKey: 'ps', pattern: /^59\d{7}$/ },
  '218': { min: 9, max: 9, errorKey: 'ly', pattern: /^9\d{8}$/ },
  '216': { min: 8, max: 8, errorKey: 'tn', pattern: /^[2459]\d{7}$/ },
  '213': { min: 9, max: 9, errorKey: 'dz', pattern: /^[567]\d{8}$/ },
  '212': { min: 9, max: 9, errorKey: 'ma', pattern: /^[67]\d{8}$/ },
  '249': { min: 9, max: 9, errorKey: 'sd', pattern: /^9\d{8}$/ },
  '1': { min: 10, max: 10, errorKey: 'us', pattern: /^[2-9]\d{2}[2-9]\d{6}$/ },
  '44': { min: 10, max: 10, errorKey: 'gb', pattern: /^7\d{9}$/ },
  '33': { min: 9, max: 9, errorKey: 'fr', pattern: /^[67]\d{8}$/ },
  '49': { min: 10, max: 11, errorKey: 'de', pattern: /^1[5-7]\d{8,9}$/ },
  '39': { min: 9, max: 11, errorKey: 'it', pattern: /^3\d{8,10}$/ },
  '90': { min: 10, max: 10, errorKey: 'tr', pattern: /^5\d{9}$/ },
  '91': { min: 10, max: 10, errorKey: 'in', pattern: /^[6-9]\d{9}$/ },
  '92': { min: 10, max: 10, errorKey: 'pk', pattern: /^3\d{9}$/ },
  '98': { min: 10, max: 10, errorKey: 'ir', pattern: /^9\d{9}$/ },
  '86': { min: 11, max: 11, errorKey: 'cn', pattern: /^1\d{10}$/ },
  '81': { min: 10, max: 10, errorKey: 'jp', pattern: /^[789]0\d{8}$/ },
  '7': { min: 10, max: 10, errorKey: 'ru', pattern: /^9\d{9}$/ },
  '62': { min: 9, max: 12, errorKey: 'id', pattern: /^8\d{8,11}$/ },
  '234': { min: 10, max: 10, errorKey: 'ng', pattern: /^[789]\d{9}$/ },
  '27': { min: 9, max: 9, errorKey: 'za', pattern: /^[678]\d{8}$/ },
  '254': { min: 9, max: 9, errorKey: 'ke', pattern: /^[17]\d{8}$/ },
  '251': { min: 9, max: 9, errorKey: 'et', pattern: /^9\d{8}$/ },
  '880': { min: 10, max: 10, errorKey: 'bd', pattern: /^1\d{9}$/ },
  '93': { min: 9, max: 9, errorKey: 'af', pattern: /^7\d{8}$/ }
}

export function normalizeNationalNumber(phone) {
  let digits = (phone || '').replace(/\D/g, '')
  while (digits.length > 1 && digits[0] === '0') {
    digits = digits.slice(1)
  }
  return digits
}

export function validatePhone(countryCode, phone, t) {
  const code = (countryCode || '').trim().replace(/^\+\s*/, '').replace(/\s/g, '')
  if (!code || code.length > 4) {
    return { valid: false, errorKey: 'invalidCountryCode' }
  }

  const digits = (phone || '').replace(/\D/g, '')
  if (digits.length > 1 && digits.startsWith('0')) {
    return { valid: false, errorKey: 'noLeadingZero' }
  }

  const national = normalizeNationalNumber(phone || '')
  if (!national) {
    return { valid: false, errorKey: 'required' }
  }

  if (!/^\d+$/.test(national)) {
    return { valid: false, errorKey: 'digitsOnly' }
  }

  const fullPhone = code + national
  if (fullPhone.length > 20) {
    return { valid: false, errorKey: 'tooLong' }
  }

  const rule = RULES[code]
  if (rule) {
    if (national.length < rule.min || national.length > rule.max || !rule.pattern.test(national)) {
      return { valid: false, errorKey: rule.errorKey }
    }
  } else if (national.length < 7 || national.length > 15) {
    return { valid: false, errorKey: 'generic' }
  }

  return { valid: true, normalized: national }
}

export function getPhoneErrorMessage(result, t) {
  if (!result.errorKey) return ''
  const key = `phoneValidation.${result.errorKey}`
  const msg = t(key)
  return msg !== key ? msg : result.errorKey
}
