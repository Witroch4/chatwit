<script setup>
import { ref, computed, watch, onMounted, onBeforeUnmount } from 'vue';
import { useDebounceFn } from '@vueuse/core';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useHaptics } from 'dashboard/composables/useHaptics';
import { dynamicTime } from 'shared/helpers/timeHelper';
import MobilePetalLoader from './MobilePetalLoader.vue';
import { vHapticTap } from './hapticTap';

const emit = defineEmits(['close', 'openConversation']);

const store = useStore();
const { t } = useI18n();
const { light, selection } = useHaptics();

const query = ref('');
const inputRef = ref(null);

const conversationRecords = useMapGetter(
  'conversationSearch/getConversationRecords'
);
const messageRecords = useMapGetter('conversationSearch/getMessageRecords');
const contactRecords = useMapGetter('conversationSearch/getContactRecords');
const uiFlags = useMapGetter('conversationSearch/getUIFlags');

const isFetching = computed(() => {
  const {
    isFetching: fetching,
    contact,
    conversation,
    message,
  } = uiFlags.value;
  return (
    fetching ||
    contact.isFetching ||
    conversation.isFetching ||
    message.isFetching
  );
});

const totalResults = computed(() => {
  return (
    conversationRecords.value.length +
    messageRecords.value.length +
    contactRecords.value.length
  );
});

const showHint = computed(() => !query.value.trim());
const showNoResults = computed(() => {
  return (
    !showHint.value &&
    !isFetching.value &&
    uiFlags.value.isSearchCompleted &&
    totalResults.value === 0
  );
});

const runSearch = useDebounceFn(q => {
  store.dispatch('conversationSearch/clearSearchResults');
  if (!q) return;
  store.dispatch('conversationSearch/fullSearch', { q, page: 1 });
}, 300);

watch(query, newQuery => runSearch(newQuery.trim()));

const onClear = () => {
  light();
  query.value = '';
  store.dispatch('conversationSearch/clearSearchResults');
  inputRef.value?.focus();
};

const onClose = () => {
  light();
  emit('close');
};

const onResultTap = conversationId => {
  if (!conversationId) return;
  selection();
  emit('openConversation', conversationId);
  emit('close');
};

const resultTime = timestamp => {
  if (!timestamp) return '';
  return dynamicTime(timestamp);
};

onMounted(() => {
  store.dispatch('conversationSearch/clearSearchResults');
  inputRef.value?.focus();
});

onBeforeUnmount(() => {
  store.dispatch('conversationSearch/clearSearchResults');
});
</script>

