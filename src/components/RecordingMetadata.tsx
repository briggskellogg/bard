import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Switch } from '@/components/ui/switch'
import { cn } from '@/lib/utils'

interface RecordingMetadataProps {
  title: string
  onTitleChange: (title: string) => void
  hasConsent: boolean
  onConsentChange: (hasConsent: boolean) => void
  disabled?: boolean
  className?: string
}

export function RecordingMetadata({
  title,
  onTitleChange,
  hasConsent,
  onConsentChange,
  disabled = false,
  className,
}: RecordingMetadataProps) {
  return (
    <div className={cn('flex items-center gap-4', className)}>
      {/* Title Input */}
      <div className="flex-1">
        <Input
          value={title}
          onChange={(e) => onTitleChange(e.target.value)}
          placeholder="Recording title..."
          disabled={disabled}
          className="h-9 bg-transparent border-border/50 focus:border-primary/50"
        />
      </div>

      {/* Consent Toggle */}
      <div className="flex items-center gap-2 shrink-0">
        <Switch
          id="consent-toggle"
          checked={hasConsent}
          onCheckedChange={onConsentChange}
          disabled={disabled}
          className="data-[state=checked]:bg-emerald-500"
        />
        <Label 
          htmlFor="consent-toggle" 
          className={cn(
            'text-xs cursor-pointer select-none',
            hasConsent ? 'text-emerald-500' : 'text-muted-foreground'
          )}
        >
          Consent
        </Label>
      </div>
    </div>
  )
}

