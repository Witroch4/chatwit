import { vHapticTap } from '../hapticTap';
import { notifyTrustedHapticTap } from 'dashboard/composables/useHaptics';

// The whole point of the directive is to call notifyTrustedHapticTap on a
// trusted tap; we assert that contract, so the real composable is mocked away.
vi.mock('dashboard/composables/useHaptics', () => ({
  notifyTrustedHapticTap: vi.fn(),
}));

// jsdom has no Vibration API by default (typeof navigator.vibrate ===
// 'undefined'), which is exactly the iOS branch the overlay exists for.
const setAndroid = () => {
  Object.defineProperty(navigator, 'vibrate', {
    value: vi.fn(),
    configurable: true,
    writable: true,
  });
};
const setIOS = () => {
  delete navigator.vibrate;
};

const mount = (tag = 'button') => {
  const el = document.createElement(tag);
  document.body.appendChild(el);
  vHapticTap.mounted(el);
  return el;
};

const overlayOf = el => el.querySelector('input[switch]');

// jsdom's Event.isTrusted is a non-configurable getter, so we can't fake a
// trusted DOM event. Instead capture the click handler the directive registers
// on the overlay and invoke it with a controlled event — this exercises the
// exact branch logic (event.isTrusted + disabled guard) that protects the
// Taptic contract.
const mountCapturingClick = (tag = 'button') => {
  const el = document.createElement(tag);
  document.body.appendChild(el);
  let handler;
  const spy = vi
    .spyOn(EventTarget.prototype, 'addEventListener')
    .mockImplementation((type, fn) => {
      if (type === 'click') handler = fn;
    });
  vHapticTap.mounted(el);
  spy.mockRestore();
  return {
    el,
    fire: (isTrusted = true) => {
      const event = { isTrusted, preventDefault: vi.fn() };
      handler(event);
      return event;
    },
  };
};

describe('vHapticTap directive', () => {
  beforeEach(() => {
    setIOS();
    document.body.innerHTML = '';
  });

  afterEach(() => {
    setIOS();
  });

  describe('iOS (no Vibration API) — overlay path', () => {
    it('injects a transparent full-size switch overlay on the host', () => {
      const el = mount();
      const overlay = overlayOf(el);

      expect(overlay).not.toBeNull();
      expect(overlay.type).toBe('checkbox');
      expect(overlay.hasAttribute('switch')).toBe(true);
      // Invisible to AT and out of the tab order — purely a haptic surface.
      expect(overlay.getAttribute('aria-hidden')).toBe('true');
      expect(overlay.tabIndex).toBe(-1);
      // Transparent and stretched over the whole host so the finger always
      // lands on the switch (the only thing iOS lets reach the Taptic Engine).
      expect(overlay.style.opacity).toBe('0');
      expect(overlay.style.position).toBe('absolute');
      expect(overlay.style.inset).toBe('0');
    });

    it('promotes a statically-positioned host to relative so the overlay anchors', () => {
      const el = mount();
      expect(el.style.position).toBe('relative');
    });

    it('leaves an already-positioned host untouched', () => {
      const el = document.createElement('div');
      el.style.position = 'fixed';
      document.body.appendChild(el);
      vHapticTap.mounted(el);
      expect(el.style.position).toBe('fixed');
    });

    it('notifies the haptic layer on a TRUSTED tap', () => {
      const { fire } = mountCapturingClick();
      fire(true);
      expect(notifyTrustedHapticTap).toHaveBeenCalledTimes(1);
    });

    it('ignores an UNTRUSTED (synthetic) click — only real taps reach the Taptic Engine', () => {
      const { fire } = mountCapturingClick();
      fire(false);
      expect(notifyTrustedHapticTap).not.toHaveBeenCalled();
    });

    it('does not fire feedback for a disabled host (disabled attribute)', () => {
      const { el, fire } = mountCapturingClick('button');
      el.disabled = true;
      const event = fire(true);
      expect(notifyTrustedHapticTap).not.toHaveBeenCalled();
      expect(event.preventDefault).toHaveBeenCalled();
    });

    it('does not fire feedback for an aria-disabled host', () => {
      const { el, fire } = mountCapturingClick('div');
      el.setAttribute('aria-disabled', 'true');
      const event = fire(true);
      expect(notifyTrustedHapticTap).not.toHaveBeenCalled();
      expect(event.preventDefault).toHaveBeenCalled();
    });

    it('removes the overlay and frees the host on unmount', () => {
      const el = mount();
      expect(overlayOf(el)).not.toBeNull();
      vHapticTap.unmounted(el);
      expect(overlayOf(el)).toBeNull();
    });
  });

  describe('Android (Vibration API present) — overlay skipped', () => {
    beforeEach(() => setAndroid());

    it('does NOT inject an overlay (useHaptics vibrates programmatically instead)', () => {
      const el = mount();
      expect(overlayOf(el)).toBeNull();
    });

    it('unmount is a safe no-op when no overlay was injected', () => {
      const el = mount();
      expect(() => vHapticTap.unmounted(el)).not.toThrow();
    });
  });
});
