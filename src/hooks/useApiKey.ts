import { useState, useEffect, useCallback } from 'react'

// ElevenLabs API key from environment variable (fallback)
const ENV_API_KEY = import.meta.env.VITE_ELEVENLABS_API_KEY || ''
const STORE_KEY = 'elevenlabs-api-key'
const REVOKED_KEY = 'elevenlabs-api-key-revoked'

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
  const [isRevoked, setIsRevoked] = useState(false)
  const [isLoaded, setIsLoaded] = useState(false)

  // Load API key from Tauri Store on mount
  useEffect(() => {
    let mounted = true

    async function loadKey() {
      try {
        const store = await getStore()
        if (store && mounted) {
          const key = await store.get<string>(STORE_KEY)
          const revoked = await store.get<boolean>(REVOKED_KEY)
          setStoredKey(key || null)
          setIsRevoked(!!revoked)
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
        await store.delete(REVOKED_KEY) // Clear revoked flag when saving new key
        await store.save()
        setStoredKey(key)
        setIsRevoked(false)
        return true
      }
    } catch (error) {
      console.error('[useApiKey] Failed to save API key:', error)
    }
    return false
  }, [])

  // Clear/revoke API key from Tauri Store
  const clearApiKey = useCallback(async () => {
    console.log('[useApiKey] clearApiKey called')
    try {
      const store = await getStore()
      console.log('[useApiKey] Store loaded:', !!store)
      if (store) {
        await store.delete(STORE_KEY)
        await store.set(REVOKED_KEY, true) // Mark as explicitly revoked
        await store.save()
        console.log('[useApiKey] Key deleted and marked as revoked')
      }
      // Always clear local state regardless of store success
      setStoredKey(null)
      setIsRevoked(true)
      console.log('[useApiKey] Local state cleared, key revoked')
      return true
    } catch (error) {
      console.error('[useApiKey] Failed to clear API key:', error)
      // Still clear local state even on error
      setStoredKey(null)
      setIsRevoked(true)
      return true
    }
  }, [])

  // Use stored key first, fall back to env variable (unless explicitly revoked)
  const apiKey = storedKey || (isRevoked ? '' : ENV_API_KEY)

  return {
    apiKey,
    isLoaded,
    hasApiKey: !!apiKey,
    hasStoredKey: !!storedKey,
    saveApiKey,
    clearApiKey,
  }
}
