// Game data, ported from the iOS app (Game/Models.swift and Game/SoundLibrary.swift).

/** Set this to the App Store page once the app is live; an empty string hides the links. */
export const APP_STORE_URL = '';

/** Bright candy colors. Each player uses one as their identity color. */
export const COLORS = [
  { id: 0, name: 'Lime', rgb: [0.64, 0.94, 0.18] },
  { id: 1, name: 'Tangerine', rgb: [1.0, 0.52, 0.10] },
  { id: 2, name: 'Bubblegum', rgb: [1.0, 0.38, 0.72] },
  { id: 3, name: 'Sky', rgb: [0.20, 0.74, 1.0] },
  { id: 4, name: 'Grape', rgb: [0.65, 0.40, 1.0] },
  { id: 5, name: 'Mint', rgb: [0.14, 0.92, 0.68] },
  { id: 6, name: 'Sunny', rgb: [1.0, 0.84, 0.18] },
  { id: 7, name: 'Coral', rgb: [1.0, 0.30, 0.34] },
];

export const colorCSS = (id, alpha = 1) => {
  const [r, g, b] = (COLORS[id] ?? COLORS[0]).rgb.map((v) => Math.round(v * 255));
  return alpha === 1 ? `rgb(${r} ${g} ${b})` : `rgb(${r} ${g} ${b} / ${alpha})`;
};

/** The 17 playable characters (Quaternius, CC0). Order matches the iOS lineup. */
export const CHARACTERS = [
  { id: 'ninja', name: 'Sand Ninja', asset: 'Ninja' },
  { id: 'classy', name: 'Classy', asset: 'Classy' },
  { id: 'wizard', name: 'Wizard', asset: 'Wizard' },
  { id: 'witch', name: 'Witch', asset: 'Witch' },
  { id: 'zombieGal', name: 'Zombie Gal', asset: 'ZombieGal' },
  { id: 'zombieGuy', name: 'Zombie Guy', asset: 'ZombieGuy' },
  { id: 'chef', name: 'Chef', asset: 'Chef' },
  { id: 'elf', name: 'Elf', asset: 'Elf' },
  { id: 'goblin', name: 'Goblin', asset: 'Goblin' },
  { id: 'kimonoGal', name: 'Kimono Gal', asset: 'KimonoGal' },
  { id: 'kimonoGuy', name: 'Kimono Guy', asset: 'KimonoGuy' },
  { id: 'pirateGal', name: 'Pirate Gal', asset: 'PirateGal' },
  { id: 'pirateGuy', name: 'Pirate Captain', asset: 'PirateGuy' },
  { id: 'soldier', name: 'Soldier', asset: 'Soldier' },
  { id: 'suit', name: 'Business Boss', asset: 'Suit' },
  { id: 'vikingHelmet', name: 'Horned Viking', asset: 'VikingHelmet' },
  { id: 'viking', name: 'Viking', asset: 'Viking' },
];

export const DEFAULT_CHARACTER = 'pirateGal';
export const character = (id) => CHARACTERS.find((c) => c.id === id) ?? CHARACTERS[11];
export const portrait = (id) => `img/characters/${character(id).asset}.png`;

const meme = (clip, name, hint) => ({ id: clip, clip, name, hint });

