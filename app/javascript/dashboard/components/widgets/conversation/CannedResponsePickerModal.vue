<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Draggable from 'vuedraggable';
import { useAlert } from 'dashboard/composables';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import Button from 'dashboard/components-next/button/Button.vue';
import { useMessageFormatter } from 'shared/composables/useMessageFormatter';

const emit = defineEmits(['close', 'select']);

const store = useStore();
const { t } = useI18n();
const { getPlainText } = useMessageFormatter();

const cannedResponses = useMapGetter('getCannedResponses');
const uiFlags = useMapGetter('getUIFlags');

const localResponses = ref([]);
const isOrganizing = ref(false);
const isSavingOrder = ref(false);
const isLoading = computed(
  () => uiFlags.value.fetchingList && !cannedResponses.value.length
);

watch(
  cannedResponses,
  responses => {
    localResponses.value = [...responses];
  },
  { immediate: true }
);

const toggleOrganizing = () => {
  isOrganizing.value = !isOrganizing.value;
};

const dismiss = () => emit('close');

const selectResponse = response => {
  if (!isOrganizing.value) emit('select', response.content);
};

const getShortCode = response => `/${response.short_code}`;

const saveOrder = async () => {
  isSavingOrder.value = true;
  try {
    await store.dispatch(
      'reorderCannedResponses',
      localResponses.value.map(({ id }) => id)
    );
    isOrganizing.value = false;
  } catch {
    await store.dispatch('getCannedResponse');
    useAlert(t('CONVERSATION.REPLYBOX.CANNED_RESPONSES.REORDER_ERROR'));
  } finally {
    isSavingOrder.value = false;
  }
};

onMounted(() => {
  store.dispatch('getCannedResponse');
});
</script>

<template>
  <div class="relative flex h-auto flex-col overflow-hidden">
    <Button
      color="slate"
      variant="ghost"
      size="sm"
      icon="i-lucide-x"
      type="button"
      class="absolute right-4 top-4 z-10"
      :aria-label="t('GENERAL.CLOSE')"
      :title="t('GENERAL.CLOSE')"
      @click="dismiss"
    />

    <woot-modal-header
      :header-title="t('CONVERSATION.REPLYBOX.CANNED_RESPONSES.TITLE')"
      :header-content="t('CONVERSATION.REPLYBOX.CANNED_RESPONSES.DESCRIPTION')"
    />

    <div class="flex justify-end px-8 pt-4">
      <Button
        color="slate"
        variant="outline"
        size="sm"
        :label="
          isOrganizing
            ? t('CONVERSATION.REPLYBOX.CANNED_RESPONSES.DONE')
            : t('CONVERSATION.REPLYBOX.CANNED_RESPONSES.ORGANIZE')
        "
        :disabled="isSavingOrder"
        @click="toggleOrganizing"
      />
    </div>

    <div class="max-h-[28rem] overflow-y-auto px-8 py-4">
      <woot-loading-state v-if="isLoading" />

      <p
        v-else-if="!localResponses.length"
        class="py-8 text-center text-sm text-n-slate-11"
      >
        {{ t('CONVERSATION.REPLYBOX.CANNED_RESPONSES.EMPTY') }}
      </p>

      <Draggable
        v-else
        v-model="localResponses"
        :disabled="!isOrganizing || isSavingOrder"
        animation="200"
        ghost-class="opacity-50"
        handle=".canned-response-drag-handle"
        item-key="id"
        class="flex flex-col gap-2"
        @end="saveOrder"
      >
        <template #item="{ element }">
          <button
            type="button"
            class="flex w-full items-start gap-3 rounded-lg bg-n-alpha-black2 p-3 text-left outline outline-1 outline-n-weak transition-colors hover:bg-n-alpha-2 hover:outline-n-slate-6 focus-visible:outline-n-brand disabled:cursor-wait disabled:opacity-50"
            :class="{ 'cursor-default': isOrganizing }"
            :disabled="isSavingOrder"
            @click="selectResponse(element)"
          >
            <span
              v-if="isOrganizing"
              class="canned-response-drag-handle mt-0.5 cursor-grab text-n-slate-10 active:cursor-grabbing"
            >
              <span class="i-lucide-grip-vertical block size-5" />
            </span>

            <span class="min-w-0 flex-1">
              <span class="block text-sm font-medium text-n-slate-12">
                {{ getShortCode(element) }}
              </span>
              <span class="mt-1 block line-clamp-2 text-sm text-n-slate-11">
                {{ getPlainText(element.content) }}
              </span>
            </span>
          </button>
        </template>
      </Draggable>
    </div>
  </div>
</template>
