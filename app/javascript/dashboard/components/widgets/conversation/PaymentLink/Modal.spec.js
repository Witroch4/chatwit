import { shallowMount } from '@vue/test-utils';
import PaymentLinkModal from './Modal.vue';

const createWrapper = () =>
  shallowMount(PaymentLinkModal, {
    global: {
      mocks: {
        $t: key => key,
        $store: {
          getters: {
            getCurrentAccountId: 1,
            'accounts/getAccount': () => ({
              custom_attributes: { infinitepay_handle: 'chatwit' },
            }),
            'paymentPresets/getPresets': [],
            'paymentPresets/getUIFlags': {},
            'whatsappInteractiveTemplates/getTemplates': [
              { id: 12, name: 'Payment CTA', template_type: 'cta_url' },
            ],
          },
        },
      },
    },
  });

describe('PaymentLinkModal', () => {
  it('restores the interactive CTA when selecting a favorite', async () => {
    const wrapper = createWrapper();

    await wrapper.vm.selectPreset({
      id: 1,
      amount_cents: 27_000,
      description: 'Single payment',
      whatsapp_interactive_template_id: 12,
    });

    expect(wrapper.vm.selectedInteractiveTemplateId).toBe(12);
  });

  it('does not restore a CTA that no longer resolves to a template', async () => {
    const wrapper = createWrapper();

    await wrapper.vm.selectPreset({
      id: 1,
      amount_cents: 27_000,
      description: 'Single payment',
      whatsapp_interactive_template_id: 999,
    });

    expect(wrapper.vm.selectedInteractiveTemplateId).toBeNull();
  });
});
