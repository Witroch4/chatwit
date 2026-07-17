class AddIdempotencyToMessages < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  INDEX_NAME = 'idx_messages_conversation_idempotency_unique'.freeze

  def up
    add_column :messages, :idempotency_key, :string unless column_exists?(:messages, :idempotency_key)
    add_column :messages, :idempotency_payload_hash, :string unless column_exists?(:messages, :idempotency_payload_hash)

    remove_idempotency_index if idempotency_index_present? && !idempotency_index_valid?
    return if idempotency_index_present?

    add_index :messages,
              %i[conversation_id idempotency_key],
              unique: true,
              where: 'idempotency_key IS NOT NULL',
              algorithm: :concurrently,
              name: INDEX_NAME
  end

  def down
    remove_idempotency_index if idempotency_index_present?
    remove_column :messages, :idempotency_payload_hash if column_exists?(:messages, :idempotency_payload_hash)
    remove_column :messages, :idempotency_key if column_exists?(:messages, :idempotency_key)
  end

  private

  def idempotency_index_present?
    connection.select_value("SELECT to_regclass(#{connection.quote(INDEX_NAME)})::text").present?
  end

  def idempotency_index_valid?
    value = connection.select_value(<<~SQL.squish)
      SELECT indisvalid
      FROM pg_index
      WHERE indexrelid = to_regclass(#{connection.quote(INDEX_NAME)})
    SQL
    ActiveModel::Type::Boolean.new.cast(value)
  end

  def remove_idempotency_index
    remove_index :messages, name: INDEX_NAME, algorithm: :concurrently
  end
end
