// Whimsical speaker name generator - zany but professional, cutesy vibes

const ADJECTIVES = [
  'Sparkly',
  'Cosmic',
  'Fuzzy',
  'Wobbly',
  'Snazzy',
  'Zippy',
  'Glittery',
  'Bouncy',
  'Toasty',
  'Squishy',
  'Dapper',
  'Peppy',
  'Mellow',
  'Twinkly',
  'Swooshy',
  'Wiggly',
]

const ANIMALS = [
  'Capybara',
  'Axolotl',
  'Quokka',
  'Narwhal',
  'Pangolin',
  'Tardigrade',
  'Blobfish',
  'Platypus',
  'Wombat',
  'Fennec',
  'Tapir',
  'Okapi',
  'Manatee',
  'Kiwi',
  'Puffin',
  'Chinchilla',
]

// Consistent color palette that matches the names
export const SPEAKER_COLOR_PALETTE = [
  { bg: 'bg-coral-500/20', text: 'text-orange-400', border: 'border-orange-500/30', hex: '#f97316' },
  { bg: 'bg-emerald-500/20', text: 'text-emerald-400', border: 'border-emerald-500/30', hex: '#10b981' },
  { bg: 'bg-teal-500/20', text: 'text-teal-400', border: 'border-teal-500/30', hex: '#14b8a6' },
  { bg: 'bg-amber-500/20', text: 'text-amber-400', border: 'border-amber-500/30', hex: '#f59e0b' },
  { bg: 'bg-blue-500/20', text: 'text-blue-400', border: 'border-blue-500/30', hex: '#3b82f6' },
  { bg: 'bg-purple-500/20', text: 'text-purple-400', border: 'border-purple-500/30', hex: '#a855f7' },
  { bg: 'bg-pink-500/20', text: 'text-pink-400', border: 'border-pink-500/30', hex: '#ec4899' },
  { bg: 'bg-sky-500/20', text: 'text-sky-400', border: 'border-sky-500/30', hex: '#0ea5e9' },
  { bg: 'bg-rose-500/20', text: 'text-rose-400', border: 'border-rose-500/30', hex: '#f43f5e' },
  { bg: 'bg-lime-500/20', text: 'text-lime-400', border: 'border-lime-500/30', hex: '#84cc16' },
  { bg: 'bg-orange-500/20', text: 'text-orange-400', border: 'border-orange-500/30', hex: '#f97316' },
  { bg: 'bg-cyan-500/20', text: 'text-cyan-400', border: 'border-cyan-500/30', hex: '#06b6d4' },
  { bg: 'bg-fuchsia-500/20', text: 'text-fuchsia-400', border: 'border-fuchsia-500/30', hex: '#d946ef' },
  { bg: 'bg-slate-500/20', text: 'text-slate-400', border: 'border-slate-500/30', hex: '#64748b' },
  { bg: 'bg-yellow-500/20', text: 'text-yellow-400', border: 'border-yellow-500/30', hex: '#eab308' },
  { bg: 'bg-indigo-500/20', text: 'text-indigo-400', border: 'border-indigo-500/30', hex: '#6366f1' },
]

// Default palette for fallback
const DEFAULT_PALETTE = { bg: 'bg-blue-500/20', text: 'text-blue-400', border: 'border-blue-500/30', hex: '#3b82f6' }

// Generate a deterministic but whimsical name from a speaker ID
export function generateWhimsicalName(speakerId: string, index: number): string {
  // Use a simple hash of the speakerId to pick adjective and animal
  let hash = 0
  for (let i = 0; i < speakerId.length; i++) {
    hash = ((hash << 5) - hash) + speakerId.charCodeAt(i)
    hash = hash & hash // Convert to 32bit integer
  }
  
  // Use both hash and index to ensure variety
  const adjIndex = Math.abs(hash + index) % ADJECTIVES.length
  const animalIndex = Math.abs(hash * 7 + index * 3) % ANIMALS.length
  
  return `${ADJECTIVES[adjIndex]} ${ANIMALS[animalIndex]}`
}

// Get color palette for a speaker based on their index
export function getSpeakerColorPalette(index: number) {
  return SPEAKER_COLOR_PALETTE[index % SPEAKER_COLOR_PALETTE.length] ?? DEFAULT_PALETTE
}

// Export types for use in other components
export interface SpeakerInfo {
  id: string
  name: string
  notes: string
  colorIndex: number
}

// Create initial speaker info from detected speakers
export function createSpeakerInfo(speakerId: string, index: number): SpeakerInfo {
  return {
    id: speakerId,
    name: generateWhimsicalName(speakerId, index),
    notes: '',
    colorIndex: index % SPEAKER_COLOR_PALETTE.length,
  }
}
