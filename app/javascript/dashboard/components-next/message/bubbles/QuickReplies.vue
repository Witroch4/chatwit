<script setup>
import { computed, onMounted, onErrorCaptured } from 'vue';
import { useMessageContext } from '../provider.js';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import BaseBubble from './Base.vue';

const { contentAttributes, id } = useMessageContext();

// Access feature flag from global config
const isRichDashboardEnabled = computed(() => {
  return window.globalConfig?.SOCIALWISE_RICH_DASHBOARD || false;
});

const items = computed(() => {
  return contentAttributes.value?.items || [];
});

const shouldRenderQuickReplies = computed(() => {
  return isRichDashboardEnabled.value && items.value.length > 0;
});

// Metrics tracking function
function trackMetric(name, labels) {
  if (window.analytics) {
    window.analytics.track(name, labels);
  }
  // Also log to console for debugging
  if (import.meta.env.MODE !== 'production') {
    // eslint-disable-next-line no-console
    console.log(`[QuickReplies] ${name}:`, labels);
  }
}

// Handle quick reply option clicks
const handleQuickReplyClick = item => {
  // Emit postback event with BUS_EVENTS.RICH_POSTBACK
  emitter.emit(BUS_EVENTS.RICH_POSTBACK, {
    messageId: id.value,
    payload: item.payload || item.value,
    text: item.title,
    type: 'quick_reply',
    timestamp: new Date().toISOString(),
  });

  trackMetric('cw_quick_replies_render_total', {
    error: 'false',
    type: 'option_click',
    message_id: id.value,
  });
};

// Track successful render on mount
onMounted(() => {
  if (shouldRenderQuickReplies.value) {
    trackMetric('cw_quick_replies_render_total', {
      error: 'false',
      type: 'render_success',
      options_count: items.value.length,
      message_id: id.value,
    });
  }
});

// Handle component errors
onErrorCaptured(err => {
  if (import.meta.env.MODE !== 'production') {
    // eslint-disable-next-line no-console
    console.error('QuickReplies error:', err);
  }
  trackMetric('cw_quick_replies_render_total', {
    error: 'true',
    type: 'component_error',
    message_id: id.value,
  });

  // Emit fallback event to parent
  emitter.emit('QUICK_REPLIES_FALLBACK', { messageId: id.value });
  return false;
});
</script>

<template>
  <template v-if="shouldRenderQuickReplies">
    <BaseBubble class="p-0 overflow-hidden">
      <div class="quick-replies-wrapper p-4">
        <div class="quick-replies-list">
          <button
            v-for="(item, index) in items"
            :key="index"
            class="quick-reply-option"
            role="button"
            :aria-label="`Quick reply option: ${item.title}`"
            @click="handleQuickReplyClick(item)"
          >
            <div class="quick-reply-content">
              <span class="quick-reply-title">{{ item.title }}</span>
              <span
                v-if="item.value && item.value !== item.title"
                class="quick-reply-value"
              >
                {{ item.value }}
              </span>
            </div>
          </button>
        </div>
      </div>
    </BaseBubble>
  </template>
</template>

<style scoped>
.quick-replies-wrapper {
  @apply max-w-full;
}

.quick-replies-list {
  @apply flex flex-col gap-2;
}

.quick-reply-option {
  @apply w-full text-left border border-n-slate-6 rounded-lg p-3 bg-n-slate-2 hover:bg-n-slate-3 cursor-pointer transition-colors duration-200 focus:outline-none focus:ring-2 focus:ring-n-solid-blue focus:ring-opacity-50;
}

.quick-reply-content {
  @apply flex flex-col gap-1;
}

.quick-reply-title {
  @apply font-medium text-n-slate-12 text-sm;
  word-break: break-word;
}

.quick-reply-value {
  @apply text-xs text-n-slate-11 font-mono bg-n-slate-4 px-2 py-1 rounded;
  word-break: break-word;
}
</style>
