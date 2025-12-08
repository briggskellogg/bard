import { useState, useEffect } from 'react'
import { Settings, Eye, EyeOff, ExternalLink } from 'lucide-react'
import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetHeader,
  SheetTitle,
  SheetTrigger,
} from '@/components/ui/sheet'
import { Button } from '@/components/ui/button'
import { Label } from '@/components/ui/label'
import { useSettingsStore } from '@/store/settings'
import { useApiKey } from '@/hooks/useApiKey'
import { cn } from '@/lib/utils'

function Kbd({ children, className }: { children: React.ReactNode; className?: string }) {
  return (
    <kbd className={cn(
      'inline-flex items-center justify-center px-1.5 py-0.5 rounded',
      'bg-muted/80 border border-border/50 text-[10px] font-medium text-muted-foreground',
      'min-w-[18px]',
      className
    )}>
      {children}
    </kbd>
  )
}

export function SettingsDialog() {
  const { settingsDialogOpen, setSettingsDialogOpen } = useSettingsStore()
  const { apiKey, saveApiKey, clearApiKey, hasApiKey } = useApiKey()
  
  const [inputValue, setInputValue] = useState('')
  const [showApiKey, setShowApiKey] = useState(false)
  const [isSaving, setIsSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    if (settingsDialogOpen) {
      setInputValue(apiKey)
      setError(null)
    }
  }, [settingsDialogOpen, apiKey])

  const handleSave = async () => {
    if (!inputValue.trim()) {
      setError('API key is required')
      return
    }

    setIsSaving(true)
    setError(null)

    try {
      await saveApiKey(inputValue.trim())
      setSettingsDialogOpen(false)
    } catch (err) {
      setError('Failed to save API key')
    } finally {
      setIsSaving(false)
    }
  }

  const handleClear = async () => {
    setIsSaving(true)
    try {
      await clearApiKey()
      setInputValue('')
    } catch (err) {
      setError('Failed to clear API key')
    } finally {
      setIsSaving(false)
    }
  }

  const openElevenLabsDashboard = () => {
    window.open('https://elevenlabs.io/app/settings/api-keys', '_blank')
  }

  return (
    <Sheet open={settingsDialogOpen} onOpenChange={setSettingsDialogOpen}>
      <SheetTrigger asChild>
        <Button
          variant="ghost"
          size="sm"
          className="h-8 px-2 gap-1.5"
          aria-label="Settings"
        >
          <Settings className="h-4 w-4" />
          <Kbd>S</Kbd>
        </Button>
      </SheetTrigger>
      <SheetContent 
        side="right" 
        className="w-[400px] sm:w-[450px] border-l-2 border-border shadow-2xl bg-background/95 backdrop-blur-sm"
      >
        <div className="h-full flex flex-col px-6 py-4">
          <SheetHeader className="pb-8 pt-4">
            <SheetTitle className="text-xl">Settings</SheetTitle>
            <SheetDescription className="text-sm leading-relaxed">
              Transcription powered by Scribe v2 Realtime. Add your ElevenLabs API key.
            </SheetDescription>
          </SheetHeader>
          
          <div className="flex-1 space-y-8 py-4">
            <div className="space-y-4">
              <Label htmlFor="api-key" className="text-sm font-medium">
                ElevenLabs API Key
              </Label>
              <div className="relative">
                <input
                  id="api-key"
                  type={showApiKey ? 'text' : 'password'}
                  value={inputValue}
                  onChange={(e) => setInputValue(e.target.value)}
                  placeholder="sk_..."
                  className="flex h-11 w-full rounded-md border border-input bg-background px-3 py-2 pr-12 text-sm ring-offset-background file:border-0 file:bg-transparent file:text-sm file:font-medium placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50"
                  autoComplete="off"
                  spellCheck={false}
                />
                <Button
                  type="button"
                  variant="ghost"
                  size="icon"
                  onClick={() => setShowApiKey(!showApiKey)}
                  className="absolute right-1 top-1/2 -translate-y-1/2 h-8 w-8"
                  aria-label={showApiKey ? 'Hide API key' : 'Show API key'}
                >
                  {showApiKey ? (
                    <EyeOff className="h-4 w-4" />
                  ) : (
                    <Eye className="h-4 w-4" />
                  )}
                </Button>
              </div>
              {error && (
                <p className="text-sm text-destructive">{error}</p>
              )}
            </div>

            <Button
              variant="link"
              size="sm"
              onClick={openElevenLabsDashboard}
              className="h-auto p-0 text-muted-foreground hover:text-foreground"
            >
              Get your API key from ElevenLabs
              <ExternalLink className="ml-1.5 h-3.5 w-3.5" />
            </Button>

            <div className="flex gap-3 pt-4">
              <Button
                onClick={handleSave}
                disabled={isSaving || !inputValue.trim()}
                className="flex-1 h-11"
              >
                {isSaving ? 'Saving...' : 'Save'}
              </Button>
              {hasApiKey && (
                <Button
                  variant="outline"
                  onClick={handleClear}
                  disabled={isSaving}
                  className="h-11 px-6"
                >
                  Clear
                </Button>
              )}
            </div>
          </div>
        </div>
      </SheetContent>
    </Sheet>
  )
}

