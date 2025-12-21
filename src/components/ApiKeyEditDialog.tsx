/**
 * ApiKeyEditDialog - Modal for editing/removing the ElevenLabs API key
 */

import { useState, useCallback, useEffect } from 'react'
import {
  Dialog,
  DialogContent,
} from '@/components/ui/dialog'
import { Input } from '@/components/ui/input'
import { Button } from '@/components/ui/button'
import { Check, Trash2, ExternalLink } from 'lucide-react'
import { cn } from '@/lib/utils'
import bardIcon from '@/assets/bard-icon.png'

interface ApiKeyEditDialogProps {
  isOpen: boolean
  onClose: () => void
  onUpdate: (key: string) => Promise<boolean>
  onRemove: () => Promise<boolean>
  hasExistingKey: boolean
}

export function ApiKeyEditDialog({
  isOpen,
  onClose,
  onUpdate,
  onRemove,
  hasExistingKey,
}: ApiKeyEditDialogProps) {
  const [apiKey, setApiKey] = useState('')
  const [isUpdating, setIsUpdating] = useState(false)
  const [isRemoving, setIsRemoving] = useState(false)

  // Reset input when dialog opens
  useEffect(() => {
    if (isOpen) {
      setApiKey('')
    }
  }, [isOpen])

  const handleUpdate = useCallback(async () => {
    const trimmedKey = apiKey.trim()
    if (!trimmedKey) return

    setIsUpdating(true)
    try {
      const success = await onUpdate(trimmedKey)
      if (success) {
        onClose()
      }
    } finally {
      setIsUpdating(false)
    }
  }, [apiKey, onUpdate, onClose])

  const handleRemove = useCallback(async () => {
    console.log('[ApiKeyEditDialog] Remove button clicked')
    setIsRemoving(true)
    try {
      await onRemove()
      console.log('[ApiKeyEditDialog] onRemove completed, closing dialog')
      // Always close dialog after removal attempt
      onClose()
    } catch (error) {
      console.error('[ApiKeyEditDialog] Remove failed:', error)
      onClose()
    } finally {
      setIsRemoving(false)
    }
  }, [onRemove, onClose])

  const handleKeyDown = useCallback((e: React.KeyboardEvent) => {
    if (e.key === 'Enter' && !isUpdating && apiKey.trim()) {
      handleUpdate()
    }
  }, [handleUpdate, isUpdating, apiKey])

  const openElevenLabsKeys = () => {
    import('@tauri-apps/plugin-opener').then(({ openUrl }) => {
      openUrl('https://elevenlabs.io/app/settings/api-keys')
    }).catch(() => {
      window.open('https://elevenlabs.io/app/settings/api-keys', '_blank')
    })
  }

  return (
    <Dialog open={isOpen} onOpenChange={(open) => !open && onClose()}>
      <DialogContent 
        className="max-w-md rounded-2xl border-border/30 bg-background/98 backdrop-blur-xl p-6"
        showCloseButton={true}
      >
        {/* Header with logo, title, and connected badge */}
        <div className="flex items-center justify-between mb-6">
          <div className="flex items-center gap-3">
            <img 
              src={bardIcon} 
              alt="Intersect" 
              className="h-[18px] w-auto object-contain"
            />
            <div>
              <h2 className="text-[18px] font-semibold tracking-tight">Intersect</h2>
              <p className="text-[13px] text-muted-foreground/60">Powered by ElevenLabs</p>
            </div>
          </div>
          {hasExistingKey && (
            <span className="flex items-center gap-1.5 px-3 py-1.5 rounded-full text-[12px] font-medium text-emerald-400 bg-emerald-400/15">
              <Check className="h-3.5 w-3.5" />
              Connected
            </span>
          )}
        </div>

        <div className="space-y-4">
          {/* Remove Key button - only show if key exists */}
          {hasExistingKey && (
            <Button
              variant="outline"
              onClick={handleRemove}
              disabled={isRemoving}
              className={cn(
                'w-full h-[48px] rounded-xl font-medium text-[14px] gap-2',
                'border-border/40 text-muted-foreground',
                'hover:bg-muted/20 hover:text-foreground transition-colors',
                isRemoving && 'opacity-50 cursor-not-allowed'
              )}
            >
              {isRemoving ? (
                <div className="h-4 w-4 animate-spin rounded-full border-2 border-current border-t-transparent" />
              ) : (
                <>
                  <Trash2 className="h-4 w-4" />
                  Remove Key
                </>
              )}
            </Button>
          )}

          {/* Get API key link */}
          <button
            onClick={openElevenLabsKeys}
            className="flex items-center gap-2 text-[13px] text-muted-foreground/70 hover:text-foreground transition-colors"
          >
            <ExternalLink className="h-3.5 w-3.5" />
            Get your API key
          </button>

          {/* Divider with "or update" text - only if key exists */}
          {hasExistingKey && (
            <div className="flex items-center gap-3 pt-2">
              <div className="flex-1 h-px bg-border/30" />
              <span className="text-[11px] text-muted-foreground/40">or enter a new key</span>
              <div className="flex-1 h-px bg-border/30" />
            </div>
          )}

          <Input
            type="password"
            placeholder={hasExistingKey ? "Enter new key..." : "Paste your API key..."}
            value={apiKey}
            onChange={(e) => setApiKey(e.target.value)}
            onKeyDown={handleKeyDown}
            className="h-[48px] rounded-xl bg-muted/30 border-border/30 text-[14px] placeholder:text-muted-foreground/40"
            autoFocus={!hasExistingKey}
          />

          <Button
            onClick={handleUpdate}
            disabled={!apiKey.trim() || isUpdating}
            className={cn(
              'w-full h-[48px] rounded-xl font-medium text-[14px] text-white',
              'hover:opacity-90 transition-opacity',
              (!apiKey.trim() || isUpdating) && 'opacity-50 cursor-not-allowed'
            )}
            style={{
              background: 'linear-gradient(135deg, #EAB308 0%, #EF4444 100%)',
            }}
          >
            {isUpdating ? (
              <div className="h-4 w-4 animate-spin rounded-full border-2 border-current border-t-transparent" />
            ) : (
              hasExistingKey ? 'Update Key' : 'Save Key'
            )}
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  )
}

