import { useEffect, useState, useCallback } from 'react'
import { WaveformDisplay } from './components/WaveformDisplay'
import { BrandCopyIcon, BrandCheckIcon, BrandPauseIcon, BrandPlayIcon, ShieldIcon } from '@/components/ui/brand-icons'
import { RecordingBar, type ScribeLanguageCode } from './components/RecordingBar'
import { TranscriptBox } from './components/TranscriptBox'
import { ArchiveDialog } from './components/ArchiveDialog'
import { ThemeToggle } from './components/ThemeToggle'
import { ApiKeySetupDialog } from './components/ApiKeySetupDialog'
import { useApiKey } from './hooks/useApiKey'
import { useAnthropicApiKey } from './hooks/useAnthropicApiKey'
import { useArchive } from './hooks/useArchive'
import { useScribeTranscription } from './hooks/useScribeTranscription'
import { usePlatform } from './hooks/use-platform'
import { useSettingsStore } from './store/settings'
import { Button } from '@/components/ui/button'
import { cn } from '@/lib/utils'
import { toast } from 'sonner'
import { FolderArchive, PictureInPicture2, X } from 'lucide-react'
// Logo is rendered as text using PP Neue Machina Inktrap font
import bekGold from './assets/bek-gold.png'
import bardIcon from './assets/bard-icon.png'
import './App.css'

// Golden ratio based spacing (φ ≈ 1.618)
// Base: 8px → 13px → 21px → 34px → 55px → 89px

function Kbd({ children, className }: { children: React.ReactNode; className?: string }) {
  return (
    <kbd className={cn(
      'inline-flex items-center justify-center px-[6px] py-[2px] rounded-[4px]',
      'bg-background/60 border border-border/40 text-[10px] font-medium text-muted-foreground/80',
      'min-w-[18px] min-h-[18px] backdrop-blur-sm',
      className
    )}>
      {children}
    </kbd>
  )
}

