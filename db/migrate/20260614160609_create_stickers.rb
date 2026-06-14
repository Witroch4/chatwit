class CreateStickers < ActiveRecord::Migration[7.1]
  def change
    create_table :stickers do |t|
      t.bigint :account_id, null: false
      t.bigint :user_id
      t.boolean :animated, null: false, default: false
      t.timestamps
    end
    add_index :stickers, :account_id
    add_index :stickers, [:account_id, :created_at]
    add_foreign_key :stickers, :accounts
  end
end
