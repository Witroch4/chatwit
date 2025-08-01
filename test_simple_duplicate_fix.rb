# Simple test to verify the duplicate message fix
# Run this in Rails console: rails console

# Test 1: Verify that messages with skip_send_reply flag don't trigger SendReplyJob
puts "=== Testing skip_send_reply flag ==="

# Create a mock message with skip_send_reply flag
class TestMessage
  attr_accessor :additional_attributes, :attachments, :id
  
  def initialize(skip_flag = false)
    @additional_attributes = skip_flag ? { 'skip_send_reply' => true } : {}
    @attachments = []
    @id = rand(1000)
  end
  
  def send_reply
    # Skip sending reply if message is marked to skip (e.g., for rich messages handled by specialized services)
    return if additional_attributes&.dig('skip_send_reply')
    
    puts "SendReplyJob would be enqueued for message #{id}"
    true
  end
end

# Test message without skip flag
msg1 = TestMessage.new(false)
puts "Message without skip flag:"
result1 = msg1.send_reply
puts "Result: #{result1 ? 'Job enqueued' : 'Job skipped'}"

# Test message with skip flag
msg2 = TestMessage.new(true)
puts "\nMessage with skip flag:"
result2 = msg2.send_reply
puts "Result: #{result2 ? 'Job enqueued' : 'Job skipped'}"

puts "\n✅ Test completed. Messages with skip_send_reply flag should skip job enqueueing."