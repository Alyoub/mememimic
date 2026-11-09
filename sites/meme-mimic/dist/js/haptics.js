// Vibration feedback where the browser supports it (Android Chrome). A quiet no-op elsewhere.
const can = typeof navigator !== 'undefined' && typeof navigator.vibrate === 'function';

export const haptics = {
  supported: can,
  enabled: true,
  buzz(pattern) {
    if (!can || !this.enabled) return;
    try { navigator.vibrate(pattern); } catch {}
  },
  tap() { this.buzz(8); },
  select() { this.buzz(5); },
  tick() { this.buzz(4); },
  thump() { this.buzz(22); },
  success() { this.buzz([10, 50, 16]); },
  warning() { this.buzz([18, 40, 18]); },
};
