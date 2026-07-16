class AddPositionToCannedResponses < ActiveRecord::Migration[7.1]
  def up
    add_column :canned_responses, :position, :integer

    execute <<~SQL.squish
      UPDATE canned_responses
      SET position = ordered.position
      FROM (
        SELECT id, ROW_NUMBER() OVER (PARTITION BY account_id ORDER BY created_at, id) AS position
        FROM canned_responses
      ) AS ordered
      WHERE canned_responses.id = ordered.id
    SQL

    change_column_null :canned_responses, :position, false
    add_index :canned_responses, [:account_id, :position]
  end

  def down
    remove_index :canned_responses, column: [:account_id, :position]
    remove_column :canned_responses, :position
  end
end
