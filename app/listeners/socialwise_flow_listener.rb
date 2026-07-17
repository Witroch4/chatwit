# Chatwit: release the durable Socialwise/Captain ownership fence on resolve.
class SocialwiseFlowListener < BaseListener
  def conversation_resolved(event)
    conversation = event.data[:conversation]
    return if conversation.blank?

    Integrations::SocialwiseFlow::OwnershipGuard.new(conversation).release_for_resolve!(cutoff: event.timestamp)
  end
end
