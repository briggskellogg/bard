import { useState, useEffect, useCallback } from 'react'

// ElevenLabs API key from environment variable (fallback)
const ENV_API_KEY = import.meta.env.VITE_ELEVENLABS_API_KEY || ''
const STORE_KEY = 'elevenlabs-api-key'

// Store instance singleton
let storeInstance: Awaited<ReturnType<typeof import('@tauri-apps/plugin-store').Store.load>> | null = null

async function getStore() {
  if (storeInstance) return storeInstance
  
  try {
    const { Store } = await import('@tauri-apps/plugin-store')
    storeInstance = await Store.load('settings.json', { autoSave: true, defaults: {} })
    return storeInstance
  } catch (error) {
    console.warn('[useApiKey] Failed to load Tauri Store:', error)
    return null
  }
}

export function useApiKey() {
  const [storedKey, setStoredKey] = useState<string | null>(null)
  const [isLoaded, setIsLoaded] = useState(false)

  // Load API key from Tauri Store on mount
  useEffect(() => {
    let mounted = true

    async function loadKey() {
      try {
        const store = await getStore()
        if (store && mounted) {
          const key = await store.get<string>(STORE_KEY)
          setStoredKey(key || null)
        }
      } catch (error) {
        console.warn('[useApiKey] Failed to load API key from store:', error)
      } finally {
        if (mounted) {
          setIsLoaded(true)
        }
      }
    }

    loadKey()

    return () => {
      mounted = false
    }
  }, [])

  // Save API key to Tauri Store
  const saveApiKey = useCallback(async (key: string) => {
    try {
      const store = await getStore()
      if (store) {
        await store.set(STORE_KEY, key)
        await store.save()
        setStoredKey(key)
        return true
      }
    } catch (error) {
      console.error('[useApiKey] Failed to save API key:', error)
    }
    return false
  }, [])

  // Clear API key from Tauri Store
  const clearApiKey = useCallback(async () => {
    console.log('[useApiKey] clearApiKey called')
    try {
      const store = await getStore()
      console.log('[useApiKey] Store loaded:', !!store)
      if (store) {
        await store.delete(STORE_KEY)
        await store.save()
        console.log('[useApiKey] Key deleted from store')
      }
      // Always clear local state regardless of store success
      setStoredKey(null)
      console.log('[useApiKey] Local state cleared, storedKey set to null')
      return true
    } catch (error) {
      console.error('[useApiKey] Failed to clear API key:', error)
      // Still clear local state even on error
      setStoredKey(null)
      return true
    }
  }, [])

  // Use stored key first, fall back to env variable
  const apiKey = storedKey || ENV_API_KEY

  return {
    apiKey,
    isLoaded,
    hasApiKey: !!apiKey,
    hasStoredKey: !!storedKey,
    saveApiKey,
    clearApiKey,
  }
}
