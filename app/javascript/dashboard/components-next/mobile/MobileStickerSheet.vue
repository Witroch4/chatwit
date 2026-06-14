<script setup>
import { ref, onMounted } from 'vue';
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

onMounted(fetchLibrary);

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
    <div class="grid grid-cols-4 gap-2 max-h-[50vh] overflow-y-auto">
      <button
        class="flex items-center justify-center border border-dashed rounded-lg aspect-square border-n-weak text-n-slate-11"
        :aria-label="t('MOBILE.STICKERS.ADD')"
        @click="onPick"
      >
        <span class="text-xl i-lucide-plus" aria-hidden="true" />
      </button>
      <button
        v-for="sticker in [...recent, ...stickers]"
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
