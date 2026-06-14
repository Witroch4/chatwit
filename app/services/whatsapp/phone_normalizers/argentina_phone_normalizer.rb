# Handles Argentina phone number normalization
#
# Argentina phone numbers can appear with or without "9" after country code
# This normalizer removes the "9" when present to create consistent format: 54 + area + number
class Whatsapp::PhoneNormalizers::ArgentinaPhoneNormalizer < Whatsapp::PhoneNormalizers::BasePhoneNormalizer
  def normalize(waid)
    return waid unless handles_country?(waid)

    # Remove "9" after country code if present (549 → 54)
    waid.sub(/^549/, '54')
  end

  # Both the without-9 (canonical) and with-9 forms, so the same number
  # matches regardless of how it was first stored.
  def equivalents(waid)
    return [waid] unless handles_country?(waid)

    without_nine = waid.sub(/^549/, '54')
    [without_nine, without_nine.sub(/^54/, '549')]
  end

  private

  def country_code_pattern
    /^54/
  end
end
