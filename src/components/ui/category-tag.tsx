/**
 * CategoryTag - Icon-based pill component for memo categories
 * Uses ElevenLabs brand palette colors with category-specific icons
 */

import { cn } from '@/lib/utils'
import {
  CategoryNoteIcon,
  CategoryMessageIcon,
  CategoryRantIcon,
  CategoryIdeaIcon,
  CategoryMeetingIcon,
  CategoryConversationIcon,
  CategoryTaskIcon,
  CategoryJournalIcon,
} from '@/components/ui/brand-icons'

// ElevenLabs brand color mapping for categories
const CATEGORY_COLORS: Record<string, { bg: string; text: string; border: string }> = {
  Note: {
    bg: 'bg-[#5D79DF]/15',
    text: 'text-[#5D79DF]',
    border: 'border-[#5D79DF]/30',
  },
  Message: {
    bg: 'bg-[#4EC7E0]/15',
    text: 'text-[#4EC7E0]',
    border: 'border-[#4EC7E0]/30',
  },
  Rant: {
    bg: 'bg-[#EB524B]/15',
    text: 'text-[#EB524B]',
    border: 'border-[#EB524B]/30',
  },
  Idea: {
    bg: 'bg-[#EFDE44]/15',
    text: 'text-[#EFDE44] dark:text-[#EFDE44]',
    border: 'border-[#EFDE44]/30',
  },
  Meeting: {
    bg: 'bg-[#C47DE5]/15',
    text: 'text-[#C47DE5]',
    border: 'border-[#C47DE5]/30',
  },
  Conversation: {
    bg: 'bg-[#37C8B5]/15',
    text: 'text-[#37C8B5]',
    border: 'border-[#37C8B5]/30',
  },
  Task: {
    bg: 'bg-[#2DD28D]/15',
    text: 'text-[#2DD28D]',
    border: 'border-[#2DD28D]/30',
  },
  Journal: {
    bg: 'bg-[#F59E0B]/15',
    text: 'text-[#F59E0B]',
    border: 'border-[#F59E0B]/30',
  },
}

// Category icon mapping
const CATEGORY_ICONS: Record<string, React.ComponentType<{ size?: number; className?: string }>> = {
  Note: CategoryNoteIcon,
  Message: CategoryMessageIcon,
  Rant: CategoryRantIcon,
  Idea: CategoryIdeaIcon,
  Meeting: CategoryMeetingIcon,
  Conversation: CategoryConversationIcon,
  Task: CategoryTaskIcon,
  Journal: CategoryJournalIcon,
}

// Helper to get category icon component
export function getCategoryIcon(category: string): React.ComponentType<{ size?: number; className?: string }> {
  return CATEGORY_ICONS[category] || CategoryNoteIcon
}

// Helper to get category colors
export function getCategoryColors(category: string): { bg: string; text: string; border: string } {
  return CATEGORY_COLORS[category] || DEFAULT_COLOR
}

// Default/fallback for custom categories
const DEFAULT_COLOR = {
  bg: 'bg-[#37C8B5]/15',
  text: 'text-[#37C8B5]',
  border: 'border-[#37C8B5]/30',
}

interface CategoryTagProps {
  category: string
  size?: 'sm' | 'md' | 'lg'
  onClick?: () => void
  selected?: boolean
  className?: string
  showLabel?: boolean // Show text label alongside icon (useful for selectors)
}

export function CategoryTag({
  category,
  size = 'md',
  onClick,
  selected = false,
  className,
  showLabel = false,
}: CategoryTagProps) {
  const colors = CATEGORY_COLORS[category] || DEFAULT_COLOR
  const IconComponent = CATEGORY_ICONS[category] || CategoryNoteIcon

  const sizeClasses = {
    sm: 'p-1',
    md: 'p-1.5',
    lg: 'p-2',
  }
  
  const iconSizes = {
    sm: 12,
    md: 14,
    lg: 16,
  }

  return (
    <span
      onClick={onClick}
      title={category}
      className={cn(
        'inline-flex items-center justify-center rounded-full border transition-all duration-200',
        colors.bg,
        colors.text,
        colors.border,
        sizeClasses[size],
        showLabel && 'px-2 gap-1',
        onClick && 'cursor-pointer hover:scale-110 hover:shadow-sm active:scale-100',
        selected && 'ring-2 ring-offset-1 ring-offset-background ring-current shadow-md',
        className
      )}
    >
      <IconComponent size={iconSizes[size]} />
      {showLabel && (
        <span className="text-[10px] font-semibold uppercase tracking-wide">{category}</span>
      )}
    </span>
  )
}

