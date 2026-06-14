import { ref } from 'vue';
import StickersAPI from 'dashboard/api/stickers';
import { useAlert } from 'dashboard/composables';

export function useStickers() {
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

  const createFromFile = async file => {
    const formData = new FormData();
    formData.append('file', file);
    const { data } = await StickersAPI.create(formData);
    stickers.value = [data, ...stickers.value];
    return data;
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
