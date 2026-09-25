<script setup>
import { ref, inject, watch, computed } from 'vue';
import { useHaptics } from 'dashboard/composables/useHaptics';
import { vHapticTap } from './hapticTap';

const props = defineProps({
  rowId: {
    type: [String, Number],
    required: true,
  },
  actions: {
    type: Array,
    default: () => [],
  },
  leftActions: {
    type: Array,
    default: () => [],
  },
  threshold: {
    type: Number,
    default: 80,
  },
  // WhatsApp-style: buttons stretch with the finger and dragging past
  // FULL_SWIPE_RATIO of the row fires the first action of that side.
  fullSwipe: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['action', 'leftAction']);

const ACTION_WIDTH = 72;
const FULL_SWIPE_RATIO = 0.6;

const { medium } = useHaptics();

const openRowId = inject('swipeOpenRowId', ref(null));

const rootRef = ref(null);
const rowWidth = ref(0);
const offsetX = ref(0);
const isAnimating = ref(false);
// Side whose first action takes over the whole strip ('left' | 'right').
// Kept after release so the strip stays expanded while the row slides back.
const armedSide = ref(null);
let startX = 0;
let startY = 0;
let isTracking = false;
let directionLocked = false;
let isHorizontal = false;
let hapticFired = false;
let swipeDirection = null; // 'left' or 'right'

const rightActionsWidth = computed(() => props.actions.length * ACTION_WIDTH);
const leftActionsWidth = computed(
  () => props.leftActions.length * ACTION_WIDTH
);

const maxLeftReveal = computed(() => {
  if (!props.leftActions.length) return 0;
  return props.fullSwipe ? rowWidth.value : leftActionsWidth.value;
});
const maxRightReveal = computed(() => {
  if (!props.actions.length) return 0;
  return props.fullSwipe ? rowWidth.value : rightActionsWidth.value;
});

const clampedOffset = computed(() =>
  Math.max(-maxRightReveal.value, Math.min(maxLeftReveal.value, offsetX.value))
);

const areRightActionsHidden = computed(() => clampedOffset.value >= 0);
const areLeftActionsHidden = computed(() => clampedOffset.value <= 0);

const leftStripWidth = computed(() =>
  props.fullSwipe ? Math.max(clampedOffset.value, 0) : leftActionsWidth.value
);
const rightStripWidth = computed(() =>
  props.fullSwipe ? Math.max(-clampedOffset.value, 0) : rightActionsWidth.value
);

const openSide = computed(() => {
  if (openRowId.value === `${props.rowId}-right`) return 'right';
  if (openRowId.value === `${props.rowId}-left`) return 'left';
  return null;
});

// In full-swipe mode the armed action grows to fill the strip and the others
// collapse; otherwise every action shares the revealed width equally.
const actionClass = (side, index) => {
  if (!props.fullSwipe) return 'w-[72px]';
  if (armedSide.value !== side) return 'flex-1 basis-0 justify-center';
  if (index > 0) return 'grow-0 basis-0';
  return side === 'left'
    ? 'flex-1 basis-0 justify-end'
    : 'flex-1 basis-0 justify-start';
};

watch(
  () => openRowId.value,
  newId => {
    const isThisRow =
      newId === `${props.rowId}-right` || newId === `${props.rowId}-left`;
    if (!isThisRow && offsetX.value !== 0) {
      isAnimating.value = true;
      offsetX.value = 0;
    }
  }
);

const onTouchStart = event => {
  if (isAnimating.value) return;
  const touch = event.touches[0];
  startX = touch.clientX;
  startY = touch.clientY;
  rowWidth.value = rootRef.value?.offsetWidth || 0;
  isTracking = true;
  directionLocked = false;
  isHorizontal = false;
  hapticFired = false;
  swipeDirection = null;
  armedSide.value = null;
  isAnimating.value = false;
};

const onTouchMove = event => {
  if (!isTracking) return;

  const touch = event.touches[0];
  const deltaX = touch.clientX - startX;
  const deltaY = touch.clientY - startY;

  if (!directionLocked) {
    if (Math.abs(deltaX) > 8 || Math.abs(deltaY) > 8) {
      directionLocked = true;
      isHorizontal = Math.abs(deltaX) > Math.abs(deltaY) * 1.5;
    }
    if (!directionLocked) return;
  }

  if (!isHorizontal) {
    isTracking = false;
    return;
  }

  let base = 0;
  if (openSide.value === 'right') base = -rightActionsWidth.value;
  else if (openSide.value === 'left') base = leftActionsWidth.value;

  const raw = base + deltaX;

  // Determine swipe direction based on raw movement
  if (raw < 0 && props.actions.length > 0) {
    swipeDirection = 'left';
  } else if (raw > 0 && props.leftActions.length > 0) {
    swipeDirection = 'right';
  }

  offsetX.value = raw;

  if (!hapticFired && Math.abs(offsetX.value) >= props.threshold) {
    medium();
    hapticFired = true;
  }

  if (props.fullSwipe) {
    const fullSwipeAt = rowWidth.value * FULL_SWIPE_RATIO;
    let nextArmed = null;
    if (clampedOffset.value >= fullSwipeAt) nextArmed = 'left';
    else if (clampedOffset.value <= -fullSwipeAt) nextArmed = 'right';
    if (nextArmed && nextArmed !== armedSide.value) medium();
    armedSide.value = nextArmed;
  }
};

// Only flag the animation when the row actually moves; otherwise no
// transitionend fires and the row would ignore the next touch.
const animateTo = value => {
  const from = clampedOffset.value;
  offsetX.value = value;
  isAnimating.value = clampedOffset.value !== from;
};

const closeRow = () => {
  animateTo(0);
  if (openSide.value) openRowId.value = null;
};

const onTouchEnd = () => {
  if (!isTracking || !isHorizontal) {
    isTracking = false;
    return;
  }
  isTracking = false;

  if (armedSide.value === 'left') {
    emit('leftAction', props.leftActions[0].key);
    closeRow();
  } else if (armedSide.value === 'right') {
    emit('action', props.actions[0].key);
    closeRow();
  } else if (swipeDirection === 'left' && offsetX.value < -props.threshold) {
    animateTo(-rightActionsWidth.value);
    openRowId.value = `${props.rowId}-right`;
  } else if (swipeDirection === 'right' && offsetX.value > props.threshold) {
    animateTo(leftActionsWidth.value);
    openRowId.value = `${props.rowId}-left`;
  } else {
    closeRow();
  }
};

const onTransitionEnd = () => {
  isAnimating.value = false;
  if (offsetX.value === 0) armedSide.value = null;
};

const onRightActionClick = actionKey => {
  emit('action', actionKey);
  closeRow();
};

const onLeftActionClick = actionKey => {
  emit('leftAction', actionKey);
  closeRow();
};
</script>

<template>
  <div ref="rootRef" class="relative overflow-hidden rounded-lg">
    <!-- Left action buttons (revealed on swipe right) -->
    <div
      v-if="leftActions.length"
      class="absolute inset-y-0 left-0 flex items-stretch overflow-hidden"
      :class="{
        'pointer-events-none': areLeftActionsHidden,
        'transition-[width] duration-200 ease-out': isAnimating,
      }"
      :style="{ width: `${leftStripWidth}px` }"
      :inert="areLeftActionsHidden"
    >
      <button
        v-for="(action, index) in leftActions"
        :key="action.key"
        v-haptic-tap
        class="flex min-w-0 items-center overflow-hidden text-white text-xs font-medium transition-[flex-grow] duration-200 ease-out"
        :class="[action.color, actionClass('left', index)]"
        :tabindex="areLeftActionsHidden ? -1 : 0"
        @click.stop="onLeftActionClick(action.key)"
      >
        <span
          class="flex w-[72px] shrink-0 flex-col items-center justify-center gap-1"
        >
          <span class="size-5" :class="action.icon" />
          <span class="whitespace-nowrap">{{ action.label }}</span>
        </span>
      </button>
    </div>
    <!-- Right action buttons (revealed on swipe left) -->
    <div
      v-if="actions.length"
      class="absolute inset-y-0 right-0 flex items-stretch overflow-hidden"
      :class="{
        'pointer-events-none': areRightActionsHidden,
        'transition-[width] duration-200 ease-out': isAnimating,
      }"
      :style="{ width: `${rightStripWidth}px` }"
      :inert="areRightActionsHidden"
    >
      <button
        v-for="(action, index) in actions"
        :key="action.key"
        v-haptic-tap
        class="flex min-w-0 items-center overflow-hidden text-white text-xs font-medium transition-[flex-grow] duration-200 ease-out"
        :class="[action.color, actionClass('right', index)]"
        :tabindex="areRightActionsHidden ? -1 : 0"
        @click.stop="onRightActionClick(action.key)"
      >
        <span
          class="flex w-[72px] shrink-0 flex-col items-center justify-center gap-1"
        >
          <span class="size-5" :class="action.icon" />
          <span class="whitespace-nowrap">{{ action.label }}</span>
        </span>
      </button>
    </div>
    <!-- Swipeable content -->
    <div
      :style="{ transform: `translateX(${clampedOffset}px)` }"
      :class="{ 'transition-transform duration-200 ease-out': isAnimating }"
      class="relative z-10 bg-white dark:bg-n-background"
      @touchstart.passive="onTouchStart"
      @touchmove.passive="onTouchMove"
      @touchend="onTouchEnd"
      @transitionend.self="onTransitionEnd"
    >
      <slot />
    </div>
  </div>
</template>
