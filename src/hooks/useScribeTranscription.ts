import { useState, useCallback } from 'react'
import { useScribe, type ScribeStatus } from '@elevenlabs/react'
import { fetchToken } from '@/lib/token'

export interface TranscriptSegment {
  text: string
  speakerId: string | null
}

export interface UseScribeTranscriptionOptions {
  apiKey: string
  deviceId?: string
  languageCode?: string
  onError?: (error: Error) => void
}

export interface UseScribeTranscriptionReturn {
  status: ScribeStatus
  isConnected: boolean
  isTranscribing: boolean
  transcript: string
  segments: TranscriptSegment[]
  speakers: Set<string>
  partialTranscript: string
  partialSpeaker: string | null
  error: string | null
  start: () => Promise<void>
  stop: () => void
  pause: () => void
  resume: () => Promise<void>
  clearTranscript: () => void
}

export function useScribeTranscription({
  apiKey,
  deviceId,
  languageCode = 'en',
  onError,
}: UseScribeTranscriptionOptions): UseScribeTranscriptionReturn {
  const [segments, setSegments] = useState<TranscriptSegment[]>([])
  const [speakers, setSpeakers] = useState<Set<string>>(new Set())
  const [partialSpeaker, setPartialSpeaker] = useState<string | null>(null)
  const [tokenError, setTokenError] = useState<string | null>(null)

  const scribe = useScribe({
    modelId: 'scribe_v2_realtime',
    languageCode,
    includeTimestamps: true,
    // Tuned VAD settings for better noise rejection
    vadThreshold: 0.6, // Higher threshold = less sensitive to quiet sounds
    minSpeechDurationMs: 250, // Require longer speech to trigger
    minSilenceDurationMs: 500, // Require longer silence to end segment
    microphone: {
      deviceId,
      echoCancellation: true,
      noiseSuppression: true,
      autoGainControl: true,
    },
    onCommittedTranscriptWithTimestamps: (data) => {
      const text = data.text.trim()
      if (!text) return

      // Extract speaker from words if available
      let speakerId: string | null = null
      if (data.words && data.words.length > 0) {
        // Find the most common speaker in this segment
        const speakerCounts = new Map<string, number>()
        for (const word of data.words) {
          if (word.speaker_id) {
            speakerCounts.set(word.speaker_id, (speakerCounts.get(word.speaker_id) || 0) + 1)
          }
        }
        if (speakerCounts.size > 0) {
          speakerId = [...speakerCounts.entries()].reduce((a, b) => a[1] > b[1] ? a : b)[0]
        }
      }

      setSegments(prev => [...prev, { text, speakerId }])
      
      if (speakerId) {
        setSpeakers(prev => new Set([...prev, speakerId]))
      }
    },
    // Fallback for when timestamps aren't available
    onCommittedTranscript: (data) => {
      const text = data.text.trim()
      if (!text) return
      
      // Check if we already handled this in onCommittedTranscriptWithTimestamps
      // by checking if the last segment has the same text
      setSegments(prev => {
        const lastSegment = prev[prev.length - 1]
        if (lastSegment && lastSegment.text === text) {
          return prev // Already handled
        }
        return [...prev, { text, speakerId: null }]
      })
    },
    onPartialTranscript: () => {
      // For partial transcripts, we track via scribe.partialTranscript
    },
    onError: (error) => {
      console.error('Scribe error:', error)
      if (onError && error instanceof Error) {
        onError(error)
      }
    },
    onAuthError: (data) => {
      console.error('Auth error:', data.error)
      setTokenError(data.error)
    },
    onQuotaExceededError: (data) => {
      console.error('Quota exceeded:', data.error)
      setTokenError('Quota exceeded. Please check your ElevenLabs plan.')
    },
    onDisconnect: () => {
      console.log('Scribe disconnected')
    },
  })

  // Compute full transcript from segments
  const transcript = segments.map(s => s.text).join(' ')

  const start = useCallback(async () => {
    if (!apiKey) {
      console.error('No API key provided')
      setTokenError('API key is required')
      throw new Error('API key is required')
    }

    setTokenError(null)

    try {
      console.log('Fetching token with API key...')
      const token = await fetchToken(apiKey)
      console.log('Token received:', token.substring(0, 20) + '...')
      console.log('Connecting to scribe...')
      await scribe.connect({ token })
      console.log('Scribe connected, status:', scribe.status)
    } catch (error) {
      console.error('Start transcription error:', error)
      const errorMessage = error instanceof Error ? error.message : 'Failed to start transcription'
      setTokenError(errorMessage)
      if (onError && error instanceof Error) {
        onError(error)
      }
      throw error
    }
  }, [apiKey, scribe, onError])

  const stop = useCallback(() => {
    scribe.disconnect()
  }, [scribe])

  // Pause by disconnecting (stops API calls, preserves transcript)
  const pause = useCallback(() => {
    scribe.disconnect()
  }, [scribe])

  // Resume by reconnecting
  const resume = useCallback(async () => {
    if (!apiKey) {
      setTokenError('API key is required')
      return
    }

    setTokenError(null)

    try {
      const token = await fetchToken(apiKey)
      await scribe.connect({ token })
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Failed to resume transcription'
      setTokenError(errorMessage)
      if (onError && error instanceof Error) {
        onError(error)
      }
    }
  }, [apiKey, scribe, onError])

  const clearTranscript = useCallback(() => {
    setSegments([])
    setSpeakers(new Set())
    setPartialSpeaker(null)
    scribe.clearTranscripts()
    setTokenError(null)
  }, [scribe])

  // Combine errors
  const combinedError = tokenError || scribe.error

  return {
    status: scribe.status,
    isConnected: scribe.isConnected,
    isTranscribing: scribe.isTranscribing,
    transcript,
    segments,
    speakers,
    partialTranscript: scribe.partialTranscript,
    partialSpeaker,
    error: combinedError,
    start,
    stop,
    pause,
    resume,
    clearTranscript,
  }
}