function App() {
  const { apiKey, isLoaded, hasApiKey, saveApiKey } = useApiKey()
  useAnthropicApiKey() // Initialize Anthropic API key from env/localStorage
  const { archiveTranscript } = useArchive()
  const { setArchiveDialogOpen, theme, compactMode, setCompactMode } = useSettingsStore()
  const { isMobile, isDesktop } = usePlatform()
  const [isStarting, setIsStarting] = useState(false)
  const [isPaused, setIsPaused] = useState(false)
  const [isProcessing, setIsProcessing] = useState(false)
  const [recordingStartTime, setRecordingStartTime] = useState<number | null>(null)
  const [selectedDeviceId, setSelectedDeviceId] = useState<string | undefined>()
  const [selectedLanguage, setSelectedLanguage] = useState<ScribeLanguageCode>('en')
  
  // Track if current content has been archived (prevent double archiving)
  const [isArchived, setIsArchived] = useState(false)
  
  // Action feedback states
  const [copyTriggered, setCopyTriggered] = useState(false)

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

  // Apply theme on mount and when it changes
  useEffect(() => {
    const root = document.documentElement
    let isDark = false
    
    if (theme === 'dark') {
      root.classList.add('dark')
      isDark = true
    } else if (theme === 'light') {
      root.classList.remove('dark')
      isDark = false
    } else {
      // System preference
      const prefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches
      if (prefersDark) {
        root.classList.add('dark')
        isDark = true
      } else {
        root.classList.remove('dark')
        isDark = false
      }
    }
    
    // Update dock icon to match theme (macOS only)
    if (isDesktop) {
      import('@tauri-apps/api/core').then(({ invoke }) => {
        invoke('set_dock_icon', { darkMode: isDark }).catch((err) => {
          console.debug('Failed to set dock icon:', err)
        })
      })
    }
  }, [theme, isDesktop])


  // Check if there's existing content before starting new recording
  const hasExistingContent = !!(transcript || partialTranscript)

  // Include isPaused to keep the recording bar in "recording" state when paused
  const isRecording = isConnected || isTranscribing || isPaused
  const hasContent = !!(transcript || partialTranscript)

  const handleStartRecording = useCallback(async () => {
    // Clear any existing content and start fresh
    if (hasExistingContent) {
      clearTranscript()
      setIsArchived(false)
    }
    
    // Start recording directly
    setIsStarting(true)
    try {
      console.log('Starting recording with API key:', apiKey ? 'present' : 'missing')
      await start()
      setRecordingStartTime(Date.now())
    } catch (error) {
      console.error('Failed to start recording:', error)
    } finally {
      setIsStarting(false)
    }
  }, [hasExistingContent, start, apiKey, clearTranscript])


  const handleStopRecording = useCallback(async () => {
    setIsProcessing(true)
    stop() // This commits any partial transcript and disconnects
    setIsPaused(false)
    setRecordingStartTime(null)
    
    // Brief delay to let the UI update with finalized text
    await new Promise(resolve => setTimeout(resolve, 300))
    
    // Get the full transcript text (segments + any remaining partial)
    const fullText = [transcript, partialTranscript].filter(Boolean).join(' ').trim()
    
    if (fullText) {
      try {
        // Archive with Claude analysis (generates title, category, flags)
        await archiveTranscript({
          title: '', // Claude will generate
          text: fullText,
          segments,
          speakers: [],
          hasConsent: true,
        })
        setIsArchived(true)
        
        // Show fun archived confirmation
        toast('Tucked away safely.', {
          icon: <FolderArchive className="h-4 w-4 text-muted-foreground" />,
          duration: 2500,
        })
      } catch (error) {
        console.error('Failed to archive:', error)
        toast.error('Failed to archive transcript')
      }
    }
    
    setIsProcessing(false)
  }, [stop, transcript, partialTranscript, segments, archiveTranscript])

  // Handler for when max recording time is reached
  const handleMaxTimeReached = useCallback(() => {
    stop()
    setIsPaused(false)
    setRecordingStartTime(null)
  }, [stop])

  const handlePauseRecording = useCallback(() => {
    pause()
    setIsPaused(true)
  }, [pause])

  const handleResumeRecording = useCallback(async () => {
    await resume()
    setIsPaused(false)
  }, [resume])

  const handleDiscard = useCallback(() => {
    stop()
    setIsPaused(false)
    setRecordingStartTime(null)
    clearTranscript()
    setIsArchived(false)
  }, [stop, clearTranscript])

  const handleClear = useCallback(() => {
    if (!transcript && !partialTranscript) return
    clearTranscript()
    setIsArchived(false)
  }, [transcript, partialTranscript, clearTranscript])

  const handleCopy = useCallback(async () => {
    const textToCopy = transcript || partialTranscript
    if (!textToCopy) return
    
    try {
      await navigator.clipboard.writeText(textToCopy)
      setCopyTriggered(true)
      setTimeout(() => setCopyTriggered(false), 1500)
    } catch (error) {
      console.error('Failed to copy:', error)
    }
  }, [transcript, partialTranscript])

  const handleToggleTheme = useCallback(() => {
    const newTheme = theme === 'dark' ? 'light' : 'dark'
    useSettingsStore.getState().setTheme(newTheme)
  }, [theme])

  // Toggle compact floating mode
  const handleToggleCompact = useCallback(async () => {
    const newCompactMode = !compactMode
    setCompactMode(newCompactMode)
    
    // Resize window using Tauri API
    try {
      const { getCurrentWindow, LogicalSize } = await import('@tauri-apps/api/window')
      const { invoke } = await import('@tauri-apps/api/core')
      const appWindow = getCurrentWindow()
      
      if (newCompactMode) {
        // Compact mode: small floating window that hovers above everything including fullscreen
        await appWindow.setResizable(false)
        await appWindow.setSize(new LogicalSize(280, 240))
        // Use native macOS API to float above fullscreen apps
        await invoke('set_floating_window_level', { floating: true })
      } else {
        // Normal mode: regular window behavior
        await invoke('set_floating_window_level', { floating: false })
        await appWindow.setResizable(true)
        await appWindow.setSize(new LogicalSize(600, 800))
        await appWindow.center()
      }
    } catch (error) {
      console.error('Failed to resize window:', error)
    }
  }, [compactMode, setCompactMode])

  // Global keyboard shortcuts (desktop only)
  useEffect(() => {
    // Skip keyboard shortcuts on mobile
    if (isMobile) return

    const handleKeyDown = (e: KeyboardEvent) => {
      // Don't trigger shortcuts when typing in inputs
      if (e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement) {
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
          if (!isConnected) {
            handleStartRecording()
          }
          break
        case 'e':
          e.preventDefault()
          // Allow ending recording when connected OR when paused
          if (isConnected || isPaused) {
            handleStopRecording()
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
        case 'v':
          e.preventDefault()
          setArchiveDialogOpen(true)
          break
        case 't':
          e.preventDefault()
          handleToggleTheme()
          break
        case 'p':
          e.preventDefault()
          // Use isRecording (which includes isPaused) to allow resume from paused state
          if (isRecording) {
            if (isPaused) {
              handleResumeRecording()
            } else {
              handlePauseRecording()
            }
          }
          break
        case 'f':
          e.preventDefault()
          handleToggleCompact()
          break
      }
    }

    window.addEventListener('keydown', handleKeyDown)
    return () => window.removeEventListener('keydown', handleKeyDown)
  }, [isMobile, isConnected, isRecording, isPaused, handleStartRecording, handleStopRecording, handlePauseRecording, handleResumeRecording, handleCopy, handleClear, handleDiscard, handleToggleTheme, handleToggleCompact, setArchiveDialogOpen])

  // Bard logo is rendered as text with PP Neue Machina Inktrap font
  // BEK logo for footer - gold color
  const footerLogo = bekGold

  // Show loading state while API key is being loaded
  if (!isLoaded) {
    return (
      <div className="flex flex-col h-screen bg-background text-foreground items-center justify-center">
        <div className="animate-pulse text-muted-foreground">Loading...</div>
      </div>
    )
  }

  // Show API key setup dialog if no key configured
  if (!hasApiKey) {
    return (
      <div className="flex flex-col h-screen bg-background text-foreground">
        <ApiKeySetupDialog isOpen={true} onSave={saveApiKey} />
      </div>
    )
  }

  // Compact mode - minimal floating window
  if (compactMode) {
    return (
      <div className="flex flex-col h-screen bg-background text-foreground">
        {/* Compact Header */}
        <header 
          className="relative flex items-center justify-center shrink-0 h-[36px] px-[13px]"
          {...(isDesktop ? { 'data-tauri-drag-region': true } : {})}
        >
          {/* Logo - centered */}
          <div className="flex items-center gap-1.5">
            <img src={bardIcon} alt="" className="h-[14px] w-auto" />
            <span 
              className="font-brand text-[14px] tracking-tight"
              style={{ 
                fontFamily: "'PP Neue Machina Inktrap', sans-serif", 
                fontWeight: 800,
                background: 'linear-gradient(135deg, #EAB308 0%, #EF4444 100%)',
                WebkitBackgroundClip: 'text',
                WebkitTextFillColor: 'transparent',
                backgroundClip: 'text',
              }}
            >
              Bard
            </span>
            <span 
              className="px-1 py-0.5 rounded bg-muted/40 border border-border/30 text-[8px] text-muted-foreground/60"
              style={{ fontFamily: "'PP Neue Machina Inktrap', sans-serif", fontWeight: 400 }}
            >
              v1
            </span>
          </div>
          
          {/* Exit button - right side */}
          <Button
            variant="ghost"
            size="sm"
            onClick={handleToggleCompact}
            className="absolute right-[13px] h-[24px] w-[24px] p-0 rounded-lg"
            aria-label="Exit compact mode"
          >
            <X className="h-3.5 w-3.5 opacity-60" />
          </Button>
        </header>
        
        {/* Compact Content */}
        <main className="flex flex-col flex-1 px-[13px] pb-[13px] gap-[8px] overflow-hidden">
          {/* Waveform */}
          <WaveformDisplay
            isRecording={isRecording}
            isPaused={isPaused}
            isProcessing={status === 'connecting'}
            deviceId={selectedDeviceId}
          />
          
          {/* Transcript */}
          <div className="flex-1 min-h-0 rounded-xl bg-muted/20 border border-border/30 overflow-y-auto p-[10px]">
            {hasContent ? (
              <p className="text-[12px] leading-[1.5] text-foreground/80">
                {transcript || ''}
                {partialTranscript && (
                  <span className="text-muted-foreground/60">
                    {transcript ? ' ' : ''}{partialTranscript}
                    {isRecording && (
                      <span className="inline-block w-[2px] h-[13px] bg-primary/80 ml-1 animate-pulse align-text-bottom rounded-full" />
                    )}
                  </span>
                )}
              </p>
            ) : (
              <p className="text-[10px] text-muted-foreground/30 text-center pt-2">
                F to exit · R to record
              </p>
            )}
          </div>
        </main>
      </div>
    )
  }

  return (
    <div className="flex flex-col h-screen bg-background text-foreground">
      {/* Header - φ⁴ height (55px), with safe area padding for iOS notch */}
      <header 
        className={cn(
          "relative flex items-center justify-center shrink-0",
          isMobile ? "h-[55px] pt-[env(safe-area-inset-top)]" : "h-[55px]"
        )}
        {...(isDesktop ? { 'data-tauri-drag-region': true } : {})}
      >
        <div className="flex items-center gap-2">
          <img src={bardIcon} alt="" className="h-[18px] w-auto" />
          <span 
            className="font-brand text-[18px] tracking-tight"
            style={{ 
              fontFamily: "'PP Neue Machina Inktrap', sans-serif", 
              fontWeight: 800,
              background: 'linear-gradient(135deg, #EAB308 0%, #EF4444 100%)',
              WebkitBackgroundClip: 'text',
              WebkitTextFillColor: 'transparent',
              backgroundClip: 'text',
            }}
          >
            Bard
          </span>
          <span 
            className="px-1.5 py-0.5 rounded-md bg-muted/40 border border-border/30 text-[10px] text-muted-foreground/60"
            style={{ fontFamily: "'PP Neue Machina Inktrap', sans-serif", fontWeight: 400 }}
          >
            v1
          </span>
        </div>
        <div className={cn(
          "absolute flex items-center gap-0",
          isMobile ? "right-[16px]" : "right-[21px]"
        )}>
          {/* Compact mode toggle */}
          {!isMobile && (
            <Button
              variant="ghost"
              size="sm"
              onClick={handleToggleCompact}
              className="h-[34px] px-1.5 gap-0.5 rounded-lg"
              aria-label="Compact mode"
            >
              <PictureInPicture2 className="h-4 w-4 opacity-60" />
              <Kbd>F</Kbd>
            </Button>
          )}
          <ArchiveDialog />
          <ThemeToggle />
        </div>
      </header>

      {/* Main Content - φ² padding (21px on desktop, 16px on mobile) */}
      <main className={cn(
        "flex flex-col flex-1 pb-[13px] gap-[13px] overflow-hidden",
        isMobile ? "px-[16px]" : "px-[21px]"
      )}>
        {/* Recording Bar */}
        <RecordingBar
          isRecording={isRecording}
          isLoading={isStarting || status === 'connecting'}
          isProcessing={isProcessing}
          disabled={!isLoaded}
          hasContent={hasContent}
          onStartRecording={handleStartRecording}
          onStopRecording={handleStopRecording}
          selectedDeviceId={selectedDeviceId}
          onDeviceChange={setSelectedDeviceId}
          selectedLanguage={selectedLanguage}
          onLanguageChange={setSelectedLanguage}
        />

        {/* Waveform - fixed height */}
        <WaveformDisplay
          isRecording={isRecording}
          isPaused={isPaused}
          isProcessing={status === 'connecting'}
          deviceId={selectedDeviceId}
        />

        {/* Action Bar - minimal height */}
        <div className="flex items-center justify-between h-[34px]">
          {/* Left side - Pause/Resume button (only when recording) */}
          <div className="flex items-center gap-2">
            {isRecording && (
              <Button
                variant="ghost"
                size="sm"
                onClick={isPaused ? handleResumeRecording : handlePauseRecording}
                className={cn(
                  'h-[34px] px-2 gap-1 rounded-lg transition-all',
                  isPaused && 'bg-[#EAB308]/15 hover:bg-[#EAB308]/25'
                )}
                aria-label={isPaused ? "Resume recording" : "Pause recording"}
              >
                {isPaused ? (
                  <BrandPlayIcon size={18} />
                ) : (
                  <BrandPauseIcon size={18} />
                )}
                {/* Hide keyboard hint on mobile */}
                {!isMobile && <Kbd>P</Kbd>}
              </Button>
            )}
          </div>
          
          {/* Right side - Copy button */}
          <Button
            variant="ghost"
            size="sm"
            onClick={handleCopy}
            disabled={!hasContent}
            className={cn(
              'h-[34px] px-2 gap-1 rounded-lg transition-all',
              copyTriggered && 'bg-[#00D4FF]/15'
            )}
            aria-label="Copy transcript"
          >
            {copyTriggered ? (
              <BrandCheckIcon size={18} />
            ) : (
              <BrandCopyIcon size={18} />
            )}
            {/* Hide keyboard hint on mobile */}
            {!isMobile && <Kbd>C</Kbd>}
          </Button>
        </div>

        {/* Transcript */}
        <TranscriptBox
          transcript={transcript}
          segments={segments}
          partialTranscript={partialTranscript}
          isRecording={isRecording}
          isPaused={isPaused}
          isProcessing={isProcessing}
          isArchived={isArchived}
          recordingStartTime={recordingStartTime}
          onMaxTimeReached={handleMaxTimeReached}
        />
      </main>

      {/* Footer - minimal, elegant, with safe area padding for iOS home indicator */}
      <footer className={cn(
        "relative flex items-center justify-center border-t border-border/20",
        isMobile 
          ? "h-auto min-h-[55px] px-[16px] pb-[env(safe-area-inset-bottom)]" 
          : "h-[55px] px-[21px]"
      )}>
        <div className="flex items-center gap-2">
          <ShieldIcon size={13} className="text-[#00D4FF]/60" />
          <span className="text-[10px] text-muted-foreground/50 tracking-wide">
            All data processed and stored locally on your device
          </span>
        </div>
        <button
          onClick={() => {
            import('@tauri-apps/plugin-opener').then(({ openUrl }) => {
              openUrl('https://briggskellogg.com')
            }).catch(() => {
              window.open('https://briggskellogg.com', '_blank')
            })
          }}
          className={cn(
            "group absolute p-0 border-0 bg-transparent cursor-pointer",
            isMobile ? "right-[16px]" : "right-[21px]"
          )}
          aria-label="BEK"
        >
          <img 
            src={footerLogo} 
            alt="BEK" 
            className="h-[16px] w-auto opacity-40 hover:opacity-70 transition-opacity duration-200"
          />
        </button>
      </footer>
    </div>
  )
}

export default App

