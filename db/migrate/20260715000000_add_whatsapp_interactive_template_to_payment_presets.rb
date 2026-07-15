class AddWhatsappInteractiveTemplateToPaymentPresets < ActiveRecord::Migration[7.0]
  def change
    add_reference :payment_presets,
                  :whatsapp_interactive_template,
                  null: true,
                  foreign_key: { on_delete: :nullify }
  end
end
