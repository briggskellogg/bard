import { useState, useEffect } from 'react'
import { Mic, Languages, PlayCircle, StopCircle, FilePlus } from 'lucide-react'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { cn } from '@/lib/utils'

function Kbd({ children, className }: { children: React.ReactNode; className?: string }) {
  return (
    <kbd className={cn(
      'inline-flex items-center justify-center px-[6px] py-[2px] rounded-[4px]',
      'bg-background/60 border border-border/40 text-[10px] font-medium text-muted-foreground/80',
      'min-w-[18px] min-h-[18px] backdrop-blur-sm',
      className
    )}>
      {children}
    </kbd>
  )
}

// Scribe v2 supported languages
// Language quality tiers for ElevenLabs Scribe v2
type QualityTier = 'excellent' | 'high' | 'good' | 'moderate'

const SCRIBE_LANGUAGES = [
  // Excellent accuracy
  { code: 'bg', name: 'Bulgarian', tier: 'excellent' as QualityTier },
  { code: 'ca', name: 'Catalan', tier: 'excellent' as QualityTier },
  { code: 'cs', name: 'Czech', tier: 'excellent' as QualityTier },
  { code: 'da', name: 'Danish', tier: 'excellent' as QualityTier },
  { code: 'nl', name: 'Dutch', tier: 'excellent' as QualityTier },
  { code: 'en', name: 'English', tier: 'excellent' as QualityTier },
  { code: 'fi', name: 'Finnish', tier: 'excellent' as QualityTier },
  { code: 'fr', name: 'French', tier: 'excellent' as QualityTier },
  { code: 'gl', name: 'Galician', tier: 'excellent' as QualityTier },
  { code: 'de', name: 'German', tier: 'excellent' as QualityTier },
  { code: 'el', name: 'Greek', tier: 'excellent' as QualityTier },
  { code: 'hi', name: 'Hindi', tier: 'excellent' as QualityTier },
  { code: 'id', name: 'Indonesian', tier: 'excellent' as QualityTier },
  { code: 'it', name: 'Italian', tier: 'excellent' as QualityTier },
  { code: 'ja', name: 'Japanese', tier: 'excellent' as QualityTier },
  { code: 'kn', name: 'Kannada', tier: 'excellent' as QualityTier },
  { code: 'ms', name: 'Malay', tier: 'excellent' as QualityTier },
  { code: 'ml', name: 'Malayalam', tier: 'excellent' as QualityTier },
  { code: 'mk', name: 'Macedonian', tier: 'excellent' as QualityTier },
  { code: 'no', name: 'Norwegian', tier: 'excellent' as QualityTier },
  { code: 'pl', name: 'Polish', tier: 'excellent' as QualityTier },
  { code: 'pt', name: 'Portuguese', tier: 'excellent' as QualityTier },
  { code: 'ro', name: 'Romanian', tier: 'excellent' as QualityTier },
  { code: 'ru', name: 'Russian', tier: 'excellent' as QualityTier },
  { code: 'sr', name: 'Serbian', tier: 'excellent' as QualityTier },
  { code: 'sk', name: 'Slovak', tier: 'excellent' as QualityTier },
  { code: 'es', name: 'Spanish', tier: 'excellent' as QualityTier },
  { code: 'sv', name: 'Swedish', tier: 'excellent' as QualityTier },
  { code: 'tr', name: 'Turkish', tier: 'excellent' as QualityTier },
  { code: 'uk', name: 'Ukrainian', tier: 'excellent' as QualityTier },
  { code: 'vi', name: 'Vietnamese', tier: 'excellent' as QualityTier },
  // High accuracy
  { code: 'bn', name: 'Bengali', tier: 'high' as QualityTier },
  { code: 'be', name: 'Belarusian', tier: 'high' as QualityTier },
  { code: 'bs', name: 'Bosnian', tier: 'high' as QualityTier },
  { code: 'yue', name: 'Cantonese', tier: 'high' as QualityTier },
  { code: 'et', name: 'Estonian', tier: 'high' as QualityTier },
  { code: 'fil', name: 'Filipino', tier: 'high' as QualityTier },
  { code: 'gu', name: 'Gujarati', tier: 'high' as QualityTier },
  { code: 'hu', name: 'Hungarian', tier: 'high' as QualityTier },
  { code: 'kk', name: 'Kazakh', tier: 'high' as QualityTier },
  { code: 'lv', name: 'Latvian', tier: 'high' as QualityTier },
  { code: 'lt', name: 'Lithuanian', tier: 'high' as QualityTier },
  { code: 'zh', name: 'Mandarin', tier: 'high' as QualityTier },
  { code: 'mr', name: 'Marathi', tier: 'high' as QualityTier },
  { code: 'ne', name: 'Nepali', tier: 'high' as QualityTier },
  { code: 'or', name: 'Odia', tier: 'high' as QualityTier },
  { code: 'fa', name: 'Persian', tier: 'high' as QualityTier },
  { code: 'sl', name: 'Slovenian', tier: 'high' as QualityTier },
  { code: 'ta', name: 'Tamil', tier: 'high' as QualityTier },
  { code: 'te', name: 'Telugu', tier: 'high' as QualityTier },
  // Good accuracy
  { code: 'af', name: 'Afrikaans', tier: 'good' as QualityTier },
  { code: 'ar', name: 'Arabic', tier: 'good' as QualityTier },
  { code: 'hy', name: 'Armenian', tier: 'good' as QualityTier },
  { code: 'as', name: 'Assamese', tier: 'good' as QualityTier },
  { code: 'ast', name: 'Asturian', tier: 'good' as QualityTier },
  { code: 'az', name: 'Azerbaijani', tier: 'good' as QualityTier },
  { code: 'my', name: 'Burmese', tier: 'good' as QualityTier },
  { code: 'ceb', name: 'Cebuano', tier: 'good' as QualityTier },
  { code: 'hr', name: 'Croatian', tier: 'good' as QualityTier },
  { code: 'ka', name: 'Georgian', tier: 'good' as QualityTier },
  { code: 'ha', name: 'Hausa', tier: 'good' as QualityTier },
  { code: 'he', name: 'Hebrew', tier: 'good' as QualityTier },
  { code: 'is', name: 'Icelandic', tier: 'good' as QualityTier },
  { code: 'jv', name: 'Javanese', tier: 'good' as QualityTier },
  { code: 'kea', name: 'Kabuverdianu', tier: 'good' as QualityTier },
  { code: 'ko', name: 'Korean', tier: 'good' as QualityTier },
  { code: 'ky', name: 'Kyrgyz', tier: 'good' as QualityTier },
  { code: 'ln', name: 'Lingala', tier: 'good' as QualityTier },
  { code: 'mt', name: 'Maltese', tier: 'good' as QualityTier },
  { code: 'mn', name: 'Mongolian', tier: 'good' as QualityTier },
  { code: 'mi', name: 'Māori', tier: 'good' as QualityTier },
  { code: 'oc', name: 'Occitan', tier: 'good' as QualityTier },
  { code: 'pa', name: 'Punjabi', tier: 'good' as QualityTier },
  { code: 'sd', name: 'Sindhi', tier: 'good' as QualityTier },
  { code: 'sw', name: 'Swahili', tier: 'good' as QualityTier },
  { code: 'tg', name: 'Tajik', tier: 'good' as QualityTier },
  { code: 'th', name: 'Thai', tier: 'good' as QualityTier },
  { code: 'ur', name: 'Urdu', tier: 'good' as QualityTier },
  { code: 'uz', name: 'Uzbek', tier: 'good' as QualityTier },
  { code: 'cy', name: 'Welsh', tier: 'good' as QualityTier },
  // Moderate accuracy
  { code: 'am', name: 'Amharic', tier: 'moderate' as QualityTier },
  { code: 'ny', name: 'Chichewa', tier: 'moderate' as QualityTier },
  { code: 'ff', name: 'Fulah', tier: 'moderate' as QualityTier },
  { code: 'lg', name: 'Ganda', tier: 'moderate' as QualityTier },
  { code: 'ig', name: 'Igbo', tier: 'moderate' as QualityTier },
  { code: 'ga', name: 'Irish', tier: 'moderate' as QualityTier },
  { code: 'km', name: 'Khmer', tier: 'moderate' as QualityTier },
  { code: 'ku', name: 'Kurdish', tier: 'moderate' as QualityTier },
  { code: 'lo', name: 'Lao', tier: 'moderate' as QualityTier },
  { code: 'lb', name: 'Luxembourgish', tier: 'moderate' as QualityTier },
  { code: 'luo', name: 'Luo', tier: 'moderate' as QualityTier },
  { code: 'nso', name: 'Northern Sotho', tier: 'moderate' as QualityTier },
  { code: 'ps', name: 'Pashto', tier: 'moderate' as QualityTier },
  { code: 'sn', name: 'Shona', tier: 'moderate' as QualityTier },
  { code: 'so', name: 'Somali', tier: 'moderate' as QualityTier },
  { code: 'umb', name: 'Umbundu', tier: 'moderate' as QualityTier },
  { code: 'wo', name: 'Wolof', tier: 'moderate' as QualityTier },
  { code: 'xh', name: 'Xhosa', tier: 'moderate' as QualityTier },
  { code: 'zu', name: 'Zulu', tier: 'moderate' as QualityTier },
] as const

