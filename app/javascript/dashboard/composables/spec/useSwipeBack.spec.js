const swipeBackMock = vi.hoisted(() => ({
  mountedCallbacks: [],
}));

vi.mock('vue', async importOriginal => ({
  ...(await importOriginal()),
  onMounted: vi.fn(callback => swipeBackMock.mountedCallbacks.push(callback)),
  onUnmounted: vi.fn(),
}));

vi.mock('dashboard/composables/useHaptics', () => ({
  useHaptics: () => ({ light: vi.fn() }),
}));

import { ref } from 'vue';
import { useSwipeBack } from 'dashboard/composables/useSwipeBack';

describe('useSwipeBack', () => {
  let element;

  const dispatchTouch = (type, clientX, clientY = 100) =>
    element.dispatchEvent(
      Object.assign(new Event(type), { touches: [{ clientX, clientY }] })
    );

  const mountComposable = () => {
    const composable = useSwipeBack(ref(element), vi.fn());
    swipeBackMock.mountedCallbacks.forEach(callback => callback());
    return composable;
  };

  beforeEach(() => {
    swipeBackMock.mountedCallbacks = [];
    element = document.createElement('div');
    window.innerWidth = 400;
  });

  // MobileLayout mirrors swipeProgress into isChatSwiping, which un-hides the
  // bottom tab bar. The bar is fixed at z-50, so a swipe state that never
  // settles leaves it covering the composer and the chat becomes unanswerable.
  it('settles the swipe when iOS cancels the gesture mid-drag', () => {
    const { isSwiping, swipeOffset, swipeProgress } = mountComposable();

    dispatchTouch('touchstart', 5);
    dispatchTouch('touchmove', 120);
    expect(isSwiping.value).toBe(true);
    expect(swipeProgress.value).toBeGreaterThan(0);

    dispatchTouch('touchcancel', 120);

    expect(isSwiping.value).toBe(false);
    expect(swipeOffset.value).toBe(0);
    expect(swipeProgress.value).toBe(0);
  });

  it('settles the swipe when released below the back threshold', () => {
    const { isSwiping, swipeOffset, swipeProgress } = mountComposable();

    dispatchTouch('touchstart', 5);
    dispatchTouch('touchmove', 60);
    expect(isSwiping.value).toBe(true);

    dispatchTouch('touchend', 60);

    expect(isSwiping.value).toBe(false);
    expect(swipeOffset.value).toBe(0);
    expect(swipeProgress.value).toBe(0);
  });
});
