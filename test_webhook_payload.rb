#!/usr/bin/env ruby

# Simular um payload de webhook como o que está sendo enviado
webhook_payload = {
  "account" => {
    "id" => 3,
    "name" => "DraAmandaSousa"
  },
  "additional_attributes" => {},
  "content_attributes" => {
    "button_reply" => {
      "id" => "btn_confirm_123",
      "title" => "Confirmar"
    },
    "interaction_type" => "button_reply"
  },
  "content_type" => "text",
  "content" => "Confirmar",
  "conversation" => {
    "id" => 1982,
    "status" => "pending",
    "assignee_id" => nil,
    "created_at" => "2025-07-24T22:03:22Z",
    "updated_at" => "2025-07-24T22:03:43Z",
    "contact" => {
      "id" => 1873,
      "name" => "- LM",
      "phone_number" => "+5521996322195",
      "email" => "",
      "identifier" => "",
      "custom_attributes" => {}
    }
  },
  "created_at" => "2025-07-24T22:03:43Z",
  "id" => 32027,
  "inbox" => {
    "id" => 4,
    "name" => "WhatsApp - ANA",
    "channel_type" => "Channel::Whatsapp",
    "channel" => {
      "provider_config" => {
        "api_key" => "EAAGIBII4GXQBO2qgvJ2jdcUmgkdqBo5bUKEanJWmCLpcZAsq0Ovpm4JNlrNLeZAv3OYNrdCqqQBAHfEfPFD0FPnZAOQJURB9GKcbjXeDpa83XdAsa3i6fTr23lBFM2LwUZC23xXrZAnB8QjCCFZBxrxlBvzPj8LsejvUjz0C04Q8Jsl8nTGHUd4ZBRPc4NiHFnc",
        "phone_number_id" => "123456789",
        "business_account_id" => "987654321"
      }
    }
  },
  "message_type" => "incoming",
  "private" => false,
  "sender" => {
    "id" => 1873,
    "name" => "- LM",
    "phone_number" => "+5521996322195"
  },
  "source_id" => "wamid.HBgNNTUyMTk5NjMyMjE5NRUCABIYIEJBOTVGQjE5NTYwNkI5NDYzNDA1MzQ2RDM4ODVGRTk4AA==",
  "event" => "message_created"
}

puts "Payload de teste criado:"
puts JSON.pretty_generate(webhook_payload)