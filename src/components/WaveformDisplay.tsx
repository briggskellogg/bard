import { LiveWaveform } from '@/components/ui/live-waveform'
import { cn } from '@/lib/utils'
import { Key, Info } from 'lucide-react'
import {
  Tooltip,
  TooltipContent,
  TooltipProvider,
  TooltipTrigger,
} from '@/components/ui/tooltip'

interface WaveformDisplayProps {
  isRecording: boolean
  isPaused?: boolean
  isProcessing?: boolean
  deviceId?: string
  className?: string
  apiConnected?: boolean
  apiError?: string | null
  onKeyClick?: () => void
}

export function WaveformDisplay({
  isRecording,
  isPaused = false,
  isProcessing = false,
  deviceId,
  className,
  apiConnected = false,
  apiError = null,
  onKeyClick,
}: WaveformDisplayProps) {
  // Determine recording status
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
        {/* Left: Recording status */}
        <div className="flex items-center gap-2">
          <div className={cn(
            'h-2 w-2 rounded-full',
            status === 'Live' && 'bg-[#EF4444] animate-pulse',
            status === 'Paused' && 'bg-[#EAB308]',
            status === 'Offline' && 'bg-gray-400'
          )} />
          <span className={cn(
            'text-xs font-medium',
            status === 'Live' && 'text-foreground',
            status === 'Paused' && 'text-[#EAB308]',
            status === 'Offline' && 'text-muted-foreground'
          )}>
            {status}
          </span>
        </div>

        {/* Right: API status + Key */}
        <div className="flex items-center gap-2">
          {/* API connection status */}
          <div className="flex items-center gap-1.5">
            <div className={cn(
              'h-2 w-2 rounded-full',
              apiConnected && !apiError && 'bg-[#22c55e]',
              apiError && 'bg-[#EF4444]',
              !apiConnected && !apiError && 'bg-gray-400'
            )} />
            <span className={cn(
              'text-xs font-medium',
              apiConnected && !apiError && 'text-[#22c55e]',
              apiError && 'text-[#EF4444]',
              !apiConnected && !apiError && 'text-muted-foreground'
            )}>
              {apiConnected && !apiError ? 'Connected' : 'Disconnected'}
            </span>
          </div>

          {/* Error info tooltip */}
          {apiError && (
            <TooltipProvider delayDuration={0}>
              <Tooltip>
                <TooltipTrigger asChild>
                  <button 
                    className="p-0.5 rounded hover:bg-muted/50 transition-colors cursor-pointer"
                    aria-label="API error details"
                  >
                    <Info className="h-3.5 w-3.5 text-[#EF4444]/70" />
                  </button>
                </TooltipTrigger>
                <TooltipContent 
                  side="top" 
                  className="max-w-[200px] text-xs bg-background border-border/50"
                >
                  {apiError}
                </TooltipContent>
              </Tooltip>
            </TooltipProvider>
          )}

          {/* Key button */}
          <button
            onClick={onKeyClick}
            className="p-1 rounded-md hover:bg-muted/50 transition-colors cursor-pointer"
            aria-label="Edit API key"
          >
            <Key className="h-4 w-4 text-muted-foreground/70 hover:text-foreground transition-colors" />
          </button>
        </div>
      </div>
    </div>
  )
}
