class AddStatusToStickers < ActiveRecord::Migration[7.1]
  def change
    # 1 = ready (default for existing rows); async uploads start at 0 = processing.
    add_column :stickers, :status, :integer, null: false, default: 1
  end
end
