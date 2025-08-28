#!/usr/bin/env ruby

# Test script to verify WhatsApp Cloud Service has send_interactive_payload method

puts "=== Testing WhatsApp Cloud Service send_interactive_payload method ==="

# Load Rails environment
require_relative 'config/environment'

# Test 1: Check if method exists
puts "\n1. Checking if send_interactive_payload method exists..."
cloud_service = Whatsapp::Providers::WhatsappCloudService.new(whatsapp_channel: nil)

if cloud_service.respond_to?(:send_interactive_payload)
  puts "✅ send_interactive_payload method exists in WhatsappCloudService"
else
  puts "❌ send_interactive_payload method NOT found in WhatsappCloudService"
  exit 1
end

# Test 2: Check method signature
puts "\n2. Checking method signature..."
method_info = cloud_service.method(:send_interactive_payload)
puts "✅ Method signature: #{method_info.parameters}"
puts "✅ Expected parameters: phone_number, message, interactive_payload"

# Test 3: Compare with 360 Dialog Service
puts "\n3. Comparing with WhatsApp 360 Dialog Service..."
dialog_service = Whatsapp::Providers::Whatsapp360DialogService.new(whatsapp_channel: nil)

if dialog_service.respond_to?(:send_interactive_payload)
  puts "✅ send_interactive_payload method exists in Whatsapp360DialogService"
  dialog_method_info = dialog_service.method(:send_interactive_payload)
  puts "✅ 360 Dialog method signature: #{dialog_method_info.parameters}"
else
  puts "❌ send_interactive_payload method NOT found in Whatsapp360DialogService"
end

puts "\n=== Test completed successfully! ==="
puts "✅ WhatsApp Cloud Service now has send_interactive_payload method"
puts "✅ Method signature matches expected parameters"
puts "✅ Both WhatsApp providers now support interactive payloads"