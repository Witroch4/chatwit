import { ref, onMounted, onUnmounted } from 'vue';

export const useKeyboardResize = () => {
  const keyboardHeight = ref(0);
  const isKeyboardOpen = ref(false);

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
    const height = Math.round(window.innerHeight - viewport.height);
    const keyboardVisible = height > 50 && hasEditableFocus();

    keyboardHeight.value = keyboardVisible ? Math.max(0, height) : 0;
    isKeyboardOpen.value = keyboardVisible;

    if (isKeyboardOpen.value && document.activeElement) {
      requestAnimationFrame(() => {
        document.activeElement.scrollIntoView?.({
          block: 'nearest',
          behavior: 'smooth',
        });
      });
    }
  };

  onMounted(() => {
    viewport = window.visualViewport;
    if (viewport) {
      viewport.addEventListener('resize', onResize);
    }
    window.addEventListener('focusin', onResize);
    window.addEventListener('focusout', onResize);
  });

  onUnmounted(() => {
    if (viewport) {
      viewport.removeEventListener('resize', onResize);
    }
    window.removeEventListener('focusin', onResize);
    window.removeEventListener('focusout', onResize);
  });

  return { keyboardHeight, isKeyboardOpen };
};
