<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStickers } from 'dashboard/composables/useStickers';

const props = defineProps({
  conversationId: { type: [Number, String], required: true },
});
const emit = defineEmits(['close']);

const { t } = useI18n();
const {
  stickers,
  recent,
  isLoading,
  fetchLibrary,
  createFromFile,
  send,
  remove,
} = useStickers();

const fileInput = ref(null);
const activeTab = ref('recent');

const tabs = [
  { key: 'recent', label: 'STICKERS.RECENT' },
  { key: 'all', label: 'STICKERS.ALL' },
];

const displayed = computed(() =>
  activeTab.value === 'recent' ? recent.value : stickers.value
);

onMounted(async () => {
  await fetchLibrary();
  activeTab.value = recent.value.length ? 'recent' : 'all';
});

const onSend = async sticker => {
  await send({ stickerId: sticker.id, conversationId: props.conversationId });
  emit('close');
};

const onPick = () => fileInput.value?.click();

const onFile = async e => {
  const file = e.target.files?.[0];
  if (file) await createFromFile(file);
  e.target.value = '';
};

const onDelete = sticker => remove(sticker.id);
</script>

<template>
  <div
    class="flex flex-col w-80 max-h-96 overflow-hidden border shadow-lg bg-n-background border-n-weak rounded-xl"
  >
    <div
      class="flex items-center justify-between px-3 py-2 border-b border-n-weak"
    >
      <div class="flex gap-1">
        <button
          v-for="tab in tabs"
          :key="tab.key"
          class="px-2 py-1 text-xs font-medium rounded-md transition-colors"
          :class="
            activeTab === tab.key
              ? 'bg-n-alpha-2 text-n-slate-12'
              : 'text-n-slate-11 hover:text-n-slate-12'
          "
          @click="activeTab = tab.key"
        >
          {{ t(tab.label) }}
        </button>
      </div>
      <button class="text-xs text-n-brand" @click="onPick">
        {{ t('STICKERS.ADD') }}
      </button>
    </div>
    <div v-if="isLoading" class="p-4 text-sm text-center text-n-slate-11">
      {{ t('STICKERS.LOADING') }}
    </div>
    <div
      v-else-if="!displayed.length"
      class="p-6 text-sm text-center text-n-slate-11"
    >
      {{ t('STICKERS.EMPTY') }}
    </div>
    <div v-else class="grid grid-cols-4 gap-2 p-3 overflow-y-auto">
      <div
        v-for="sticker in displayed"
        :key="sticker.id"
        class="relative group aspect-square"
      >
        <button
          class="flex items-center justify-center w-full h-full rounded-lg hover:bg-n-alpha-2"
          @click="onSend(sticker)"
          @contextmenu.prevent="onDelete(sticker)"
        >
          <img :src="sticker.url" alt="" class="object-contain w-full h-full" />
        </button>
        <button
          class="absolute flex items-center justify-center w-5 h-5 transition-opacity rounded-full opacity-0 -top-1 -right-1 bg-n-slate-12 text-n-slate-1 group-hover:opacity-100"
          :aria-label="t('STICKERS.DELETE')"
          @click.stop="onDelete(sticker)"
        >
          <span class="text-xs i-lucide-x" aria-hidden="true" />
        </button>
      </div>
    </div>
    <input
      ref="fileInput"
      type="file"
      accept="image/*"
      class="hidden"
      @change="onFile"
    />
  </div>
</template>
