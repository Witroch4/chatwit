class CreateCaptainPaymentReviewRuns < ActiveRecord::Migration[7.0]
  def change
    create_run_table
    add_run_indexes
    add_run_foreign_keys
    add_run_constraints
  end

  private

  def create_run_table
    create_table :captain_payment_review_runs do |t|
      run_identity_columns(t)
      run_lease_columns(t)
      run_decision_columns(t)
      t.timestamps
    end
  end

  def run_identity_columns(table)
    table.integer :account_id, null: false
    table.integer :conversation_id, null: false
    table.bigint :captain_assistant_id
    table.string :trigger_label, null: false
    table.string :trigger_key, null: false
    table.integer :generation, null: false
    table.datetime :triggered_at, null: false
    table.integer :trigger_message_id
    table.integer :decision_watermark_message_id
    table.string :payment_context_id
    table.integer :payment_context_version
    table.string :payment_order_nsu
  end

  def run_lease_columns(table)
    table.integer :status, null: false, default: 0
    table.integer :outcome
    table.uuid :execution_token
    table.datetime :lease_expires_at
    table.datetime :heartbeat_at
    table.datetime :next_attempt_at
    table.integer :attempts, null: false, default: 0
    table.datetime :usage_recorded_at
  end

  def run_decision_columns(table)
    table.integer :response_message_id
    table.string :decision_action
    table.string :reason_code
    table.string :error_code
    table.string :error_message
    table.datetime :retrigger_requested_at
    table.string :pending_trigger_key
    table.datetime :started_at
    table.datetime :completed_at
  end

  def add_run_indexes
    add_index :captain_payment_review_runs, :account_id
    add_index :captain_payment_review_runs, :conversation_id
    add_index :captain_payment_review_runs, :trigger_key, unique: true, name: 'idx_captain_pay_runs_trigger_key'
    add_index :captain_payment_review_runs, :response_message_id, unique: true,
                                                                  where: 'response_message_id IS NOT NULL', name: 'idx_captain_pay_runs_response'
    add_index :captain_payment_review_runs,
              %i[conversation_id trigger_label],
              unique: true,
              where: 'status IN (0, 1)',
              name: 'idx_captain_pay_runs_one_active'
    add_index :captain_payment_review_runs, :lease_expires_at, name: 'idx_captain_pay_runs_lease'
  end

  def add_run_foreign_keys
    add_foreign_key :captain_payment_review_runs, :accounts, on_delete: :cascade
    add_foreign_key :captain_payment_review_runs, :conversations, on_delete: :cascade
    add_foreign_key :captain_payment_review_runs, :messages, column: :response_message_id, on_delete: :nullify
  end

  def add_run_constraints
    add_check_constraint :captain_payment_review_runs, 'generation > 0', name: 'chk_captain_pay_run_generation'
    add_check_constraint :captain_payment_review_runs, 'attempts >= 0', name: 'chk_captain_pay_run_attempts'
    add_check_constraint :captain_payment_review_runs, 'status IN (0, 1, 2, 3, 4)', name: 'chk_captain_pay_run_status'
    add_check_constraint :captain_payment_review_runs,
                         'outcome IS NULL OR outcome IN (0, 1, 2, 3, 4, 5, 6, 7, 8)',
                         name: 'chk_captain_pay_run_outcome'
    add_check_constraint :captain_payment_review_runs,
                         'char_length(btrim(trigger_label)) > 0 AND char_length(btrim(trigger_key)) > 0',
                         name: 'chk_captain_pay_run_identity'
    add_check_constraint :captain_payment_review_runs,
                         <<~SQL.squish,
                           ((payment_context_id IS NULL AND payment_context_version IS NULL) OR
                            (payment_context_id IS NOT NULL AND char_length(btrim(payment_context_id)) > 0 AND
                             payment_context_version > 0))
                         SQL
                         name: 'chk_captain_pay_run_context'
  end
end
