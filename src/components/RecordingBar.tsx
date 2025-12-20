import { useState, useEffect } from 'react'
import {
  BrandMicIcon,
  BrandLanguagesIcon,
  BrandRecordIcon,
  BrandStopIcon,
} from '@/components/ui/brand-icons'
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
const SCRIBE_LANGUAGES = [
  { code: 'en', name: 'English' },
  { code: 'fr', name: 'French' },
  { code: 'de', name: 'German' },
  { code: 'it', name: 'Italian' },
  { code: 'es', name: 'Spanish' },
  { code: 'pt', name: 'Portuguese' },
  { code: 'hi', name: 'Hindi' },
  { code: 'ja', name: 'Japanese' },
  { code: 'th', name: 'Thai' },
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
          'flex-1 basis-1/3 h-[40px] flex items-center px-4 rounded-xl transition-all duration-200',
          'bg-muted/40 hover:bg-muted/60 shadow-sm',
          isRecording && 'bg-destructive/20 hover:bg-destructive/30',
          isProcessing && 'opacity-70',
          (disabled || isLoading || isProcessing) && 'cursor-not-allowed opacity-50'
        )}
      >
        {isLoading || isProcessing ? (
          <div className="h-4 w-4 animate-spin rounded-full border-2 border-current border-t-transparent opacity-50 shrink-0" />
        ) : isRecording ? (
          <BrandStopIcon size={18} className="opacity-50 shrink-0" />
        ) : (
          <BrandRecordIcon size={18} className="opacity-50 shrink-0" />
        )}
        <span className="flex-1 text-center text-[12px] opacity-70">
          {isProcessing ? 'Processing' : isRecording ? 'End' : hasContent ? 'New' : 'Record'}
        </span>
        {!isProcessing && <Kbd className="shrink-0">{isRecording ? 'E' : 'R'}</Kbd>}
      </button>

      {/* Microphone Selector - 1/3 width */}
      <Select
        value={effectiveDeviceId}
        onValueChange={onDeviceChange}
        disabled={isRecording}
      >
        <SelectTrigger className="flex-1 basis-1/3 min-w-0 h-[40px] bg-muted/40 border-0 gap-2 rounded-xl hover:bg-muted/60 transition-all duration-200 shadow-sm">
          <BrandMicIcon size={18} className="opacity-50 shrink-0" />
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
          <BrandLanguagesIcon size={18} className="opacity-50 shrink-0" />
          <SelectValue>
            <span className="truncate text-[12px] opacity-70">{currentLanguage?.name}</span>
          </SelectValue>
        </SelectTrigger>
        <SelectContent className="rounded-xl border-border/30 shadow-xl">
          {SCRIBE_LANGUAGES.map((lang) => (
            <SelectItem key={lang.code} value={lang.code} className="rounded-lg text-[13px]">
              {lang.name}
            </SelectItem>
          ))}
        </SelectContent>
      </Select>
    </div>
  )
}
