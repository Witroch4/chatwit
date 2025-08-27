#!/usr/bin/env ruby
# Test WhatsApp rich dashboard functionality
# Run with: docker exec chatwit-dev-rails-1 bundle exec rails runner test_whatsapp_rich_dashboard.rb

puts "=== Testing WhatsApp Rich Dashboard ==="

# Test the mapper directly
interactive_payload = {
  'type' => 'button',
  'body' => {
    'text' => '> Sr(a) *Witalo*, \nSomos especializados em mandado de segurança e ação ordinária agimos em todo o pais.\n• Especialidade OAB\nProcesso analisado direto pela nossa especialista.'
  },
  'header' => {
    'type' => 'image',
    'image' => {
      'link' => 'https://objstoreapi.witdev.com.br/chatwit-social/33ad7e6c-7524-4bbb-a7f5-80d35768b3f8-c328cd8b-9d43-4a7a-8a2c-5c92c4848e7c-IMG_8514-scaled.png'
    }
  },
  'footer' => {
    'text' => 'Dra. Amanda Sousa Advocacia e Consultoria Jurídica™'
  },
  'action' => {
    'buttons' => [
      {
        'type' => 'reply',
        'reply' => {
          'id' => 'btn_1756256766794_0_vno9',
          'title' => 'Falar com a Dra'
        }
      },
      {
        'type' => 'reply',
        'reply' => {
          'id' => 'btn_1756256766794_1_20a0',
          'title' => 'Tenho Direito?'
        }
      },
      {
        'type' => 'reply',
        'reply' => {
          'id' => 'btn_1756256766794_2_l6co',
          'title' => 'Finalizar'
        }
      }
    ]
  }
}

puts "\n=== Testing Mapper ==="
begin
  mapped_result = Messages::WhatsappRendererMapper.map(interactive_payload)
  puts "✅ Mapper worked successfully!"
  puts "Content type: #{mapped_result.content_type}"
  puts "Fallback text: #{mapped_result.fallback_text}"
  puts "Content attributes keys: #{mapped_result.content_attributes.keys}"
  
  if mapped_result.content_type == 'cards'
    items = mapped_result.content_attributes['items']
    puts "Number of cards: #{items.length}"
    
    items.each_with_index do |item, index|
      puts "  Card #{index + 1}:"
      puts "    Title: #{item['title']}"
      puts "    Description: #{item['description']}" if item['description']
      puts "    Media URL: #{item['media_url']}" if item['media_url']
      puts "    Actions: #{item['actions'].length}" if item['actions']
    end
  end
  
rescue StandardError => e
  puts "❌ Mapper failed: #{e.class}: #{e.message}"
  puts "Backtrace: #{e.backtrace.first(3).join('\n')}"
end

puts "\n=== Testing Account Feature ==="
begin
  account = Account.find(3)
  enabled = account.feature_enabled?('SOCIALWISE_RICH_DASHBOARD')
  puts "Account: #{account.name}"
  puts "SOCIALWISE_RICH_DASHBOARD enabled: #{enabled}"
  
  # Check if we can find a recent message
  recent_messages = account.messages.where(content_type: 'integrations').order(created_at: :desc).limit(5)
  puts "Recent integrations messages: #{recent_messages.count}"
  
  recent_messages.each do |msg|
    puts "  Message #{msg.id}: #{msg.content_type} - #{msg.content.truncate(50)}"
    puts "    Content attributes keys: #{msg.content_attributes.keys}"
    puts "    Additional attributes keys: #{msg.additional_attributes.keys}"
  end
  
rescue StandardError => e
  puts "❌ Account check failed: #{e.class}: #{e.message}"
end

puts "\n=== Test Complete ==="