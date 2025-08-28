#!/usr/bin/env ruby
# frozen_string_literal: true

# Test script to validate WhatsApp SocialWise Flow rich message fix
# This script tests the new WhatsappResponseProcessor implementation

require_relative 'config/environment'

class WhatsAppSocialWiseFlowTest
  def initialize
    @account = Account.first
    @inbox = @account.inboxes.where(channel_type: 'Channel::Whatsapp').first
    
    unless @inbox
      puts "❌ No WhatsApp inbox found. Creating test data..."
      create_test_data
    end
    
    @conversation = @inbox.conversations.first || create_test_conversation
    puts "✅ Test setup complete"
    puts "   Account: #{@account.name} (ID: #{@account.id})"
    puts "   Inbox: #{@inbox.name} (ID: #{@inbox.id})"
    puts "   Conversation: #{@conversation.id}"
  end

  def run_tests
    puts "\n🧪 Starting WhatsApp SocialWise Flow Rich Message Tests"
    puts "=" * 60
    
    test_interactive_button_message
    test_interactive_list_message
    test_text_message
    test_fallback_scenarios
    
    puts "\n✅ All tests completed!"
  end

  private

  def test_interactive_button_message
    puts "\n📱 Testing Interactive Button Message"
    puts "-" * 40
    
    # Create test message
    incoming_message = create_test_message("Test button message")
    
    # Create WhatsApp interactive button payload
    whatsapp_payload = {
      'type' => 'interactive',
      'interactive' => {
        'type' => 'button',
        'body' => {
          'text' => 'Escolha uma opção:'
        },
        'action' => {
          'buttons' => [
            {
              'type' => 'reply',
              'reply' => {
                'id' => 'btn_1',
                'title' => 'Opção 1'
              }
            },
            {
              'type' => 'reply',
              'reply' => {
                'id' => 'btn_2',
                'title' => 'Opção 2'
              }
            }
          ]
        }
      }
    }
    
    puts "   Payload: #{whatsapp_payload.inspect}"
    
    # Test the processor
    begin
      success = Integrations::SocialwiseFlow::WhatsappResponseProcessor.process(whatsapp_payload, incoming_message)
      
      if success
        puts "   ✅ Interactive button message processed successfully"
        
        # Check if rich message was created
        rich_messages = @conversation.messages.where(message_type: 'outgoing').where("content_type = ? OR content_type = ?", 'integrations', 'cards')
        
        if rich_messages.any?
          latest_message = rich_messages.last
          puts "   ✅ Rich message created (ID: #{latest_message.id})"
          puts "   📊 Content type: #{latest_message.content_type}"
          puts "   📝 Content: #{latest_message.content}"
          puts "   🎛️  Content attributes keys: #{latest_message.content_attributes.keys}"
          
          # Check for SocialWise Flow flag
          if latest_message.additional_attributes&.dig('socialwise_flow_message')
            puts "   ✅ SocialWise Flow flag present"
          else
            puts "   ⚠️  SocialWise Flow flag missing"
          end
          
          # Check for skip_send_reply flag
          if latest_message.additional_attributes&.dig('skip_send_reply')
            puts "   ✅ Skip send reply flag present (prevents flash effect)"
          else
            puts "   ⚠️  Skip send reply flag missing"
          end
        else
          puts "   ❌ No rich message found"
        end
      else
        puts "   ❌ Interactive button message processing failed"
      end
    rescue => e
      puts "   ❌ Exception: #{e.class}: #{e.message}"
      puts "   📍 Backtrace: #{e.backtrace.first(3).join('\n   ')}"
    end
  end

  def test_interactive_list_message
    puts "\n📋 Testing Interactive List Message"
    puts "-" * 40
    
    # Create test message
    incoming_message = create_test_message("Test list message")
    
    # Create WhatsApp interactive list payload
    whatsapp_payload = {
      'type' => 'interactive',
      'interactive' => {
        'type' => 'list',
        'body' => {
          'text' => 'Selecione uma categoria:'
        },
        'action' => {
          'button' => 'Ver opções',
          'sections' => [
            {
              'title' => 'Categoria 1',
              'rows' => [
                {
                  'id' => 'row_1',
                  'title' => 'Item 1',
                  'description' => 'Descrição do item 1'
                },
                {
                  'id' => 'row_2',
                  'title' => 'Item 2',
                  'description' => 'Descrição do item 2'
                }
              ]
            }
          ]
        }
      }
    }
    
    puts "   Payload: #{whatsapp_payload.inspect}"
    
    # Test the processor
    begin
      success = Integrations::SocialwiseFlow::WhatsappResponseProcessor.process(whatsapp_payload, incoming_message)
      
      if success
        puts "   ✅ Interactive list message processed successfully"
        
        # Check if rich message was created
        rich_messages = @conversation.messages.where(message_type: 'outgoing').where("content_type = ? OR content_type = ?", 'integrations', 'cards')
        
        if rich_messages.any?
          latest_message = rich_messages.last
          puts "   ✅ Rich message created (ID: #{latest_message.id})"
          puts "   📊 Content type: #{latest_message.content_type}"
          puts "   📝 Content: #{latest_message.content}"
          puts "   🎛️  Content attributes keys: #{latest_message.content_attributes.keys}"
        else
          puts "   ❌ No rich message found"
        end
      else
        puts "   ❌ Interactive list message processing failed"
      end
    rescue => e
      puts "   ❌ Exception: #{e.class}: #{e.message}"
      puts "   📍 Backtrace: #{e.backtrace.first(3).join('\n   ')}"
    end
  end

  def test_text_message
    puts "\n💬 Testing Text Message"
    puts "-" * 40
    
    # Create test message
    incoming_message = create_test_message("Test text message")
    
    # Create WhatsApp text payload
    whatsapp_payload = {
      'type' => 'text',
      'text' => {
        'body' => 'Esta é uma mensagem de texto simples'
      }
    }
    
    puts "   Payload: #{whatsapp_payload.inspect}"
    
    # Test the processor
    begin
      success = Integrations::SocialwiseFlow::WhatsappResponseProcessor.process(whatsapp_payload, incoming_message)
      
      if success
        puts "   ✅ Text message processed successfully"
        
        # Check if text message was created
        text_messages = @conversation.messages.where(message_type: 'outgoing', content_type: 'text')
        
        if text_messages.any?
          latest_message = text_messages.last
          puts "   ✅ Text message created (ID: #{latest_message.id})"
          puts "   📝 Content: #{latest_message.content}"
        else
          puts "   ❌ No text message found"
        end
      else
        puts "   ❌ Text message processing failed"
      end
    rescue => e
      puts "   ❌ Exception: #{e.class}: #{e.message}"
      puts "   📍 Backtrace: #{e.backtrace.first(3).join('\n   ')}"
    end
  end

  def test_fallback_scenarios
    puts "\n🛡️  Testing Fallback Scenarios"
    puts "-" * 40
    
    # Test invalid payload
    puts "   Testing invalid payload..."
    incoming_message = create_test_message("Test invalid payload")
    
    begin
      success = Integrations::SocialwiseFlow::WhatsappResponseProcessor.process("invalid", incoming_message)
      
      if success
        puts "   ✅ Invalid payload handled with fallback"
      else
        puts "   ❌ Invalid payload not handled properly"
      end
    rescue => e
      puts "   ❌ Exception with invalid payload: #{e.class}: #{e.message}"
    end
    
    # Test empty payload
    puts "   Testing empty payload..."
    incoming_message = create_test_message("Test empty payload")
    
    begin
      success = Integrations::SocialwiseFlow::WhatsappResponseProcessor.process({}, incoming_message)
      
      if success
        puts "   ✅ Empty payload handled with fallback"
      else
        puts "   ❌ Empty payload not handled properly"
      end
    rescue => e
      puts "   ❌ Exception with empty payload: #{e.class}: #{e.message}"
    end
  end

  def create_test_data
    # This would create test WhatsApp channel if needed
    # For now, assume it exists
    puts "   Please ensure a WhatsApp inbox exists for testing"
  end

  def create_test_conversation
    contact = @account.contacts.create!(
      name: 'Test Contact',
      phone_number: '+5511999999999'
    )
    
    @inbox.conversations.create!(
      account: @account,
      contact: contact,
      status: 'open'
    )
  end

  def create_test_message(content)
    @conversation.messages.create!(
      content: content,
      message_type: 'incoming',
      account: @account,
      inbox: @inbox,
      contact: @conversation.contact
    )
  end
end

# Run the tests
if __FILE__ == $0
  begin
    test = WhatsAppSocialWiseFlowTest.new
    test.run_tests
  rescue => e
    puts "❌ Test setup failed: #{e.class}: #{e.message}"
    puts "📍 Backtrace: #{e.backtrace.first(5).join('\n')}"
  end
end