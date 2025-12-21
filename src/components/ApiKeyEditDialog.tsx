/**
 * ApiKeyEditDialog - Modal for editing/removing the ElevenLabs API key
 */

import { useState, useCallback, useEffect } from 'react'
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { Input } from '@/components/ui/input'
import { Button } from '@/components/ui/button'
import { Key } from 'lucide-react'
import { cn } from '@/lib/utils'

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
    setIsRemoving(true)
    try {
      const success = await onRemove()
      if (success) {
        onClose()
      }
    } finally {
      setIsRemoving(false)
    }
  }, [onRemove, onClose])

  const handleKeyDown = useCallback((e: React.KeyboardEvent) => {
    if (e.key === 'Enter' && !isUpdating && apiKey.trim()) {
      handleUpdate()
    }
  }, [handleUpdate, isUpdating, apiKey])

  return (
    <Dialog open={isOpen} onOpenChange={(open) => !open && onClose()}>
      <DialogContent 
        className="max-w-sm rounded-2xl border-border/30 bg-background/98 backdrop-blur-xl p-6"
        showCloseButton={true}
      >
        <DialogHeader className="pb-2">
          <div className="flex items-center gap-3">
            <Key className="h-5 w-5 text-[#00D4FF]" />
            <DialogTitle className="text-[16px] font-semibold tracking-tight">
              API Key
            </DialogTitle>
          </div>
        </DialogHeader>

        <div className="space-y-4">
          <Input
            type="password"
            placeholder="Enter new key..."
            value={apiKey}
            onChange={(e) => setApiKey(e.target.value)}
            onKeyDown={handleKeyDown}
            className="h-[42px] rounded-xl bg-muted/30 border-border/30 text-[14px] placeholder:text-muted-foreground/40"
            autoFocus
          />

          <div className="flex items-center gap-3">
            <Button
              onClick={handleUpdate}
              disabled={!apiKey.trim() || isUpdating}
              className={cn(
                'flex-1 h-[42px] rounded-xl font-medium text-[14px]',
                'bg-gradient-to-r from-[#EAB308] via-[#84cc16] to-[#22d3d1]',
                'hover:opacity-90 transition-opacity',
                'text-black',
                (!apiKey.trim() || isUpdating) && 'opacity-50 cursor-not-allowed'
              )}
            >
              {isUpdating ? (
                <div className="h-4 w-4 animate-spin rounded-full border-2 border-current border-t-transparent" />
              ) : (
                'Update'
              )}
            </Button>
            <Button
              variant="outline"
              onClick={handleRemove}
              disabled={!hasExistingKey || isRemoving}
              className={cn(
                'h-[42px] px-6 rounded-xl font-medium text-[14px]',
                'border-border/30 text-muted-foreground',
                'hover:bg-muted/20 hover:text-foreground transition-colors',
                (!hasExistingKey || isRemoving) && 'opacity-50 cursor-not-allowed'
              )}
            >
              {isRemoving ? (
                <div className="h-4 w-4 animate-spin rounded-full border-2 border-current border-t-transparent" />
              ) : (
                'Remove'
              )}
            </Button>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  )
}

