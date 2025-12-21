import { useState, useEffect, useCallback, useRef } from 'react'
import {
  BrandHistoryIcon,
  BrandSearchIcon,
  BrandCloseIcon,
  BrandCopyIcon,
  BrandTrashIcon,
  EmptyArchiveIcon,
  ShieldIcon,
} from '@/components/ui/brand-icons'
import { Download, ChevronLeft, ChevronRight, Star } from 'lucide-react'
import {
  Sheet,
  SheetContent,
  SheetHeader,
  SheetTitle,
  SheetTrigger,
} from '@/components/ui/sheet'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Switch } from '@/components/ui/switch'
import { useSettingsStore } from '@/store/settings'
import { useArchive } from '@/hooks/useArchive'
import { cn } from '@/lib/utils'
import { toast } from 'sonner'

// Auth expiration time (5 minutes)
const AUTH_EXPIRATION_MS = 5 * 60 * 1000

// Check if running in Tauri
function isTauri(): boolean {
  return typeof window !== 'undefined' && '__TAURI__' in window
}

// Biometric authentication helper using custom Tauri command
async function authenticateWithBiometric(): Promise<boolean> {
  if (!isTauri()) {
    console.log('[Biometric] Not in Tauri, skipping auth')
    return true // Allow access in dev mode
  }
  
  try {
    const { invoke } = await import('@tauri-apps/api/core')
    const result = await invoke<boolean>('authenticate_biometric', {
      reason: 'Bard requires authentication to access your saved memos.'
    })
    return result
  } catch (e) {
    console.error('[Biometric] Authentication failed:', e)
    return false
  }
}

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

function formatDate(timestamp: number): string {
  const date = new Date(timestamp)
  const day = date.getDate()
  const month = date.toLocaleDateString('en-US', { month: 'short' })
  const year = date.getFullYear()
  const time = date.toLocaleTimeString('en-US', { 
    hour: 'numeric', 
    minute: '2-digit',
    hour12: true 
  })
  return `${month} ${day}, ${year} · ${time}`
}

function truncateText(text: string, maxLength = 150): string {
  if (text.length <= maxLength) return text
  return text.slice(0, maxLength).trim() + '...'
}

const ITEMS_PER_PAGE = 8

