class Sticker < ApplicationRecord
  RECENT_LIMIT = 20

  belongs_to :account
  belongs_to :user, optional: true
  has_one_attached :file

  validates :account_id, presence: true

  # Appends a sticker id to the per-user recents list (newest first, capped).
  def self.touch_recent(user, sticker_id)
    settings = user.ui_settings || {}
    recents = Array(settings['recent_stickers']).reject { |id| id == sticker_id }
    recents.unshift(sticker_id)
    user.update!(ui_settings: settings.merge('recent_stickers' => recents.first(RECENT_LIMIT)))
  end

  # Returns the user's recent stickers in recency order, scoped to the account.
  def self.recent_for(account, user)
    ids = Array(user.ui_settings&.dig('recent_stickers'))
    return none if ids.blank?

    scope = account.stickers.where(id: ids).index_by(&:id)
    ids.filter_map { |id| scope[id] }
  end
end
