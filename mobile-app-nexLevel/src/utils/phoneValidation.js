/**
 * التحقق من صحة أرقام الهواتف حسب الدولة.
 * يطابق قواعد الباك اند - يرفض 0 في البداية ويطابق طول الرقم لكل دولة.
 *
 * Rules: dialCode => { min, max, errorKey }
 * errorKey يستخدم مع i18n: phoneValidation.{errorKey}
 */
const RULES = {
  '964': { min: 10, max: 10, errorKey: 'iq' },
  '966': { min: 9, max: 9, errorKey: 'sa' },
  '20': { min: 9, max: 10, errorKey: 'eg' },
  '971': { min: 9, max: 9, errorKey: 'ae' },
  '962': { min: 9, max: 9, errorKey: 'jo' },
  '965': { min: 8, max: 8, errorKey: 'kw' },
  '974': { min: 8, max: 8, errorKey: 'qa' },
  '973': { min: 8, max: 8, errorKey: 'bh' },
  '968': { min: 8, max: 8, errorKey: 'om' },
  '967': { min: 9, max: 9, errorKey: 'ye' },
  '963': { min: 9, max: 9, errorKey: 'sy' },
  '961': { min: 8, max: 8, errorKey: 'lb' },
  '970': { min: 9, max: 9, errorKey: 'ps' },
  '218': { min: 9, max: 9, errorKey: 'ly' },
  '216': { min: 8, max: 8, errorKey: 'tn' },
  '213': { min: 9, max: 9, errorKey: 'dz' },
  '212': { min: 9, max: 9, errorKey: 'ma' },
  '249': { min: 9, max: 9, errorKey: 'sd' },
  '1': { min: 10, max: 10, errorKey: 'us' },
  '44': { min: 10, max: 10, errorKey: 'gb' },
  '33': { min: 9, max: 9, errorKey: 'fr' },
  '49': { min: 10, max: 11, errorKey: 'de' },
  '39': { min: 9, max: 11, errorKey: 'it' },
  '90': { min: 10, max: 10, errorKey: 'tr' },
  '91': { min: 10, max: 10, errorKey: 'in' },
  '92': { min: 10, max: 10, errorKey: 'pk' },
  '98': { min: 10, max: 10, errorKey: 'ir' },
  '86': { min: 11, max: 11, errorKey: 'cn' },
  '81': { min: 10, max: 10, errorKey: 'jp' },
  '7': { min: 10, max: 10, errorKey: 'ru' },
  '62': { min: 9, max: 12, errorKey: 'id' },
  '234': { min: 10, max: 10, errorKey: 'ng' },
  '27': { min: 9, max: 9, errorKey: 'za' },
  '254': { min: 9, max: 9, errorKey: 'ke' },
  '251': { min: 9, max: 9, errorKey: 'et' },
  '880': { min: 10, max: 10, errorKey: 'bd' },
  '93': { min: 9, max: 9, errorKey: 'af' }
}

/**
 * إزالة الصفر من بداية الرقم
 */
export function normalizeNationalNumber(phone) {
  let digits = (phone || '').replace(/\D/g, '')
  while (digits.length > 1 && digits[0] === '0') {
    digits = digits.slice(1)
  }
  return digits
}

/**
 * التحقق من صحة الرقم
 * @param {string} countryCode - مفتاح الدولة (مثل 964، 966) بدون +
 * @param {string} phone - الرقم كما أدخله المستخدم
 * @param {Function} t - دالة الترجمة useI18n().t
 * @returns {{ valid: boolean, errorKey?: string, normalized?: string }}
 */
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
    if (national.length < rule.min || national.length > rule.max) {
      return { valid: false, errorKey: rule.errorKey }
    }
  } else {
    if (national.length < 7 || national.length > 15) {
      return { valid: false, errorKey: 'generic' }
    }
  }

  return { valid: true, normalized: national }
}

/**
 * الحصول على رسالة الخطأ المترجمة
 */
export function getPhoneErrorMessage(result, t) {
  if (!result.errorKey) return ''
  const key = `phoneValidation.${result.errorKey}`
  const msg = t(key)
  return msg !== key ? msg : result.errorKey
}
