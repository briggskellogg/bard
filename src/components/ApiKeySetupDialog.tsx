/**
 * ApiKeySetupDialog - First-launch experience for entering ElevenLabs API key
 */

import { useState, useCallback } from 'react'
import { cn } from '@/lib/utils'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { ArrowRight, Loader2 } from 'lucide-react'
import bardIcon from '@/assets/bard-icon.png'

interface ApiKeySetupDialogProps {
  onSave: (apiKey: string) => Promise<boolean>
  isOpen: boolean
}

export function ApiKeySetupDialog({ onSave, isOpen }: ApiKeySetupDialogProps) {
  const [apiKey, setApiKey] = useState('')
  const [isSaving, setIsSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const handleSave = useCallback(async () => {
    const trimmedKey = apiKey.trim()
    
    if (!trimmedKey) {
      setError('Please enter your API key')
      return
    }

    if (trimmedKey.length < 20) {
      setError('API key seems too short')
      return
    }

    setIsSaving(true)
    setError(null)

    try {
      const success = await onSave(trimmedKey)
      if (!success) {
        setError('Failed to save API key. Please try again.')
      }
    } catch (err) {
      setError('An error occurred while saving')
      console.error('[ApiKeySetupDialog] Save error:', err)
    } finally {
      setIsSaving(false)
    }
  }, [apiKey, onSave])

  const handleKeyDown = useCallback((e: React.KeyboardEvent) => {
    if (e.key === 'Enter' && !isSaving) {
      handleSave()
    }
  }, [handleSave, isSaving])

  if (!isOpen) return null

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center">
      {/* Gradient background */}
      <div className="absolute inset-0 bg-gradient-to-br from-background via-background to-primary/5" />
      
      <div className={cn(
        'relative w-full max-w-sm mx-6 p-8',
        'animate-in fade-in-0 zoom-in-95 duration-500'
      )}>
        {/* Logo */}
        <div className="flex flex-col items-center mb-10">
          <img 
            src={bardIcon} 
            alt="Bard" 
            className="w-20 h-20 mb-6 rounded-[22px] shadow-lg"
          />
          <h1 className="text-xl font-medium tracking-tight text-foreground">
            Welcome to Bard
          </h1>
          <p className="text-sm text-muted-foreground mt-2 text-center max-w-[280px]">
            Real-time voice transcription powered by ElevenLabs Scribe
          </p>
        </div>

        {/* API Key Input */}
        <div className="space-y-5">
          <div className="space-y-2">
            <Input
              id="api-key"
              type="password"
              placeholder="Paste your ElevenLabs API key"
              value={apiKey}
              onChange={(e) => {
                setApiKey(e.target.value)
                setError(null)
              }}
              onKeyDown={handleKeyDown}
              disabled={isSaving}
              className={cn(
                'h-12 text-base bg-muted/50 border-border/50 placeholder:text-muted-foreground/50',
                'focus:bg-background focus:border-primary/50',
                'transition-all duration-200',
                error && 'border-red-500/50 focus:border-red-500'
              )}
              autoFocus
            />
            {error && (
              <p className="text-xs text-red-400 pl-1">{error}</p>
            )}
          </div>

          {/* Continue Button */}
          <Button
            onClick={handleSave}
            disabled={isSaving || !apiKey.trim()}
            className={cn(
              'w-full h-12 text-base font-medium',
              'bg-primary hover:bg-primary/90',
              'transition-all duration-200'
            )}
          >
            {isSaving ? (
              <Loader2 className="w-4 h-4 animate-spin" />
            ) : (
              <>
                Continue
                <ArrowRight className="w-4 h-4 ml-2" />
              </>
            )}
          </Button>

          {/* Get API Key Link */}
          <button
            onClick={() => {
              import('@tauri-apps/plugin-opener').then(({ openUrl }) => {
                openUrl('https://elevenlabs.io/app/settings/api-keys')
              }).catch(() => {
                window.open('https://elevenlabs.io/app/settings/api-keys', '_blank')
              })
            }}
            className="w-full text-sm text-muted-foreground hover:text-foreground transition-colors"
          >
            Don't have a key? <span className="underline underline-offset-2">Get one free</span>
          </button>
        </div>

        {/* Footer */}
        <p className="text-[11px] text-muted-foreground/40 text-center mt-8">
          Your key is stored locally on this device
        </p>
      </div>
    </div>
  )
}
