<script setup>
import { ref, computed, watch, onMounted, onUnmounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { useHaptics } from 'dashboard/composables/useHaptics';
import { useAlert } from 'dashboard/composables';
import { useAppBadge } from './useAppBadge';
import { useOfflineOutbox } from './useOfflineOutbox';
import { consumeMobileTabDeepLink } from './mobileDeepLink';
import { withViewTransition, afterNextNavigation } from './viewTransition';
import {
  consumeMobileShareText,
  setShareComposerPrefill,
} from './mobileShareTarget';
import MobileActionPickerSheet from './MobileActionPickerSheet.vue';
import MobileBottomTabBar from './MobileBottomTabBar.vue';
import MobileInboxView from './MobileInboxView.vue';
import MobileConversationList from './MobileConversationList.vue';
import MobileChatView from './MobileChatView.vue';
import MobileSettingsView from './MobileSettingsView.vue';

const route = useRoute();
const router = useRouter();
const { t } = useI18n();
const { accountScopedRoute } = useAccount();
const { selection } = useHaptics();

useAppBadge();
useOfflineOutbox({
  onFlushed: count => useAlert(t('MOBILE.OFFLINE.FLUSHED', { count })),
});

const activeTab = ref(1);

// Web Share Target (Android): texto compartilhado aguardando escolha de conversa.
const shareText = ref(null);

const allConversations = useMapGetter('getAllConversations');

const shareTargetItems = computed(() => {
  return [...allConversations.value]
    .sort((a, b) => (b.last_activity_at || 0) - (a.last_activity_at || 0))
    .slice(0, 20)
    .map(chat => {
      const sender = chat.meta?.sender || {};
      return {
        key: chat.id,
        label: sender.name || t('MOBILE.SHARE_TARGET.UNNAMED'),
        name: sender.name,
        avatar: sender.thumbnail,
        description: chat.last_non_activity_message?.content || '',
      };
    });
});

const onShareSelect = item => {
  selection();
  setShareComposerPrefill(shareText.value);
  shareText.value = null;
  router.push(
    accountScopedRoute(
      'inbox_conversation',
      { conversation_id: item.key },
      { focus_reply: '1' }
    )
  );
};

const INBOX_ROUTES = ['inbox_view', 'inbox_view_conversation'];

const SETTINGS_ROUTES = [
  'general_settings_index',
  'settings_inbox_list',
  'agent_list',
];

const activeChatId = computed(() => {
  const id =
    route.params.conversationId ||
    route.params.conversation_id ||
    route.params.id;
  return id ? Number(id) : null;
});

const isInChatView = computed(() => {
  return activeChatId.value !== null && activeChatId.value > 0;
});

const syncTabFromRoute = () => {
  const name = route.name;
  if (INBOX_ROUTES.includes(name)) {
    activeTab.value = 0;
  } else if (SETTINGS_ROUTES.includes(name)) {
    activeTab.value = 2;
  } else {
    activeTab.value = 1;
  }
};

watch(() => route.name, syncTabFromRoute, { immediate: true });

const onTabChange = tabId => {
  activeTab.value = tabId;
  if (tabId === 0) {
    router.push(accountScopedRoute('inbox_view'));
  } else if (tabId === 1) {
    router.push(accountScopedRoute('home'));
  } else if (tabId === 2) {
    router.push(accountScopedRoute('general_settings_index'));
  }
};

const onOpenConversation = conversationId => {
  withViewTransition(() =>
    router.push(
      accountScopedRoute('inbox_conversation', {
        conversation_id: conversationId,
      })
    )
  );
};

const isChatSwiping = ref(false);
const chatSwipeProgress = ref(0);

const navigateBack = () => {
  if (window.history.state?.back) {
    router.back();
    // router.back não retorna promise; aguarda a navegação para a
    // view transition capturar o novo estado do DOM.
    return afterNextNavigation(router);
  }
  return router.replace(accountScopedRoute('home'));
};

const onBack = () => {
  // O swipe-back já anima a saída do chat; view transition apenas
  // quando o back vem do botão (sem animação própria).
  if (isChatSwiping.value) {
    navigateBack();
    return;
  }
  withViewTransition(navigateBack);
};

const onSwipeProgress = progress => {
  chatSwipeProgress.value = progress;
  isChatSwiping.value = progress > 0;
};

const onSwipeEnd = () => {
  chatSwipeProgress.value = 0;
  isChatSwiping.value = false;
};

// The swipe flag lives here but is owned by MobileChatView, and the successful
// swipe-back destroys that view before its watcher can emit `swipeEnd` — the
// signal is lost and the flag stays true. A stuck flag brings the tab bar back
// over the chat (`v-show` below), and since the bar is `fixed bottom-0 z-50` it
// covers the composer: the user lands in a chat with no way to reply until a
// full reload. No chat view means no swipe, so assert that here instead of
// trusting the child to always report back.
watch(isInChatView, inChatView => {
  if (!inChatView) onSwipeEnd();
});

const bgDimStyle = computed(() => ({
  opacity: chatSwipeProgress.value * 0.3,
}));

// iOS PWA standalone: when restored from bfcache, JS event handlers
// may not be re-attached, making the page visually correct but non-interactive.
// Force a reload to re-hydrate the app.
const isStandalone =
  window.matchMedia('(display-mode: standalone)').matches ||
  window.navigator.standalone === true;

const onPageShow = event => {
  if (event.persisted) {
    window.location.reload();
  }
};

// Rotas-alvo dos atalhos do ícone (manifest shortcuts, Android long-press).
const DEEP_LINK_ROUTES = {
  inbox: 'inbox_view',
  conversations: 'home',
  settings: 'general_settings_index',
};

onMounted(() => {
  if (isStandalone) {
    window.addEventListener('pageshow', onPageShow);
  }

  const deepLinkRoute = DEEP_LINK_ROUTES[consumeMobileTabDeepLink()];
  if (deepLinkRoute) {
    router.replace(accountScopedRoute(deepLinkRoute));
  }

  // Share target: abre a tab Conversas com o sheet "Compartilhar em...".
  const sharedText = consumeMobileShareText();
  if (sharedText) {
    shareText.value = sharedText;
    router.replace(accountScopedRoute('home'));
  }
});

onUnmounted(() => {
  if (isStandalone) {
    window.removeEventListener('pageshow', onPageShow);
  }
});
</script>

<template>
  <div
    class="flex flex-col w-full h-full bg-n-surface-1 touch-manipulation [-webkit-tap-highlight-color:transparent]"
  >
    <div class="relative flex-1 overflow-hidden">
      <!-- Layer 0: Tab content (always rendered, sits behind chat) -->
      <div
        class="absolute inset-0 z-0 pb-[52px]"
        :class="{ 'pointer-events-none': isInChatView && !isChatSwiping }"
      >
        <!-- KeepAlive caches each tab instance after its first visit, so
             switching tabs no longer unmounts/remounts the view. Without it,
             every tab switch re-ran onMounted -> emptyAllConversations + full
             refetch (white flash, "reload from scratch"). Now each list fetches
             once and the global websocket keeps the store fresh, matching the
             native app's load-once-then-live-update feel. -->
        <KeepAlive>
          <MobileInboxView
            v-if="activeTab === 0"
            @open-conversation="onOpenConversation"
          />
          <MobileConversationList
            v-else-if="activeTab === 1"
            @open-conversation="onOpenConversation"
          />
          <MobileSettingsView v-else />
        </KeepAlive>
      </div>

      <!-- Dim overlay on background during swipe -->
      <div
        v-if="isChatSwiping"
        class="absolute inset-0 z-[5] bg-black pointer-events-none"
        :style="bgDimStyle"
      />

      <!-- Layer 1: Chat view (overlays on top) -->
      <div v-if="isInChatView" class="absolute inset-0 z-10">
        <MobileChatView
          :conversation-id="activeChatId"
          @back="onBack"
          @swipe-progress="onSwipeProgress"
          @swipe-end="onSwipeEnd"
        />
      </div>
    </div>
    <MobileBottomTabBar
      v-show="!isInChatView || isChatSwiping"
      :active-tab="activeTab"
      @change="onTabChange"
    />
    <!-- Web Share Target (Android): escolher conversa para o conteúdo compartilhado -->
    <MobileActionPickerSheet
      :open="!!shareText"
      :title="t('MOBILE.SHARE_TARGET.TITLE')"
      :items="shareTargetItems"
      :search-placeholder="t('MOBILE.SHARE_TARGET.SEARCH')"
      :empty-text="t('MOBILE.SHARE_TARGET.EMPTY')"
      @close="shareText = null"
      @select="onShareSelect"
    />
  </div>
</template>