<template>
  <Teleport to="body">
    <div
      class="fixed inset-0 z-[70] flex flex-col bg-white dark:bg-n-background"
    >
      <!-- Search input bar -->
      <div
        class="flex flex-shrink-0 items-center gap-1.5 border-b border-n-weak px-2 py-2 pt-[calc(env(safe-area-inset-top)+0.5rem)]"
      >
        <button
          v-haptic-tap
          class="flex size-9 flex-shrink-0 items-center justify-center rounded-lg text-n-slate-11 active:bg-n-alpha-2"
          :aria-label="t('MOBILE.SEARCH.BACK')"
          @click="onClose"
        >
          <span class="i-lucide-arrow-left size-5" />
        </button>
        <div
          class="flex h-10 flex-1 items-center gap-2 rounded-xl bg-n-alpha-2 px-3"
        >
          <span class="i-lucide-search size-4 flex-shrink-0 text-n-slate-10" />
          <input
            ref="inputRef"
            v-model="query"
            type="search"
            autocomplete="off"
            autofocus
            :placeholder="t('MOBILE.SEARCH.PLACEHOLDER')"
            class="h-full min-w-0 flex-1 bg-transparent text-sm text-n-slate-12 outline-none placeholder:text-n-slate-9 [&::-webkit-search-cancel-button]:hidden"
          />
          <button
            v-if="query"
            v-haptic-tap
            class="flex size-6 flex-shrink-0 items-center justify-center rounded-full text-n-slate-10 active:bg-n-alpha-2"
            :aria-label="t('MOBILE.SEARCH.CLEAR')"
            @click="onClear"
          >
            <span class="i-lucide-x size-4" />
          </button>
        </div>
      </div>

      <!-- Results -->
      <div
        class="flex-1 overflow-y-auto overscroll-y-contain pb-[env(safe-area-inset-bottom)]"
      >
        <!-- Empty hint -->
        <div
          v-if="showHint"
          class="flex flex-col items-center gap-2 px-6 py-12 text-center"
        >
          <span class="i-lucide-search size-8 text-n-slate-8" />
          <p class="text-sm text-n-slate-10">
            {{ t('MOBILE.SEARCH.HINT') }}
          </p>
        </div>

        <!-- Loading -->
        <div
          v-else-if="isFetching && !totalResults"
          class="flex items-center justify-center py-12"
        >
          <MobilePetalLoader spinning />
        </div>

        <!-- No results -->
        <div
          v-else-if="showNoResults"
          class="flex flex-col items-center gap-2 px-6 py-12 text-center"
        >
          <span class="i-lucide-search-x size-8 text-n-slate-8" />
          <p class="text-sm text-n-slate-10">
            {{ t('MOBILE.SEARCH.NO_RESULTS', { query: query.trim() }) }}
          </p>
        </div>

        <template v-else>
          <!-- Conversations -->
          <section v-if="conversationRecords.length">
            <h2
              class="px-4 pb-1 pt-4 text-xs font-semibold uppercase tracking-wide text-n-slate-10"
            >
              {{ t('MOBILE.SEARCH.CONVERSATIONS') }}
            </h2>
            <button
              v-for="conv in conversationRecords"
              :key="`conversation-${conv.id}`"
              v-haptic-tap
              class="flex w-full items-center gap-3 px-4 py-3 text-left active:bg-n-alpha-2"
              @click="onResultTap(conv.id)"
            >
              <span
                class="flex size-9 flex-shrink-0 items-center justify-center rounded-full bg-n-blue-2 text-n-blue-10"
              >
                <span class="i-lucide-message-circle size-4" />
              </span>
              <span class="min-w-0 flex-1">
                <span
                  class="block truncate text-sm font-medium text-n-slate-12"
                >
                  {{ conv.contact?.name || `#${conv.id}` }}
                </span>
                <span
                  v-if="conv.contact?.email"
                  class="block truncate text-xs text-n-slate-10"
                >
                  {{ conv.contact.email }}
                </span>
              </span>
              <span class="flex-shrink-0 text-xs text-n-slate-10">
                {{ resultTime(conv.created_at) }}
              </span>
            </button>
          </section>

          <!-- Messages -->
          <section v-if="messageRecords.length">
            <h2
              class="px-4 pb-1 pt-4 text-xs font-semibold uppercase tracking-wide text-n-slate-10"
            >
              {{ t('MOBILE.SEARCH.MESSAGES') }}
            </h2>
            <button
              v-for="message in messageRecords"
              :key="`message-${message.id}`"
              v-haptic-tap
              class="flex w-full items-center gap-3 px-4 py-3 text-left active:bg-n-alpha-2"
              @click="onResultTap(message.conversation_id)"
            >
              <span
                class="flex size-9 flex-shrink-0 items-center justify-center rounded-full bg-n-teal-3 text-n-teal-10"
              >
                <span class="i-lucide-message-square-text size-4" />
              </span>
              <span class="min-w-0 flex-1">
                <span class="block truncate text-sm text-n-slate-12">
                  {{ message.content }}
                </span>
                <span
                  v-if="message.sender?.name"
                  class="block truncate text-xs text-n-slate-10"
                >
                  {{ message.sender.name }}
                </span>
              </span>
              <span class="flex-shrink-0 text-xs text-n-slate-10">
                {{ resultTime(message.created_at) }}
              </span>
            </button>
          </section>

          <!-- Contacts -->
          <section v-if="contactRecords.length">
            <h2
              class="px-4 pb-1 pt-4 text-xs font-semibold uppercase tracking-wide text-n-slate-10"
            >
              {{ t('MOBILE.SEARCH.CONTACTS') }}
            </h2>
            <div
              v-for="contact in contactRecords"
              :key="`contact-${contact.id}`"
              class="flex w-full items-center gap-3 px-4 py-3 text-left"
            >
              <span
                class="flex size-9 flex-shrink-0 items-center justify-center rounded-full bg-n-amber-3 text-n-amber-11"
              >
                <span class="i-lucide-user-round size-4" />
              </span>
              <span class="min-w-0 flex-1">
                <span
                  class="block truncate text-sm font-medium text-n-slate-12"
                >
                  {{ contact.name }}
                </span>
                <span
                  v-if="contact.email || contact.phone_number"
                  class="block truncate text-xs text-n-slate-10"
                >
                  {{ contact.email || contact.phone_number }}
                </span>
              </span>
            </div>
          </section>
        </template>
      </div>
    </div>
  </Teleport>
</template>