export type ScribeLanguageCode = typeof SCRIBE_LANGUAGES[number]['code']

interface RecordingBarProps {
  isRecording: boolean
  isLoading?: boolean
  isProcessing?: boolean  // True when analyzing/archiving after recording ends
  disabled?: boolean
  hasContent?: boolean
  onStartRecording: () => void
  onStopRecording: () => void
  selectedDeviceId?: string
  onDeviceChange?: (deviceId: string) => void
  selectedLanguage: ScribeLanguageCode
  onLanguageChange: (language: ScribeLanguageCode) => void
}

// Helper to get a clean device name
function getCleanDeviceName(label: string | undefined): string {
  if (!label) return 'Microphone'
  // Remove parenthetical info like "(Built-in)" for display
  return label.replace(/\s*\(.*?\)\s*/g, '').trim() || 'Microphone'
}

export function RecordingBar({
  isRecording,
  isLoading = false,
  isProcessing = false,
  disabled = false,
  hasContent = false,
  onStartRecording,
  onStopRecording,
  selectedDeviceId,
  onDeviceChange,
  selectedLanguage,
  onLanguageChange,
}: RecordingBarProps) {
  const [devices, setDevices] = useState<MediaDeviceInfo[]>([])
  const [defaultDeviceLabel, setDefaultDeviceLabel] = useState<string>('Microphone')

  // Fetch available audio input devices
  useEffect(() => {
    // Check if mediaDevices API is available
    if (!navigator.mediaDevices) {
      console.warn('navigator.mediaDevices is not available')
      return
    }

    async function getDevices() {
      try {
        // Request permission first
        await navigator.mediaDevices.getUserMedia({ audio: true })
        const allDevices = await navigator.mediaDevices.enumerateDevices()
        const audioInputs = allDevices.filter(d => d.kind === 'audioinput')
        setDevices(audioInputs)
        
        // Find the default device (usually first or has 'default' in deviceId)
        const defaultDevice = audioInputs.find(d => d.deviceId === 'default') || audioInputs[0]
        if (defaultDevice) {
          setDefaultDeviceLabel(getCleanDeviceName(defaultDevice.label))
        }
      } catch (error) {
        console.error('Failed to get audio devices:', error)
      }
    }
    getDevices()

    // Listen for device changes
    navigator.mediaDevices.addEventListener('devicechange', getDevices)
    return () => navigator.mediaDevices.removeEventListener('devicechange', getDevices)
  }, [])

  // Use 'default' as the default value
  const effectiveDeviceId = selectedDeviceId || 'default'
  const currentLanguage = SCRIBE_LANGUAGES.find(l => l.code === selectedLanguage) || SCRIBE_LANGUAGES[0]

  // Get display name for selected device
  const getSelectedDeviceDisplay = () => {
    if (effectiveDeviceId === 'default') {
      return `${defaultDeviceLabel}`
    }
    const device = devices.find(d => d.deviceId === effectiveDeviceId)
    return getCleanDeviceName(device?.label)
  }

  return (
    <div className="flex items-center gap-2 p-[6px] rounded-2xl bg-muted/10 border border-border/20">
      {/* Start/Stop Recording Button - 1/3 width */}
      <button
        onClick={isRecording ? onStopRecording : onStartRecording}
        disabled={disabled || isLoading || isProcessing}
        className={cn(
          'flex-1 basis-1/3 min-w-0 h-[40px] flex items-center gap-2 px-4 rounded-xl transition-all duration-200',
          'bg-muted/40 hover:bg-muted/60 shadow-sm',
          isRecording && 'bg-destructive/20 hover:bg-destructive/30',
          isProcessing && 'opacity-70',
          (disabled || isLoading || isProcessing) && 'cursor-not-allowed opacity-50'
        )}
      >
        {isLoading || isProcessing ? (
          <div className="h-4 w-4 animate-spin rounded-full border-2 border-current border-t-transparent opacity-50 shrink-0" />
        ) : isRecording ? (
          <StopCircle size={18} className="opacity-50 shrink-0" />
        ) : hasContent ? (
          <FilePlus size={18} className="opacity-50 shrink-0" />
        ) : (
          <PlayCircle size={18} className="opacity-50 shrink-0" />
        )}
        <span className="flex-1 text-[12px] opacity-70 truncate">
          {isProcessing ? 'Processing' : isRecording ? 'End' : 'Record'}
        </span>
        {!isProcessing && <Kbd className="shrink-0 gap-0.5"><span className="text-[10px]">⌘</span><span className="text-[10px]">↩</span></Kbd>}
      </button>

      {/* Microphone Selector - 1/3 width */}
      <Select
        value={effectiveDeviceId}
        onValueChange={onDeviceChange}
        disabled={isRecording}
      >
        <SelectTrigger className="flex-1 basis-1/3 min-w-0 h-[40px] bg-muted/40 border-0 gap-2 rounded-xl hover:bg-muted/60 transition-all duration-200 shadow-sm">
          <Mic size={18} className="opacity-50 shrink-0" />
          <SelectValue placeholder="Select mic">
            <span className="truncate text-[12px] opacity-70">
              {getSelectedDeviceDisplay()}
            </span>
          </SelectValue>
        </SelectTrigger>
        <SelectContent className="rounded-xl border-border/30 shadow-xl">
          <SelectItem value="default" className="rounded-lg text-[13px]">
            Default · {defaultDeviceLabel}
          </SelectItem>
          {devices
            .filter(d => d.deviceId !== 'default')
            .map((device) => (
              <SelectItem key={device.deviceId} value={device.deviceId} className="rounded-lg text-[13px]">
                {device.label || `Microphone ${device.deviceId.slice(0, 8)}`}
              </SelectItem>
            ))}
        </SelectContent>
      </Select>

      {/* Language Selector - 1/3 width */}
      <Select
        value={selectedLanguage}
        onValueChange={(value) => onLanguageChange(value as ScribeLanguageCode)}
        disabled={isRecording}
      >
        <SelectTrigger className="flex-1 basis-1/3 min-w-0 h-[40px] bg-muted/40 border-0 gap-2 rounded-xl hover:bg-muted/60 transition-all duration-200 shadow-sm">
          <Languages size={18} className="opacity-50 shrink-0" />
          <SelectValue>
            <span className="truncate text-[12px] opacity-70">{currentLanguage?.name}</span>
          </SelectValue>
        </SelectTrigger>
        <SelectContent className="rounded-xl border-border/30 shadow-xl max-h-[300px]">
          {SCRIBE_LANGUAGES.map((lang) => (
            <SelectItem key={lang.code} value={lang.code} className="rounded-lg text-[13px]">
              <span className="flex items-center gap-2">
                {lang.name}
                <span className={cn(
                  'text-[9px] px-1.5 py-0.5 rounded-full font-medium',
                  lang.tier === 'excellent' && 'bg-emerald-500/20 text-emerald-400',
                  lang.tier === 'high' && 'bg-blue-500/20 text-blue-400',
                  lang.tier === 'good' && 'bg-amber-500/20 text-amber-400',
                  lang.tier === 'moderate' && 'bg-orange-500/20 text-orange-400',
                )}>
                  {lang.tier}
                </span>
              </span>
            </SelectItem>
          ))}
        </SelectContent>
      </Select>
    </div>
  )
}
