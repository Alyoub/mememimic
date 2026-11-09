// Inline SVG icons standing in for the SF Symbols the iOS app uses.
import { h } from 'preact';

const S = 'stroke'; // stroked shape
const F = 'fill';   // filled shape

const ICONS = {
  play: [F, '<path d="M7 4.2v15.6c0 .9 1 1.4 1.7.9l11.4-7.8c.7-.5.7-1.4 0-1.8L8.7 3.3C8 2.8 7 3.3 7 4.2z"/>'],
  book: [S, '<path d="M2 4h6a4 4 0 0 1 4 4v13a3 3 0 0 0-3-3H2z"/><path d="M22 4h-6a4 4 0 0 0-4 4v13a3 3 0 0 1 3-3h7z"/>'],
  speaker: [S, '<path d="M11 5 6 9H2v6h4l5 4V5z" fill="currentColor"/><path d="M15.5 8.5a5 5 0 0 1 0 7"/><path d="M19 5a10 10 0 0 1 0 14"/>'],
  speakerOff: [S, '<path d="M11 5 6 9H2v6h4l5 4V5z" fill="currentColor"/><path d="m22 9-6 6"/><path d="m16 9 6 6"/>'],
  gear: [S, '<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 1 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 1 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 1 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 1 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"/>'],
  chevronLeft: [S, '<path d="m15 18-6-6 6-6"/>'],
  chevronRight: [S, '<path d="m9 18 6-6-6-6"/>'],
  x: [S, '<path d="M18 6 6 18"/><path d="m6 6 12 12"/>'],
  check: [S, '<path d="M20 6 9 17l-5-5"/>'],
  plus: [S, '<path d="M12 5v14"/><path d="M5 12h14"/>'],
  mic: [S, '<rect x="9" y="2" width="6" height="12" rx="3" fill="currentColor"/><path d="M19 10v1a7 7 0 0 1-14 0v-1"/><path d="M12 18v4"/><path d="M8 22h8"/>'],
  stop: [F, '<rect x="5" y="5" width="14" height="14" rx="3"/>'],
  again: [S, '<path d="M3 12a9 9 0 1 0 2.64-6.36L3 8"/><path d="M3 3v5h5"/>'],
  wand: [S, '<path d="m21.64 3.64-1.28-1.28a1.21 1.21 0 0 0-1.72 0L2.36 18.64a1.21 1.21 0 0 0 0 1.72l1.28 1.28a1.2 1.2 0 0 0 1.72 0L21.64 5.36a1.2 1.2 0 0 0 0-1.72z"/><path d="m14 7 3 3"/><path d="M5 6v4"/><path d="M19 14v4"/><path d="M10 2v2"/><path d="M7 8H3"/><path d="M21 16h-4"/><path d="M11 3H9"/>'],
  waveform: [S, '<path d="M2 10v4"/><path d="M6 6v12"/><path d="M10 3v18"/><path d="M14 8v8"/><path d="M18 5v14"/><path d="M22 10v4"/>'],
  ear: [S, '<path d="M6 8.5a6.5 6.5 0 1 1 13 0c0 6-6 6-6 10a3.5 3.5 0 1 1-7 0"/><path d="M15 8.5a2.5 2.5 0 0 0-5 0v1a2 2 0 1 1 0 4"/>'],
  trophy: [S, '<path d="M6 9H4.5a2.5 2.5 0 0 1 0-5H6"/><path d="M18 9h1.5a2.5 2.5 0 0 0 0-5H18"/><path d="M4 22h16"/><path d="M10 14.66V17c0 .55-.47.98-.97 1.21C7.85 18.75 7 20.24 7 22"/><path d="M14 14.66V17c0 .55.47.98.97 1.21C16.15 18.75 17 20.24 17 22"/><path d="M18 2H6v7a6 6 0 0 0 12 0V2z" fill="currentColor"/>'],
  lock: [F, '<path d="M7 10V7a5 5 0 0 1 10 0v3h.5A2.5 2.5 0 0 1 20 12.5v7a2.5 2.5 0 0 1-2.5 2.5h-11A2.5 2.5 0 0 1 4 19.5v-7A2.5 2.5 0 0 1 6.5 10H7zm2.5 0h5V7a2.5 2.5 0 0 0-5 0v3z"/>'],
  door: [S, '<path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><path d="m16 17 5-5-5-5"/><path d="M21 12H9"/>'],
  share: [S, '<path d="M4 12v8a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-8"/><path d="m16 6-4-4-4 4"/><path d="M12 2v13"/>'],
  shield: [S, '<path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/><path d="m9 12 2 2 4-4"/>'],
  star: [F, '<path d="M12 2.5l2.94 5.96 6.56.95-4.75 4.63 1.12 6.54L12 17.5l-5.87 3.08 1.12-6.54L2.5 9.41l6.56-.95z"/>'],
  phone: [S, '<rect x="7" y="2" width="10" height="20" rx="2.5"/><path d="M11 18h2"/>'],
  vibrate: [S, '<rect x="7" y="4" width="10" height="16" rx="2"/><path d="M3 9v6"/><path d="M21 9v6"/>'],
  bubble: [F, '<path d="M4 3h16a2 2 0 0 1 2 2v11a2 2 0 0 1-2 2H9l-5 4v-4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2zm7 3.5v5.5h2V6.5h-2zm0 7.5v2h2v-2h-2z" fill-rule="evenodd"/>'],
  up: [F, '<path d="M12 5 21 19H3z"/>'],
  down: [F, '<path d="M12 19 3 5h18z"/>'],
  smile: [S, '<circle cx="12" cy="12" r="10" fill="currentColor" stroke="none"/><path d="M8 14s1.5 2 4 2 4-2 4-2" stroke="var(--icon-ink, #26020a)"/><path d="M9 9h.01" stroke="var(--icon-ink, #26020a)" stroke-width="3"/><path d="M15 9h.01" stroke="var(--icon-ink, #26020a)" stroke-width="3"/>'],
  masks: [F, '<path d="M2 4.5c3.3-1.6 6.7-1.6 10 0v5.5c0 3.4-2.2 6-5 6s-5-2.6-5-6V4.5zm3 3.2a1.2 1.2 0 1 0 2.4 0 1.2 1.2 0 0 0-2.4 0zm4.6 0a1.2 1.2 0 1 0 2.4 0 1.2 1.2 0 0 0-2.4 0zM4.9 11.7c1.4 1.3 2.8 1.3 4.2 0-.3 1.5-1.1 2.2-2.1 2.2s-1.8-.7-2.1-2.2z" fill-rule="evenodd"/><path d="M13.5 8.6c2.8-1 5.6-.8 8.5.6v4.3c0 3.1-2 5.5-4.5 5.5-1.4 0-2.6-.7-3.4-1.9.5-.9.8-2 .8-3.2V8.7zm1.9 3.4a1.1 1.1 0 1 0 2.2 0 1.1 1.1 0 0 0-2.2 0zm3.4.2a1.1 1.1 0 1 0 2.2 0 1.1 1.1 0 0 0-2.2 0zm-2.6 4.3c.9-1.2 2.4-1.3 3.4-.1-1-.5-2.3-.4-3.4.1z" fill-rule="evenodd"/>'],
  globe: [S, '<circle cx="12" cy="12" r="10"/><path d="M2 12h20"/><path d="M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z"/>'],
  brain: [S, '<path d="M9.5 2A2.5 2.5 0 0 1 12 4.5v15a2.5 2.5 0 0 1-4.96.44 2.5 2.5 0 0 1-2.96-3.08 3 3 0 0 1-.34-5.58 2.5 2.5 0 0 1 1.32-4.24 2.5 2.5 0 0 1 1.98-3A2.5 2.5 0 0 1 9.5 2z"/><path d="M14.5 2A2.5 2.5 0 0 0 12 4.5v15a2.5 2.5 0 0 0 4.96.44 2.5 2.5 0 0 0 2.96-3.08 3 3 0 0 0 .34-5.58 2.5 2.5 0 0 0-1.32-4.24 2.5 2.5 0 0 0-1.98-3A2.5 2.5 0 0 0 14.5 2z"/>'],
  film: [S, '<rect x="3" y="3" width="18" height="18" rx="2"/><path d="M7 3v18"/><path d="M17 3v18"/><path d="M3 12h18"/><path d="M3 7.5h4"/><path d="M3 16.5h4"/><path d="M17 16.5h4"/><path d="M17 7.5h4"/>'],
  external: [S, '<path d="M15 3h6v6"/><path d="M10 14 21 3"/><path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"/>'],
  apple: [F, '<path d="M16.37 12.62c-.02-2.3 1.88-3.4 1.96-3.46-1.07-1.56-2.73-1.77-3.32-1.8-1.41-.14-2.76.83-3.47.83-.72 0-1.82-.81-2.99-.79-1.54.02-2.96.9-3.75 2.27-1.6 2.78-.41 6.89 1.15 9.14.76 1.1 1.67 2.34 2.86 2.3 1.15-.05 1.58-.74 2.97-.74 1.38 0 1.77.74 2.98.72 1.23-.02 2.01-1.12 2.76-2.23.87-1.28 1.23-2.52 1.25-2.58-.03-.01-2.39-.92-2.4-3.66zM14.1 5.86c.63-.77 1.06-1.83.94-2.89-.91.04-2.02.61-2.67 1.37-.58.67-1.1 1.76-.96 2.8 1.02.08 2.06-.52 2.69-1.28z"/>'],
};

export function Icon({ name, size = 20, class: cls = '', label }) {
  const def = ICONS[name];
  if (!def) return null;
  const [kind, body] = def;
  const props = {
    viewBox: '0 0 24 24',
    width: size,
    height: size,
    class: `icon ${cls}`,
    'aria-hidden': label ? undefined : 'true',
    'aria-label': label,
    role: label ? 'img' : undefined,
    dangerouslySetInnerHTML: { __html: body },
  };
  if (kind === S) Object.assign(props, { fill: 'none', stroke: 'currentColor', 'stroke-width': 2.4, 'stroke-linecap': 'round', 'stroke-linejoin': 'round' });
  else props.fill = 'currentColor';
  return h('svg', props);
}