export function ArchiveDialog() {
  const { archiveDialogOpen, setArchiveDialogOpen } = useSettingsStore()
  const { archivedTranscripts, deleteTranscript, updateTranscript, exportToCSV } = useArchive()
  const [expandedId, setExpandedId] = useState<string | null>(null)
  const [selectedIndex, setSelectedIndex] = useState(0)
  const [searchQuery, setSearchQuery] = useState('')
  const [editingTitleId, setEditingTitleId] = useState<string | null>(null)
  const [editingTitleValue, setEditingTitleValue] = useState('')
  const [currentPage, setCurrentPage] = useState(0)
  const [showImportantOnly, setShowImportantOnly] = useState(false)
  
  // Biometric auth state
  const [isAuthenticated, setIsAuthenticated] = useState(false)
  const [isAuthenticating, setIsAuthenticating] = useState(false)
  const authTimestampRef = useRef<number>(0)
  
  // Check if auth has expired
  const isAuthExpired = useCallback(() => {
    if (!isAuthenticated) return true
    return Date.now() - authTimestampRef.current > AUTH_EXPIRATION_MS
  }, [isAuthenticated])
  
  // Reset auth when page becomes hidden (screen lock, tab switch, etc.)
  useEffect(() => {
    const handleVisibilityChange = () => {
      if (document.hidden) {
        // Page is hidden - reset auth after a short delay (in case user is just alt-tabbing briefly)
        const timeout = setTimeout(() => {
          if (document.hidden) {
            console.log('[Vault] Page hidden, resetting authentication')
            setIsAuthenticated(false)
            authTimestampRef.current = 0
          }
        }, 3000) // 3 second grace period
        return () => clearTimeout(timeout)
      }
    }
    
    document.addEventListener('visibilitychange', handleVisibilityChange)
    return () => document.removeEventListener('visibilitychange', handleVisibilityChange)
  }, [])
  
  // Authenticate and open dialog
  const handleOpenVault = useCallback(async () => {
    // Check if already authenticated and not expired
    if (isAuthenticated && !isAuthExpired()) {
      setArchiveDialogOpen(true)
      return
    }
    
    setIsAuthenticating(true)
    
    try {
      const success = await authenticateWithBiometric()
      if (success) {
        setIsAuthenticated(true)
        authTimestampRef.current = Date.now()
        setArchiveDialogOpen(true)
      } else {
        toast.error('Authentication failed')
      }
    } catch (error) {
      console.error('[Vault] Auth error:', error)
      toast.error('Failed to authenticate')
    } finally {
      setIsAuthenticating(false)
    }
  }, [isAuthenticated, isAuthExpired, setArchiveDialogOpen])
  
  // Handle dialog open/close with auth check
  const handleDialogChange = useCallback((open: boolean) => {
    if (!open) {
      setArchiveDialogOpen(false)
    }
  }, [setArchiveDialogOpen])
  
  // Intercept programmatic opens (V hotkey) and require auth
  useEffect(() => {
    if (archiveDialogOpen && (!isAuthenticated || isAuthExpired()) && !isAuthenticating) {
      setArchiveDialogOpen(false)
      handleOpenVault()
    }
  }, [archiveDialogOpen, isAuthenticated, isAuthExpired, isAuthenticating, setArchiveDialogOpen, handleOpenVault])

  // Filter transcripts based on search and important
  const filteredTranscripts = archivedTranscripts.filter(t => {
    // Important filter
    if (showImportantOnly && !t.isImportant) return false
    
    // Search filter
    if (!searchQuery.trim()) return true
    const query = searchQuery.toLowerCase()
    return (
      t.text.toLowerCase().includes(query) ||
      (t.title && t.title.toLowerCase().includes(query)) ||
      (t.category && t.category.toLowerCase().includes(query))
    )
  })

  // Pagination
  const totalPages = Math.ceil(filteredTranscripts.length / ITEMS_PER_PAGE)
  const paginatedTranscripts = filteredTranscripts.slice(
    currentPage * ITEMS_PER_PAGE,
    (currentPage + 1) * ITEMS_PER_PAGE
  )

  // Reset selection and filters when dialog opens/closes
  useEffect(() => {
    if (archiveDialogOpen) {
      setSelectedIndex(0)
      setSearchQuery('')
      setCurrentPage(0)
      setShowImportantOnly(false)
    }
  }, [archiveDialogOpen])

  useEffect(() => {
    setSelectedIndex(0)
    setCurrentPage(0)
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


  const handleTitleEdit = useCallback((id: string, currentTitle: string) => {
    setEditingTitleId(id)
    setEditingTitleValue(currentTitle || '')
  }, [])

  const handleTitleSave = useCallback(async (id: string) => {
    try {
      await updateTranscript(id, { title: editingTitleValue.trim() || 'Untitled' })
      setEditingTitleId(null)
      setEditingTitleValue('')
    } catch (error) {
      console.error('Failed to update title:', error)
      toast.error('Failed to update title')
    }
  }, [updateTranscript, editingTitleValue])

  const handleTitleKeyDown = useCallback((e: React.KeyboardEvent, id: string) => {
    if (e.key === 'Enter') {
      e.preventDefault()
      handleTitleSave(id)
    } else if (e.key === 'Escape') {
      e.preventDefault()
      setEditingTitleId(null)
      setEditingTitleValue('')
    }
  }, [handleTitleSave])

  // Keyboard navigation inside dialog
  useEffect(() => {
    if (!archiveDialogOpen) return

    const handleKeyDown = (e: KeyboardEvent) => {
      // Allow typing in inputs
      if (e.target instanceof HTMLInputElement) {
        if (e.key === 'Escape') {
          e.preventDefault()
          if (editingTitleId) {
            setEditingTitleId(null)
            setEditingTitleValue('')
          } else if (searchQuery) {
            setSearchQuery('')
          } else {
            setArchiveDialogOpen(false)
          }
        }
        return
      }

      if (paginatedTranscripts.length === 0) {
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
          setSelectedIndex(prev => Math.min(paginatedTranscripts.length - 1, prev + 1))
          break
        case 'ArrowLeft':
          e.preventDefault()
          if (currentPage > 0) {
            setCurrentPage(prev => prev - 1)
            setSelectedIndex(0)
          }
          break
        case 'ArrowRight':
          e.preventDefault()
          if (currentPage < totalPages - 1) {
            setCurrentPage(prev => prev + 1)
            setSelectedIndex(0)
          }
          break
        case 'Enter':
          e.preventDefault()
          {
            const selected = paginatedTranscripts[selectedIndex]
            if (selected) {
              setExpandedId(expandedId === selected.id ? null : selected.id)
            }
          }
          break
        case 'c':
          e.preventDefault()
          {
            const toCopy = paginatedTranscripts[selectedIndex]
            if (toCopy) {
              copyTranscript(toCopy.text)
            }
          }
          break
        case 'd':
        case 'Backspace':
        case 'Delete':
          e.preventDefault()
          {
            const toDelete = paginatedTranscripts[selectedIndex]
            if (toDelete) {
              handleDelete(toDelete.id)
              if (selectedIndex >= paginatedTranscripts.length - 1) {
                setSelectedIndex(Math.max(0, paginatedTranscripts.length - 2))
              }
            }
          }
          break
        case '/':
          e.preventDefault()
          document.getElementById('archive-search')?.focus()
          break
        case 'Escape':
          setArchiveDialogOpen(false)
          break
      }
    }

    window.addEventListener('keydown', handleKeyDown)
    return () => window.removeEventListener('keydown', handleKeyDown)
  }, [archiveDialogOpen, paginatedTranscripts, selectedIndex, expandedId, copyTranscript, handleDelete, setArchiveDialogOpen, searchQuery, currentPage, totalPages, editingTitleId])

  return (
    <Sheet open={archiveDialogOpen} onOpenChange={handleDialogChange}>
      <SheetTrigger asChild>
        <Button
          variant="ghost"
          size="sm"
          className="h-[34px] px-2 gap-1 rounded-lg"
          aria-label="Vault"
          onClick={(e) => {
            e.preventDefault()
            handleOpenVault()
          }}
          disabled={isAuthenticating}
        >
          {isAuthenticating ? (
            <div className="h-5 w-5 animate-spin rounded-full border-2 border-current border-t-transparent" />
          ) : (
            <BrandHistoryIcon size={20} className="opacity-70" />
          )}
          <Kbd>V</Kbd>
        </Button>
      </SheetTrigger>
      <SheetContent 
        side="bottom" 
        className="h-[80vh] rounded-t-3xl border-t border-border/30 shadow-2xl bg-background/98 backdrop-blur-xl"
      >
        <div className="h-full flex flex-col px-[21px] sm:px-[34px] max-w-3xl mx-auto pt-[13px]">
          {/* Header */}
          <SheetHeader className="pb-[21px]">
            <div className="flex items-center justify-center gap-[13px]">
              <SheetTitle className="text-[21px] font-semibold tracking-tight font-display">
                Vault
              </SheetTitle>
              {archivedTranscripts.length > 0 && (
                <Button
                  variant="outline"
                  size="sm"
                  onClick={async () => {
                    try {
                      await exportToCSV()
                      toast.success(`Exported ${archivedTranscripts.length} transcripts`)
                    } catch (error) {
                      console.error('Export failed:', error)
                      toast.error('Failed to export')
                    }
                  }}
                  className="h-[28px] gap-2 px-3 text-[11px] font-medium rounded-lg border-[#00D4FF]/30 text-[#00D4FF] hover:bg-[#00D4FF]/10 hover:border-[#00D4FF]/50 transition-colors"
                  aria-label="Export all transcripts to CSV"
                >
                  <Download className="h-3 w-3" />
                  Export
                </Button>
              )}
            </div>
          </SheetHeader>

          {/* Search bar and filter row - full width */}
          <div className="flex items-center gap-3 mb-[21px]">
            {/* Search bar - takes remaining space */}
            <div className="relative flex-1 min-w-0">
              <div className="absolute left-[13px] top-1/2 -translate-y-1/2">
                <BrandSearchIcon size={18} className="opacity-40" />
              </div>
              <Input
                id="archive-search"
                type="text"
                placeholder="Search..."
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                className="pl-[42px] pr-[42px] w-full h-[42px] rounded-xl bg-muted/30 border-border/30 text-[14px] placeholder:text-muted-foreground/40"
              />
              {searchQuery && (
                <button
                  onClick={() => setSearchQuery('')}
                  className="absolute right-[13px] top-1/2 -translate-y-1/2 text-muted-foreground/40 hover:text-foreground transition-colors"
                >
                  <BrandCloseIcon size={16} />
                </button>
              )}
            </div>

            {/* Starred filter toggle - fixed width to prevent search bar resizing */}
            <div className="flex items-center justify-end gap-1.5 shrink-0 w-[60px]">
              <Switch
                id="starred-filter"
                checked={showImportantOnly}
                onCheckedChange={setShowImportantOnly}
                className="data-[state=checked]:bg-amber-500"
              />
              <Star className={cn(
                "h-4 w-4 transition-colors",
                showImportantOnly ? "fill-amber-400 text-amber-400" : "text-muted-foreground/30"
              )} />
            </div>
          </div>

          {/* Content */}
          <div className="flex-1 overflow-y-auto">
            {filteredTranscripts.length === 0 ? (
              <div className="flex flex-col items-center justify-center py-[89px] text-center">
                <EmptyArchiveIcon size={55} className="text-muted-foreground/15 mb-[21px]" />
                <p className="text-[13px] text-muted-foreground/30 tracking-wide">
                  {searchQuery ? 'No matches found' : 'Nothing here yet'}
                </p>
              </div>
            ) : (
              <div className="space-y-[13px] pb-[34px]">
                {paginatedTranscripts.map((transcript, index) => {
                  return (
                    <div
                      key={transcript.id}
                      className={cn(
                        'rounded-2xl border bg-card/50 p-[21px] transition-all duration-200 cursor-pointer',
                        selectedIndex === index 
                          ? 'border-primary/50 shadow-lg shadow-primary/5 bg-card' 
                          : 'border-border/30 hover:border-border/50 hover:bg-card/80',
                      )}
                      onClick={() => {
                        setSelectedIndex(index)
                        setExpandedId(expandedId === transcript.id ? null : transcript.id)
                      }}
                    >
                      {/* Header row - Title and Date */}
                      <div className="flex items-center gap-3 mb-[13px]">
                        {/* Editable Title */}
                        {editingTitleId === transcript.id ? (
                          <Input
                            value={editingTitleValue}
                            onChange={(e) => setEditingTitleValue(e.target.value)}
                            onKeyDown={(e) => handleTitleKeyDown(e, transcript.id)}
                            onBlur={() => handleTitleSave(transcript.id)}
                            onClick={(e) => e.stopPropagation()}
                            className="h-[28px] text-[14px] font-medium px-2 py-0 w-auto min-w-[100px] max-w-[200px] rounded-lg"
                            autoFocus
                          />
                        ) : (
                          <h3 
                            className="font-medium text-[14px] truncate cursor-text hover:bg-muted/30 px-2 py-1 -mx-2 rounded-lg transition-colors"
                            onClick={(e) => {
                              e.stopPropagation()
                              handleTitleEdit(transcript.id, transcript.title || '')
                            }}
                            title="Click to edit"
                          >
                            {transcript.title || 'Untitled'}
                          </h3>
                        )}
                        
                        {/* Date - right next to title */}
                        <span className="text-[11px] text-muted-foreground/40 tracking-wide shrink-0">
                          {formatDate(transcript.createdAt)}
                        </span>

                        {/* Spacer */}
                        <div className="flex-1" />

                        {/* Action buttons - Copy, Delete */}
                        <div className="flex items-center -mr-1 shrink-0">
                          {/* Copy button */}
                          <Button
                            variant="ghost"
                            size="sm"
                            className="h-[22px] px-0.5 gap-0 rounded-md"
                            onClick={(e) => {
                              e.stopPropagation()
                              copyTranscript(transcript.text)
                            }}
                            aria-label="Copy"
                          >
                            <BrandCopyIcon size={12} />
                            <Kbd>C</Kbd>
                          </Button>

                          {/* Delete button */}
                          <Button
                            variant="ghost"
                            size="sm"
                            className="h-[22px] px-0.5 gap-0 rounded-md hover:bg-destructive/10 hover:text-destructive"
                            onClick={(e) => {
                              e.stopPropagation()
                              handleDelete(transcript.id)
                            }}
                            aria-label="Delete"
                          >
                            <BrandTrashIcon size={12} />
                            <Kbd>D</Kbd>
                          </Button>
                        </div>
                      </div>
                      
                      {/* Transcript text with star in bottom right */}
                      <div className="relative">
                        <p className="text-[14px] leading-[1.7] text-foreground/70 pr-8">
                          {expandedId === transcript.id
                            ? transcript.text
                            : truncateText(transcript.text)
                          }
                        </p>
                        
                        {/* Star button - bottom right */}
                        <Button
                          variant="ghost"
                          size="sm"
                          className={cn(
                            "absolute bottom-0 right-0 h-[24px] w-[24px] p-0 rounded-md",
                            transcript.isImportant && "text-amber-400"
                          )}
                          onClick={(e) => {
                            e.stopPropagation()
                            updateTranscript(transcript.id, { isImportant: !transcript.isImportant })
                          }}
                          aria-label={transcript.isImportant ? "Unmark" : "Mark important"}
                        >
                          <Star 
                            className={cn(
                              "h-4 w-4",
                              transcript.isImportant && "fill-amber-400"
                            )} 
                          />
                        </Button>
                      </div>
                    </div>
                  )
                })}
              </div>
            )}
          </div>

          {/* Pagination */}
          {totalPages > 1 && (
            <div className="flex items-center justify-center gap-[21px] py-[13px] border-t border-border/20">
              <Button
                variant="ghost"
                size="sm"
                onClick={() => {
                  setCurrentPage(prev => prev - 1)
                  setSelectedIndex(0)
                }}
                disabled={currentPage === 0}
                className="h-[32px] px-2 gap-1 rounded-lg"
              >
                <ChevronLeft className="h-4 w-4" />
                <span className="text-[12px]">Prev</span>
              </Button>
              <span className="text-[12px] text-muted-foreground/60 tabular-nums">
                {currentPage + 1} / {totalPages}
              </span>
              <Button
                variant="ghost"
                size="sm"
                onClick={() => {
                  setCurrentPage(prev => prev + 1)
                  setSelectedIndex(0)
                }}
                disabled={currentPage === totalPages - 1}
                className="h-[32px] px-2 gap-1 rounded-lg"
              >
                <span className="text-[12px]">Next</span>
                <ChevronRight className="h-4 w-4" />
              </Button>
            </div>
          )}

          {/* Footer */}
          <div className="flex items-center justify-center gap-2 py-[13px] border-t border-border/20">
            <ShieldIcon size={13} className="text-[#00D4FF]/60" />
            <span className="text-[10px] text-muted-foreground/40 tracking-wide font-mono">
              All data processed and stored locally on your device
            </span>
          </div>
        </div>
      </SheetContent>
    </Sheet>
  )
}
