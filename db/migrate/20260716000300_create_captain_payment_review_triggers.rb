class CreateCaptainPaymentReviewTriggers < ActiveRecord::Migration[7.0]
  def change
    create_trigger_table
    add_trigger_indexes
    add_trigger_foreign_keys
    add_trigger_constraints
  end

  private

  def create_trigger_table
    create_table :captain_payment_review_triggers do |t|
      t.integer :account_id, null: false
      t.integer :conversation_id, null: false
      t.string :trigger_label, null: false
      t.integer :generation, null: false
      t.integer :state, null: false
      t.integer :source, null: false
      t.datetime :activated_at, null: false
      t.datetime :deactivated_at
      t.integer :trigger_message_id
      t.string :payment_context_id
      t.integer :payment_context_version
      t.bigint :run_id
      t.string :event_key, null: false
      t.timestamps
    end
  end

  def add_trigger_indexes
    add_index :captain_payment_review_triggers, :account_id
    add_index :captain_payment_review_triggers,
              %i[conversation_id generation],
              unique: true,
              name: 'idx_captain_pay_triggers_conv_generation'
    add_index :captain_payment_review_triggers, :event_key, unique: true, name: 'idx_captain_pay_triggers_event_key'
    add_index :captain_payment_review_triggers,
              %i[conversation_id trigger_label],
              unique: true,
              where: 'deactivated_at IS NULL',
              name: 'idx_captain_pay_triggers_one_present'
    add_index :captain_payment_review_triggers, :run_id, where: 'run_id IS NOT NULL', name: 'idx_captain_pay_triggers_run'
  end

  def add_trigger_foreign_keys
    add_foreign_key :captain_payment_review_triggers, :accounts, on_delete: :cascade
    add_foreign_key :captain_payment_review_triggers, :conversations, on_delete: :cascade
  end

  def add_trigger_constraints
    add_check_constraint :captain_payment_review_triggers,
                         'generation > 0',
                         name: 'chk_captain_pay_trigger_generation'
    add_check_constraint :captain_payment_review_triggers,
                         'state IN (0, 1, 2, 3, 4)',
                         name: 'chk_captain_pay_trigger_state'
    add_check_constraint :captain_payment_review_triggers,
                         'source IN (0, 1, 2)',
                         name: 'chk_captain_pay_trigger_source'
    add_check_constraint :captain_payment_review_triggers,
                         'char_length(btrim(trigger_label)) > 0 AND char_length(btrim(event_key)) > 0',
                         name: 'chk_captain_pay_trigger_identity'
    add_presence_constraints
    add_payment_context_constraint
  end

  def add_presence_constraints
    add_check_constraint :captain_payment_review_triggers,
                         '(deactivated_at IS NULL OR deactivated_at >= activated_at)',
                         name: 'chk_captain_pay_trigger_dates'
    add_check_constraint :captain_payment_review_triggers,
                         <<~SQL.squish,
                           ((state IN (0, 1, 2) AND deactivated_at IS NULL) OR
                            (state IN (3, 4) AND deactivated_at IS NOT NULL))
                         SQL
                         name: 'chk_captain_pay_trigger_presence'
  end

  def add_payment_context_constraint
    add_check_constraint :captain_payment_review_triggers,
                         <<~SQL.squish,
                           ((payment_context_id IS NULL AND payment_context_version IS NULL) OR
                            (payment_context_id IS NOT NULL AND char_length(btrim(payment_context_id)) > 0 AND
                             payment_context_version > 0))
                         SQL
                         name: 'chk_captain_pay_trigger_context'
  end
end
