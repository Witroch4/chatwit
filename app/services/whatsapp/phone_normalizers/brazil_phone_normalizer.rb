# Handles Brazil phone number normalization
# ref: https://github.com/chatwoot/chatwoot/issues/5840
#
# Brazil changed its mobile number system by adding a "9" prefix to existing numbers.
# This normalizer adds the "9" digit if the number is 12 digits (making it 13 digits total)
# to match the new format: 55 + DDD + 9 + number
class Whatsapp::PhoneNormalizers::BrazilPhoneNormalizer < Whatsapp::PhoneNormalizers::BasePhoneNormalizer
  COUNTRY_CODE_LENGTH = 2
  DDD_LENGTH = 2

  def normalize(waid)
    return waid unless handles_country?(waid)

    ddd = waid[COUNTRY_CODE_LENGTH, DDD_LENGTH]
    number = waid[COUNTRY_CODE_LENGTH + DDD_LENGTH, waid.length - (COUNTRY_CODE_LENGTH + DDD_LENGTH)]
    normalized_number = "55#{ddd}#{number}"
    normalized_number = "55#{ddd}9#{number}" if normalized_number.length != 13
    normalized_number
  end

  # Both the 13-digit (with 9th digit, canonical) and 12-digit (without it)
  # forms, so the same number matches regardless of how it was first stored.
  def equivalents(waid)
    return [waid] unless handles_country?(waid)

    ddd = waid[COUNTRY_CODE_LENGTH, DDD_LENGTH]
    rest = waid[(COUNTRY_CODE_LENGTH + DDD_LENGTH)..] || ''
    # A 9-digit local part is the 8-digit base plus the mandatory 9th digit;
    # an 8-digit local part is already the base. Decide by length, never by
    # "starts with 9" — subscriber numbers can legitimately start with 9
    # (e.g. 9694-5743), and stripping it would miss the canonical variant.
    base = rest.length >= 9 ? rest[1..] : rest
    ["55#{ddd}9#{base}", "55#{ddd}#{base}"]
  end

  private

  def country_code_pattern
    /^55/
  end
end
