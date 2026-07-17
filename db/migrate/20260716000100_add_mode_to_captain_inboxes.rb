class AddModeToCaptainInboxes < ActiveRecord::Migration[7.0]
  def change
    add_column :captain_inboxes, :mode, :integer, default: 0, null: false

    remove_index :captain_inboxes, :inbox_id, name: 'index_captain_inboxes_on_inbox_id'
    add_index :captain_inboxes, :inbox_id, unique: true, name: 'index_captain_inboxes_on_inbox_id'
  end
end
