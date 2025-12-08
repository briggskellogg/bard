import { Clipboard, Trash2, Check, Archive, Loader2 } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { cn } from '@/lib/utils'

function Kbd({ children, className }: { children: React.ReactNode; className?: string }) {
  return (
    <kbd className={cn(
      'inline-flex items-center justify-center px-1.5 py-0.5 rounded',
      'bg-muted/80 border border-border/50 text-[10px] font-medium text-muted-foreground',
      'min-w-[20px]',
      className
    )}>
      {children}
    </kbd>
  )
}

interface ActionBarProps {
  hasContent: boolean
  isArchived?: boolean
  isProcessing?: boolean
  onArchive: () => void
  onCopy: () => void
  onClear: () => void
  archiveTriggered?: boolean
  copyTriggered?: boolean
  clearTriggered?: boolean
}

export function ActionBar({
  hasContent,
  isArchived = false,
  isProcessing = false,
  onArchive,
  onCopy,
  onClear,
  archiveTriggered = false,
  copyTriggered = false,
  clearTriggered = false,
}: ActionBarProps) {
  const archiveDisabled = !hasContent || isArchived || isProcessing

  return (
    <div className="flex items-center gap-1">
        <Button
          variant="ghost"
          size="sm"
          onClick={onArchive}
          disabled={archiveDisabled}
          className={cn(
            'h-8 px-2.5 gap-2 transition-all',
            archiveTriggered && 'bg-green-500/20 text-green-500',
            isArchived && hasContent && 'opacity-50'
          )}
          aria-label="Archive transcript"
          title={isArchived ? 'Already archived' : isProcessing ? 'Processing...' : 'Archive transcript'}
        >
          {archiveTriggered || isArchived ? (
            <Check className="h-4 w-4" />
          ) : isProcessing ? (
            <Loader2 className="h-4 w-4 animate-spin" />
          ) : (
            <Archive className="h-4 w-4" />
          )}
          <Kbd>A</Kbd>
        </Button>
      <Button
        variant="ghost"
        size="sm"
        onClick={onCopy}
        disabled={!hasContent}
        className={cn(
          'h-8 px-2.5 gap-2 transition-all',
          copyTriggered && 'bg-green-500/20 text-green-500'
        )}
        aria-label="Copy transcript"
      >
        {copyTriggered ? (
          <Check className="h-4 w-4" />
        ) : (
          <Clipboard className="h-4 w-4" />
        )}
        <Kbd>C</Kbd>
      </Button>
      <Button
        variant="ghost"
        size="sm"
        onClick={onClear}
        disabled={!hasContent}
        className={cn(
          'h-8 px-2.5 gap-2 transition-all',
          clearTriggered && 'bg-red-500/20 text-red-500'
        )}
        aria-label="Clear transcript"
      >
        {clearTriggered ? (
          <Check className="h-4 w-4" />
        ) : (
          <Trash2 className="h-4 w-4" />
        )}
        <Kbd>D</Kbd>
      </Button>
    </div>
  )
}
