import { useEffect, useState, useCallback } from 'react'
import { Toaster, toast } from 'sonner'
import { X, Trash2, Clipboard, Archive } from 'lucide-react'
import { WaveformDisplay } from './components/WaveformDisplay'
import { RecordingBar, type ScribeLanguageCode } from './components/RecordingBar'
import { TranscriptBox } from './components/TranscriptBox'
import { ActionBar } from './components/ActionBar'
import { ArchiveDialog } from './components/ArchiveDialog'
import { ThemeToggle } from './components/ThemeToggle'
import { useApiKey } from './hooks/useApiKey'
import { useArchive } from './hooks/useArchive'
import { useScribeTranscription } from './hooks/useScribeTranscription'
import { useSettingsStore } from './store/settings'
import {
  AlertDialog,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from '@/components/ui/alert-dialog'
import { Button } from '@/components/ui/button'
import llmemoLogoDark from './assets/llmemo-logo-dark.svg'
import llmemoLogoLight from './assets/llmemo-logo-light.svg'
import orbLogo from './assets/orb-logo.png'
import './App.css'

function App() {
  const { apiKey, isLoaded } = useApiKey()
  const { archiveTranscript } = useArchive()
  const { setArchiveDialogOpen, theme } = useSettingsStore()
  const [isStarting, setIsStarting] = useState(false)
  const [isPaused, setIsPaused] = useState(false)
  const [recordingStartTime, setRecordingStartTime] = useState<number | null>(null)
  const [selectedDeviceId, setSelectedDeviceId] = useState<string | undefined>()
  const [selectedLanguage, setSelectedLanguage] = useState<ScribeLanguageCode>('en')
  
  // Track if current content has been archived (prevent double archiving)
  const [isArchived, setIsArchived] = useState(false)
  
  // Action feedback states
  const [archiveTriggered, setArchiveTriggered] = useState(false)
  const [copyTriggered, setCopyTriggered] = useState(false)
  const [clearTriggered, setClearTriggered] = useState(false)
  
  // Confirmation dialog for new recording with existing content
  const [showNewRecordingDialog, setShowNewRecordingDialog] = useState(false)

  const {
    status,
    isConnected,
    isTranscribing,
    transcript,
    segments,
    partialTranscript,
    start,
    stop,
    pause,
    resume,
    clearTranscript,
  } = useScribeTranscription({
    apiKey,
    deviceId: selectedDeviceId,
    languageCode: selectedLanguage,
    onError: (err) => {
      console.error('Transcription error:', err)
      setIsStarting(false)
    },
  })

  // Apply dark theme by default on mount
  useEffect(() => {
    document.documentElement.classList.add('dark')
  }, [])

  // Reset archived state when transcript changes
  useEffect(() => {
    if (transcript || partialTranscript) {
      setIsArchived(false)
    }
  }, [transcript, partialTranscript])

  // Check if there's existing content before starting new recording
  const hasExistingContent = !!(transcript || partialTranscript)

  const handleStartRecording = useCallback(async () => {
    // If there's existing content, show confirmation dialog
    if (hasExistingContent) {
      setShowNewRecordingDialog(true)
      return
    }
    
    // Start recording directly
    setIsStarting(true)
    toast.info('Connecting to ElevenLabs...')
    try {
      console.log('Starting recording with API key:', apiKey ? 'present' : 'missing')
      await start()
      setRecordingStartTime(Date.now())
      toast.success('Recording started')
    } catch (error) {
      console.error('Failed to start recording:', error)
      const message = error instanceof Error ? error.message : 'Unknown error'
      toast.error(`Failed: ${message}`)
    } finally {
      setIsStarting(false)
    }
  }, [hasExistingContent, start, apiKey])

  // Start recording after handling existing content
  const startNewRecording = useCallback(async () => {
    setShowNewRecordingDialog(false)
    clearTranscript()
    setIsArchived(false)
    
    setIsStarting(true)
    try {
      await start()
      setRecordingStartTime(Date.now())
      toast.success('Recording started')
    } finally {
      setIsStarting(false)
    }
  }, [start, clearTranscript])

  // Archive existing content then start new recording
  const archiveAndStartNew = useCallback(async () => {
    const textToArchive = transcript || partialTranscript
    if (textToArchive && !isArchived) {
      try {
        await archiveTranscript({
          title: 'Recording',
          text: textToArchive,
          segments,
          speakers: [],
          hasConsent: true,
        })
        setIsArchived(true)
        toast.success('Recording archived')
        setShowNewRecordingDialog(false)
      } catch (err) {
        console.error('Failed to archive:', err)
        toast.error('Failed to archive')
      }
    }
  }, [transcript, partialTranscript, segments, isArchived, archiveTranscript])

  // Copy existing content then start new recording  
  const copyAndStartNew = useCallback(async () => {
    const textToCopy = transcript || partialTranscript
    if (textToCopy) {
      try {
        await navigator.clipboard.writeText(textToCopy)
        toast.success('Copied to clipboard')
      } catch (error) {
        console.error('Failed to copy:', error)
        toast.error('Failed to copy')
        return
      }
    }
    
    await startNewRecording()
  }, [transcript, partialTranscript, startNewRecording])

  const handleStopRecording = useCallback(() => {
    stop()
    setIsPaused(false)
    setRecordingStartTime(null)
    toast.success('Recording stopped')
  }, [stop])

  const handlePauseRecording = useCallback(() => {
    pause()
    setIsPaused(true)
    toast.success('Recording paused')
  }, [pause])

  const handleResumeRecording = useCallback(async () => {
    await resume()
    setIsPaused(false)
    toast.success('Recording resumed')
  }, [resume])

  const handleDiscard = useCallback(() => {
    stop()
    setIsPaused(false)
    setRecordingStartTime(null)
    clearTranscript()
    setIsArchived(false)
    toast.success('Recording discarded')
  }, [stop, clearTranscript])

  const handleArchive = useCallback(async () => {
    const textToArchive = transcript || partialTranscript
    if (!textToArchive) {
      toast.error('Nothing to archive')
      return
    }
    
    if (isArchived) {
      toast.error('Already archived')
      return
    }
    
    try {
      await archiveTranscript({
        title: 'Recording',
        text: textToArchive,
        segments,
        speakers: [],
        hasConsent: true,
      })
      setIsArchived(true)
      setArchiveTriggered(true)
      setTimeout(() => setArchiveTriggered(false), 1500)
      toast.success('Archived')
    } catch (err) {
      console.error('Failed to archive:', err)
      toast.error('Failed to archive')
    }
  }, [transcript, partialTranscript, segments, isArchived, archiveTranscript])

  const handleClear = useCallback(() => {
    if (!transcript && !partialTranscript) return
    clearTranscript()
    setIsArchived(false)
    setClearTriggered(true)
    setTimeout(() => setClearTriggered(false), 1500)
    toast.success('Cleared')
  }, [transcript, partialTranscript, clearTranscript])

  const handleCopy = useCallback(async () => {
    const textToCopy = transcript || partialTranscript
    if (!textToCopy) return
    
    try {
      await navigator.clipboard.writeText(textToCopy)
      setCopyTriggered(true)
      setTimeout(() => setCopyTriggered(false), 1500)
      toast.success('Copied to clipboard')
    } catch (error) {
      console.error('Failed to copy:', error)
      toast.error('Failed to copy')
    }
  }, [transcript, partialTranscript])

  const handleToggleTheme = useCallback(() => {
    const newTheme = theme === 'dark' ? 'light' : 'dark'
    useSettingsStore.getState().setTheme(newTheme)
  }, [theme])

  // Global keyboard shortcuts
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      // Don't trigger shortcuts when typing in inputs
      if (e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement) {
        return
      }

      // Handle new recording dialog hotkeys
      if (showNewRecordingDialog) {
        switch (e.key.toLowerCase()) {
          case 'escape':
            e.preventDefault()
            setShowNewRecordingDialog(false)
            break
          case 'a':
            e.preventDefault()
            archiveAndStartNew()
                    break
          case 'c':
            e.preventDefault()
            copyAndStartNew()
                    break
          case 'd':
            e.preventDefault()
            startNewRecording()
                    break
                }
        return
      }

      // Don't trigger shortcuts when archive dialog is open
      const { archiveDialogOpen } = useSettingsStore.getState()
      
      if (e.key === 'Escape') {
        if (archiveDialogOpen) {
          return // Let the dialog handle its own escape
        }
        if (isConnected) {
          e.preventDefault()
          handleDiscard()
        }
        return
      }

      // Don't process other hotkeys when dialogs are open
      if (archiveDialogOpen) {
        return
      }

      switch (e.key.toLowerCase()) {
        case 'r':
          e.preventDefault()
          if (isConnected) {
            handleStopRecording()
          } else {
            handleStartRecording()
          }
          break
        case 'c':
          e.preventDefault()
          handleCopy()
          break
        case 'd':
          e.preventDefault()
          handleClear()
          break
        case 'a':
          e.preventDefault()
          handleArchive()
          break
        case 'h':
          e.preventDefault()
          setArchiveDialogOpen(true)
          break
        case 't':
          e.preventDefault()
          handleToggleTheme()
          break
        case 'p':
          e.preventDefault()
          if (isConnected) {
            if (isPaused) {
              handleResumeRecording()
            } else {
              handlePauseRecording()
            }
          }
          break
      }
    }

    window.addEventListener('keydown', handleKeyDown)
    return () => window.removeEventListener('keydown', handleKeyDown)
  }, [isConnected, isPaused, showNewRecordingDialog, handleStartRecording, handleStopRecording, handlePauseRecording, handleResumeRecording, handleCopy, handleClear, handleArchive, handleDiscard, handleToggleTheme, setArchiveDialogOpen, archiveAndStartNew, copyAndStartNew, startNewRecording])

  const isRecording = isConnected || isTranscribing
  const hasContent = !!(transcript || partialTranscript)

  // Determine which logos to use based on theme
  const isDark = theme === 'dark' || 
    (theme === 'system' && window.matchMedia('(prefers-color-scheme: dark)').matches)
  const headerLogo = isDark ? llmemoLogoLight : llmemoLogoDark

  return (
    <div className="flex flex-col h-screen bg-background text-foreground">
      {/* Toast notifications */}
      <Toaster 
        position="bottom-left"
        toastOptions={{
          duration: 2000,
          className: 'text-sm bg-background border border-border shadow-lg',
        }}
        closeButton
      />

      {/* Header with logo and controls */}
      <div 
        className="relative flex items-center justify-center py-3"
        data-tauri-drag-region
      >
        <img 
          src={headerLogo} 
          alt="llMemo" 
          className="h-5 w-auto"
        />
        <div className="absolute right-3 flex items-center gap-1">
          <ArchiveDialog />
          <ThemeToggle />
        </div>
      </div>

      {/* Main Content */}
      <main className="flex flex-col flex-1 p-4 gap-4 overflow-hidden">
        {/* Recording Bar - above waveform */}
        <RecordingBar
          isRecording={isRecording}
          isPaused={isPaused}
          isLoading={isStarting || status === 'connecting'}
          disabled={!isLoaded}
          onStartRecording={handleStartRecording}
          onStopRecording={handleStopRecording}
          onPauseRecording={handlePauseRecording}
          onResumeRecording={handleResumeRecording}
          selectedDeviceId={selectedDeviceId}
          onDeviceChange={setSelectedDeviceId}
          selectedLanguage={selectedLanguage}
          onLanguageChange={setSelectedLanguage}
        />

        {/* Waveform */}
        <WaveformDisplay
          isRecording={isRecording}
          isPaused={isPaused}
          isProcessing={status === 'connecting'}
          deviceId={selectedDeviceId}
        />

        {/* Action Bar */}
        <div className="flex items-center justify-end gap-3">
          <ActionBar
            hasContent={hasContent}
            isArchived={isArchived}
            isProcessing={!!partialTranscript && isRecording}
            onArchive={handleArchive}
            onCopy={handleCopy}
            onClear={handleClear}
            archiveTriggered={archiveTriggered}
            copyTriggered={copyTriggered}
            clearTriggered={clearTriggered}
          />
        </div>

        {/* Transcript */}
        <TranscriptBox
          transcript={transcript}
          segments={segments}
          partialTranscript={partialTranscript}
          isRecording={isRecording}
          recordingStartTime={recordingStartTime}
          onMaxTimeReached={handleStopRecording}
        />
      </main>

      {/* Footer */}
      <footer className="relative flex flex-col items-center justify-center px-4 py-3 border-t border-border/30">
        <div className="text-center leading-relaxed">
          <p className="text-xs text-muted-foreground">"An agent can carry out tasks, but the final responsibility should always remain with a human."</p>
          <p className="text-[11px] text-muted-foreground/80 mt-0.5">Policy based on{' '}
            <a
              href="https://linear.app/developers/aig"
              target="_blank"
              rel="noopener noreferrer"
              className="underline hover:text-muted-foreground transition-colors"
            >
              Linear's framework
            </a>.
          </p>
        </div>
        <img 
          src={orbLogo} 
          alt="" 
          className="absolute right-3 bottom-3 h-6 w-6 rounded-full opacity-60 hover:opacity-100 transition-opacity"
        />
      </footer>

      {/* Confirmation dialog for starting new recording with existing content */}
      <AlertDialog open={showNewRecordingDialog} onOpenChange={setShowNewRecordingDialog}>
        <AlertDialogContent className="max-w-md">
          <AlertDialogHeader>
            <AlertDialogTitle>Existing Recording</AlertDialogTitle>
            <AlertDialogDescription>
              You have an existing transcription. What would you like to do with it before starting a new recording?
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter className="flex-col sm:flex-row gap-2">
            <Button
              variant="secondary"
              onClick={copyAndStartNew}
              className="w-full sm:w-auto gap-2"
            >
              <Clipboard className="h-4 w-4" />
              Copy
              <kbd className="ml-1 px-1.5 py-0.5 rounded bg-muted/80 border border-border/50 text-[10px] font-medium">C</kbd>
            </Button>
            <Button
              variant="default"
              onClick={archiveAndStartNew}
              disabled={isArchived}
              className="w-full sm:w-auto gap-2"
            >
              <Archive className="h-4 w-4" />
              Archive
              <kbd className="ml-1 px-1.5 py-0.5 rounded bg-primary/80 border border-primary/50 text-[10px] font-medium text-primary-foreground">A</kbd>
            </Button>
            <Button
              variant="destructive"
              onClick={startNewRecording}
              className="w-full sm:w-auto gap-2"
            >
              <Trash2 className="h-4 w-4" />
              Delete
              <kbd className="ml-1 px-1.5 py-0.5 rounded bg-destructive/80 border border-destructive/50 text-[10px] font-medium">D</kbd>
            </Button>
            <Button
              variant="outline"
              onClick={() => setShowNewRecordingDialog(false)}
              className="w-full sm:w-auto gap-2"
            >
              <X className="h-4 w-4" />
              Cancel
              <kbd className="ml-1 px-1.5 py-0.5 rounded bg-muted/80 border border-border/50 text-[10px] font-medium">Esc</kbd>
            </Button>
          </AlertDialogFooter>
          <p className="text-xs text-muted-foreground/60 mt-2 text-center">
            For privacy, only your voice is archived.
          </p>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  )
}

export default App
