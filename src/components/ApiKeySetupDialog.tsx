/**
 * ApiKeySetupDialog - First-launch experience for entering ElevenLabs API key
 */

import { useState, useCallback } from 'react'
import { cn } from '@/lib/utils'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { ExternalLink, Key, Loader2 } from 'lucide-react'

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

    // Basic validation - ElevenLabs keys typically start with specific patterns
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
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm">
      <div className={cn(
        'relative w-full max-w-md mx-4 p-8 rounded-2xl',
        'bg-background border border-border/50 shadow-2xl',
        'animate-in fade-in-0 zoom-in-95 duration-300'
      )}>
        {/* Logo/Branding */}
        <div className="flex flex-col items-center mb-8">
          <div className="w-16 h-16 mb-4 rounded-2xl bg-gradient-to-br from-primary/20 to-primary/5 flex items-center justify-center border border-primary/20">
            <Key className="w-8 h-8 text-primary" />
          </div>
          <h1 className="text-2xl font-semibold tracking-tight">Welcome to ElevenMemo</h1>
          <p className="text-sm text-muted-foreground mt-2 text-center">
            Enter your ElevenLabs API key to get started with voice transcription.
          </p>
        </div>

        {/* API Key Input */}
        <div className="space-y-4">
          <div className="space-y-2">
            <label htmlFor="api-key" className="text-sm font-medium text-foreground/80">
              ElevenLabs API Key
            </label>
            <Input
              id="api-key"
              type="password"
              placeholder="sk_..."
              value={apiKey}
              onChange={(e) => {
                setApiKey(e.target.value)
                setError(null)
              }}
              onKeyDown={handleKeyDown}
              disabled={isSaving}
              className={cn(
                'h-12 text-base',
                error && 'border-red-500 focus-visible:ring-red-500'
              )}
              autoFocus
            />
            {error && (
              <p className="text-sm text-red-500">{error}</p>
            )}
          </div>

          {/* Get API Key Link */}
          <a
            href="https://elevenlabs.io/app/settings/api-keys"
            target="_blank"
            rel="noopener noreferrer"
            className={cn(
              'inline-flex items-center gap-1.5 text-sm text-primary hover:text-primary/80',
              'transition-colors'
            )}
            onClick={(e) => {
              e.preventDefault()
              // Open in default browser via Tauri
              import('@tauri-apps/plugin-opener').then(({ openUrl }) => {
                openUrl('https://elevenlabs.io/app/settings/api-keys')
              }).catch(() => {
                // Fallback to window.open
                window.open('https://elevenlabs.io/app/settings/api-keys', '_blank')
              })
            }}
          >
            <ExternalLink className="w-3.5 h-3.5" />
            Get your API key from ElevenLabs
          </a>

          {/* Save Button */}
          <Button
            onClick={handleSave}
            disabled={isSaving || !apiKey.trim()}
            className="w-full h-12 text-base font-medium mt-4"
          >
            {isSaving ? (
              <>
                <Loader2 className="w-4 h-4 mr-2 animate-spin" />
                Saving...
              </>
            ) : (
              'Get Started'
            )}
          </Button>
        </div>

        {/* Footer Note */}
        <p className="text-xs text-muted-foreground/60 text-center mt-6">
          Your API key is stored locally and never shared.
        </p>
      </div>
    </div>
  )
}

