<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStickers } from 'dashboard/composables/useStickers';
import MobileBottomSheet from './MobileBottomSheet.vue';

const props = defineProps({
  open: { type: Boolean, default: false },
  conversationId: { type: [Number, String], default: null },
});
const emit = defineEmits(['close']);

const { t } = useI18n();
const { stickers, recent, fetchLibrary, createFromFile, send } = useStickers();

const fileInput = ref(null);
const activeTab = ref('recent');

const tabs = [
  { key: 'recent', label: 'MOBILE.STICKERS.RECENT' },
  { key: 'all', label: 'MOBILE.STICKERS.ALL' },
];

const displayed = computed(() =>
  activeTab.value === 'recent' ? recent.value : stickers.value
);

onMounted(async () => {
  await fetchLibrary();
  activeTab.value = recent.value.length ? 'recent' : 'all';
});

const onSend = async sticker => {
  if (!props.conversationId) return;
  await send({ stickerId: sticker.id, conversationId: props.conversationId });
  emit('close');
};

const onPick = () => fileInput.value?.click();

const onFile = async e => {
  const file = e.target.files?.[0];
  if (file) await createFromFile(file);
  e.target.value = '';
};
</script>

<template>
  <MobileBottomSheet
    v-if="open"
    :title="t('MOBILE.STICKERS.TITLE')"
    @close="emit('close')"
  >
    <div class="flex items-center gap-1 mb-2">
      <button
        v-for="tab in tabs"
        :key="tab.key"
        class="px-3 py-1.5 text-sm font-medium rounded-full transition-colors"
        :class="
          activeTab === tab.key
            ? 'bg-n-alpha-2 text-n-slate-12'
            : 'text-n-slate-11'
        "
        @click="activeTab = tab.key"
      >
        {{ t(tab.label) }}
      </button>
    </div>
    <div class="grid grid-cols-4 gap-2 max-h-[50vh] overflow-y-auto">
      <button
        class="flex items-center justify-center border border-dashed rounded-lg aspect-square border-n-weak text-n-slate-11"
        :aria-label="t('MOBILE.STICKERS.ADD')"
        @click="onPick"
      >
        <span class="text-xl i-lucide-plus" aria-hidden="true" />
      </button>
      <button
        v-for="sticker in displayed"
        :key="sticker.id"
        class="flex items-center justify-center rounded-lg aspect-square active:bg-n-alpha-2"
        @click="onSend(sticker)"
      >
        <img :src="sticker.url" alt="" class="object-contain w-full h-full" />
      </button>
    </div>
    <input
      ref="fileInput"
      type="file"
      accept="image/*"
      class="hidden"
      @change="onFile"
    />
  </MobileBottomSheet>
</template>
