#!/usr/bin/env ruby

# Teste rápido da validação de timestamp
timestamp_with_timezone = "2025-07-25T00:21:51+00:00"
timestamp_with_z = "2025-07-25T00:21:51Z"

# Regex atualizada
regex = /\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(Z|[+-]\d{2}:\d{2})/

puts "=== TESTE DE VALIDAÇÃO DE TIMESTAMP ==="
puts ""
puts "Timestamp com timezone: #{timestamp_with_timezone}"
puts "Válido? #{timestamp_with_timezone.match?(regex)}"
puts ""
puts "Timestamp com Z: #{timestamp_with_z}"
puts "Válido? #{timestamp_with_z.match?(regex)}"
puts ""

# Teste de parsing
require 'time'

begin
  parsed_tz = Time.parse(timestamp_with_timezone)
  puts "Parsed com timezone: #{parsed_tz}"
  puts "UTC: #{parsed_tz.utc}"
  puts "ISO8601: #{parsed_tz.utc.iso8601}"
rescue => e
  puts "Erro parsing timezone: #{e.message}"
end

begin
  parsed_z = Time.parse(timestamp_with_z)
  puts "Parsed com Z: #{parsed_z}"
  puts "UTC: #{parsed_z.utc}"
  puts "ISO8601: #{parsed_z.utc.iso8601}"
rescue => e
  puts "Erro parsing Z: #{e.message}"
end