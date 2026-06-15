import { ref, onMounted, onUnmounted } from 'vue';

// Drives the mobile chat layout from window.visualViewport — the single source
// of truth for the *visible* area. Sizing the chat to `viewportHeight` keeps the
// composer flush above the keyboard (open) and at the screen bottom (closed)
// without the fragile `innerHeight - visualViewport.height` padding, which
// double-counts the keyboard height when iOS changes the two values at
// different times (the intermittent "huge gap" on keyboard open).
export const useKeyboardResize = () => {
  const keyboardHeight = ref(0);
  const isKeyboardOpen = ref(false);
  const viewportHeight = ref(
    typeof window !== 'undefined' ? window.innerHeight : 0
  );
  const viewportOffsetTop = ref(0);

  let viewport = null;

  const hasEditableFocus = () => {
    const el = document.activeElement;
    if (!el) return false;
    return (
      el.tagName === 'TEXTAREA' ||
      el.tagName === 'INPUT' ||
      el.tagName === 'SELECT' ||
      el.isContentEditable
    );
  };

  const onResize = () => {
    if (!viewport) return;
    viewportHeight.value = Math.round(viewport.height);
    viewportOffsetTop.value = Math.round(viewport.offsetTop);
    // Use the layout viewport (clientHeight) as the stable reference: iOS shrinks
    // window.innerHeight when the keyboard opens, which makes innerHeight - height
    // ~0 and the keyboard undetectable.
    const delta = Math.round(
      document.documentElement.clientHeight - viewport.height
    );
    const keyboardVisible = delta > 50 && hasEditableFocus();
    keyboardHeight.value = keyboardVisible ? Math.max(0, delta) : 0;
    isKeyboardOpen.value = keyboardVisible;
  };

  onMounted(() => {
    viewport = window.visualViewport;
    if (viewport) {
      viewport.addEventListener('resize', onResize);
      viewport.addEventListener('scroll', onResize);
      onResize();
    }
    window.addEventListener('focusin', onResize);
    window.addEventListener('focusout', onResize);
  });

  onUnmounted(() => {
    if (viewport) {
      viewport.removeEventListener('resize', onResize);
      viewport.removeEventListener('scroll', onResize);
    }
    window.removeEventListener('focusin', onResize);
    window.removeEventListener('focusout', onResize);
  });

  return { keyboardHeight, isKeyboardOpen, viewportHeight, viewportOffsetTop };
};
