import { useRef, useEffect, useState, useMemo } from 'react'
import { ScrollArea } from '@/components/ui/scroll-area'
import { cn } from '@/lib/utils'
import { Clock } from 'lucide-react'
import type { TranscriptSegment } from '@/hooks/useScribeTranscription'
import { BrandMicIcon } from '@/components/ui/brand-icons'
import { getSpeakerName, getSpeakerColor } from '@/lib/speakerNames'

// Maximum recording time in milliseconds (1 hour)
const MAX_RECORDING_TIME_MS = 60 * 60 * 1000

interface TranscriptBoxProps {
  transcript: string
  segments: TranscriptSegment[]
  partialTranscript?: string
  isRecording?: boolean
  isPaused?: boolean
  isProcessing?: boolean
  isArchived?: boolean
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
  segments,
  partialTranscript = '',
  isRecording = false,
  isPaused = false,
  isProcessing = false,
  isArchived = false,
  recordingStartTime = null,
  onMaxTimeReached,
  className,
}: TranscriptBoxProps) {
  const scrollRef = useRef<HTMLDivElement>(null)
  const [elapsedTime, setElapsedTime] = useState(0)
  // Track time accumulated before pause
  const pausedTimeRef = useRef(0)
  const lastActiveTimeRef = useRef<number | null>(null)

  // Timer effect - handles pause/resume
  useEffect(() => {
    if (!isRecording || !recordingStartTime) {
      setElapsedTime(0)
      pausedTimeRef.current = 0
      lastActiveTimeRef.current = null
      return
    }

    // If paused, don't run the interval but preserve the elapsed time
    if (isPaused) {
      // Store the current elapsed time when pausing
      if (lastActiveTimeRef.current !== null) {
        pausedTimeRef.current = elapsedTime
      }
      lastActiveTimeRef.current = null
      return
    }

    // Resuming or starting - set the reference time
    if (lastActiveTimeRef.current === null) {
      lastActiveTimeRef.current = Date.now()
    }

    const updateTimer = () => {
      const now = Date.now()
      const activeElapsed = now - (lastActiveTimeRef.current ?? now)
      const totalElapsed = pausedTimeRef.current + activeElapsed
      setElapsedTime(totalElapsed)
      
      // Check if max time reached
      if (totalElapsed >= MAX_RECORDING_TIME_MS && onMaxTimeReached) {
        onMaxTimeReached()
      }
    }

    // Update immediately
    updateTimer()
    
    // Update every second
    const interval = setInterval(updateTimer, 1000)
    return () => clearInterval(interval)
  }, [isRecording, isPaused, recordingStartTime, onMaxTimeReached, elapsedTime])

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

  // Group text into paragraphs
  // First try sentence-ending punctuation, fallback to word count
  const formatIntoParagraphs = (text: string): string[] => {
    if (!text.trim()) return []
    
    const trimmedText = text.trim()
    
    // Check if text has sentence-ending punctuation
    const hasPunctuation = /[.!?]/.test(trimmedText)
    
    if (hasPunctuation) {
      // Split on sentence endings followed by space, but keep the punctuation
      const sentences = trimmedText.split(/(?<=[.!?])\s+/)
      
      // Group sentences into paragraphs (roughly 4-6 sentences per paragraph)
      const paragraphs: string[] = []
      let currentParagraph: string[] = []
      
      for (const sentence of sentences) {
        currentParagraph.push(sentence)
        
        // Start new paragraph after 5 sentences or if paragraph is long enough
        if (currentParagraph.length >= 5 || currentParagraph.join(' ').length > 500) {
          paragraphs.push(currentParagraph.join(' '))
          currentParagraph = []
        }
      }
      
      // Don't forget remaining sentences
      if (currentParagraph.length > 0) {
        paragraphs.push(currentParagraph.join(' '))
      }
      
      return paragraphs
    } else {
      // No punctuation - split by word count (roughly 75 words per paragraph)
      const words = trimmedText.split(/\s+/)
      const paragraphs: string[] = []
      
      for (let i = 0; i < words.length; i += 75) {
        const paragraphWords = words.slice(i, i + 75)
        paragraphs.push(paragraphWords.join(' '))
      }
      
      return paragraphs.length > 0 ? paragraphs : [trimmedText]
    }
  }

  // Group segments into paragraphs (every 4-6 sentences based on length)
  const groupedParagraphs = useMemo(() => {
    if (segments.length === 0) return formatIntoParagraphs(transcript)
    
    const paragraphs: string[] = []
    let currentParagraph: string[] = []
    let sentenceCount = 0
    
    for (const segment of segments) {
      currentParagraph.push(segment.text)
      
      // Count sentences in this segment (by sentence-ending punctuation)
      const sentencesInSegment = (segment.text.match(/[.!?]+/g) || []).length
      sentenceCount += Math.max(1, sentencesInSegment)
      
      // Start new paragraph after 4-6 sentences or when paragraph gets long
      const paragraphText = currentParagraph.join(' ')
      const shouldBreak = sentenceCount >= 5 || paragraphText.length > 500
      
      if (shouldBreak && currentParagraph.length > 0) {
        paragraphs.push(paragraphText)
        currentParagraph = []
        sentenceCount = 0
      }
    }
    
    // Don't forget remaining segments
    if (currentParagraph.length > 0) {
      paragraphs.push(currentParagraph.join(' '))
    }
    
    return paragraphs.length > 0 ? paragraphs : formatIntoParagraphs(transcript)
  }, [segments, transcript])
  
  // Check if we have multi-speaker content
  const hasSpeakers = useMemo(() => {
    return segments.some(s => s.speakerId !== null)
  }, [segments])

  return (
    <div
      className={cn(
        'relative flex-1 rounded-2xl bg-muted/20 border border-border/30 overflow-hidden flex flex-col min-h-0',
        'transition-all duration-300',
        className
      )}
    >
      {/* Status indicator - bottom right */}
      {(isProcessing || isArchived) && (
        <div className="absolute bottom-[13px] right-[13px] z-10">
          {isProcessing ? (
            <div className="flex items-center gap-2 px-3 py-1.5 rounded-full bg-[#00D4FF]/10 border border-[#00D4FF]/20 backdrop-blur-sm">
              <div className="h-2.5 w-2.5 animate-spin rounded-full border-[1.5px] border-[#00D4FF] border-t-transparent" />
              <span className="text-[11px] text-[#00D4FF] font-medium tracking-wide">Processing</span>
            </div>
          ) : isArchived ? (
            <div className="flex items-center gap-2 px-3 py-1.5 rounded-full bg-[#00D4FF]/10 border border-[#00D4FF]/20 backdrop-blur-sm">
              <svg className="h-2.5 w-2.5 text-[#00D4FF]" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round">
                <path d="M5 12L10 17L19 8" />
              </svg>
              <span className="text-[11px] text-[#00D4FF] font-medium tracking-wide">Saved</span>
            </div>
          ) : null}
        </div>
      )}

      {/* Transcript content */}
      <ScrollArea ref={scrollRef} className="flex-1 min-h-0">
        <div className="p-[21px] pb-[55px]">
          {hasContent ? (
            <div className={cn(
              "leading-[1.7]",
              // Use PP NeueBit (8-bit font) while transcribing - larger size for readability
              // PP Neue Montreal Mono when archived - standard size
              isRecording 
                ? "font-transcribe text-[20px] tracking-[0.02em]" 
                : "font-body text-[15px] tracking-[-0.01em]"
            )}>
              {/* Multi-speaker view - show speaker labels */}
              {hasSpeakers ? (
                <div className="space-y-[13px]">
                  {segments.map((segment, index) => {
                    const speakerName = segment.speakerId ? getSpeakerName(segment.speakerId) : null
                    const speakerColor = segment.speakerId ? getSpeakerColor(segment.speakerId) : null
                    const isLast = index === segments.length - 1
                    
                    return (
                      <div key={index} className="flex gap-3">
                        {speakerName && (
                          <span 
                            className="text-xs font-medium shrink-0 mt-1 opacity-80"
                            style={{ color: speakerColor || undefined }}
                          >
                            {speakerName}
                          </span>
                        )}
                        <p className="whitespace-pre-wrap flex-1 text-foreground/90">
                          {segment.text}
                          {/* Inline partial transcript after last segment */}
                          {isLast && partialTranscript && (
                            <span className="text-muted-foreground/60">
                              {' '}{partialTranscript}
                              {isRecording && (
                                <span className="inline-block w-[2px] h-[18px] bg-primary/80 ml-1 animate-pulse align-text-bottom rounded-full" />
                              )}
                            </span>
                          )}
                        </p>
                      </div>
                    )
                  })}
                  {/* Show partial alone if no segments yet */}
                  {segments.length === 0 && partialTranscript && (
                    <p className="whitespace-pre-wrap text-muted-foreground/60">
                      {partialTranscript}
                      {isRecording && (
                        <span className="inline-block w-[2px] h-[18px] bg-primary/80 ml-1 animate-pulse align-text-bottom rounded-full" />
                      )}
                    </p>
                  )}
                </div>
              ) : (
                /* Single speaker view - format into paragraphs with inline partial */
                <div className="space-y-[21px]">
                  {groupedParagraphs.map((paragraph, index) => {
                    const isLast = index === groupedParagraphs.length - 1
                    return (
                      <p key={index} className="whitespace-pre-wrap text-foreground/90">
                        {paragraph}
                        {/* Inline partial transcript after last paragraph */}
                        {isLast && partialTranscript && (
                          <span className="text-muted-foreground/60">
                            {' '}{partialTranscript}
                            {isRecording && (
                              <span className="inline-block w-[2px] h-[18px] bg-primary/80 ml-1 animate-pulse align-text-bottom rounded-full" />
                            )}
                          </span>
                        )}
                      </p>
                    )
                  })}
                  {/* Show partial alone if no paragraphs yet */}
                  {groupedParagraphs.length === 0 && partialTranscript && (
                    <p className="whitespace-pre-wrap text-muted-foreground/60">
                      {partialTranscript}
                      {isRecording && (
                        <span className="inline-block w-[2px] h-[18px] bg-primary/80 ml-1 animate-pulse align-text-bottom rounded-full" />
                      )}
                    </p>
                  )}
                </div>
              )}
            </div>
          ) : (
            <div className="flex flex-col items-center justify-center h-full min-h-[144px] py-[34px] gap-[13px]">
              <BrandMicIcon size={34} className="text-muted-foreground/20" />
              <p className="text-[13px] text-muted-foreground/30 tracking-wide">Press R to start recording</p>
            </div>
          )}
        </div>
      </ScrollArea>

      {/* Timer - only show when recording */}
      {isRecording && recordingStartTime && (
        <div className="absolute bottom-[13px] right-[13px] flex items-center gap-2 px-3 py-1.5 rounded-lg bg-background/80 backdrop-blur-sm border border-border/30">
          <Clock className={cn('h-3.5 w-3.5', isLowTime ? 'text-[#EAB308]' : 'text-muted-foreground/60')} />
          <span className={cn(
            'text-[11px] font-mono tabular-nums tracking-wide',
            isLowTime ? 'text-[#EAB308]' : 'text-muted-foreground/60'
          )}>
            {formatTime(remainingTime)}
          </span>
        </div>
      )}
    </div>
  )
}
