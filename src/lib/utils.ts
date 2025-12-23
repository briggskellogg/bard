import { clsx, type ClassValue } from 'clsx'
import { twMerge } from 'tailwind-merge'
import type { TranscriptSegment } from '@/hooks/useScribeTranscription'

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs))
}

// Pause threshold for paragraph breaks (in seconds)
const PAUSE_THRESHOLD_SECS = 2.0

/**
 * Format plain text into paragraphs based on sentence count
 * Fallback when no timing data is available
 */
export function formatTextIntoParagraphs(text: string): string[] {
  if (!text.trim()) return []
  
  const trimmedText = text.trim()
  const hasPunctuation = /[.!?]/.test(trimmedText)
  
  if (hasPunctuation) {
    const sentences = trimmedText.split(/(?<=[.!?])\s+/)
    const paragraphs: string[] = []
    let currentParagraph: string[] = []
    
    for (const sentence of sentences) {
      currentParagraph.push(sentence)
      if (currentParagraph.length >= 5 || currentParagraph.join(' ').length > 500) {
        paragraphs.push(currentParagraph.join(' '))
        currentParagraph = []
      }
    }
    
    if (currentParagraph.length > 0) {
      paragraphs.push(currentParagraph.join(' '))
    }
    
    return paragraphs
  } else {
    const words = trimmedText.split(/\s+/)
    const paragraphs: string[] = []
    
    for (let i = 0; i < words.length; i += 75) {
      paragraphs.push(words.slice(i, i + 75).join(' '))
    }
    
    return paragraphs.length > 0 ? paragraphs : [trimmedText]
  }
}

/**
 * Format segments into paragraphs using pause-based detection
 * A paragraph break occurs when: previous segment ends with punctuation AND pause > threshold
 */
export function formatSegmentsIntoParagraphs(segments: TranscriptSegment[], fallbackText: string = ''): string[] {
  if (segments.length === 0) return formatTextIntoParagraphs(fallbackText)
  
  const paragraphs: string[] = []
  let currentParagraph: string[] = []
  
  for (let i = 0; i < segments.length; i++) {
    const segment = segments[i]
    if (!segment) continue
    
    const prevSegment = i > 0 ? segments[i - 1] : null
    
    if (prevSegment && currentParagraph.length > 0) {
      const prevEndedWithPunctuation = /[.!?]\s*$/.test(prevSegment.text.trim())
      
      let pauseGap = 0
      if (prevSegment.endTime !== null && segment.startTime !== null) {
        pauseGap = segment.startTime - prevSegment.endTime
      }
      
      const shouldBreak = prevEndedWithPunctuation && pauseGap >= PAUSE_THRESHOLD_SECS
      
      if (shouldBreak) {
        paragraphs.push(currentParagraph.join(' '))
        currentParagraph = []
      }
    }
    
    currentParagraph.push(segment.text)
  }
  
  if (currentParagraph.length > 0) {
    paragraphs.push(currentParagraph.join(' '))
  }
  
  return paragraphs.length > 0 ? paragraphs : formatTextIntoParagraphs(fallbackText)
}
