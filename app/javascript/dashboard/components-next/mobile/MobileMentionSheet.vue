<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { useHaptics } from 'dashboard/composables/useHaptics';
import Avatar from 'next/avatar/Avatar.vue';
import { vHapticTap } from './hapticTap';

const props = defineProps({
  searchKey: {
    type: String,
    default: '',
  },
});

const emit = defineEmits(['selectAgent']);

const { t } = useI18n();
const { selection } = useHaptics();

const verifiedAgents = useMapGetter('agents/getVerifiedAgents');

const filteredAgents = computed(() => {
  const search = props.searchKey.trim().toLowerCase();
  if (!search) return verifiedAgents.value;
  return verifiedAgents.value.filter(agent =>
    agent.name.toLowerCase().includes(search)
  );
});

const onAgentTap = agent => {
  selection();
  emit('selectAgent', agent);
};
</script>

<template>
  <div
    class="absolute bottom-full inset-x-0 z-30 max-h-52 overflow-y-auto overscroll-y-contain rounded-t-xl border-t border-x border-n-weak bg-white dark:bg-n-background shadow-lg"
  >
    <p
      class="px-4 pb-1 pt-3 text-xs font-semibold uppercase tracking-wide text-n-slate-10"
    >
      {{ t('MOBILE.MENTIONS.TITLE') }}
    </p>
    <template v-if="filteredAgents.length">
      <button
        v-for="agent in filteredAgents"
        :key="agent.id"
        v-haptic-tap
        class="flex w-full items-center gap-3 px-4 py-2.5 text-left active:bg-n-alpha-2"
        @click="onAgentTap(agent)"
      >
        <Avatar
          :src="agent.thumbnail"
          :name="agent.name"
          :size="32"
          rounded-full
        />
        <span class="min-w-0 flex-1">
          <span class="block truncate text-sm font-medium text-n-slate-12">
            {{ agent.name }}
          </span>
          <span class="block truncate text-xs text-n-slate-10">
            {{ agent.email }}
          </span>
        </span>
      </button>
    </template>
    <p v-else class="px-4 pb-4 pt-1 text-sm text-n-slate-10">
      {{ t('MOBILE.MENTIONS.EMPTY') }}
    </p>
  </div>
</template>
