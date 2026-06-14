class StickerPolicy < ApplicationPolicy
  def index?
    true
  end

  def create?
    true
  end

  def send_sticker?
    true
  end

  def destroy?
    @account_user.administrator? || record.user_id == @user.id
  end
end
