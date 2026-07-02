<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import { useDossierSelection } from 'dashboard/composables/useDossierSelection';
import DossiersAPI from 'dashboard/api/dossiers';
import NextButton from 'dashboard/components-next/button/Button.vue';

const { t } = useI18n();
const currentChat = useMapGetter('getSelectedChat');
const {
  selectedIds,
  selectedCount,
  isGenerating,
  stop,
  selectAll,
  setGenerating,
} = useDossierSelection();

const conversationId = computed(() => currentChat.value?.id);
const orderedMessageIds = computed(() =>
  (currentChat.value?.messages || []).map(message => message.id)
);

// Fire-and-forget: enqueue and release the UI right away. The ZIP arrives as a
// private note in this conversation when ready (errors are posted there too),
// so the agent does not need to keep the chat open.
const generateDossier = async () => {
  if (!selectedCount.value || isGenerating.value) return;
  setGenerating(true);
  try {
    await DossiersAPI.create(conversationId.value, selectedIds.value);
    useAlert(t('CONVERSATION.DOSSIER.QUEUED'));
    stop();
  } catch (error) {
    useAlert(t('CONVERSATION.DOSSIER.ERROR'));
    setGenerating(false);
  }
};
</script>

<template>
  <div
    class="flex items-center gap-3 px-4 py-2 border-t border-n-weak bg-n-solid-2"
  >
    <span class="text-sm font-medium text-n-slate-12">
      {{ t('CONVERSATION.DOSSIER.SELECTED', { count: selectedCount }) }}
    </span>
    <span class="hidden text-xs md:inline text-n-slate-11">
      {{ t('CONVERSATION.DOSSIER.HINT') }}
    </span>
    <div class="flex items-center gap-2 ml-auto">
      <NextButton
        sm
        slate
        faded
        :label="t('CONVERSATION.DOSSIER.SELECT_ALL')"
        :disabled="isGenerating"
        @click="selectAll(orderedMessageIds)"
      />
      <NextButton
        sm
        slate
        ghost
        :label="t('CONVERSATION.DOSSIER.CANCEL')"
        :disabled="isGenerating"
        @click="stop"
      />
      <NextButton
        sm
        blue
        icon="i-ph-file-zip"
        :label="t('CONVERSATION.DOSSIER.DOWNLOAD')"
        :is-loading="isGenerating"
        :disabled="!selectedCount || isGenerating"
        @click="generateDossier"
      />
    </div>
  </div>
</template>
