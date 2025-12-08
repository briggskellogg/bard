import { useState, useEffect } from 'react'

// Hardcoded API key for internal distribution
const EMBEDDED_API_KEY = '' // Add your ElevenLabs API key here

export function useApiKey() {
  const [isLoaded, setIsLoaded] = useState(false)

  useEffect(() => {
    setIsLoaded(true)
  }, [])

  return {
    apiKey: EMBEDDED_API_KEY,
    isLoaded,
    hasApiKey: true,
    saveApiKey: async () => {},
    clearApiKey: async () => {},
  }
}