/** The real meme clips from the app (EchoBloom/Sounds), trimmed and level-matched. */
export const PACKS = [
  { id: 'reactions', name: 'Meme Reactions', blurb: 'Short, loud, iconic.', icon: 'smile', tint: 6, prompts: [
    meme('faaah', 'Faaah!', 'One long, dramatic "faaah".'),
    meme('you-what-spongebob', 'You What?', 'Squeaky disbelief.'),
    meme('what_JOcN7Y8', 'What?!', 'A sharp, shocked "what".'),
    meme('omg-bruh-oh-hell-nah', 'OMG Bruh, Oh Hell Nah', 'Escalating disbelief. Match every word.'),
    meme('emotional-damage-meme', 'Emotional Damage', 'Deliver it like a final blow.'),
    meme('meme-okay-lets-go', "Okay, Let's Go!", 'Pure hype. Get louder at the end.'),
    meme('cringe-sus-anime-girl', 'Sus Anime Girl', 'A tiny, very suspicious squeal.'),
  ] },
  { id: 'voices', name: 'Silly Voices', blurb: 'Cats, frogs, aliens and worse.', icon: 'masks', tint: 4, prompts: [
    meme('oiia-oiia-sound', 'OIIA OIIA', 'The spinning cat. The pitch goes everywhere.'),
    meme('mu-hehehe-cat-meme', 'Mu-hehehe Cat', 'A sneaky, evil little laugh.'),
    meme('frog-laughing-meme', 'Laughing Frog', 'Croaky laughter. Keep the rhythm.'),
    meme('zab-zab-zab-bla-bla-blu-blu-alien-tiktok-meme', 'Zab Zab Alien', 'Zab zab zab, bla bla, blu blu.'),
    meme('snore-mimimimimimi', 'Mimimi Snore', 'Snore in, "mimimi" out.'),
    meme('oi-oi-oe-oi-a-eye-eye', 'Oi Oi Oe Oi', 'Oi oi oe oi, a-eye-eye!'),
    meme('anime-wow-sound-effect-mp3cut', 'Anime Wow', 'A dreamy, wide-eyed "wow".'),
  ] },
  { id: 'worldwide', name: 'Worldwide & Wild', blurb: 'Memes from everywhere.', icon: 'globe', tint: 3, prompts: [
    meme('bom-dia-a-todos-e-todes-meme', 'Bom Dia a Todos', 'Portuguese for "good morning, everyone". Say it with gusto.'),
    meme('lula-bom-dia-motivacional-meme-kkkkkk', 'Bom Dia Motivacional', 'A motivational Brazilian good morning.'),
    meme('du-bist-gut-genug', 'Du Bist Gut Genug', 'German for "you are good enough".'),
    meme('man-screaming', 'Man Screaming', 'Just scream. Match the length.'),
    meme('michael-dont-leave-me-here', "Michael, Don't Leave Me Here", 'Desperate and dramatic.'),
    meme('ny-video-online-audio-converter', 'Mystery Meme #1', 'No spoilers. Just copy what you hear.'),
    meme('yt1s_wU4BGgD', 'Mystery Meme #2', 'No spoilers. Just copy what you hear.'),
  ] },
  { id: 'brainrot', name: 'Brainrot', blurb: 'Peak internet nonsense.', icon: 'brain', tint: 5, prompts: [
    meme('italian-brainrot', 'Italian Brainrot', 'Fast, dramatic and very Italian.'),
    meme('Dragon-Cannelloni', 'Dragon Cannelloni', 'Announce it like a legend.'),
    meme('Chinese-rapping', 'Chinese Rapping', 'Keep up with the flow.'),
    meme('cat-iphone-ringtone', 'Cat Ringtone', 'Meow the ringtone, note for note.'),
    meme('This-thing-is-called-Ratafak', 'This Thing Is Called Ratafak', 'Present it with total confidence.'),
    meme('Plankton-Aughhhhh', 'Plankton AUGHHH', 'One long, tiny, furious scream.'),
    meme('Its-Time-For-Scoo', "It's Time For...", 'Big announcement energy.'),
  ] },
  { id: 'lines', name: 'Movie & TV Lines', blurb: 'Quotes everyone knows.', icon: 'film', tint: 1, prompts: [
    meme('No-its-Thursday-bro', "No, It's Thursday Bro", 'A dead-serious correction.'),
    meme('Nobodys-gonna-know', "Nobody's Gonna Know", "Like you're getting away with it."),
    meme('Somebody-Get-These-Beggars-Outta-Here', 'Get These Beggars Outta Here', 'Maximum disgust.'),
    meme('Ted-Hey-can-i-have-this', 'Hey, Can I Have This?', 'Innocent. Polite. Suspicious.'),
    meme('naoya_zenin', 'Naoya Zenin', 'Anime villain energy.'),
    meme('Dictator-Mbappe', 'Dictator Mbappé', 'Copy every word, and the attitude.'),
    meme('Surprise-mother-fer', 'Surprise!', 'The famous jump-scare line. Strong language.'),
    meme('Aller-ftg-', 'Aller, FTG!', 'French, rude and very fast.'),
  ] },
];

export const clipURL = (clip) => `sounds/${encodeURIComponent(clip)}.m4a`;

export function verdict(total) {
  if (total >= 90) return 'Uncanny. Are you the sound?';
  if (total >= 78) return 'Seriously close!';
  if (total >= 62) return 'Solid echo.';
  if (total >= 45) return 'We heard the ambition.';
  return 'Bold. Interpretive. Wrong.';
}

/** Ordinal ranks with ties sharing a place: [90, 80, 80, 70] → [1, 2, 2, 4]. */
export const competitionRanks = (scores) => scores.map((s) => scores.filter((o) => o > s).length + 1);
