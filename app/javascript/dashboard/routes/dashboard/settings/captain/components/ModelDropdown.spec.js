import { nextTick, ref } from 'vue';
import { shallowMount } from '@vue/test-utils';
import { createPinia, setActivePinia } from 'pinia';
import ModelDropdown from './ModelDropdown.vue';
import { useCaptainConfigStore } from 'dashboard/store/captain/preferences';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ isOnChatwootCloud: ref(false) }),
}));

describe('ModelDropdown', () => {
  let store;

  const mountDropdown = () =>
    shallowMount(ModelDropdown, {
      props: { featureKey: 'editor' },
      global: {
        directives: { onClickaway: () => {} },
        stubs: {
          DropdownBody: { template: '<div><slot /></div>' },
          DropdownItem: {
            name: 'DropdownItem',
            props: ['click'],
            template: '<button type="button" @click="click"><slot /></button>',
          },
          Icon: {
            props: ['icon'],
            template: '<i :data-icon="icon" />',
          },
        },
      },
    });

  beforeEach(() => {
    setActivePinia(createPinia());
    store = useCaptainConfigStore();
  });

  it('disables model selection when the WitDev catalog is unavailable', () => {
    store.catalog = {
      route: 'witdev',
      source: 'unavailable',
      operational: false,
    };
    store.features = {
      editor: { models: [], selected: null, selection_valid: false },
    };

    const wrapper = mountDropdown();

    expect(wrapper.get('button').attributes('disabled')).toBeDefined();
    expect(wrapper.text()).toContain(
      'CAPTAIN_SETTINGS.MODEL_CONFIG.CATALOG_UNAVAILABLE'
    );
  });

  it('shows an invalid persisted model alias', () => {
    store.catalog = {
      route: 'witdev',
      source: 'litellm_proxy',
      operational: true,
    };
    store.features = {
      editor: {
        models: [],
        selected: 'witdev/dead',
        selection_valid: false,
      },
    };

    const wrapper = mountDropdown();

    expect(wrapper.text()).toContain('witdev/dead');
    expect(wrapper.text()).toContain(
      'CAPTAIN_SETTINGS.MODEL_CONFIG.MODEL_UNAVAILABLE'
    );
  });

  it('uses the generic bot icon for an unknown provider', async () => {
    store.catalog = {
      route: 'witdev',
      source: 'litellm_proxy',
      operational: true,
    };
    store.features = {
      editor: {
        models: [
          {
            id: 'witdev/unknown',
            display_name: 'Unknown model',
            provider: 'unknown',
          },
        ],
        selected: 'witdev/unknown',
        selection_valid: true,
      },
    };

    const wrapper = mountDropdown();
    await wrapper.get('button').trigger('click');

    expect(wrapper.find('[data-icon="i-lucide-bot"]').exists()).toBe(true);
  });

  it('closes an open menu and blocks selection when the catalog becomes unavailable', async () => {
    const model = {
      id: 'witdev/available',
      display_name: 'Available model',
      provider: 'openai',
    };
    store.catalog = {
      route: 'witdev',
      source: 'litellm_proxy',
      operational: true,
    };
    store.features = {
      editor: {
        models: [model],
        selected: model.id,
        selection_valid: true,
      },
    };

    const wrapper = mountDropdown();
    await wrapper.get('button').trigger('click');
    const selectModel = wrapper
      .findComponent({ name: 'DropdownItem' })
      .props('click');

    store.catalog = {
      route: 'witdev',
      source: 'unavailable',
      operational: false,
    };
    await nextTick();
    selectModel();

    expect(wrapper.findComponent({ name: 'DropdownItem' }).exists()).toBe(
      false
    );
    expect(wrapper.emitted('change')).toBeUndefined();
  });

  it('clears the stale selected label and item highlight when selection and default are removed', async () => {
    const model = {
      id: 'witdev/available',
      display_name: 'Available model',
      provider: 'openai',
    };
    store.features = {
      editor: {
        models: [model],
        selected: model.id,
        default: model.id,
        selection_valid: true,
      },
    };

    const wrapper = mountDropdown();
    await wrapper.get('button').trigger('click');
    store.features.editor = {
      ...store.features.editor,
      selected: null,
      default: null,
    };
    await nextTick();

    expect(wrapper.get('button').text()).toContain(
      'CAPTAIN_SETTINGS.MODEL_CONFIG.SELECT_MODEL'
    );
    expect(wrapper.get('button').text()).not.toContain('Available model');
    expect(
      wrapper.findComponent({ name: 'DropdownItem' }).classes()
    ).not.toContain('dark:bg-n-solid-3');
  });
});
