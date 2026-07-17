class AddPhase2SettingsToCaptainInboxes < ActiveRecord::Migration[7.1]
  def change
    add_column :captain_inboxes, :phase2_model, :string
    add_column :captain_inboxes, :phase2_prompt, :text
    add_column :captain_inboxes, :phase2_payment_preset_ids, :jsonb, null: false, default: []
  end
end
