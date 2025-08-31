<script>
import { debounce } from '@chatwoot/utils';
import { mapGetters } from 'vuex';
import { useAlert } from 'dashboard/composables';

export default {
  name: 'StickerPicker',
  props: {
    conversationId: {
      type: [String, Number],
      required: true,
    },
    isVisible: {
      type: Boolean,
      default: false,
    },
  },
  emits: ['close', 'stickerSelected'],
  data() {
    return {
      activeTab: 'library',
      searchTerm: '',
      stickers: [],
      isLoading: false,
      isSearching: false,
      error: null,
      customPacks: [],
      tabs: [
        {
          key: 'library',
          label: this.$t('CONVERSATION.STICKER_PICKER.TABS.LIBRARY'),
          icon: 'i-ph-sticker',
        },
        {
          key: 'trending',
          label: this.$t('CONVERSATION.STICKER_PICKER.TABS.TRENDING'),
        },
        {
          key: 'search',
          label: this.$t('CONVERSATION.STICKER_PICKER.TABS.SEARCH'),
        },
        {
          key: 'recent',
          label: this.$t('CONVERSATION.STICKER_PICKER.TABS.RECENT'),
        },
      ],
    };
  },
  computed: {
    ...mapGetters({
      currentAccount: 'getCurrentAccount',
    }),
    emptyStateMessage() {
      switch (this.activeTab) {
        case 'library':
          return this.$t('CONVERSATION.STICKER_PICKER.EMPTY_STATES.LIBRARY');
        case 'trending':
          return this.$t('CONVERSATION.STICKER_PICKER.EMPTY_STATES.TRENDING');
        case 'search':
          return this.searchTerm
            ? this.$t('CONVERSATION.STICKER_PICKER.EMPTY_STATES.SEARCH_RESULTS')
            : this.$t('CONVERSATION.STICKER_PICKER.EMPTY_STATES.SEARCH_PROMPT');
        case 'recent':
          return this.$t('CONVERSATION.STICKER_PICKER.EMPTY_STATES.RECENT');
        default:
          return this.$t('CONVERSATION.STICKER_PICKER.EMPTY_STATES.DEFAULT');
      }
    },
  },
  watch: {
    isVisible(newValue) {
      if (newValue) {
        this.loadInitialData();
      }
    },
    activeTab() {
      this.loadTabData();
    },
  },
  created() {
    this.debouncedSearch = debounce(this.performSearch, 500);
  },
  mounted() {
    if (this.isVisible) {
      this.loadInitialData();
    }
  },
  methods: {
    async loadInitialData() {
      await this.loadCustomPacks();
      await this.loadTabData();
    },
    async loadCustomPacks() {
      try {
        const response = await window.axios.get(
          `/api/v1/accounts/${this.currentAccount.id}/stickers`,
          {
            params: { provider: 'custom', pack_name: null },
          }
        );

        // Group custom stickers by pack
        const packGroups = {};
        response.data.stickers.forEach(sticker => {
          const stickerPackName = sticker.meta?.sticker_pack || 'Default';
          if (!packGroups[stickerPackName]) {
            packGroups[stickerPackName] = [];
          }
          packGroups[stickerPackName].push(sticker);
        });

        // Add custom pack tabs
        this.customPacks = Object.keys(packGroups).map(stickerPackName => ({
          key: `pack_${stickerPackName}`,
          label: stickerPackName,
          stickers: packGroups[stickerPackName],
        }));

        // Add custom pack tabs to tabs array with shorter labels
        this.tabs = [
          {
            key: 'library',
            label: this.$t('CONVERSATION.STICKER_PICKER.TABS.LIBRARY'),
            icon: 'i-ph-sticker',
          },
          {
            key: 'trending',
            label: this.$t('CONVERSATION.STICKER_PICKER.TABS.TRENDING'),
          },
          {
            key: 'search',
            label: this.$t('CONVERSATION.STICKER_PICKER.TABS.SEARCH'),
          },
          {
            key: 'recent',
            label: this.$t('CONVERSATION.STICKER_PICKER.TABS.RECENT'),
          },
          ...this.customPacks.map(pack => ({
            ...pack,
            label:
              pack.label.length > 8
                ? pack.label.substring(0, 8) + '...'
                : pack.label,
          })),
        ];
      } catch (error) {
        // Failed to load custom packs
      }
    },
    async loadTabData() {
      this.error = null;
      this.isLoading = true;

      try {
        let response;

        if (this.activeTab === 'library') {
          response = await window.axios.get(
            `/api/v1/accounts/${this.currentAccount.id}/stickers`,
            {
              params: { provider: 'custom' },
            }
          );
        } else if (this.activeTab === 'trending') {
          response = await window.axios.get(
            `/api/v1/accounts/${this.currentAccount.id}/stickers`,
            {
              params: { provider: 'giphy' },
            }
          );
        } else if (this.activeTab === 'recent') {
          response = await window.axios.get(
            `/api/v1/accounts/${this.currentAccount.id}/stickers`,
            {
              params: { provider: 'recent' },
            }
          );
        } else if (this.activeTab.startsWith('pack_')) {
          const pack = this.customPacks.find(p => p.key === this.activeTab);
          this.stickers = pack ? pack.stickers : [];
          this.isLoading = false;
          return;
        }

        // Handle API response with error checking
        if (response?.data?.error) {
          this.handleApiError(response.data);
          return;
        }

        this.stickers = response?.data?.stickers || [];

        // If no stickers and it's trending tab, show helpful message
        if (this.stickers.length === 0 && this.activeTab === 'trending') {
          // No trending stickers available - this might be due to missing Giphy API key
        }
      } catch (error) {
        // Failed to load stickers
        this.handleLoadError(error);
      } finally {
        this.isLoading = false;
      }
    },
    async performSearch() {
      if (!this.searchTerm.trim()) {
        this.stickers = [];
        return;
      }

      this.isSearching = true;
      this.error = null;

      try {
        const response = await window.axios.get(
          `/api/v1/accounts/${this.currentAccount.id}/stickers`,
          {
            params: {
              provider: 'giphy',
              search_term: this.searchTerm.trim(),
            },
          }
        );

        // Handle API response with error checking
        if (response?.data?.error) {
          this.handleApiError(response.data);
          return;
        }

        this.stickers = response.data.stickers || [];
      } catch (error) {
        // Search failed
        this.handleSearchError(error);
      } finally {
        this.isSearching = false;
      }
    },
    switchTab(tabKey) {
      this.activeTab = tabKey;
      this.searchTerm = '';
      this.error = null;
    },
    async selectSticker(sticker) {
      // Close modal immediately for optimistic UI
      this.closeModal();
      this.$emit('stickerSelected', sticker);

      try {
        const response = await window.axios.post(
          `/api/v1/accounts/${this.currentAccount.id}/stickers/send_sticker`,
          {
            conversation_id: this.conversationId,
            sticker: {
              id: sticker.id,
              url: sticker.url,
              alt: sticker.alt,
              provider: sticker.provider,
            },
          }
        );

        if (response.data.success) {
          // Success is handled by backend message status updates via websocket
          // No need to show success alert as the message will appear with proper status
        } else {
          this.handleSendStickerError(response.data);
        }
      } catch (error) {
        // Failed to send sticker - show error to user
        this.handleSendStickerError(
          error.response?.data || { error: 'UNKNOWN_ERROR' }
        );
      }
    },
    closeModal() {
      this.$emit('close');
    },
    retryLoad() {
      this.loadTabData();
    },
    handleImageError(event) {
      // Hide broken images
      event.target.style.display = 'none';
    },
    handleApiError(errorData) {
      const errorCode = errorData.error_code || errorData.error;
      const userMessage = errorData.user_message || errorData.message;

      switch (errorCode) {
        case 'GIPHY_API_KEY_MISSING':
          this.error = this.$t(
            'CONVERSATION.STICKER_PICKER.ERRORS.GIPHY_NOT_CONFIGURED'
          );
          break;
        case 'GIPHY_RATE_LIMIT':
          this.error = this.$t('CONVERSATION.STICKER_PICKER.ERRORS.RATE_LIMIT');
          break;
        case 'GIPHY_UNAVAILABLE':
          this.error = this.$t(
            'CONVERSATION.STICKER_PICKER.ERRORS.SERVICE_UNAVAILABLE'
          );
          break;
        case 'CUSTOM_STICKERS_ERROR':
          this.error = this.$t(
            'CONVERSATION.STICKER_PICKER.ERRORS.CUSTOM_STICKERS_FAILED'
          );
          break;
        default:
          this.error =
            userMessage ||
            this.$t('CONVERSATION.STICKER_PICKER.ERRORS.LOAD_FAILED');
      }
    },
    handleLoadError(error) {
      if (error.response?.status === 503) {
        this.error = this.$t(
          'CONVERSATION.STICKER_PICKER.ERRORS.SERVICE_UNAVAILABLE'
        );
      } else if (error.response?.status === 429) {
        this.error = this.$t('CONVERSATION.STICKER_PICKER.ERRORS.RATE_LIMIT');
      } else if (error.response?.status >= 500) {
        this.error = this.$t('CONVERSATION.STICKER_PICKER.ERRORS.SERVER_ERROR');
      } else if (error.code === 'NETWORK_ERROR' || !navigator.onLine) {
        this.error = this.$t(
          'CONVERSATION.STICKER_PICKER.ERRORS.NETWORK_ERROR'
        );
      } else {
        this.error = this.$t('CONVERSATION.STICKER_PICKER.ERRORS.LOAD_FAILED');
      }
    },
    handleSearchError(error) {
      if (error.response?.status === 503) {
        this.error = this.$t(
          'CONVERSATION.STICKER_PICKER.ERRORS.SEARCH_SERVICE_UNAVAILABLE'
        );
      } else if (error.response?.status === 429) {
        this.error = this.$t(
          'CONVERSATION.STICKER_PICKER.ERRORS.SEARCH_RATE_LIMIT'
        );
      } else if (error.code === 'NETWORK_ERROR' || !navigator.onLine) {
        this.error = this.$t(
          'CONVERSATION.STICKER_PICKER.ERRORS.NETWORK_ERROR'
        );
      } else {
        this.error = this.$t(
          'CONVERSATION.STICKER_PICKER.ERRORS.SEARCH_FAILED'
        );
      }
    },
    handleSendStickerError(errorData) {
      const errorCode = errorData.error_code || errorData.error;
      const userMessage = errorData.user_message || errorData.message;

      let alertMessage;

      switch (errorCode) {
        case 'INVALID_CHANNEL_TYPE':
          alertMessage = this.$t(
            'CONVERSATION.STICKER_PICKER.ERRORS.INVALID_CHANNEL'
          );
          break;
        case 'CONVERSATION_NOT_FOUND':
          alertMessage = this.$t(
            'CONVERSATION.STICKER_PICKER.ERRORS.CONVERSATION_NOT_FOUND'
          );
          break;
        case 'MEDIA_UPLOAD_FAILED':
          alertMessage = this.$t(
            'CONVERSATION.STICKER_PICKER.ERRORS.UPLOAD_FAILED'
          );
          break;
        case 'WHATSAPP_RATE_LIMIT':
          alertMessage = this.$t(
            'CONVERSATION.STICKER_PICKER.ERRORS.WHATSAPP_RATE_LIMIT'
          );
          break;
        case 'WHATSAPP_INVALID_MEDIA':
          alertMessage = this.$t(
            'CONVERSATION.STICKER_PICKER.ERRORS.INVALID_STICKER_FORMAT'
          );
          break;
        case 'WHATSAPP_AUTH_ERROR':
          alertMessage = this.$t(
            'CONVERSATION.STICKER_PICKER.ERRORS.WHATSAPP_AUTH_ERROR'
          );
          break;
        case 'NETWORK_ERROR':
          alertMessage = this.$t(
            'CONVERSATION.STICKER_PICKER.ERRORS.NETWORK_ERROR'
          );
          break;
        case 'TIMEOUT_ERROR':
          alertMessage = this.$t(
            'CONVERSATION.STICKER_PICKER.ERRORS.TIMEOUT_ERROR'
          );
          break;
        default:
          alertMessage =
            userMessage ||
            this.$t('CONVERSATION.STICKER_PICKER.ERRORS.SEND_FAILED');
      }

      useAlert(alertMessage);
    },
  },
};
</script>

