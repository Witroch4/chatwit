class AddPhase2PixKeyToCaptainInboxes < ActiveRecord::Migration[7.1]
  def change
    add_column :captain_inboxes, :phase2_pix_key, :string
  end
end
