import { useState, useEffect, useCallback } from 'react'
import { History, FileText, Search, X } from 'lucide-react'
import {
  Sheet,
  SheetContent,
  SheetHeader,
  SheetTitle,
  SheetTrigger,
} from '@/components/ui/sheet'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { useSettingsStore } from '@/store/settings'
import { useArchive } from '@/hooks/useArchive'
import { cn } from '@/lib/utils'
import { toast } from 'sonner'

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

function formatDate(timestamp: number): string {
  const date = new Date(timestamp)
  const day = date.getDate()
  const month = date.toLocaleDateString('en-US', { month: 'long' })
  const year = date.getFullYear()
  const time = date.toLocaleTimeString('en-US', { 
    hour: 'numeric', 
    minute: '2-digit',
    hour12: true 
  })
  return `${day} ${month} ${year}, ${time}`
}

function truncateText(text: string, maxLength: number = 150): string {
  if (text.length <= maxLength) return text
  return text.slice(0, maxLength).trim() + '...'
}

export function ArchiveDialog() {
  const { archiveDialogOpen, setArchiveDialogOpen } = useSettingsStore()
  const { archivedTranscripts, deleteTranscript } = useArchive()
  const [expandedId, setExpandedId] = useState<string | null>(null)
  const [selectedIndex, setSelectedIndex] = useState(0)
  const [searchQuery, setSearchQuery] = useState('')

  // Filter transcripts based on search
  const filteredTranscripts = archivedTranscripts.filter(t => {
    if (!searchQuery.trim()) return true
    const query = searchQuery.toLowerCase()
    return (
      t.text.toLowerCase().includes(query) ||
      (t.title && t.title.toLowerCase().includes(query))
    )
  })

  // Reset selection when dialog opens/closes or search changes
  useEffect(() => {
    if (archiveDialogOpen) {
      setSelectedIndex(0)
      setSearchQuery('')
    }
  }, [archiveDialogOpen])

  useEffect(() => {
    setSelectedIndex(0)
  }, [searchQuery])

  const copyTranscript = useCallback(async (text: string) => {
    try {
      await navigator.clipboard.writeText(text)
      toast.success('Copied to clipboard')
    } catch (error) {
      console.error('Failed to copy:', error)
      toast.error('Failed to copy')
    }
  }, [])

  const handleDelete = useCallback(async (id: string) => {
    try {
      await deleteTranscript(id)
      if (expandedId === id) {
        setExpandedId(null)
      }
      toast.success('Deleted')
    } catch (error) {
      console.error('Failed to delete:', error)
      toast.error('Failed to delete')
    }
  }, [deleteTranscript, expandedId])

  // Keyboard navigation inside dialog
  useEffect(() => {
    if (!archiveDialogOpen) return

    const handleKeyDown = (e: KeyboardEvent) => {
      // Allow typing in search
      if (e.target instanceof HTMLInputElement) {
        if (e.key === 'Escape') {
          e.preventDefault()
          if (searchQuery) {
            setSearchQuery('')
          } else {
            setArchiveDialogOpen(false)
          }
        }
        return
      }

      if (filteredTranscripts.length === 0) {
        if (e.key === 'Escape') {
          setArchiveDialogOpen(false)
        }
        return
      }

      switch (e.key) {
        case 'ArrowUp':
          e.preventDefault()
          setSelectedIndex(prev => Math.max(0, prev - 1))
          break
        case 'ArrowDown':
          e.preventDefault()
          setSelectedIndex(prev => Math.min(filteredTranscripts.length - 1, prev + 1))
          break
        case 'Enter':
          e.preventDefault()
          const selected = filteredTranscripts[selectedIndex]
          if (selected) {
            setExpandedId(expandedId === selected.id ? null : selected.id)
          }
          break
        case 'c':
          e.preventDefault()
          const toCopy = filteredTranscripts[selectedIndex]
          if (toCopy) {
            copyTranscript(toCopy.text)
          }
          break
        case 'd':
        case 'Backspace':
        case 'Delete':
          e.preventDefault()
          const toDelete = filteredTranscripts[selectedIndex]
          if (toDelete) {
            handleDelete(toDelete.id)
            if (selectedIndex >= filteredTranscripts.length - 1) {
              setSelectedIndex(Math.max(0, filteredTranscripts.length - 2))
            }
          }
          break
        case '/':
          e.preventDefault()
          const searchInput = document.getElementById('archive-search')
          searchInput?.focus()
          break
        case 'Escape':
          setArchiveDialogOpen(false)
          break
      }
    }

    window.addEventListener('keydown', handleKeyDown)
    return () => window.removeEventListener('keydown', handleKeyDown)
  }, [archiveDialogOpen, filteredTranscripts, selectedIndex, expandedId, copyTranscript, handleDelete, setArchiveDialogOpen, searchQuery])

  return (
    <Sheet open={archiveDialogOpen} onOpenChange={setArchiveDialogOpen}>
      <SheetTrigger asChild>
        <Button
          variant="ghost"
          size="sm"
          className="h-8 px-2 gap-1.5"
          aria-label="Archive"
        >
          <History className="h-4 w-4" />
          <Kbd>H</Kbd>
        </Button>
      </SheetTrigger>
      <SheetContent 
        side="bottom" 
        className="h-[75vh] rounded-t-2xl border-t-2 border-border shadow-2xl bg-background/95 backdrop-blur-sm"
      >
        <div className="h-full flex flex-col px-6 sm:px-10 max-w-4xl mx-auto pt-4">
          <SheetHeader className="pb-4">
            <SheetTitle className="flex items-center justify-center gap-3 text-xl">
              <History className="h-5 w-5" />
              Archive
            </SheetTitle>
          </SheetHeader>

          {/* Search bar */}
          <div className="relative mb-4">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
            <Input
              id="archive-search"
              type="text"
              placeholder="Search transcripts..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="pl-10 pr-10"
            />
            {searchQuery ? (
              <button
                onClick={() => setSearchQuery('')}
                className="absolute right-3 top-1/2 -translate-y-1/2 text-muted-foreground hover:text-foreground"
              >
                <X className="h-4 w-4" />
              </button>
            ) : (
              <span className="absolute right-3 top-1/2 -translate-y-1/2 text-muted-foreground/50 text-xs">
                <Kbd>/</Kbd>
              </span>
            )}
          </div>

          {/* Keyboard hints */}
          {filteredTranscripts.length > 0 && (
            <div className="flex items-center gap-6 pb-4 text-xs text-muted-foreground/70">
              <span className="flex items-center gap-2"><Kbd>↑</Kbd><Kbd>↓</Kbd> Navigate</span>
              <span className="flex items-center gap-2"><Kbd>Enter</Kbd> Expand</span>
              <span className="flex items-center gap-2"><Kbd>C</Kbd> Copy</span>
              <span className="flex items-center gap-2"><Kbd>D</Kbd> Delete</span>
            </div>
          )}

          <div className="flex-1 overflow-y-auto -mx-6 sm:-mx-10 px-6 sm:px-10">
            {filteredTranscripts.length === 0 ? (
              <div className="flex flex-col items-center justify-center py-20 text-center">
                <FileText className="h-20 w-20 text-muted-foreground/15 mb-6" />
                <p className="text-base text-muted-foreground">
                  {searchQuery ? 'No matching transcripts' : 'No archived transcriptions yet'}
                </p>
                <p className="text-sm text-muted-foreground/60 mt-2">
                  {searchQuery ? 'Try a different search term' : 'Press A to archive a transcription'}
                </p>
              </div>
            ) : (
              <div className="space-y-3 pb-8">
                {filteredTranscripts.map((transcript, index) => (
                  <div
                    key={transcript.id}
                    className={cn(
                      'rounded-xl border-2 bg-card p-5 transition-all cursor-pointer',
                      selectedIndex === index 
                        ? 'border-primary shadow-lg shadow-primary/10' 
                        : 'border-border/50 hover:border-border'
                    )}
                    onClick={() => {
                      setSelectedIndex(index)
                      setExpandedId(expandedId === transcript.id ? null : transcript.id)
                    }}
                  >
                    <div className="flex items-start justify-between gap-4">
                      <div className="flex-1 min-w-0">
                        {transcript.title && (
                          <h3 className="font-semibold text-sm mb-1 truncate">
                            {transcript.title}
                          </h3>
                        )}
                        <p className="text-xs text-muted-foreground mb-2">
                          {formatDate(transcript.createdAt)}
                          {transcript.hasConsent !== undefined && (
                            <span className={cn(
                              'ml-2 px-1.5 py-0.5 rounded text-[10px]',
                              transcript.hasConsent 
                                ? 'bg-green-500/20 text-green-500' 
                                : 'bg-amber-500/20 text-amber-500'
                            )}>
                              {transcript.hasConsent ? 'Consented' : 'No consent'}
                            </span>
                          )}
                        </p>
                        <p className="text-sm leading-relaxed text-foreground/80">
                          {expandedId === transcript.id
                            ? transcript.text
                            : truncateText(transcript.text)
                          }
                        </p>
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </div>
        </div>
      </SheetContent>
    </Sheet>
  )
}