<template>
  <div v-if="isVisible" class="sticker-picker-modal">
    <!-- Modal Overlay -->
    <div
      class="fixed inset-0 z-50 flex items-end justify-center bg-black bg-opacity-50"
      @click="closeModal"
    >
      <div
        class="bg-white rounded-t-lg shadow-lg w-full max-w-md h-96 flex flex-col"
        @click.stop
      >
        <!-- Header with Tabs -->
        <div
          class="flex border-b border-gray-200 bg-gray-50 rounded-t-lg overflow-x-auto"
        >
          <button
            v-for="tab in tabs"
            :key="tab.key"
            class="flex-shrink-0 py-3 px-3 text-xs font-medium text-center border-b-2 transition-colors flex items-center justify-center gap-1 min-w-0"
            :class="[
              activeTab === tab.key
                ? 'border-blue-500 text-blue-600 bg-white'
                : 'border-transparent text-gray-500 hover:text-gray-700 hover:bg-gray-100',
            ]"
            @click="switchTab(tab.key)"
          >
            <i
              v-if="tab.icon"
              :class="tab.icon"
              class="text-xs flex-shrink-0"
            />
            <span class="truncate">{{ tab.label }}</span>
          </button>
        </div>

        <!-- Search Input (only for search tab) -->
        <div v-if="activeTab === 'search'" class="p-3 border-b border-gray-200">
          <div class="relative">
            <input
              v-model="searchTerm"
              type="text"
              :placeholder="
                $t('CONVERSATION.STICKER_PICKER.SEARCH_PLACEHOLDER')
              "
              class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent"
              @keyup.enter="performSearch"
              @input="debouncedSearch"
            />
            <div v-if="isSearching" class="absolute right-3 top-2.5">
              <div
                class="animate-spin rounded-full h-4 w-4 border-b-2 border-blue-500"
              />
            </div>
          </div>
        </div>

        <!-- Content Area -->
        <div class="flex-1 overflow-y-auto p-3">
          <!-- Loading State -->
          <div v-if="isLoading" class="flex items-center justify-center h-full">
            <div class="text-center">
              <div
                class="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-500 mx-auto mb-2"
              />
              <p class="text-gray-500 text-sm">
                {{ $t('CONVERSATION.STICKER_PICKER.LOADING') }}
              </p>
            </div>
          </div>

          <!-- Error State -->
          <div
            v-else-if="error"
            class="flex items-center justify-center h-full"
          >
            <div class="text-center">
              <div class="text-red-500 mb-2">
                <i class="i-ph-warning-circle text-2xl" />
              </div>
              <p class="text-gray-600 text-sm">{{ error }}</p>
              <button
                class="mt-2 px-3 py-1 bg-blue-500 text-white text-xs rounded hover:bg-blue-600"
                @click="retryLoad"
              >
                {{ $t('CONVERSATION.STICKER_PICKER.RETRY') }}
              </button>
            </div>
          </div>

          <!-- Empty State -->
          <div
            v-else-if="stickers.length === 0"
            class="flex items-center justify-center h-full"
          >
            <div class="text-center">
              <div class="text-gray-400 mb-2">
                <i class="i-ph-smiley-sad text-2xl" />
              </div>
              <p class="text-gray-500 text-sm">{{ emptyStateMessage }}</p>
            </div>
          </div>

          <!-- Stickers Grid -->
          <div v-else class="grid grid-cols-4 gap-2">
            <div
              v-for="sticker in stickers"
              :key="sticker.id"
              class="aspect-square bg-gray-100 rounded-lg overflow-hidden cursor-pointer hover:bg-gray-200 transition-colors"
              @click="selectSticker(sticker)"
            >
              <img
                :src="sticker.url"
                :alt="sticker.alt"
                class="w-full h-full object-cover"
                @error="handleImageError"
              />
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
  <div v-else />
</template>

<style scoped>
.sticker-picker-modal {
  position: fixed;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  z-index: 1000;
}

/* Custom scrollbar for stickers grid */
.sticker-picker-modal ::-webkit-scrollbar {
  width: 6px;
}

.sticker-picker-modal ::-webkit-scrollbar-track {
  background: #f1f1f1;
  border-radius: 3px;
}

.sticker-picker-modal ::-webkit-scrollbar-thumb {
  background: #c1c1c1;
  border-radius: 3px;
}

.sticker-picker-modal ::-webkit-scrollbar-thumb:hover {
  background: #a8a8a8;
}
</style>
