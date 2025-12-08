import { useEffect, useCallback } from 'react'
import { Store } from '@tauri-apps/plugin-store'
import { useSettingsStore, type ArchivedTranscript, type ArchivedSpeaker } from '@/store/settings'
import type { TranscriptSegment } from '@/hooks/useScribeTranscription'

const STORE_PATH = 'echo-settings.json'
const ARCHIVE_STORE_KEY = 'archived-transcripts'

let storePromise: Promise<Store> | null = null

async function getStore(): Promise<Store> {
  if (!storePromise) {
    storePromise = Store.load(STORE_PATH)
  }
  return storePromise
}

export interface ArchiveTranscriptInput {
  title: string
  text: string
  segments: TranscriptSegment[]
  speakers: ArchivedSpeaker[]
  hasConsent: boolean
  noveltyScore?: number
  coherenceScore?: number
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
  } = useSettingsStore()

  // Load archived transcripts from Tauri store on mount
  useEffect(() => {
    async function loadArchive() {
      try {
        const store = await getStore()
        const stored = await store.get<ArchivedTranscript[]>(ARCHIVE_STORE_KEY)
        if (stored && Array.isArray(stored)) {
          // Migrate old transcripts without new fields
          const migrated = stored.map(t => ({
            ...t,
            title: t.title || 'Untitled Recording',
            segments: t.segments || [],
            speakers: t.speakers || [],
            hasConsent: t.hasConsent ?? true,
          }))
          setArchivedTranscripts(migrated)
        }
      } catch (error) {
        console.error('Failed to load archive:', error)
      } finally {
        setIsArchiveLoaded(true)
      }
    }

    if (!isArchiveLoaded) {
      loadArchive()
    }
  }, [isArchiveLoaded, setArchivedTranscripts, setIsArchiveLoaded])

  // Save an archived transcript with full data
  const archiveTranscript = useCallback(async (input: ArchiveTranscriptInput) => {
    if (!input.text.trim()) return null

    const transcript: ArchivedTranscript = {
      id: crypto.randomUUID(),
      title: input.title || 'Untitled Recording',
      text: input.text.trim(),
      segments: input.segments,
      speakers: input.speakers,
      hasConsent: input.hasConsent,
      noveltyScore: input.noveltyScore,
      coherenceScore: input.coherenceScore,
      createdAt: Date.now(),
    }

    try {
      addArchivedTranscript(transcript)
      const store = await getStore()
      const current = await store.get<ArchivedTranscript[]>(ARCHIVE_STORE_KEY) || []
      await store.set(ARCHIVE_STORE_KEY, [transcript, ...current])
      await store.save()
      return transcript
    } catch (error) {
      console.error('Failed to archive transcript:', error)
      throw error
    }
  }, [addArchivedTranscript])

  // Update an archived transcript (e.g., to add scores)
  const updateTranscript = useCallback(async (id: string, updates: Partial<ArchivedTranscript>) => {
    try {
      updateArchivedTranscript(id, updates)
      const store = await getStore()
      const current = await store.get<ArchivedTranscript[]>(ARCHIVE_STORE_KEY) || []
      const updated = current.map(t => t.id === id ? { ...t, ...updates } : t)
      await store.set(ARCHIVE_STORE_KEY, updated)
      await store.save()
    } catch (error) {
      console.error('Failed to update transcript:', error)
      throw error
    }
  }, [updateArchivedTranscript])

  // Delete an archived transcript
  const deleteTranscript = useCallback(async (id: string) => {
    try {
      removeArchivedTranscript(id)
      const store = await getStore()
      const current = await store.get<ArchivedTranscript[]>(ARCHIVE_STORE_KEY) || []
      await store.set(ARCHIVE_STORE_KEY, current.filter(t => t.id !== id))
      await store.save()
    } catch (error) {
      console.error('Failed to delete transcript:', error)
      throw error
    }
  }, [removeArchivedTranscript])

  return {
    archivedTranscripts,
    isLoaded: isArchiveLoaded,
    archiveTranscript,
    updateTranscript,
    deleteTranscript,
  }
}
