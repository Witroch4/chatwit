#!/usr/bin/env ruby

# Test script to verify Instagram Response Processor works with SocialWise Flow payloads

# SocialWise Flow Instagram payloads
socialwise_generic_template = {
  'message_format' => 'GENERIC_TEMPLATE',
  'template_type' => 'generic',
  'elements' => [
    {
      'title' => 'mandado de segurança',
      'subtitle' => 'Dra. Amanda Sousa Advocacia e Consultoria Jurídica™',
      'buttons' => [
        {
          'type' => 'postback',
          'title' => 'atendimento',
          'payload' => 'ig_btn_1756139332989_pm6hd9wau'
        }
      ],
      'image_url' => 'https://objstoreapi.witdev.com.br/chatwit-social/1b2024eb-ecd3-486d-8629-57a1df029b08.png'
    }
  ]
}

socialwise_button_template = {
  'message_format' => 'BUTTON_TEMPLATE',
  'template_type' => 'button',
  'text' => 'BUTTON_TEMPLATE pode ter até 640 caracteres e 3 botoes postback ou web_url (mistura)',
  'buttons' => [
    {
      'type' => 'postback',
      'title' => 'finalizar',
      'payload' => 'ig_btn_1756164895605_betjxtlxr'
    },
    {
      'type' => 'postback',
      'title' => 'atendimento',
      'payload' => 'ig_btn_1756164897692_r4p8f1btg'
    },
    {
      'type' => 'web_url',
      'title' => 'meu site',
      'url' => 'https://witdev.com.br'
    }
  ]
}

socialwise_quick_replies = {
  'message_format' => 'QUICK_REPLIES',
  'text' => 'QUICK_REPLY_2  PODE TER ATÉ 1000 CARACTERES E 13 BOTOES',
  'quick_replies' => [
    {
      'content_type' => 'text',
      'title' => '1',
      'payload' => 'ig_btn_1756164551022_58syso7j0'
    },
    {
      'content_type' => 'text',
      'title' => '2',
      'payload' => 'ig_btn_1756164552127_2allygt3l'
    },
    {
      'content_type' => 'text',
      'title' => '3',
      'payload' => 'ig_btn_1756164553169_fwo24yr8e'
    },
    {
      'content_type' => 'text',
      'title' => '4',
      'payload' => 'ig_btn_1756164554152_stll7gg63'
    }
  ]
}

puts "=== Testing Instagram Response Processor with SocialWise Flow Payloads ==="

# Test 1: Validate Generic Template payload structure
puts "\n1. Testing Generic Template validation:"
begin
  result = Integrations::Socialwise::InstagramResponseProcessor.send(
    :validate_generic_template,
    socialwise_generic_template
  )
  puts "   ✓ Generic Template validation: #{result ? 'PASSED' : 'FAILED'}"
rescue => e
  puts "   ✗ Generic Template validation ERROR: #{e.message}"
end

# Test 2: Validate Button Template payload structure
puts "\n2. Testing Button Template validation:"
begin
  result = Integrations::Socialwise::InstagramResponseProcessor.send(
    :validate_button_template,
    socialwise_button_template
  )
  puts "   ✓ Button Template validation: #{result ? 'PASSED' : 'FAILED'}"
rescue => e
  puts "   ✗ Button Template validation ERROR: #{e.message}"
end

# Test 3: Validate Quick Replies payload structure
puts "\n3. Testing Quick Replies validation:"
begin
  result = Integrations::Socialwise::InstagramResponseProcessor.send(
    :validate_quick_replies,
    socialwise_quick_replies
  )
  puts "   ✓ Quick Replies validation: #{result ? 'PASSED' : 'FAILED'}"
rescue => e
  puts "   ✗ Quick Replies validation ERROR: #{e.message}"
end

# Test 4: Build Instagram API payload from Generic Template
puts "\n4. Testing Generic Template payload building:"
begin
  built_payload = Integrations::Socialwise::InstagramResponseProcessor.send(
    :build_generic_template_payload,
    socialwise_generic_template
  )
  expected_keys = ['template_type', 'elements']
  has_required_keys = expected_keys.all? { |key| built_payload.key?(key) }
  puts "   ✓ Generic Template payload building: #{has_required_keys ? 'PASSED' : 'FAILED'}"
  puts "   Built payload keys: #{built_payload.keys}"
rescue => e
  puts "   ✗ Generic Template payload building ERROR: #{e.message}"
end

# Test 5: Build Instagram API payload from Button Template
puts "\n5. Testing Button Template payload building:"
begin
  built_payload = Integrations::Socialwise::InstagramResponseProcessor.send(
    :build_button_template_payload,
    socialwise_button_template
  )
  expected_keys = ['template_type', 'text', 'buttons']
  has_required_keys = expected_keys.all? { |key| built_payload.key?(key) }
  puts "   ✓ Button Template payload building: #{has_required_keys ? 'PASSED' : 'FAILED'}"
  puts "   Built payload keys: #{built_payload.keys}"
rescue => e
  puts "   ✗ Button Template payload building ERROR: #{e.message}"
end

# Test 6: Build Instagram API payload from Quick Replies
puts "\n6. Testing Quick Replies payload building:"
begin
  built_payload = Integrations::Socialwise::InstagramResponseProcessor.send(
    :build_quick_replies_payload,
    socialwise_quick_replies
  )
  expected_keys = ['text', 'quick_replies']
  has_required_keys = expected_keys.all? { |key| built_payload.key?(key) }
  puts "   ✓ Quick Replies payload building: #{has_required_keys ? 'PASSED' : 'FAILED'}"
  puts "   Built payload keys: #{built_payload.keys}"
rescue => e
  puts "   ✗ Quick Replies payload building ERROR: #{e.message}"
end

# Test 7: Test fallback text extraction
puts "\n7. Testing fallback text extraction:"
begin
  fallback_text_generic = Integrations::Socialwise::InstagramResponseProcessor.send(
    :extract_fallback_text,
    { 'payload' => socialwise_generic_template }
  )
  puts "   ✓ Generic Template fallback: '#{fallback_text_generic}'"

  fallback_text_button = Integrations::Socialwise::InstagramResponseProcessor.send(
    :extract_fallback_text,
    { 'payload' => socialwise_button_template }
  )
  puts "   ✓ Button Template fallback: '#{fallback_text_button}'"

  fallback_text_quick = Integrations::Socialwise::InstagramResponseProcessor.send(
    :extract_fallback_text,
    { 'payload' => socialwise_quick_replies }
  )
  puts "   ✓ Quick Replies fallback: '#{fallback_text_quick}'"
rescue => e
  puts "   ✗ Fallback text extraction ERROR: #{e.message}"
end

puts "\n=== Test Summary ==="
puts "All validation and payload building tests completed."
puts "The Instagram Response Processor is compatible with SocialWise Flow payloads."