// Urgency indicator - clock icon for time sensitivity
interface UrgencyIndicatorProps {
  level: number // 0-5
  size?: 'sm' | 'md'
  className?: string
}

export function UrgencyIndicator({ level, size = 'md', className }: UrgencyIndicatorProps) {
  if (level === 0) return null

  const sizeClasses = {
    sm: 'h-3.5 w-3.5',
    md: 'h-4.5 w-4.5',
  }

  // Color intensity based on urgency level
  const colorClasses: Record<number, string> = {
    1: 'text-[#F58633]/50',
    2: 'text-[#F58633]/70',
    3: 'text-[#EB524B]/80',
    4: 'text-[#EB524B]',
    5: 'text-[#EB524B]',
  }

  const label = level >= 4 ? 'Urgent' : level >= 2 ? 'Time-sensitive' : 'Low priority'

  return (
    <div 
      className={cn('flex items-center gap-1', className)}
      title={`${label} (${level}/5)`}
    >
      <svg
        className={cn(
          sizeClasses[size],
          colorClasses[level],
          level >= 4 && 'animate-pulse'
        )}
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        strokeWidth="2"
        strokeLinecap="round"
        strokeLinejoin="round"
      >
        {/* Clock icon */}
        <circle cx="12" cy="12" r="10" />
        <polyline points="12 6 12 12 16 14" />
      </svg>
      {level >= 3 && (
        <span className={cn(
          'text-[9px] font-semibold uppercase tracking-wide',
          colorClasses[level]
        )}>
          {level >= 4 ? '!' : ''}
        </span>
      )}
    </div>
  )
}

// Novelty indicator - lightbulb icon for genuinely novel ideas
interface NoveltyIndicatorProps {
  level: number // 0-5
  size?: 'sm' | 'md'
  className?: string
}

export function NoveltyIndicator({ level, size = 'md', className }: NoveltyIndicatorProps) {
  if (level === 0) return null

  const sizeClasses = {
    sm: 'h-3.5 w-3.5',
    md: 'h-4.5 w-4.5',
  }

  // Color intensity based on novelty level
  const colorClasses: Record<number, string> = {
    1: 'text-[#EFDE44]/50',
    2: 'text-[#EFDE44]/70',
    3: 'text-[#EFDE44]/90',
    4: 'text-[#EFDE44]',
    5: 'text-[#EFDE44]',
  }

  const label = level >= 4 ? 'Genuinely novel' : level >= 2 ? 'Interesting' : 'Standard'

  return (
    <div 
      className={cn('flex items-center gap-1', className)}
      title={`${label} (${level}/5)`}
    >
      <svg
        className={cn(
          sizeClasses[size],
          colorClasses[level],
          level >= 4 && 'fill-current'
        )}
        viewBox="0 0 24 24"
        fill={level >= 4 ? 'currentColor' : 'none'}
        stroke="currentColor"
        strokeWidth="2"
        strokeLinecap="round"
        strokeLinejoin="round"
      >
        {/* Lightbulb icon */}
        <path d="M9 18h6" />
        <path d="M10 22h4" />
        <path d="M15.09 14c.18-.98.65-1.74 1.41-2.5A4.65 4.65 0 0 0 18 8 6 6 0 0 0 6 8c0 1 .23 2.23 1.5 3.5A4.61 4.61 0 0 1 8.91 14" />
      </svg>
      {level >= 4 && (
        <span className={cn(
          'text-[9px] font-semibold uppercase tracking-wide',
          colorClasses[level]
        )}>
          ✦
        </span>
      )}
    </div>
  )
}

// Category selector grid
interface CategorySelectorProps {
  value: string
  onChange: (category: string) => void
  categories?: string[]
  className?: string
}

export function CategorySelector({
  value,
  onChange,
  categories = ['Note', 'Message', 'Rant', 'Idea', 'Meeting', 'Conversation', 'Task', 'Journal'],
  className,
}: CategorySelectorProps) {
  return (
    <div className={cn('flex flex-wrap gap-1.5', className)}>
      {categories.map((category) => (
        <CategoryTag
          key={category}
          category={category}
          size="sm"
          selected={value === category}
          onClick={() => onChange(category)}
          showLabel={value === category} // Only show label for selected category
        />
      ))}
    </div>
  )
}

export { CATEGORY_COLORS, DEFAULT_COLOR }

