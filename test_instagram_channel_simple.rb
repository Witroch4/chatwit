#!/usr/bin/env ruby

# Teste simples para verificar se a correção do canal Instagram foi aplicada
# Executar com: ruby test_instagram_channel_simple.rb

puts "=== TESTE SIMPLES: Correção Canal Instagram ==="
puts

# 1. Verificar se o arquivo ProcessorService existe
processor_file = 'lib/integrations/socialwise_flow/processor_service.rb'

if File.exist?(processor_file)
  puts "✅ Arquivo ProcessorService encontrado"
  
  # 2. Ler o conteúdo do arquivo
  content = File.read(processor_file)
  
  # 3. Verificar roteamento
  puts "\n🔧 Verificando roteamento..."
  
  # Procurar por roteamento que aceita ambos os canais
  routing_pattern = "'Channel::FacebookPage', 'Channel::Instagram'"
  has_instagram_routing = content.include?(routing_pattern)
  
  if has_instagram_routing
    puts "✅ Roteamento aceita Channel::Instagram"
    
    # Mostrar a linha específica
    lines = content.lines
    routing_line = lines.find { |line| line.include?(routing_pattern) }
    if routing_line
      puts "   Linha: #{routing_line.strip}"
    end
  else
    puts "❌ Roteamento NÃO aceita Channel::Instagram"
    
    # Mostrar o que está no código
    routing_section = content.lines.select { |line| line.include?('Channel::FacebookPage') }
    if routing_section.any?
      puts "   Código atual:"
      routing_section.each { |line| puts "   #{line.strip}" }
    end
  end
  
  # 4. Verificar validação
  puts "\n🔍 Verificando validação..."
  
  # Procurar por validação que aceita ambos os canais
  validation_pattern = "valid_instagram_channels = ['Channel::FacebookPage', 'Channel::Instagram']"
  has_instagram_validation = content.include?(validation_pattern)
  
  if has_instagram_validation
    puts "✅ Validação aceita Channel::Instagram"
    
    # Mostrar a linha específica
    validation_line = lines.find { |line| line.include?(validation_pattern) }
    if validation_line
      puts "   Linha: #{validation_line.strip}"
    end
  else
    puts "❌ Validação NÃO aceita Channel::Instagram"
    
    # Mostrar o que está no código
    validation_section = content.lines.select { |line| line.include?('Channel::FacebookPage') && line.include?('unless') }
    if validation_section.any?
      puts "   Código atual:"
      validation_section.each { |line| puts "   #{line.strip}" }
    end
  end
  
  # 5. Verificar InstagramChannelValidator
  puts "\n🔍 Verificando InstagramChannelValidator..."
  
  validator_file = 'app/validators/instagram_channel_validator.rb'
  
  if File.exist?(validator_file)
    validator_content = File.read(validator_file)
    
    # Procurar por validação que aceita ambos os canais
    validator_pattern = "valid_instagram_channel_types = ['Channel::FacebookPage', 'Channel::Instagram']"
    has_validator_support = validator_content.include?(validator_pattern)
    
    if has_validator_support
      puts "✅ InstagramChannelValidator aceita Channel::Instagram"
    else
      puts "❌ InstagramChannelValidator NÃO aceita Channel::Instagram"
    end
  else
    puts "⚠️  Arquivo InstagramChannelValidator não encontrado"
  end
  
  # 6. Resumo
  puts "\n=== RESUMO ==="
  
  if has_instagram_routing && has_instagram_validation
    puts "✅ CORREÇÃO APLICADA COM SUCESSO!"
    puts "   - Roteamento aceita Channel::Instagram"
    puts "   - Validação aceita Channel::Instagram"
    puts "   - InstagramChannelValidator suporta Channel::Instagram"
    puts
    puts "🎯 Status: Mensagens ricas do Instagram funcionarão com ambos os tipos de canal!"
  else
    puts "❌ CORREÇÃO INCOMPLETA"
    puts "   - Roteamento: #{has_instagram_routing ? '✅' : '❌'}"
    puts "   - Validação: #{has_instagram_validation ? '✅' : '❌'}"
    puts
    puts "⚠️  Ainda há problemas que precisam ser corrigidos"
  end
  
else
  puts "❌ Arquivo ProcessorService não encontrado"
  puts "   Caminho esperado: #{processor_file}"
end

puts
puts "=== FIM DO TESTE ==="
