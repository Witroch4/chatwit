import { useHaptics, notifyTrustedHapticTap } from '../useHaptics';

// Android exposes navigator.vibrate; iOS does not. jsdom ships without it, so
// the default state is "iOS" and we opt into Android per-test.
const setAndroid = () => {
  const vibrate = vi.fn();
  Object.defineProperty(navigator, 'vibrate', {
    value: vibrate,
    configurable: true,
    writable: true,
  });
  return vibrate;
};
const setIOS = () => {
  delete navigator.vibrate;
};

describe('useHaptics', () => {
  let now;
  let clickSpy;

  beforeEach(() => {
    // Deterministic clock so the 400ms trusted-tap suppression window is exact
    // and never contaminated by a prior test's notifyTrustedHapticTap call.
    now = 1_000_000;
    vi.spyOn(performance, 'now').mockImplementation(() => now);
    // tapticPulse() ultimately calls .click() on a hidden <label> switch.
    clickSpy = vi
      .spyOn(HTMLElement.prototype, 'click')
      .mockImplementation(() => {});
    setIOS();
  });

  afterEach(() => {
    vi.restoreAllMocks();
    setIOS();
  });

  describe('Android — Vibration API', () => {
    it('vibrates with the UIKit-equivalent pattern and never touches the switch', () => {
      const vibrate = setAndroid();
      const h = useHaptics();

      h.light();
      h.medium();
      h.selection();

      expect(vibrate).toHaveBeenNthCalledWith(1, 10);
      expect(vibrate).toHaveBeenNthCalledWith(2, 25);
      expect(vibrate).toHaveBeenNthCalledWith(3, 5);
      expect(clickSpy).not.toHaveBeenCalled();
    });
  });

  describe('iOS — programmatic switch fallback', () => {
    it('pulses the hidden switch when there is no recent trusted tap', () => {
      useHaptics().medium();
      expect(clickSpy).toHaveBeenCalledTimes(1);
    });

    it('SUPPRESSES the programmatic burst right after a trusted tap (no double feedback)', () => {
      now = 1000;
      notifyTrustedHapticTap();
      now = 1300; // 300ms later — inside the 400ms window

      useHaptics().light();

      expect(clickSpy).not.toHaveBeenCalled();
    });

    it('resumes the programmatic burst once the 400ms window has elapsed', () => {
      now = 1000;
      notifyTrustedHapticTap();
      now = 1500; // 500ms later — window expired

      useHaptics().selection();

      expect(clickSpy).toHaveBeenCalledTimes(1);
    });
  });
});
