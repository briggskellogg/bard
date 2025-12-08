import { useState, useEffect, useCallback } from 'react'
import { Store } from '@tauri-apps/plugin-store'

const STORE_PATH = 'settings.json'
const API_KEY_FIELD = 'elevenlabs_api_key'

export function useApiKey() {
  const [apiKey, setApiKey] = useState('')
  const [isLoaded, setIsLoaded] = useState(false)

  useEffect(() => {
    const loadApiKey = async () => {
      try {
        const store = await Store.load(STORE_PATH)
        const storedKey = await store.get<string>(API_KEY_FIELD)
        if (storedKey) {
          setApiKey(storedKey)
        }
      } catch (error) {
        console.error('Failed to load API key:', error)
      } finally {
        setIsLoaded(true)
      }
    }
    loadApiKey()
  }, [])

  const saveApiKey = useCallback(async (key: string) => {
    try {
      const store = await Store.load(STORE_PATH)
      await store.set(API_KEY_FIELD, key)
      await store.save()
      setApiKey(key)
    } catch (error) {
      console.error('Failed to save API key:', error)
      throw error
    }
  }, [])

  const clearApiKey = useCallback(async () => {
    try {
      const store = await Store.load(STORE_PATH)
      await store.delete(API_KEY_FIELD)
      await store.save()
      setApiKey('')
    } catch (error) {
      console.error('Failed to clear API key:', error)
      throw error
    }
  }, [])

  return {
    apiKey,
    isLoaded,
    hasApiKey: !!apiKey,
    saveApiKey,
    clearApiKey,
  }
}
