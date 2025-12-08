import { useRef, useCallback, useState } from 'react'

export function useAudioMonitor() {
  const [isMonitoring, setIsMonitoring] = useState(false)
  const audioContextRef = useRef<AudioContext | null>(null)
  const sourceNodeRef = useRef<MediaStreamAudioSourceNode | null>(null)
  const gainNodeRef = useRef<GainNode | null>(null)

  const startMonitoring = useCallback(async (deviceId?: string) => {
    // Check if mediaDevices API is available
    if (!navigator.mediaDevices) {
      throw new Error('navigator.mediaDevices is not available')
    }
    
    try {
      // Create audio context if it doesn't exist
      if (!audioContextRef.current) {
        audioContextRef.current = new AudioContext()
      }

      // Resume if suspended
      if (audioContextRef.current.state === 'suspended') {
        await audioContextRef.current.resume()
      }

      // Get microphone stream
      const stream = await navigator.mediaDevices.getUserMedia({
        audio: {
          deviceId: deviceId ? { exact: deviceId } : undefined,
          echoCancellation: true,
          noiseSuppression: true,
          autoGainControl: true,
        }
      })

      // Create source from stream
      sourceNodeRef.current = audioContextRef.current.createMediaStreamSource(stream)

      // Create gain node for volume control (slightly reduced to prevent feedback)
      gainNodeRef.current = audioContextRef.current.createGain()
      gainNodeRef.current.gain.value = 0.8

      // Connect: mic -> gain -> speakers
      sourceNodeRef.current.connect(gainNodeRef.current)
      gainNodeRef.current.connect(audioContextRef.current.destination)

      setIsMonitoring(true)
    } catch (error) {
      console.error('Failed to start audio monitoring:', error)
      throw error
    }
  }, [])

  const stopMonitoring = useCallback(() => {
    // Disconnect nodes
    if (sourceNodeRef.current) {
      sourceNodeRef.current.disconnect()
      sourceNodeRef.current = null
    }

    if (gainNodeRef.current) {
      gainNodeRef.current.disconnect()
      gainNodeRef.current = null
    }

    setIsMonitoring(false)
  }, [])

  const setVolume = useCallback((volume: number) => {
    if (gainNodeRef.current) {
      // Clamp volume between 0 and 1
      gainNodeRef.current.gain.value = Math.max(0, Math.min(1, volume))
    }
  }, [])

  return {
    isMonitoring,
    startMonitoring,
    stopMonitoring,
    setVolume,
  }
}

