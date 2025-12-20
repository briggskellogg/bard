import { useEffect, useCallback, useRef } from 'react'
import { useSettingsStore, type ArchivedTranscript, type ArchivedSpeaker } from '@/store/settings'
import { transcriptsToExportCSV, downloadCSV } from '@/lib/csv'
import { analyzeTranscript } from '@/lib/claude'
import type { TranscriptSegment } from '@/hooks/useScribeTranscription'

// localStorage keys as fallback
const STORAGE_KEY = 'echo-archive'
const CATEGORIES_KEY = 'echo-categories'

// Check if running in Tauri
function isTauri(): boolean {
  return typeof window !== 'undefined' && '__TAURI__' in window
}

// Tauri Store helpers
async function getTauriStore() {
  const { load } = await import('@tauri-apps/plugin-store')
  return await load('archive.json')
}

// Load from Tauri store
async function loadFromTauriStore(): Promise<{ transcripts: ArchivedTranscript[]; categories: string[] }> {
  try {
    const store = await getTauriStore()
    const transcripts = await store.get<ArchivedTranscript[]>('transcripts') || []
    const categories = await store.get<string[]>('categories') || []
    console.log('[Archive] Loaded from Tauri store:', transcripts.length, 'transcripts')
    return { transcripts, categories }
  } catch (e) {
    console.error('[Archive] Failed to load from Tauri store:', e)
    return { transcripts: [], categories: [] }
  }
}

// Save to Tauri store
async function saveToTauriStore(transcripts: ArchivedTranscript[], categories: string[]): Promise<void> {
  try {
    const store = await getTauriStore()
    await store.set('transcripts', transcripts)
    await store.set('categories', categories)
    await store.save()
    console.log('[Archive] Saved to Tauri store:', transcripts.length, 'transcripts')
  } catch (e) {
    console.error('[Archive] Failed to save to Tauri store:', e)
    throw e
  }
}

// localStorage fallback for development (non-Tauri)
function loadFromLocalStorage(): { transcripts: ArchivedTranscript[]; categories: string[] } {
  try {
    const data = localStorage.getItem(STORAGE_KEY)
    const categoriesData = localStorage.getItem(CATEGORIES_KEY)
    return {
      transcripts: data ? JSON.parse(data) : [],
      categories: categoriesData ? JSON.parse(categoriesData) : [],
    }
  } catch (e) {
    console.error('[Archive] Failed to load from localStorage:', e)
    return { transcripts: [], categories: [] }
  }
}

function saveToLocalStorage(transcripts: ArchivedTranscript[], categories: string[]): void {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(transcripts))
    localStorage.setItem(CATEGORIES_KEY, JSON.stringify(categories))
    console.log('[Archive] Saved to localStorage:', transcripts.length, 'transcripts')
  } catch (e) {
    console.error('[Archive] Failed to save to localStorage:', e)
  }
}

export interface ArchiveTranscriptInput {
  title: string
  text: string
  segments: TranscriptSegment[]
  speakers: ArchivedSpeaker[]
  hasConsent: boolean
  category?: string
}

