import { useRef, useEffect, useState } from 'react'
import { ScrollArea } from '@/components/ui/scroll-area'
import { cn } from '@/lib/utils'
import { Clock } from 'lucide-react'
import type { TranscriptSegment } from '@/hooks/useScribeTranscription'

// Maximum recording time in milliseconds (1 hour)
const MAX_RECORDING_TIME_MS = 60 * 60 * 1000

interface TranscriptBoxProps {
  transcript: string
  segments: TranscriptSegment[]
  partialTranscript?: string
  isRecording?: boolean
  recordingStartTime?: number | null
  onMaxTimeReached?: () => void
  className?: string
}

function formatTime(ms: number): string {
  const totalSeconds = Math.floor(ms / 1000)
  const hours = Math.floor(totalSeconds / 3600)
  const minutes = Math.floor((totalSeconds % 3600) / 60)
  const seconds = totalSeconds % 60
  
  if (hours > 0) {
    return `${hours}:${minutes.toString().padStart(2, '0')}:${seconds.toString().padStart(2, '0')}`
  }
  return `${minutes}:${seconds.toString().padStart(2, '0')}`
}

export function TranscriptBox({
  transcript,
  segments: _segments,
  partialTranscript = '',
  isRecording = false,
  recordingStartTime = null,
  onMaxTimeReached,
  className,
}: TranscriptBoxProps) {
  const scrollRef = useRef<HTMLDivElement>(null)
  const [elapsedTime, setElapsedTime] = useState(0)

  // Timer effect
  useEffect(() => {
    if (!isRecording || !recordingStartTime) {
      setElapsedTime(0)
      return
    }

    const updateTimer = () => {
      const elapsed = Date.now() - recordingStartTime
      setElapsedTime(elapsed)
      
      // Check if max time reached
      if (elapsed >= MAX_RECORDING_TIME_MS && onMaxTimeReached) {
        onMaxTimeReached()
      }
    }

    // Update immediately
    updateTimer()
    
    // Update every second
    const interval = setInterval(updateTimer, 1000)
    return () => clearInterval(interval)
  }, [isRecording, recordingStartTime, onMaxTimeReached])

  // Auto-scroll to bottom when transcript changes
  useEffect(() => {
    if (scrollRef.current) {
      const scrollContainer = scrollRef.current.querySelector('[data-radix-scroll-area-viewport]')
      if (scrollContainer) {
        scrollContainer.scrollTop = scrollContainer.scrollHeight
      }
    }
  }, [transcript, partialTranscript])

  const hasContent = transcript || partialTranscript
  const remainingTime = MAX_RECORDING_TIME_MS - elapsedTime
  const isLowTime = remainingTime < 5 * 60 * 1000 // Less than 5 minutes

  // Group text into paragraphs based on sentence-ending punctuation
  // Split on sentences that end with . ! or ? followed by a space
  const formatIntoParagraphs = (text: string): string[] => {
    if (!text.trim()) return []
    
    // Split on sentence endings followed by space, but keep the punctuation
    const sentences = text.split(/(?<=[.!?])\s+/)
    
    // Group sentences into paragraphs (roughly 2-4 sentences per paragraph)
    const paragraphs: string[] = []
    let currentParagraph: string[] = []
    
    for (const sentence of sentences) {
      currentParagraph.push(sentence)
      
      // Start new paragraph after 3 sentences or if sentence is long
      if (currentParagraph.length >= 3 || currentParagraph.join(' ').length > 300) {
        paragraphs.push(currentParagraph.join(' '))
        currentParagraph = []
      }
    }
    
    // Don't forget remaining sentences
    if (currentParagraph.length > 0) {
      paragraphs.push(currentParagraph.join(' '))
    }
    
    return paragraphs
  }

  const paragraphs = formatIntoParagraphs(transcript)

  return (
    <div
      className={cn(
        'relative flex-1 rounded-xl bg-muted/30 border border-border/50 overflow-hidden flex flex-col min-h-0',
        className
      )}
    >
      {/* Transcript content */}
      <ScrollArea ref={scrollRef} className="flex-1 min-h-0">
        <div className="p-4 pb-10">
          {hasContent ? (
            <div className="text-sm leading-relaxed space-y-4">
              {paragraphs.map((paragraph, index) => (
                <p key={index} className="whitespace-pre-wrap">
                  {paragraph}
                </p>
              ))}
              {partialTranscript && (
                <p className="text-muted-foreground/70 italic">
                  {partialTranscript}
                </p>
              )}
            </div>
          ) : (
            <p className="text-sm text-muted-foreground/50 italic">
              Start recording to see the transcript…
            </p>
          )}
        </div>
      </ScrollArea>

      {/* Timer - only show when recording */}
      {isRecording && recordingStartTime && (
        <div className="absolute bottom-2 right-3 flex items-center gap-1.5 px-2 py-1 rounded-md bg-background/80 backdrop-blur-sm border border-border/50">
          <Clock className={cn('h-3 w-3', isLowTime ? 'text-amber-500' : 'text-muted-foreground')} />
          <span className={cn(
            'text-xs font-mono tabular-nums',
            isLowTime ? 'text-amber-500' : 'text-muted-foreground'
          )}>
            {formatTime(remainingTime)}
          </span>
        </div>
      )}
    </div>
  )
}
