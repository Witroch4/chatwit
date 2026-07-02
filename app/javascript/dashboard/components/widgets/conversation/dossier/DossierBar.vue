<script setup>
import { computed, onBeforeUnmount } from 'vue';
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

const POLL_INTERVAL_MS = 2000;
const MAX_POLL_ATTEMPTS = 150; // ~5 minutes

const conversationId = computed(() => currentChat.value?.id);
const orderedMessageIds = computed(() =>
  (currentChat.value?.messages || []).map(message => message.id)
);

let cancelled = false;
onBeforeUnmount(() => {
  cancelled = true;
});

const sleep = ms =>
  new Promise(resolve => {
    setTimeout(resolve, ms);
  });

const triggerDownload = (url, filename) => {
  const link = document.createElement('a');
  link.href = url;
  link.download = filename || '';
  link.rel = 'noopener';
  document.body.appendChild(link);
  link.click();
  document.body.removeChild(link);
};

const pollUntilReady = async (chatId, dossierId) => {
  for (let attempt = 0; attempt < MAX_POLL_ATTEMPTS; attempt += 1) {
    // eslint-disable-next-line no-await-in-loop
    await sleep(POLL_INTERVAL_MS);
    if (cancelled) return null;
    // eslint-disable-next-line no-await-in-loop
    const { data } = await DossiersAPI.status(chatId, dossierId);
    if (data.status === 'completed') return data;
    if (data.status === 'failed') {
      throw new Error(data.error || 'dossier generation failed');
    }
  }
  throw new Error('dossier generation timed out');
};

const downloadDossier = async () => {
  if (!selectedCount.value || isGenerating.value) return;
  const chatId = conversationId.value;
  setGenerating(true);
  try {
    const { data } = await DossiersAPI.create(chatId, selectedIds.value);
    const result = await pollUntilReady(chatId, data.id);
    if (!result) return;
    triggerDownload(result.url, result.filename);
    useAlert(t('CONVERSATION.DOSSIER.SUCCESS'));
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
        :label="
          isGenerating
            ? t('CONVERSATION.DOSSIER.GENERATING')
            : t('CONVERSATION.DOSSIER.DOWNLOAD')
        "
        :is-loading="isGenerating"
        :disabled="!selectedCount || isGenerating"
        @click="downloadDossier"
      />
    </div>
  </div>
</template>
