# frozen_string_literal: true

# Fills contact identity (email, name) from what the contact himself sent,
# whenever the field is still empty on the contact record.
#
# Two sources, in descending order of confidence:
#
#   1. WhatsApp Flow response — the contact literally filled out a form. The
#      answers live in `content_attributes.whatsapp_flow_response.response_json`
#      (see Whatsapp::IncomingMessageBaseService#message_content_attributes).
#      Meta generates the keys ("screen_0_Email_1"), so fields are matched by
#      name heuristic, never by position.
#   2. Free text — an email address typed in the message body. The message
#      content of a Flow response is only an i18n placeholder, which is exactly
#      why source 1 has to exist.
#
# This never overwrites data the contact already has. Writing here is what makes
# the answers useful downstream: the update fires CONTACT_UPDATED, which the
# WebhookListener forwards to the Socialwise lead sync.
class ContactIdentityDetectionListener < BaseListener
  EMAIL_REGEX = /\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b/
  FLOW_EMAIL_KEY_REGEX = /e-?mail/i
  FLOW_NAME_KEY_REGEX = /name|nome/i
  FLOW_METADATA_KEYS = %w[flow_token flow_id].freeze
  PHONE_LIKE_NAME_REGEX = /\A\+?[\d\s().-]{6,}\z/

  def message_created(event)
    message = extract_message_and_account(event)[0]
    return unless should_process?(message)

    contact = message.conversation&.contact
    return if contact.blank?

    attributes = detected_attributes(message, contact)
    return if attributes.blank?

    contact.update(attributes)
  end

  private

  def should_process?(message)
    return false unless message&.incoming?

    message.content.present? || flow_answers(message).present?
  end

  def detected_attributes(message, contact)
    attributes = {}
    attributes[:email] = detected_email(message) if contact.email.blank?
    attributes[:name] = detected_name(message) if name_placeholder?(contact)
    attributes.compact
  end

  def detected_email(message)
    from_flow = flow_answer(message, FLOW_EMAIL_KEY_REGEX)&.match(EMAIL_REGEX)&.to_s
    return from_flow if from_flow.present?

    message.content&.match(EMAIL_REGEX)&.to_s.presence
  end

  # Name is taken from a filled form only: free text is not a reliable source.
  def detected_name(message)
    flow_answer(message, FLOW_NAME_KEY_REGEX)
  end

  # Chatwoot falls back to the phone number when the channel gives no name.
  def name_placeholder?(contact)
    contact.name.blank? ||
      contact.name == contact.phone_number ||
      contact.name.match?(PHONE_LIKE_NAME_REGEX)
  end

  def flow_answer(message, key_regex)
    _key, value = flow_answers(message).find do |key, answer|
      key.to_s.match?(key_regex) && answer.to_s.strip.present?
    end

    value.to_s.strip.presence
  end

  def flow_answers(message)
    answers = message&.content_attributes&.dig('whatsapp_flow_response', 'response_json')
    return {} unless answers.is_a?(Hash)

    answers.except(*FLOW_METADATA_KEYS)
  end
end
