import { useState } from 'react'
import { Key, Info } from 'lucide-react'
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { cn } from '@/lib/utils'

interface ApiKeyEditorModalProps {
  isOpen: boolean
  onClose: () => void
  currentKey: string
  onSave: (key: string) => Promise<boolean>
  onRemove: () => Promise<boolean>
}

export function ApiKeyEditorModal({
  isOpen,
  onClose,
  currentKey,
  onSave,
  onRemove,
}: ApiKeyEditorModalProps) {
  const [newKey, setNewKey] = useState('')
  const [isSaving, setIsSaving] = useState(false)
  const [isRemoving, setIsRemoving] = useState(false)

  const handleSave = async () => {
    if (!newKey.trim()) return
    setIsSaving(true)
    try {
      const success = await onSave(newKey.trim())
      if (success) {
        setNewKey('')
        onClose()
      }
    } finally {
      setIsSaving(false)
    }
  }

  const handleRemove = async () => {
    setIsRemoving(true)
    try {
      const success = await onRemove()
      if (success) {
        onClose()
      }
    } finally {
      setIsRemoving(false)
    }
  }

  return (
    <Dialog open={isOpen} onOpenChange={(open) => !open && onClose()}>
      <DialogContent className="max-w-md w-[90vw] rounded-2xl border border-border/30 shadow-2xl bg-background/98 backdrop-blur-xl p-6">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2 text-lg font-semibold">
            <Key className="h-5 w-5 text-[#00D4FF]" />
            API Key
          </DialogTitle>
        </DialogHeader>
        
        <div className="space-y-4 mt-4">
          <Input
            type="password"
            placeholder="Enter new key..."
            value={newKey}
            onChange={(e) => setNewKey(e.target.value)}
            className="h-11 rounded-xl bg-muted/30 border-border/30 text-sm placeholder:text-muted-foreground/40"
            onKeyDown={(e) => {
              if (e.key === 'Enter') {
                handleSave()
              }
            }}
          />
          
          <div className="flex gap-3">
            <Button
              onClick={handleSave}
              disabled={!newKey.trim() || isSaving}
              className={cn(
                "flex-1 h-11 rounded-xl font-medium",
                "bg-gradient-to-r from-[#EAB308] to-[#00D4FF] hover:opacity-90",
                "text-black"
              )}
            >
              {isSaving ? 'Saving...' : 'Update'}
            </Button>
            <Button
              variant="outline"
              onClick={handleRemove}
              disabled={!currentKey || isRemoving}
              className="h-11 px-6 rounded-xl border-border/50"
            >
              {isRemoving ? 'Removing...' : 'Remove'}
            </Button>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  )
}

interface ApiStatusIndicatorProps {
  hasApiKey: boolean
  isConnected: boolean
  error: string | null
  onKeyClick: () => void
}

export function ApiStatusIndicator({
  hasApiKey,
  isConnected,
  error,
  onKeyClick,
}: ApiStatusIndicatorProps) {
  const getStatus = () => {
    if (!hasApiKey) return { label: 'No API Key', color: 'text-muted-foreground', dot: 'bg-gray-400' }
    if (error) return { label: 'Error', color: 'text-red-400', dot: 'bg-red-400' }
    if (isConnected) return { label: 'Connected', color: 'text-emerald-400', dot: 'bg-emerald-400' }
    return { label: 'Ready', color: 'text-muted-foreground', dot: 'bg-gray-400' }
  }

  const status = getStatus()

  return (
    <div className="flex items-center gap-2">
      <div className={cn('h-2 w-2 rounded-full', status.dot)} />
      <span className={cn('text-xs font-medium', status.color)}>
        {status.label}
      </span>
      {error && (
        <div className="group relative">
          <Info className="h-3.5 w-3.5 text-red-400 cursor-help" />
          <div className="absolute bottom-full right-0 mb-2 px-3 py-2 bg-popover border border-border rounded-lg shadow-lg text-xs text-foreground max-w-[200px] opacity-0 invisible group-hover:opacity-100 group-hover:visible transition-all z-50">
            {error}
          </div>
        </div>
      )}
      <button
        onClick={onKeyClick}
        className="p-1 rounded-md hover:bg-muted/50 transition-colors"
        aria-label="Edit API Key"
      >
        <Key className="h-3.5 w-3.5 text-[#00D4FF]/70 hover:text-[#00D4FF]" />
      </button>
    </div>
  )
}

