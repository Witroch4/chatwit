<script setup>
import { useI18n } from 'vue-i18n';
import { useHaptics } from 'dashboard/composables/useHaptics';
import { vHapticTap } from './hapticTap';

const emit = defineEmits(['openFilter', 'openSearch']);
const { t } = useI18n();
const { light } = useHaptics();

const onSearchClick = () => {
  light();
  emit('openSearch');
};
</script>

<template>
  <header
    class="flex items-center justify-between px-4 py-3 pt-[env(safe-area-inset-top)] flex-shrink-0 bg-white dark:bg-n-background border-b border-n-weak"
  >
    <h1 class="text-lg font-semibold text-n-slate-12">
      {{ t('MOBILE.CONVERSATIONS.TITLE') }}
    </h1>
    <div class="flex items-center gap-1">
      <button
        v-haptic-tap
        class="flex items-center justify-center size-9 rounded-lg text-n-slate-11 active:bg-n-alpha-2"
        :aria-label="t('MOBILE.SEARCH.OPEN')"
        @click="onSearchClick"
      >
        <span class="i-lucide-search size-5" />
      </button>
      <button
        class="flex items-center justify-center size-9 rounded-lg text-n-slate-11 active:bg-n-alpha-2"
        @click="emit('openFilter')"
      >
        <span class="i-lucide-sliders-horizontal size-5" />
      </button>
    </div>
  </header>
</template>
