import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import StickersAPI from 'dashboard/api/stickers';
import { useAlert } from 'dashboard/composables';

export function useStickers() {
  const { t } = useI18n();
  const stickers = ref([]);
  const recent = ref([]);
  const isLoading = ref(false);

  const fetchLibrary = async () => {
    isLoading.value = true;
    try {
      const [{ data: all }, { data: recents }] = await Promise.all([
        StickersAPI.get(),
        StickersAPI.getRecent(),
      ]);
      stickers.value = all;
      recent.value = recents;
    } finally {
      isLoading.value = false;
    }
  };

  const replaceSticker = data => {
    const idx = stickers.value.findIndex(s => s.id === data.id);
    if (idx !== -1) stickers.value.splice(idx, 1, data);
  };

  // Optimistic flow: a heavy sticker comes back as `processing` (original shown as
  // preview) while it converts in the background. Poll until it's ready/failed.
  const pollUntilReady = (sticker, attempt = 0) => {
    setTimeout(async () => {
      let data;
      try {
        ({ data } = await StickersAPI.show(sticker.id));
      } catch {
        return;
      }
      replaceSticker(data);
      if (data.status === 'ready') {
        useAlert(t('STICKERS.SAVED'));
      } else if (data.status === 'failed') {
        useAlert(t('STICKERS.SAVE_FAILED'));
        stickers.value = stickers.value.filter(s => s.id !== sticker.id);
      } else if (attempt < 30) {
        pollUntilReady(sticker, attempt + 1);
      }
    }, 1500);
  };

  const createFromFile = async file => {
    isLoading.value = true;
    try {
      const formData = new FormData();
      formData.append('file', file);
      const { data } = await StickersAPI.create(formData);
      stickers.value = [data, ...stickers.value];
      if (data.status === 'processing') {
        pollUntilReady(data);
      } else {
        useAlert(t('STICKERS.SAVED'));
      }
      return data;
    } catch (e) {
      useAlert(e?.response?.data?.error || t('STICKERS.SAVE_FAILED'));
      throw e;
    } finally {
      isLoading.value = false;
    }
  };

  const createFromAttachment = async attachmentId => {
    const { data } = await StickersAPI.createFromAttachment(attachmentId);
    stickers.value = [data, ...stickers.value];
    return data;
  };

  const remove = async id => {
    await StickersAPI.delete(id);
    stickers.value = stickers.value.filter(s => s.id !== id);
    recent.value = recent.value.filter(s => s.id !== id);
  };

  const send = async ({ stickerId, conversationId }) => {
    try {
      await StickersAPI.send({ stickerId, conversationId });
    } catch (e) {
      useAlert(e?.response?.data?.error);
      throw e;
    }
  };

  return {
    stickers,
    recent,
    isLoading,
    fetchLibrary,
    createFromFile,
    createFromAttachment,
    remove,
    send,
  };
}