export function useArchive() {
  const {
    archivedTranscripts,
    isArchiveLoaded,
    setArchivedTranscripts,
    addArchivedTranscript,
    removeArchivedTranscript,
    updateArchivedTranscript,
    setIsArchiveLoaded,
    customCategories,
    setCustomCategories,
    addCustomCategory: addCustomCategoryToStore,
    anthropicApiKey,
  } = useSettingsStore()

  // Use a ref to track the latest transcripts for persistence
  const transcriptsRef = useRef(archivedTranscripts)
  const categoriesRef = useRef(customCategories)
  
  // Keep refs updated
  useEffect(() => {
    transcriptsRef.current = archivedTranscripts
  }, [archivedTranscripts])
  
  useEffect(() => {
    categoriesRef.current = customCategories
  }, [customCategories])

  // Load archived transcripts on mount
  useEffect(() => {
    async function loadArchive() {
      try {
        let transcripts: ArchivedTranscript[] = []
        let categories: string[] = []
        
        if (isTauri()) {
          console.log('[Archive] Loading from Tauri store...')
          const data = await loadFromTauriStore()
          transcripts = data.transcripts
          categories = data.categories
        } else {
          console.log('[Archive] Using localStorage fallback (dev mode)')
          const data = loadFromLocalStorage()
          transcripts = data.transcripts
          categories = data.categories
        }
        
        if (transcripts.length > 0) {
          // Sort by createdAt descending (newest first)
          transcripts.sort((a, b) => b.createdAt - a.createdAt)
          setArchivedTranscripts(transcripts)
          console.log('[Archive] Loaded', transcripts.length, 'transcripts')
        }
        
        if (categories.length > 0) {
          setCustomCategories(categories)
        }
      } catch (error) {
        console.error('[Archive] Failed to load archive:', error)
      } finally {
        setIsArchiveLoaded(true)
      }
    }

    if (!isArchiveLoaded) {
      loadArchive()
    }
  }, [isArchiveLoaded, setArchivedTranscripts, setIsArchiveLoaded, setCustomCategories])

  // Persist function
  const persist = useCallback(async (transcripts: ArchivedTranscript[], categories: string[]) => {
    if (isTauri()) {
      await saveToTauriStore(transcripts, categories)
    } else {
      saveToLocalStorage(transcripts, categories)
    }
  }, [])

  // Save an archived transcript
  const archiveTranscript = useCallback(async (input: ArchiveTranscriptInput) => {
    if (!input.text.trim()) return null

    // Generate title with Claude (if API key available)
    let title = input.title || 'Voice Memo'
    if (anthropicApiKey) {
      try {
        const analysis = await analyzeTranscript(input.text.trim(), anthropicApiKey)
        title = analysis.title
        console.log('[Archive] Claude generated title:', title)
      } catch (error) {
        console.error('[Archive] Claude title generation failed:', error)
      }
    }

    const transcript: ArchivedTranscript = {
      id: crypto.randomUUID(),
      title,
      text: input.text.trim(),
      segments: input.segments,
      speakers: input.speakers,
      hasConsent: input.hasConsent,
      category: input.category || 'Note',
      isImportant: false,
      createdAt: Date.now(),
    }

    try {
      // Update in-memory store
      addArchivedTranscript(transcript)
      
      // Persist with the new transcript prepended
      const updatedTranscripts = [transcript, ...transcriptsRef.current]
      await persist(updatedTranscripts, categoriesRef.current)
      
      return transcript
    } catch (error) {
      console.error('[Archive] Failed to archive transcript:', error)
      throw error
    }
  }, [addArchivedTranscript, anthropicApiKey, persist])

  // Update an archived transcript
  const updateTranscript = useCallback(async (id: string, updates: Partial<ArchivedTranscript>) => {
    try {
      updateArchivedTranscript(id, updates)
      
      const updatedTranscripts = transcriptsRef.current.map(t => 
        t.id === id ? { ...t, ...updates } : t
      )
      await persist(updatedTranscripts, categoriesRef.current)
    } catch (error) {
      console.error('[Archive] Failed to update transcript:', error)
      throw error
    }
  }, [updateArchivedTranscript, persist])

  // Delete an archived transcript
  const deleteTranscript = useCallback(async (id: string) => {
    try {
      removeArchivedTranscript(id)
      
      const updatedTranscripts = transcriptsRef.current.filter(t => t.id !== id)
      await persist(updatedTranscripts, categoriesRef.current)
    } catch (error) {
      console.error('[Archive] Failed to delete transcript:', error)
      throw error
    }
  }, [removeArchivedTranscript, persist])

  // Add a custom category and persist it
  const addCustomCategory = useCallback(async (category: string) => {
    try {
      addCustomCategoryToStore(category)
      
      const updatedCategories = [...categoriesRef.current, category]
      await persist(transcriptsRef.current, updatedCategories)
    } catch (error) {
      console.error('[Archive] Failed to add custom category:', error)
      throw error
    }
  }, [addCustomCategoryToStore, persist])

  // Export all transcripts as a downloadable CSV
  const exportToCSV = useCallback(async () => {
    if (archivedTranscripts.length === 0) {
      console.log('[Archive] No transcripts to export')
      return
    }
    
    const csv = transcriptsToExportCSV(archivedTranscripts)
    const date = new Date().toISOString().split('T')[0]
    const filename = `echo-export-${date}.csv`
    
    await downloadCSV(csv, filename)
    console.log('[Archive] Exported', archivedTranscripts.length, 'transcripts to', filename)
  }, [archivedTranscripts])

  return {
    archivedTranscripts,
    isLoaded: isArchiveLoaded,
    archiveTranscript,
    updateTranscript,
    deleteTranscript,
    customCategories,
    addCustomCategory,
    exportToCSV,
  }
}
