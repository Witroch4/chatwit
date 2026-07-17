class CreateInfinitepayWebhookEvents < ActiveRecord::Migration[7.1]
  def change
    create_events_table
    create_reconciliations_table
  end

  private

  def create_events_table
    create_table :infinitepay_webhook_events do |t|
      t.string :provider, null: false, default: 'infinitepay'
      t.string :order_nsu, null: false
      t.string :source, null: false, default: 'webhook'
      t.string :event_hash, null: false
      t.jsonb :payload, null: false, default: {}
      t.integer :status, null: false, default: 0
      t.datetime :verified_at
      t.timestamps
    end
    add_index :infinitepay_webhook_events, :event_hash, unique: true
    add_index :infinitepay_webhook_events, [:provider, :order_nsu]
  end

  def create_reconciliations_table
    create_table :payment_reconciliations do |t|
      t.string :provider, null: false, default: 'infinitepay'
      t.string :order_nsu, null: false
      t.jsonb :receipt, null: false, default: {}
      t.jsonb :milestones, null: false, default: {}
      t.timestamps
    end
    add_index :payment_reconciliations, [:provider, :order_nsu], unique: true
  end
end
