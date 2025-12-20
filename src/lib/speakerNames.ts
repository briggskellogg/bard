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

// Echo brand color palette for speakers
export const SPEAKER_COLOR_PALETTE = [
  { bg: 'bg-[#EF4444]/20', text: 'text-[#EF4444]', border: 'border-[#EF4444]/30', hex: '#EF4444' }, // Red
  { bg: 'bg-[#00D4FF]/20', text: 'text-[#00D4FF]', border: 'border-[#00D4FF]/30', hex: '#00D4FF' }, // Cyan
  { bg: 'bg-[#E040FB]/20', text: 'text-[#E040FB]', border: 'border-[#E040FB]/30', hex: '#E040FB' }, // Pink
  { bg: 'bg-[#EAB308]/20', text: 'text-[#EAB308]', border: 'border-[#EAB308]/30', hex: '#EAB308' }, // Yellow
]

// Default palette for fallback
const DEFAULT_PALETTE = { bg: 'bg-[#00D4FF]/20', text: 'text-[#00D4FF]', border: 'border-[#00D4FF]/30', hex: '#00D4FF' }

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

// Cache for speaker names and colors
const speakerCache = new Map<string, { name: string; color: string; index: number }>()
let speakerCounter = 0

// Get a friendly name for a speaker ID (cached)
export function getSpeakerName(speakerId: string): string {
  if (!speakerCache.has(speakerId)) {
    const index = speakerCounter++
    const name = generateWhimsicalName(speakerId, index)
    const color = SPEAKER_COLOR_PALETTE[index % SPEAKER_COLOR_PALETTE.length]?.hex ?? DEFAULT_PALETTE.hex
    speakerCache.set(speakerId, { name, color, index })
  }
  return speakerCache.get(speakerId)!.name
}

// Get the color for a speaker ID (cached)
export function getSpeakerColor(speakerId: string): string {
  if (!speakerCache.has(speakerId)) {
    getSpeakerName(speakerId) // This will populate the cache
  }
  return speakerCache.get(speakerId)!.color
}

// Reset the speaker cache (call when starting a new recording)
export function resetSpeakerCache(): void {
  speakerCache.clear()
  speakerCounter = 0
}
