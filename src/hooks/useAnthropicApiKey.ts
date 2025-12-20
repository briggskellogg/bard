import { useEffect } from 'react'
import { useSettingsStore } from '@/store/settings'

// Anthropic API key from environment variable or localStorage
const ENV_API_KEY = import.meta.env.VITE_ANTHROPIC_API_KEY || ''
const LOCALSTORAGE_KEY = 'echo-anthropic-api-key'

export function useAnthropicApiKey() {
  const { anthropicApiKey, setAnthropicApiKey } = useSettingsStore()

  // Load API key on mount
  useEffect(() => {
    // Priority: env variable > localStorage > empty
    if (ENV_API_KEY) {
      setAnthropicApiKey(ENV_API_KEY)
      console.log('[Anthropic] API key loaded from environment')
    } else {
      try {
        const storedKey = localStorage.getItem(LOCALSTORAGE_KEY)
        if (storedKey) {
          setAnthropicApiKey(storedKey)
          console.log('[Anthropic] API key loaded from localStorage')
        }
      } catch (e) {
        console.warn('[Anthropic] Failed to load API key from localStorage:', e)
      }
    }
  }, [setAnthropicApiKey])

  const saveApiKey = (key: string) => {
    setAnthropicApiKey(key)
    try {
      if (key) {
        localStorage.setItem(LOCALSTORAGE_KEY, key)
      } else {
        localStorage.removeItem(LOCALSTORAGE_KEY)
      }
      console.log('[Anthropic] API key saved')
    } catch (e) {
      console.warn('[Anthropic] Failed to save API key to localStorage:', e)
    }
  }

  return {
    apiKey: anthropicApiKey,
    hasApiKey: !!anthropicApiKey,
    saveApiKey,
  }
}

