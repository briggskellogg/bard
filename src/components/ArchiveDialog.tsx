import { useState, useEffect, useCallback } from 'react'
import { FolderOpen, Search, X, Copy, Check, Trash2, Inbox, ShieldCheck, Download, ChevronLeft, ChevronRight, Star, CircleSlash } from 'lucide-react'
import {
  Dialog,
  DialogClose,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from '@/components/ui/dialog'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Switch } from '@/components/ui/switch'
import { useSettingsStore } from '@/store/settings'
import { useArchive } from '@/hooks/useArchive'
import { cn } from '@/lib/utils'
import { toast } from 'sonner'

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
  const [pendingDeleteId, setPendingDeleteId] = useState<string | null>(null)
  const [copiedId, setCopiedId] = useState<string | null>(null)
  
  // Open library directly (no auth required)
  const handleOpenLibrary = useCallback(() => {
    setArchiveDialogOpen(true)
  }, [setArchiveDialogOpen])
  
  // Handle dialog open/close
  const handleDialogChange = useCallback((open: boolean) => {
    if (!open) {
      setArchiveDialogOpen(false)
    }
  }, [setArchiveDialogOpen])

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
      setPendingDeleteId(null)
      setSearchQuery('')
      setCurrentPage(0)
      setShowImportantOnly(false)
    }
  }, [archiveDialogOpen])

  useEffect(() => {
    setSelectedIndex(0)
    setCurrentPage(0)
    setPendingDeleteId(null)
  }, [searchQuery])

  const copyTranscript = useCallback(async (text: string, id?: string) => {
    try {
      await navigator.clipboard.writeText(text)
      if (id) {
        setCopiedId(id)
        setTimeout(() => setCopiedId(null), 2000)
      }
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
          setPendingDeleteId(null)
          break
        case 'ArrowDown':
          e.preventDefault()
          setSelectedIndex(prev => Math.min(paginatedTranscripts.length - 1, prev + 1))
          setPendingDeleteId(null)
          break
        case 'ArrowLeft':
          e.preventDefault()
          if (currentPage > 0) {
            setCurrentPage(prev => prev - 1)
            setSelectedIndex(0)
            setPendingDeleteId(null)
          }
          break
        case 'ArrowRight':
          e.preventDefault()
          if (currentPage < totalPages - 1) {
            setCurrentPage(prev => prev + 1)
            setSelectedIndex(0)
            setPendingDeleteId(null)
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
        case 'C':
          // If pending delete, just 'c' cancels (no Command needed)
          if (pendingDeleteId) {
            e.preventDefault()
            setPendingDeleteId(null)
          } else if (e.metaKey || e.ctrlKey) {
            // Otherwise Command+C copies
            e.preventDefault()
            const toCopy = paginatedTranscripts[selectedIndex]
            if (toCopy) {
              copyTranscript(toCopy.text, toCopy.id)
            }
          }
          break
        case 'd':
        case 'D':
          // If pending delete, just 'd' confirms (no Command needed)
          if (pendingDeleteId) {
            e.preventDefault()
            handleDelete(pendingDeleteId)
            const deleteIndex = paginatedTranscripts.findIndex(t => t.id === pendingDeleteId)
            if (deleteIndex >= paginatedTranscripts.length - 1) {
              setSelectedIndex(Math.max(0, paginatedTranscripts.length - 2))
            }
            setPendingDeleteId(null)
          } else if (e.metaKey || e.ctrlKey) {
            // Otherwise Command+D initiates delete
            e.preventDefault()
            const toDelete = paginatedTranscripts[selectedIndex]
            if (toDelete) {
              setPendingDeleteId(toDelete.id)
            }
          }
          break
        case '/':
          e.preventDefault()
          document.getElementById('archive-search')?.focus()
          break
        case 'Escape':
          // If pending delete, cancel it; otherwise close dialog
          if (pendingDeleteId) {
            e.preventDefault()
            setPendingDeleteId(null)
          } else {
            setArchiveDialogOpen(false)
          }
          break
      }
    }

    window.addEventListener('keydown', handleKeyDown)
    return () => window.removeEventListener('keydown', handleKeyDown)
  }, [archiveDialogOpen, paginatedTranscripts, selectedIndex, expandedId, copyTranscript, handleDelete, setArchiveDialogOpen, searchQuery, currentPage, totalPages, editingTitleId, pendingDeleteId])

  return (
    <Dialog open={archiveDialogOpen} onOpenChange={handleDialogChange}>
      <DialogTrigger asChild>
        <Button
          variant="ghost"
          size="sm"
          className="h-[34px] px-1.5 gap-0.5 rounded-lg"
          aria-label="Library"
          onClick={(e) => {
            e.preventDefault()
            handleOpenLibrary()
          }}
        >
          <FolderOpen size={20} className="opacity-70" />
          <Kbd className="gap-0.5"><span className="text-[10px]">⌘</span><span className="text-[10px]">V</span></Kbd>
        </Button>
      </DialogTrigger>
      <DialogContent 
        className="max-w-2xl w-[90vw] h-[80vh] rounded-2xl border border-[#EAB308]/20 shadow-2xl bg-background p-0"
        showCloseButton={false}
      >
        <div className="h-full flex flex-col overflow-hidden px-[21px] sm:px-[34px] pt-[21px]">
          {/* Header */}
          <DialogHeader className="pb-[21px]">
            <div className="flex items-center justify-between">
              <DialogTitle className="text-[21px] font-semibold tracking-tight font-display">
                Library
              </DialogTitle>
              <div className="flex items-center gap-2">
                {archivedTranscripts.length > 0 && (
                  <Button
                    variant="ghost"
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
                    className="h-[24px] w-[24px] p-0 text-muted-foreground/40 hover:text-foreground hover:bg-muted/50 transition-colors"
                    aria-label="Export all transcripts to CSV"
                  >
                    <Download className="h-3.5 w-3.5" />
                  </Button>
                )}
                <DialogClose asChild>
                  <button
                    className="h-[24px] px-2 flex items-center justify-center rounded bg-muted/40 border border-border/30 text-[10px] font-medium text-muted-foreground/60 hover:text-foreground hover:bg-muted/60 transition-colors"
                    aria-label="Close"
                  >
                    ESC
                  </button>
                </DialogClose>
              </div>
            </div>
          </DialogHeader>

          {/* Search bar and filter row - full width */}
          <div className="flex items-center gap-3 mb-[21px]">
            {/* Search bar - takes remaining space */}
            <div className="relative flex-1 min-w-0">
              <div className="absolute left-[13px] top-1/2 -translate-y-1/2">
                <Search size={18} className="opacity-40" />
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
                  <X size={16} />
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
                <Inbox size={55} className="text-muted-foreground/15 mb-[21px]" />
                <p className="text-[13px] text-muted-foreground/30 tracking-wide">
                  {searchQuery ? 'No matches found' : 'Nothing here yet'}
                </p>
              </div>
            ) : (
              <div className="space-y-[13px] pb-[34px]">
                {paginatedTranscripts.map((transcript, index) => {
                  const isPendingDelete = pendingDeleteId === transcript.id
                  return (
                    <div
                      key={transcript.id}
                      className={cn(
                        'relative rounded-2xl border bg-card/50 p-[21px] transition-all duration-200 cursor-pointer',
                        isPendingDelete
                          ? 'border-destructive/50 bg-destructive/5'
                          : selectedIndex === index 
                            ? 'border-primary/50 shadow-lg shadow-primary/5 bg-card' 
                            : 'border-border/30 hover:border-border/50 hover:bg-card/80',
                      )}
                      onClick={() => {
                        if (isPendingDelete) return
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

                        {/* Action buttons - Copy/Delete or Cancel/Confirm when deleting */}
                        <div className="flex items-center -mr-1 shrink-0 gap-1">
                          {isPendingDelete ? (
                            <>
{/* Cancel delete */}
                              <button
                                className="h-[22px] px-1.5 text-muted-foreground/70 hover:text-foreground transition-colors flex items-center gap-1"
                                onClick={(e) => {
                                  e.stopPropagation()
                                  setPendingDeleteId(null)
                                }}
                              >
                                <CircleSlash size={12} />
                                <Kbd><span className="text-[9px]">C</span></Kbd>
                              </button>
                              {/* Confirm delete */}
                              <button
                                className="h-[22px] px-2 text-[11px] rounded-full bg-destructive text-white hover:bg-destructive/90 transition-colors flex items-center gap-1"
                                onClick={(e) => {
                                  e.stopPropagation()
                                  handleDelete(transcript.id)
                                  setPendingDeleteId(null)
                                }}
                              >
                                <Trash2 size={12} />
                                <span className="text-[9px] opacity-70">D</span>
                              </button>
                            </>
                          ) : (
                            <>
                              {/* Copy button */}
                              <Button
                                variant="ghost"
                                size="sm"
                                className={cn(
                                  "h-[22px] px-1.5 gap-1 rounded-md",
                                  copiedId === transcript.id && "text-green-500"
                                )}
                                onClick={(e) => {
                                  e.stopPropagation()
                                  copyTranscript(transcript.text, transcript.id)
                                }}
                                aria-label="Copy"
                              >
                                {copiedId === transcript.id ? <Check size={12} /> : <Copy size={12} />}
                                <Kbd><span className="text-[10px]">C</span></Kbd>
                              </Button>

                              {/* Delete button */}
                              <Button
                                variant="ghost"
                                size="sm"
                                className="h-[22px] px-1.5 gap-1 rounded-md hover:bg-destructive/10 hover:text-destructive"
                                onClick={(e) => {
                                  e.stopPropagation()
                                  setPendingDeleteId(transcript.id)
                                }}
                                aria-label="Delete"
                              >
                                <Trash2 size={12} />
                                <Kbd><span className="text-[10px]">D</span></Kbd>
                              </Button>
                            </>
                          )}
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
                  setPendingDeleteId(null)
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
                  setPendingDeleteId(null)
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
            <ShieldCheck size={13} className="text-[#00D4FF]/60" />
            <span className="text-[10px] text-muted-foreground/40 tracking-wide font-mono">
              Your data stays on your device and is never used to train models
            </span>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  )
}
