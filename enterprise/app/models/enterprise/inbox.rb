module Enterprise::Inbox
  def member_ids_with_assignment_capacity
    return super unless enable_auto_assignment?
    return filter_by_capacity(available_agents).map(&:user_id) if auto_assignment_v2_enabled?

    max_assignment_limit = auto_assignment_config['max_assignment_limit']
    overloaded_agent_ids = max_assignment_limit.present? ? get_agent_ids_over_assignment_limit(max_assignment_limit) : []
    super - overloaded_agent_ids
  end

  def active_bot?
    super || captain_auto_response_active?
  end

  def captain_active?
    captain_auto_response_active?
  end

  def captain_auto_response_active?
    captain_auto_response_configured? && more_responses?
  end

  def captain_auto_response_configured?
    captain_inbox&.continuous? && captain_assistant.present?
  end

  def captain_payment_review_available?
    captain_inbox&.phase2_only? && captain_available?
  end

  private

  def captain_available?
    captain_assistant.present? && more_responses?
  end

  def more_responses?
    account.usage_limits[:captain][:responses][:current_available].positive?
  end

  def get_agent_ids_over_assignment_limit(limit)
    conversations
      .open
      .where(account_id: account_id)
      .select(:assignee_id)
      .group(:assignee_id)
      .having("count(*) >= #{limit.to_i}")
      .filter_map(&:assignee_id)
  end

  def ensure_valid_max_assignment_limit
    return if auto_assignment_config['max_assignment_limit'].blank?
    return if auto_assignment_config['max_assignment_limit'].to_i.positive?

    errors.add(:auto_assignment_config, 'max_assignment_limit must be greater than 0')
  end
end
