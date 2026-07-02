import { reactive, computed } from 'vue';

// Chatwit: global selection state for the "Baixar Dossiê" feature.
// Module-level so ReplyBox (toolbar button), Message.vue (checkboxes) and
// DossierBar.vue (action bar) share the same state without touching Vuex.
const state = reactive({
  active: false,
  conversationId: null,
  selected: {},
  lastToggledId: null,
  generating: false,
});

const setRange = (fromId, toId, orderedIds) => {
  const fromIndex = orderedIds.indexOf(fromId);
  const toIndex = orderedIds.indexOf(toId);
  if (fromIndex === -1 || toIndex === -1) return false;

  const [start, end] = [
    Math.min(fromIndex, toIndex),
    Math.max(fromIndex, toIndex),
  ];
  orderedIds.slice(start, end + 1).forEach(id => {
    state.selected[id] = true;
  });
  return true;
};

export function useDossierSelection() {
  const selectedIds = computed(() => Object.keys(state.selected).map(Number));
  const selectedCount = computed(() => selectedIds.value.length);
  const isGenerating = computed(() => state.generating === true);

  const start = conversationId => {
    state.active = true;
    state.conversationId = conversationId;
    state.selected = {};
    state.lastToggledId = null;
    state.generating = false;
  };

  const stop = () => {
    state.active = false;
    state.conversationId = null;
    state.selected = {};
    state.lastToggledId = null;
    state.generating = false;
  };

  const toggleMode = conversationId => {
    if (state.active && state.conversationId === conversationId) {
      stop();
    } else {
      start(conversationId);
    }
  };

  const isActiveFor = conversationId =>
    state.active && state.conversationId === conversationId;

  const isSelected = id => !!state.selected[id];

  // Excel-like behavior: plain click toggles; Shift/Alt+click selects the
  // whole range between the last clicked message and the current one.
  const toggle = (id, { range = false, orderedIds = [] } = {}) => {
    const applied =
      range &&
      state.lastToggledId !== null &&
      setRange(state.lastToggledId, id, orderedIds);

    if (!applied) {
      if (state.selected[id]) delete state.selected[id];
      else state.selected[id] = true;
    }
    state.lastToggledId = id;
  };

  const selectAll = orderedIds => {
    orderedIds.forEach(id => {
      state.selected[id] = true;
    });
  };

  const setGenerating = value => {
    state.generating = value;
  };

  return {
    state,
    selectedIds,
    selectedCount,
    isGenerating,
    start,
    stop,
    toggleMode,
    isActiveFor,
    isSelected,
    toggle,
    selectAll,
    setGenerating,
  };
}
