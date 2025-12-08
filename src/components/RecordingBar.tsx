import { useState, useEffect } from 'react'
import { Mic, Languages, Pause, Play } from 'lucide-react'
import { Button } from '@/components/ui/button'
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
      'inline-flex items-center justify-center px-1.5 py-0.5 rounded',
      'bg-muted/80 border border-border/50 text-[10px] font-medium text-muted-foreground',
      'min-w-[18px]',
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
  isPaused?: boolean
  isLoading?: boolean
  disabled?: boolean
  onStartRecording: () => void
  onStopRecording: () => void
  onPauseRecording?: () => void
  onResumeRecording?: () => void
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
  isPaused = false,
  isLoading = false,
  disabled = false,
  onStartRecording,
  onStopRecording,
  onPauseRecording,
  onResumeRecording,
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
      return `(Default) ${defaultDeviceLabel}`
    }
    const device = devices.find(d => d.deviceId === effectiveDeviceId)
    return getCleanDeviceName(device?.label)
  }

  const handlePauseToggle = () => {
    if (isPaused) {
      onResumeRecording?.()
    } else {
      onPauseRecording?.()
    }
  }

  return (
    <div className="flex items-center gap-2 p-2 rounded-xl bg-muted/30 border border-border/50">
      {/* Start/Stop Recording Button */}
      <Button
        variant={isRecording ? "destructive" : "secondary"}
        onClick={isRecording ? onStopRecording : onStartRecording}
        disabled={disabled || isLoading}
        className={cn(
          'flex-1 h-10 gap-2 font-medium',
          !isRecording && 'bg-muted hover:bg-muted/80'
        )}
      >
        {isLoading ? (
          <div className="h-4 w-4 animate-spin rounded-full border-2 border-current border-t-transparent" />
        ) : (
          <>
            {isRecording ? 'Stop Recording' : 'Start Recording'}
          </>
        )}
        <Kbd>R</Kbd>
      </Button>

      {/* Pause/Resume Button - only visible when recording */}
      {isRecording && (
        <Button
          variant="secondary"
          size="icon"
          onClick={handlePauseToggle}
          className={cn(
            'h-10 w-10 shrink-0',
            isPaused && 'bg-amber-500/20 text-amber-500 hover:bg-amber-500/30'
          )}
        >
          {isPaused ? (
            <Play className="h-4 w-4" />
          ) : (
            <Pause className="h-4 w-4" />
          )}
        </Button>
      )}

      {/* Microphone Selector */}
      <Select
        value={effectiveDeviceId}
        onValueChange={onDeviceChange}
        disabled={isRecording}
      >
        <SelectTrigger className="flex-1 min-w-0 h-10 bg-transparent border-0 gap-2">
          <Mic className="h-4 w-4 text-muted-foreground shrink-0" />
          <SelectValue placeholder="Select mic">
            <span className="truncate text-sm block max-w-[120px]">
              {getSelectedDeviceDisplay()}
            </span>
          </SelectValue>
        </SelectTrigger>
        <SelectContent>
          {/* Default option */}
          <SelectItem value="default">
            (Default) {defaultDeviceLabel}
          </SelectItem>
          {/* Other devices - exclude the actual 'default' device to avoid duplication */}
          {devices
            .filter(d => d.deviceId !== 'default')
            .map((device) => (
              <SelectItem key={device.deviceId} value={device.deviceId}>
                {device.label || `Microphone ${device.deviceId.slice(0, 8)}`}
              </SelectItem>
            ))}
        </SelectContent>
      </Select>

      {/* Language Selector */}
      <Select
        value={selectedLanguage}
        onValueChange={(value) => onLanguageChange(value as ScribeLanguageCode)}
        disabled={isRecording}
      >
        <SelectTrigger className="flex-1 h-10 bg-transparent border-0 gap-2">
          <Languages className="h-4 w-4 text-muted-foreground shrink-0" />
          <SelectValue>
            <span className="truncate text-sm">{currentLanguage?.name}</span>
          </SelectValue>
        </SelectTrigger>
        <SelectContent>
          {SCRIBE_LANGUAGES.map((lang) => (
            <SelectItem key={lang.code} value={lang.code}>
              {lang.name}
            </SelectItem>
          ))}
        </SelectContent>
      </Select>
    </div>
  )
}
