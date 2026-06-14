<script setup>
import { ref, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStickers } from 'dashboard/composables/useStickers';

const props = defineProps({
  conversationId: { type: [Number, String], required: true },
});
const emit = defineEmits(['close']);

const { t } = useI18n();
const { stickers, recent, isLoading, fetchLibrary, createFromFile, send } =
  useStickers();

const fileInput = ref(null);

onMounted(fetchLibrary);

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
</script>

<template>
  <div
    class="flex flex-col w-80 max-h-96 overflow-hidden border shadow-lg bg-n-background border-n-weak rounded-xl"
  >
    <div
      class="flex items-center justify-between px-3 py-2 border-b border-n-weak"
    >
      <span class="text-sm font-medium text-n-slate-12">{{
        t('STICKERS.TITLE')
      }}</span>
      <button class="text-xs text-n-brand" @click="onPick">
        {{ t('STICKERS.ADD') }}
      </button>
    </div>
    <div v-if="isLoading" class="p-4 text-sm text-center text-n-slate-11">
      {{ t('STICKERS.LOADING') }}
    </div>
    <div v-else class="grid grid-cols-4 gap-2 p-3 overflow-y-auto">
      <button
        v-for="sticker in [...recent, ...stickers]"
        :key="sticker.id"
        class="flex items-center justify-center rounded-lg aspect-square hover:bg-n-alpha-2"
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
  </div>
</template>
