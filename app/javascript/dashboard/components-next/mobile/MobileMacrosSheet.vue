<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert, useTrack } from 'dashboard/composables';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useHaptics } from 'dashboard/composables/useHaptics';
import { CONVERSATION_EVENTS } from 'dashboard/helper/AnalyticsHelper/events';
import MobileBottomSheet from './MobileBottomSheet.vue';
import { vHapticTap } from './hapticTap';

const props = defineProps({
  open: {
    type: Boolean,
    default: false,
  },
  conversationId: {
    type: Number,
    required: true,
  },
});

const emit = defineEmits(['close']);

const store = useStore();
const { t } = useI18n();
const { medium } = useHaptics();

const macros = useMapGetter('macros/getMacros');
const uiFlags = useMapGetter('macros/getUIFlags');

const executingMacroId = ref(null);

const isLoading = computed(
  () => uiFlags.value.isFetching && !macros.value.length
);

watch(
  () => props.open,
  isOpen => {
    if (!isOpen) return;
    executingMacroId.value = null;
    store.dispatch('macros/get');
  }
);

const runMacro = async macro => {
  if (executingMacroId.value) return;

  // Haptic fires at tap time: iOS drops the Taptic switch trick once the
  // user activation expires across an await.
  medium();
  executingMacroId.value = macro.id;
  try {
    await store.dispatch('macros/execute', {
      macroId: macro.id,
      conversationIds: [props.conversationId],
    });
    useTrack(CONVERSATION_EVENTS.EXECUTED_A_MACRO);
    useAlert(t('MOBILE.MACROS.SUCCESS'));
    emit('close');
  } catch (error) {
    useAlert(t('MOBILE.MACROS.ERROR'));
  } finally {
    executingMacroId.value = null;
  }
};
</script>

<template>
  <MobileBottomSheet
    v-if="open"
    :title="t('MOBILE.MACROS.TITLE')"
    @close="emit('close')"
  >
    <p v-if="isLoading" class="px-1 py-2 text-sm text-n-slate-10">
      {{ t('MOBILE.MACROS.LOADING') }}
    </p>
    <p v-else-if="!macros.length" class="px-1 py-2 text-sm text-n-slate-10">
      {{ t('MOBILE.MACROS.EMPTY') }}
    </p>
    <div v-else class="-mx-4 -mt-4 divide-y divide-n-weak">
      <button
        v-for="macro in macros"
        :key="macro.id"
        v-haptic-tap
        class="flex w-full items-center gap-3 px-5 py-3.5 text-left active:bg-n-alpha-2 disabled:opacity-50"
        :disabled="Boolean(executingMacroId)"
        @click="runMacro(macro)"
      >
        <span
          class="flex size-9 shrink-0 items-center justify-center rounded-full bg-n-blue-2 text-n-blue-10"
        >
          <span class="i-lucide-zap size-5" />
        </span>
        <span
          class="min-w-0 flex-1 truncate text-base font-medium text-n-slate-12"
        >
          {{ macro.name }}
        </span>
        <span
          class="size-5 shrink-0 text-n-slate-9"
          :class="
            executingMacroId === macro.id
              ? 'i-lucide-loader-circle animate-spin'
              : 'i-lucide-play'
          "
        />
      </button>
    </div>
  </MobileBottomSheet>
</template>
