<script setup>
import { ref, computed, watch, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useHaptics } from 'dashboard/composables/useHaptics';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { NOTIFICATION_TYPES } from 'dashboard/routes/dashboard/settings/profile/constants';
import MobileBackButton from './MobileBackButton.vue';
import { vHapticTap } from './hapticTap';

const emit = defineEmits(['back']);

const store = useStore();
const { t } = useI18n();
const { selection } = useHaptics();

const accountId = useMapGetter('getCurrentAccountId');
const emailFlags = useMapGetter(
  'userNotificationSettings/getSelectedEmailFlags'
);
const pushFlags = useMapGetter('userNotificationSettings/getSelectedPushFlags');
const isFeatureEnabledonAccount = useMapGetter(
  'accounts/isFeatureEnabledonAccount'
);

const selectedEmailFlags = ref([]);
const selectedPushFlags = ref([]);

watch(
  emailFlags,
  value => {
    selectedEmailFlags.value = value || [];
  },
  { immediate: true }
);

watch(
  pushFlags,
  value => {
    selectedPushFlags.value = value || [];
  },
  { immediate: true }
);

const isSLAEnabled = computed(() =>
  isFeatureEnabledonAccount.value(accountId.value, FEATURE_FLAGS.SLA)
);

const filteredNotificationTypes = computed(() =>
  NOTIFICATION_TYPES.filter(notification =>
    isSLAEnabled.value
      ? true
      : ![
          'sla_missed_first_response',
          'sla_missed_next_response',
          'sla_missed_resolution',
        ].includes(notification.value)
  )
);

const groups = computed(() => [
  { key: 'email', title: t('MOBILE.NOTIF_PREFS.EMAIL_TITLE') },
  { key: 'push', title: t('MOBILE.NOTIF_PREFS.PUSH_TITLE') },
]);

onMounted(() => {
  store.dispatch('userNotificationSettings/get');
});

const isFlagEnabled = (type, value) => {
  const selected =
    type === 'email' ? selectedEmailFlags.value : selectedPushFlags.value;
  return selected.includes(`${type}_${value}`);
};

const toggleInput = (selected, current) => {
  if (selected.includes(current)) {
    return selected.filter(flag => flag !== current);
  }
  return [...selected, current];
};

const updateNotificationSettings = async () => {
  try {
    await store.dispatch('userNotificationSettings/update', {
      selectedEmailFlags: selectedEmailFlags.value,
      selectedPushFlags: selectedPushFlags.value,
    });
  } catch (error) {
    // Re-sync local state with the server-backed store so the toggles
    // revert instead of displaying a state that failed to persist.
    selectedEmailFlags.value = emailFlags.value || [];
    selectedPushFlags.value = pushFlags.value || [];
    useAlert(t('PROFILE_SETTINGS.FORM.API.UPDATE_ERROR'));
  }
};

const handleToggle = (type, value) => {
  // Haptic fires at tap time: iOS drops the Taptic switch trick once the
  // user activation expires across an await.
  selection();
  const flag = `${type}_${value}`;
  if (type === 'email') {
    selectedEmailFlags.value = toggleInput(selectedEmailFlags.value, flag);
  } else {
    selectedPushFlags.value = toggleInput(selectedPushFlags.value, flag);
  }
  updateNotificationSettings();
};
</script>

<template>
  <Teleport to="body">
    <div class="fixed inset-0 z-[60] flex flex-col bg-n-surface-1">
      <header
        class="flex items-center gap-2 px-2 py-3 pt-[env(safe-area-inset-top)] flex-shrink-0 bg-white dark:bg-n-background border-b border-n-weak"
      >
        <MobileBackButton @click="emit('back')" />
        <h1 class="text-lg font-semibold text-n-slate-12">
          {{ t('MOBILE.NOTIF_PREFS.TITLE') }}
        </h1>
      </header>

      <div
        class="flex-1 overflow-y-auto overscroll-y-contain px-4 pb-[calc(24px+env(safe-area-inset-bottom))]"
      >
        <section v-for="group in groups" :key="group.key" class="pt-5">
          <span
            class="text-xs font-medium text-n-slate-10 uppercase tracking-wider mb-2 block"
          >
            {{ group.title }}
          </span>
          <div
            class="overflow-hidden rounded-2xl border border-n-weak bg-white dark:bg-n-background shadow-sm"
          >
            <button
              v-for="(notification, index) in filteredNotificationTypes"
              :key="notification.value"
              v-haptic-tap
              class="flex w-full items-center gap-3 px-4 py-3 text-left active:bg-n-alpha-2"
              :class="{ 'border-t border-n-weak': index > 0 }"
              @click="handleToggle(group.key, notification.value)"
            >
              <span class="flex-1 min-w-0 text-sm text-n-slate-12">
                {{ t(notification.label) }}
              </span>
              <div
                class="relative w-11 h-6 rounded-full transition-colors flex-shrink-0"
                :class="
                  isFlagEnabled(group.key, notification.value)
                    ? 'bg-n-brand'
                    : 'bg-n-slate-7'
                "
              >
                <span
                  class="absolute top-0.5 ltr:left-0.5 rtl:right-0.5 size-5 rounded-full bg-white shadow transition-transform"
                  :class="
                    isFlagEnabled(group.key, notification.value)
                      ? 'ltr:translate-x-5 rtl:-translate-x-5'
                      : 'translate-x-0'
                  "
                />
              </div>
            </button>
          </div>
        </section>
      </div>
    </div>
  </Teleport>
</template>
