import { LiveWaveform } from '@/components/ui/live-waveform'
import { cn } from '@/lib/utils'

interface WaveformDisplayProps {
  isRecording: boolean
  isPaused?: boolean
  isProcessing?: boolean
  deviceId?: string
  className?: string
}

export function WaveformDisplay({
  isRecording,
  isPaused = false,
  isProcessing = false,
  deviceId,
  className,
}: WaveformDisplayProps) {
  // Determine status
  const getStatus = () => {
    if (isPaused) return 'Paused'
    if (isRecording) return 'Live'
    return 'Offline'
  }

  const status = getStatus()

  return (
    <div
      className={cn(
        'relative rounded-xl bg-muted/30 overflow-hidden',
        'border border-border/50',
        className
      )}
    >
      {/* Waveform area */}
      <div className="h-24">
        <LiveWaveform
          key={isRecording ? 'recording' : 'idle'}
          active={isRecording && !isPaused}
          processing={isProcessing}
          deviceId={deviceId}
          mode="scrolling"
          barWidth={3}
          barGap={2}
          barRadius={1.5}
          sensitivity={1.8}
          height={96}
          historySize={200}
          fadeEdges={false}
          className="text-primary"
        />
      </div>

      {/* Status bar */}
      <div className="flex items-center justify-between px-3 py-2 border-t border-border/30 bg-background/50">
        <div className="flex items-center gap-2">
          <div className={cn(
            'h-2 w-2 rounded-full',
            status === 'Live' && 'bg-red-500 animate-pulse',
            status === 'Paused' && 'bg-amber-500',
            status === 'Offline' && 'bg-gray-400'
          )} />
          <span className={cn(
            'text-xs font-medium',
            status === 'Live' && 'text-foreground',
            status === 'Paused' && 'text-amber-500',
            status === 'Offline' && 'text-muted-foreground'
          )}>
            {status}
          </span>
        </div>
      </div>
    </div>
  )
}
