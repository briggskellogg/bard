/**
 * Bard Brand Icons
 * Based on Icons_Black_Transparent_BG.svg and Icons_White_Transparent_BG.svg
 * Monochrome stroke icons that adapt to light/dark mode via currentColor
 */

import { cn } from '@/lib/utils'

interface BrandIconProps {
  size?: number
  className?: string
}

// Microphone icon - for recording and device selection
export function BrandMicIcon({ size = 24, className }: BrandIconProps) {
  return (
    <svg 
      width={size} 
      height={size} 
      viewBox="0 0 48 48" 
      fill="none" 
      xmlns="http://www.w3.org/2000/svg"
      className={cn('shrink-0', className)}
    >
      <path 
        d="M24 7V28M24 28C20.134 28 17 24.866 17 21V14C17 10.134 20.134 7 24 7C27.866 7 31 10.134 31 14V21C31 24.866 27.866 28 24 28ZM13 21V23C13 29.075 17.925 34 24 34C30.075 34 35 29.075 35 23V21M24 34V40M18 40H30" 
        stroke="currentColor" 
        strokeWidth="3" 
        strokeLinecap="round" 
        strokeLinejoin="round"
      />
    </svg>
  )
}

// Play icon - for resume (circle with filled triangle)
export function BrandPlayIcon({ size = 24, className }: BrandIconProps) {
  return (
    <svg 
      width={size} 
      height={size} 
      viewBox="0 0 48 48" 
      fill="none" 
      xmlns="http://www.w3.org/2000/svg"
      className={cn('shrink-0', className)}
    >
      <path 
        d="M20 31V17C20 16.33 20.74 15.92 21.32 16.26L32.26 22.74C32.8 23.06 32.8 23.94 32.26 24.26L21.32 30.74C20.74 31.08 20 30.67 20 30Z" 
        fill="currentColor"
      />
      <circle cx="24" cy="24" r="15" stroke="currentColor" strokeWidth="3" />
    </svg>
  )
}

// Pause icon - for pause recording
export function BrandPauseIcon({ size = 24, className }: BrandIconProps) {
  return (
    <svg 
      width={size} 
      height={size} 
      viewBox="0 0 48 48" 
      fill="none" 
      xmlns="http://www.w3.org/2000/svg"
      className={cn('shrink-0', className)}
    >
      <circle cx="24" cy="24" r="15" stroke="currentColor" strokeWidth="3" />
      <rect x="18" y="17" width="3.5" height="14" rx="1" fill="currentColor" />
      <rect x="26.5" y="17" width="3.5" height="14" rx="1" fill="currentColor" />
    </svg>
  )
}

// Archive icon - box with line
export function BrandArchiveIcon({ size = 24, className }: BrandIconProps) {
  return (
    <svg 
      width={size} 
      height={size} 
      viewBox="0 0 48 48" 
      fill="none" 
      xmlns="http://www.w3.org/2000/svg"
      className={cn('shrink-0', className)}
    >
      <path 
        d="M8 12H40V18H8V12Z" 
        stroke="currentColor" 
        strokeWidth="3" 
        strokeLinejoin="round"
      />
      <path 
        d="M10 18V36C10 37.1 10.9 38 12 38H36C37.1 38 38 37.1 38 36V18" 
        stroke="currentColor" 
        strokeWidth="3" 
        strokeLinecap="round" 
        strokeLinejoin="round"
      />
      <path d="M19 26H29" stroke="currentColor" strokeWidth="3" strokeLinecap="round" />
    </svg>
  )
}

// Copy/Clipboard icon
export function BrandCopyIcon({ size = 24, className }: BrandIconProps) {
  return (
    <svg 
      width={size} 
      height={size} 
      viewBox="0 0 48 48" 
      fill="none" 
      xmlns="http://www.w3.org/2000/svg"
      className={cn('shrink-0', className)}
    >
      <rect x="17" y="17" width="22" height="22" rx="3" stroke="currentColor" strokeWidth="3" />
      <path 
        d="M13 31H11C9.9 31 9 30.1 9 29V11C9 9.9 9.9 9 11 9H29C30.1 9 31 9.9 31 11V13" 
        stroke="currentColor" 
        strokeWidth="3" 
        strokeLinecap="round" 
        strokeLinejoin="round"
      />
    </svg>
  )
}

// Trash icon - for delete/clear
export function BrandTrashIcon({ size = 24, className }: BrandIconProps) {
  return (
    <svg 
      width={size} 
      height={size} 
      viewBox="0 0 48 48" 
      fill="none" 
      xmlns="http://www.w3.org/2000/svg"
      className={cn('shrink-0', className)}
    >
      <path d="M10 14H38" stroke="currentColor" strokeWidth="3" strokeLinecap="round" />
      <path 
        d="M17 14V11C17 9.9 17.9 9 19 9H29C30.1 9 31 9.9 31 11V14" 
        stroke="currentColor" 
        strokeWidth="3" 
        strokeLinecap="round" 
        strokeLinejoin="round"
      />
      <path 
        d="M13 14V38C13 39.1 13.9 40 15 40H33C34.1 40 35 39.1 35 38V14" 
        stroke="currentColor" 
        strokeWidth="3" 
        strokeLinecap="round" 
        strokeLinejoin="round"
      />
      <path d="M19 22V32" stroke="currentColor" strokeWidth="3" strokeLinecap="round" />
      <path d="M29 22V32" stroke="currentColor" strokeWidth="3" strokeLinecap="round" />
    </svg>
  )
}

// Check icon - for success
export function BrandCheckIcon({ size = 24, className }: BrandIconProps) {
  return (
    <svg 
      width={size} 
      height={size} 
      viewBox="0 0 48 48" 
      fill="none" 
      xmlns="http://www.w3.org/2000/svg"
      className={cn('shrink-0', className)}
    >
      <path 
        d="M10 24L19 33L38 14" 
        stroke="currentColor" 
        strokeWidth="4" 
        strokeLinecap="round" 
        strokeLinejoin="round"
      />
    </svg>
  )
}

// Folder/archive icon - for vault access
export function BrandHistoryIcon({ size = 24, className }: BrandIconProps) {
  return (
    <svg 
      width={size} 
      height={size} 
      viewBox="0 0 24 24" 
      fill="none" 
      xmlns="http://www.w3.org/2000/svg"
      className={cn('shrink-0', className)}
    >
      {/* Folder shape */}
      <path 
        d="M3 6C3 4.89543 3.89543 4 5 4H9L11 6H19C20.1046 6 21 6.89543 21 8V18C21 19.1046 20.1046 20 19 20H5C3.89543 20 3 19.1046 3 18V6Z" 
        stroke="currentColor" 
        strokeWidth="2" 
        strokeLinecap="round" 
        strokeLinejoin="round"
      />
      {/* Horizontal lines inside */}
      <path d="M8 12H16" stroke="currentColor" strokeWidth="2" strokeLinecap="round" />
      <path d="M8 16H13" stroke="currentColor" strokeWidth="2" strokeLinecap="round" />
    </svg>
  )
}

// Search icon
export function BrandSearchIcon({ size = 24, className }: BrandIconProps) {
  return (
    <svg 
      width={size} 
      height={size} 
      viewBox="0 0 48 48" 
      fill="none" 
      xmlns="http://www.w3.org/2000/svg"
      className={cn('shrink-0', className)}
    >
      <circle cx="21" cy="21" r="12" stroke="currentColor" strokeWidth="3" />
      <path d="M30 30L40 40" stroke="currentColor" strokeWidth="3" strokeLinecap="round" />
    </svg>
  )
}

// X/Close icon
export function BrandCloseIcon({ size = 24, className }: BrandIconProps) {
  return (
    <svg 
      width={size} 
      height={size} 
      viewBox="0 0 48 48" 
      fill="none" 
      xmlns="http://www.w3.org/2000/svg"
      className={cn('shrink-0', className)}
    >
      <path d="M12 12L36 36M36 12L12 36" stroke="currentColor" strokeWidth="3" strokeLinecap="round" />
    </svg>
  )
}

// Languages/Translate icon (文A style)
export function BrandLanguagesIcon({ size = 24, className }: BrandIconProps) {
  return (
    <svg 
      width={size} 
      height={size} 
      viewBox="0 0 48 48" 
      fill="none" 
      xmlns="http://www.w3.org/2000/svg"
      className={cn('shrink-0', className)}
    >
      {/* Chinese character 文 */}
      <path 
        d="M6 10H22M14 10V12M10 18C10 18 12 24 14 26C16 28 20 32 20 32M18 18C18 18 16 24 14 26C12 28 8 32 8 32" 
        stroke="currentColor" 
        strokeWidth="2.5" 
        strokeLinecap="round" 
        strokeLinejoin="round"
      />
      {/* Letter A */}
      <path 
        d="M32 38L38 22L44 38M34 34H42" 
        stroke="currentColor" 
        strokeWidth="2.5" 
        strokeLinecap="round" 
        strokeLinejoin="round"
      />
    </svg>
  )
}

// Sun icon - for light theme
export function BrandSunIcon({ size = 24, className }: BrandIconProps) {
  return (
    <svg 
      width={size} 
      height={size} 
      viewBox="0 0 48 48" 
      fill="none" 
      xmlns="http://www.w3.org/2000/svg"
      className={cn('shrink-0', className)}
    >
      <circle cx="24" cy="24" r="8" stroke="currentColor" strokeWidth="3" />
      <path d="M24 6V10" stroke="currentColor" strokeWidth="3" strokeLinecap="round" />
      <path d="M24 38V42" stroke="currentColor" strokeWidth="3" strokeLinecap="round" />
      <path d="M6 24H10" stroke="currentColor" strokeWidth="3" strokeLinecap="round" />
      <path d="M38 24H42" stroke="currentColor" strokeWidth="3" strokeLinecap="round" />
      <path d="M11.5 11.5L14.3 14.3" stroke="currentColor" strokeWidth="3" strokeLinecap="round" />
      <path d="M33.7 33.7L36.5 36.5" stroke="currentColor" strokeWidth="3" strokeLinecap="round" />
      <path d="M11.5 36.5L14.3 33.7" stroke="currentColor" strokeWidth="3" strokeLinecap="round" />
      <path d="M33.7 14.3L36.5 11.5" stroke="currentColor" strokeWidth="3" strokeLinecap="round" />
    </svg>
  )
}

// Moon icon - for dark theme
export function BrandMoonIcon({ size = 24, className }: BrandIconProps) {
  return (
    <svg 
      width={size} 
      height={size} 
      viewBox="0 0 48 48" 
      fill="none" 
      xmlns="http://www.w3.org/2000/svg"
      className={cn('shrink-0', className)}
    >
      <path 
        d="M38 28C35 30 31 31 27 31C16.5 31 8 22.5 8 12C8 10 8.3 8 9 6C5 10 2 16 2 23C2 34 11 43 22 43C31 43 39 37 42 29C40.5 28.7 39.25 28.3 38 28Z" 
        stroke="currentColor" 
        strokeWidth="3" 
        strokeLinecap="round" 
        strokeLinejoin="round"
      />
    </svg>
  )
}

// Loader/Spinner icon
export function BrandLoaderIcon({ size = 24, className }: BrandIconProps) {
  return (
    <svg 
      width={size} 
      height={size} 
      viewBox="0 0 48 48" 
      fill="none" 
      xmlns="http://www.w3.org/2000/svg"
      className={cn('shrink-0', className)}
    >
      <path d="M24 8V14" stroke="currentColor" strokeWidth="3" strokeLinecap="round" />
      <path d="M24 34V40" stroke="currentColor" strokeWidth="3" strokeLinecap="round" opacity="0.3" />
      <path d="M12.7 12.7L16.9 16.9" stroke="currentColor" strokeWidth="3" strokeLinecap="round" opacity="0.9" />
      <path d="M31.1 31.1L35.3 35.3" stroke="currentColor" strokeWidth="3" strokeLinecap="round" opacity="0.2" />
      <path d="M8 24H14" stroke="currentColor" strokeWidth="3" strokeLinecap="round" opacity="0.7" />
      <path d="M34 24H40" stroke="currentColor" strokeWidth="3" strokeLinecap="round" opacity="0.4" />
      <path d="M12.7 35.3L16.9 31.1" stroke="currentColor" strokeWidth="3" strokeLinecap="round" opacity="0.5" />
      <path d="M31.1 16.9L35.3 12.7" stroke="currentColor" strokeWidth="3" strokeLinecap="round" opacity="0.6" />
    </svg>
  )
}

// Settings/Gear icon
export function BrandSettingsIcon({ size = 24, className }: BrandIconProps) {
  return (
    <svg 
      width={size} 
      height={size} 
      viewBox="0 0 48 48" 
      fill="none" 
      xmlns="http://www.w3.org/2000/svg"
      className={cn('shrink-0', className)}
    >
      <circle cx="24" cy="24" r="6" stroke="currentColor" strokeWidth="3" />
      <path 
        d="M21 9L21.6 13.4C20.2 14 18.9 14.8 17.8 15.8L13.8 14.6L10.8 19.4L13.8 22.2C13.6 22.8 13.5 23.4 13.5 24C13.5 24.6 13.6 25.2 13.8 25.8L10.8 28.6L13.8 33.4L17.8 32.2C18.9 33.2 20.2 34 21.6 34.6L21 39H27L27.6 34.6C29 34 30.3 33.2 31.4 32.2L35.4 33.4L38.4 28.6L35.4 25.8C35.6 25.2 35.7 24.6 35.7 24C35.7 23.4 35.6 22.8 35.4 22.2L38.4 19.4L35.4 14.6L31.4 15.8C30.3 14.8 29 14 27.6 13.4L27 9H21Z" 
        stroke="currentColor" 
        strokeWidth="3" 
        strokeLinecap="round" 
        strokeLinejoin="round"
      />
    </svg>
  )
}

// Recording icon - for Start Recording button (circle with play)
export function BrandRecordIcon({ size = 24, className }: BrandIconProps) {
  return (
    <svg 
      width={size} 
      height={size} 
      viewBox="0 0 60 60" 
      fill="none" 
      xmlns="http://www.w3.org/2000/svg"
      className={cn('shrink-0', className)}
    >
      {/* Play triangle */}
      <path d="M25 37.0098V22.9902C25 21.9859 26.1244 21.3916 26.9542 21.9574L37.2353 28.9672C37.963 29.4634 37.963 30.5366 37.2353 31.0328L26.9542 38.0426C26.1244 38.6084 25 38.0141 25 37.0098Z" fill="currentColor"/>
      {/* Circle outline */}
      <path fillRule="evenodd" clipRule="evenodd" d="M30 10C18.9543 10 10 18.9543 10 30C10 41.0457 18.9543 50 30 50C41.0457 50 50 41.0457 50 30C50 18.9543 41.0457 10 30 10ZM5 30C5 16.1929 16.1929 5 30 5C43.8071 5 55 16.1929 55 30C55 43.8071 43.8071 55 30 55C16.1929 55 5 43.8071 5 30Z" fill="currentColor"/>
    </svg>
  )
}

// Stop icon - for Stop Recording
export function BrandStopIcon({ size = 24, className }: BrandIconProps) {
  return (
    <svg 
      width={size} 
      height={size} 
      viewBox="0 0 48 48" 
      fill="none" 
      xmlns="http://www.w3.org/2000/svg"
      className={cn('shrink-0', className)}
    >
      <circle cx="24" cy="24" r="15" stroke="currentColor" strokeWidth="3" />
      <rect x="17" y="17" width="14" height="14" rx="2" fill="currentColor" />
    </svg>
  )
}

// Empty transcript icon - document/transcript placeholder
export function EmptyTranscriptIcon({ size = 48, className }: BrandIconProps) {
  return (
    <svg 
      width={size} 
      height={size} 
      viewBox="0 0 48 48" 
      fill="none" 
      xmlns="http://www.w3.org/2000/svg"
      className={cn('shrink-0', className)}
    >
      <path 
        d="M14 8H28L36 16V40C36 41.1 35.1 42 34 42H14C12.9 42 12 41.1 12 40V10C12 8.9 12.9 8 14 8Z" 
        stroke="currentColor" 
        strokeWidth="3" 
        strokeLinecap="round" 
        strokeLinejoin="round"
      />
      <path d="M28 8V16H36" stroke="currentColor" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round" />
      <path d="M18 24H30" stroke="currentColor" strokeWidth="3" strokeLinecap="round" />
      <path d="M18 30H30" stroke="currentColor" strokeWidth="3" strokeLinecap="round" />
      <path d="M18 36H24" stroke="currentColor" strokeWidth="3" strokeLinecap="round" />
    </svg>
  )
}

// Empty archive icon - minimalist void/empty state
export function EmptyArchiveIcon({ size = 48, className }: BrandIconProps) {
  return (
    <svg 
      width={size} 
      height={size} 
      viewBox="0 0 48 48" 
      fill="none" 
      xmlns="http://www.w3.org/2000/svg"
      className={cn('shrink-0', className)}
    >
      {/* Dashed empty box - represents void/nothing */}
      <rect 
        x="10" 
        y="14" 
        width="28" 
        height="24" 
        rx="2" 
        stroke="currentColor" 
        strokeWidth="2" 
        strokeDasharray="4 3"
        opacity="0.5"
      />
      {/* Small circle in center - like a droplet placeholder */}
      <circle 
        cx="24" 
        cy="26" 
        r="4" 
        stroke="currentColor" 
        strokeWidth="2"
        opacity="0.4"
      />
    </svg>
  )
}

// Processing icon - spinner/loading for active transcription
export function ProcessingIcon({ size = 24, className }: BrandIconProps) {
  return (
    <svg 
      width={size} 
      height={size} 
      viewBox="0 0 48 48" 
      fill="none" 
      xmlns="http://www.w3.org/2000/svg"
      className={cn('shrink-0', className)}
    >
      <path d="M24 8V14" stroke="currentColor" strokeWidth="3" strokeLinecap="round" />
      <path d="M24 34V40" stroke="currentColor" strokeWidth="3" strokeLinecap="round" opacity="0.3" />
      <path d="M12.7 12.7L16.9 16.9" stroke="currentColor" strokeWidth="3" strokeLinecap="round" opacity="0.85" />
      <path d="M31.1 31.1L35.3 35.3" stroke="currentColor" strokeWidth="3" strokeLinecap="round" opacity="0.2" />
      <path d="M8 24H14" stroke="currentColor" strokeWidth="3" strokeLinecap="round" opacity="0.7" />
      <path d="M34 24H40" stroke="currentColor" strokeWidth="3" strokeLinecap="round" opacity="0.4" />
      <path d="M12.7 35.3L16.9 31.1" stroke="currentColor" strokeWidth="3" strokeLinecap="round" opacity="0.55" />
      <path d="M31.1 16.9L35.3 12.7" stroke="currentColor" strokeWidth="3" strokeLinecap="round" opacity="0.55" />
    </svg>
  )
}

// Download/Export icon - for CSV export
export function BrandDownloadIcon({ size = 24, className }: BrandIconProps) {
  return (
    <svg 
      width={size} 
      height={size} 
      viewBox="0 0 48 48" 
      fill="none" 
      xmlns="http://www.w3.org/2000/svg"
      className={cn('shrink-0', className)}
    >
      <path 
        d="M24 8V30M24 30L32 22M24 30L16 22" 
        stroke="currentColor" 
        strokeWidth="3" 
        strokeLinecap="round" 
        strokeLinejoin="round"
      />
      <path 
        d="M10 36V38C10 39.1 10.9 40 12 40H36C37.1 40 38 39.1 38 38V36" 
        stroke="currentColor" 
        strokeWidth="3" 
        strokeLinecap="round" 
        strokeLinejoin="round"
      />
    </svg>
  )
}

// Multiple speakers/users icon - for diarization toggle
export function BrandSpeakersIcon({ size = 24, className }: BrandIconProps) {
  return (
    <svg 
      width={size} 
      height={size} 
      viewBox="0 0 48 48" 
      fill="none" 
      xmlns="http://www.w3.org/2000/svg"
      className={cn('shrink-0', className)}
    >
      {/* First person (left) */}
      <circle cx="16" cy="16" r="6" stroke="currentColor" strokeWidth="2.5" />
      <path 
        d="M6 38C6 31.4 11.4 26 18 26H14C10.7 26 8 28.7 8 32V38H6Z" 
        stroke="currentColor" 
        strokeWidth="2.5" 
        strokeLinecap="round" 
        strokeLinejoin="round"
      />
      {/* Second person (right) */}
      <circle cx="32" cy="16" r="6" stroke="currentColor" strokeWidth="2.5" />
      <path 
        d="M42 38C42 31.4 36.6 26 30 26H34C37.3 26 40 28.7 40 32V38H42Z" 
        stroke="currentColor" 
        strokeWidth="2.5" 
        strokeLinecap="round" 
        strokeLinejoin="round"
      />
      {/* Connection/merge at bottom */}
      <path 
        d="M14 38H34" 
        stroke="currentColor" 
        strokeWidth="2.5" 
        strokeLinecap="round"
      />
    </svg>
  )
}

// Single speaker icon - for single person mode
export function BrandSingleSpeakerIcon({ size = 24, className }: BrandIconProps) {
  return (
    <svg 
      width={size} 
      height={size} 
      viewBox="0 0 48 48" 
      fill="none" 
      xmlns="http://www.w3.org/2000/svg"
      className={cn('shrink-0', className)}
    >
      <circle cx="24" cy="14" r="7" stroke="currentColor" strokeWidth="3" strokeLinejoin="round" />
      <path 
        d="M10 40C10 32.3 16.3 26 24 26C31.7 26 38 32.3 38 40" 
        stroke="currentColor" 
        strokeWidth="3" 
        strokeLinecap="round" 
        strokeLinejoin="round"
      />
    </svg>
  )
}

// Computer/System Audio icon - for capturing system sound
export function BrandComputerAudioIcon({ size = 24, className }: BrandIconProps) {
  return (
    <svg 
      width={size} 
      height={size} 
      viewBox="0 0 48 48" 
      fill="none" 
      xmlns="http://www.w3.org/2000/svg"
      className={cn('shrink-0', className)}
    >
      {/* Monitor/Screen */}
      <rect x="6" y="8" width="36" height="24" rx="2" stroke="currentColor" strokeWidth="2.5" />
      {/* Screen inner area */}
      <rect x="10" y="12" width="28" height="16" rx="1" stroke="currentColor" strokeWidth="1.5" opacity="0.5" />
      {/* Stand */}
      <path d="M18 32V36H30V32" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" />
      <path d="M14 40H34" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" />
      {/* Sound waves on screen */}
      <path d="M20 20C21 19 21 21 22 20C23 19 23 21 24 20C25 19 25 21 26 20C27 19 27 21 28 20" stroke="currentColor" strokeWidth="2" strokeLinecap="round" />
    </svg>
  )
}

// ElevenLabs brand icon (stylized "XI" or waveform)
export function BrandElevenLabsIcon({ size = 24, className }: BrandIconProps) {
  return (
    <svg 
      width={size} 
      height={size} 
      viewBox="0 0 48 48" 
      fill="none" 
      xmlns="http://www.w3.org/2000/svg"
      className={cn('shrink-0', className)}
    >
      {/* Stylized waveform bars representing ElevenLabs */}
      <rect x="8" y="18" width="4" height="12" rx="2" fill="currentColor" />
      <rect x="15" y="12" width="4" height="24" rx="2" fill="currentColor" />
      <rect x="22" y="8" width="4" height="32" rx="2" fill="currentColor" />
      <rect x="29" y="12" width="4" height="24" rx="2" fill="currentColor" />
      <rect x="36" y="18" width="4" height="12" rx="2" fill="currentColor" />
    </svg>
  )
}

// Category icons - for note categories

// Note icon - document/paper
export function CategoryNoteIcon({ size = 24, className }: BrandIconProps) {
  return (
    <svg 
      width={size} 
      height={size} 
      viewBox="0 0 48 48" 
      fill="none" 
      xmlns="http://www.w3.org/2000/svg"
      className={cn('shrink-0', className)}
    >
      <path 
        d="M14 8H28L36 16V40C36 41.1 35.1 42 34 42H14C12.9 42 12 41.1 12 40V10C12 8.9 12.9 8 14 8Z" 
        stroke="currentColor" 
        strokeWidth="3" 
        strokeLinecap="round" 
        strokeLinejoin="round"
      />
      <path d="M28 8V16H36" stroke="currentColor" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round" />
      <path d="M18 24H30" stroke="currentColor" strokeWidth="3" strokeLinecap="round" />
      <path d="M18 30H30" stroke="currentColor" strokeWidth="3" strokeLinecap="round" />
    </svg>
  )
}

// Message icon - envelope
export function CategoryMessageIcon({ size = 24, className }: BrandIconProps) {
  return (
    <svg 
      width={size} 
      height={size} 
      viewBox="0 0 48 48" 
      fill="none" 
      xmlns="http://www.w3.org/2000/svg"
      className={cn('shrink-0', className)}
    >
      <rect x="6" y="12" width="36" height="26" rx="3" stroke="currentColor" strokeWidth="3" />
      <path d="M6 15L24 28L42 15" stroke="currentColor" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  )
}

// Rant icon - fire/flame
export function CategoryRantIcon({ size = 24, className }: BrandIconProps) {
  return (
    <svg 
      width={size} 
      height={size} 
      viewBox="0 0 48 48" 
      fill="none" 
      xmlns="http://www.w3.org/2000/svg"
      className={cn('shrink-0', className)}
    >
      <path 
        d="M24 6C24 6 12 18 12 28C12 34.6 17.4 40 24 40C30.6 40 36 34.6 36 28C36 18 24 6 24 6Z" 
        stroke="currentColor" 
        strokeWidth="3" 
        strokeLinecap="round" 
        strokeLinejoin="round"
      />
      <path 
        d="M24 28C24 28 20 32 20 34C20 36.2 21.8 38 24 38C26.2 38 28 36.2 28 34C28 32 24 28 24 28Z" 
        fill="currentColor"
      />
    </svg>
  )
}

// Idea icon - lightbulb
export function CategoryIdeaIcon({ size = 24, className }: BrandIconProps) {
  return (
    <svg 
      width={size} 
      height={size} 
      viewBox="0 0 48 48" 
      fill="none" 
      xmlns="http://www.w3.org/2000/svg"
      className={cn('shrink-0', className)}
    >
      <path 
        d="M18 38H30M20 42H28M24 6C17.4 6 12 11.4 12 18C12 22.4 14.4 26.2 18 28.4V32C18 33.1 18.9 34 20 34H28C29.1 34 30 33.1 30 32V28.4C33.6 26.2 36 22.4 36 18C36 11.4 30.6 6 24 6Z" 
        stroke="currentColor" 
        strokeWidth="3" 
        strokeLinecap="round" 
        strokeLinejoin="round"
      />
    </svg>
  )
}

// Meeting icon - calendar with people
export function CategoryMeetingIcon({ size = 24, className }: BrandIconProps) {
  return (
    <svg 
      width={size} 
      height={size} 
      viewBox="0 0 48 48" 
      fill="none" 
      xmlns="http://www.w3.org/2000/svg"
      className={cn('shrink-0', className)}
    >
      <rect x="8" y="10" width="32" height="30" rx="3" stroke="currentColor" strokeWidth="3" />
      <path d="M16 6V14" stroke="currentColor" strokeWidth="3" strokeLinecap="round" />
      <path d="M32 6V14" stroke="currentColor" strokeWidth="3" strokeLinecap="round" />
      <path d="M8 20H40" stroke="currentColor" strokeWidth="3" />
      <circle cx="18" cy="30" r="3" stroke="currentColor" strokeWidth="2" />
      <circle cx="30" cy="30" r="3" stroke="currentColor" strokeWidth="2" />
    </svg>
  )
}

// Conversation icon - chat bubbles
export function CategoryConversationIcon({ size = 24, className }: BrandIconProps) {
  return (
    <svg 
      width={size} 
      height={size} 
      viewBox="0 0 48 48" 
      fill="none" 
      xmlns="http://www.w3.org/2000/svg"
      className={cn('shrink-0', className)}
    >
      <path 
        d="M8 10H32C34.2 10 36 11.8 36 14V26C36 28.2 34.2 30 32 30H18L10 38V30H8C5.8 30 4 28.2 4 26V14C4 11.8 5.8 10 8 10Z" 
        stroke="currentColor" 
        strokeWidth="3" 
        strokeLinecap="round" 
        strokeLinejoin="round"
      />
      <path 
        d="M40 18H42C43.1 18 44 18.9 44 20V32C44 33.1 43.1 34 42 34H40V40L34 34H28" 
        stroke="currentColor" 
        strokeWidth="3" 
        strokeLinecap="round" 
        strokeLinejoin="round"
      />
    </svg>
  )
}

// Task icon - checkbox with checkmark
export function CategoryTaskIcon({ size = 24, className }: BrandIconProps) {
  return (
    <svg 
      width={size} 
      height={size} 
      viewBox="0 0 48 48" 
      fill="none" 
      xmlns="http://www.w3.org/2000/svg"
      className={cn('shrink-0', className)}
    >
      <rect x="8" y="8" width="32" height="32" rx="4" stroke="currentColor" strokeWidth="3" />
      <path d="M16 24L22 30L32 18" stroke="currentColor" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  )
}

// Journal icon - open book for personal entries
export function CategoryJournalIcon({ size = 24, className }: BrandIconProps) {
  return (
    <svg 
      width={size} 
      height={size} 
      viewBox="0 0 48 48" 
      fill="none" 
      xmlns="http://www.w3.org/2000/svg"
      className={cn('shrink-0', className)}
    >
      {/* Open book - left page */}
      <path d="M24 14C24 11.79 21.31 10 18 10H8V34H18.5C20.16 34 21.72 34.42 23 35.2C22.09 35.72 21.05 36 20 36H18.5" stroke="currentColor" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round" />
      {/* Open book - right page */}
      <path d="M24 14C24 11.79 26.69 10 30 10H40V34H29.5C27.84 34 26.28 34.42 25 35.2C25.91 35.72 26.95 36 28 36H29.5" stroke="currentColor" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round" />
      {/* Spine */}
      <path d="M24 14V38" stroke="currentColor" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  )
}

// Gem icon - for most interesting/deep transcripts
export function GemIcon({ size = 24, className }: BrandIconProps) {
  return (
    <svg 
      width={size} 
      height={size} 
      viewBox="0 0 112 112" 
      fill="none" 
      xmlns="http://www.w3.org/2000/svg"
      className={cn('shrink-0', className)}
    >
      <path 
        d="M49.75 46L44.75 51L49.75 56M29.75 51L44.75 36H67.25L82.25 51L56 77.25L29.75 51Z" 
        stroke="currentColor" 
        strokeWidth="5" 
        strokeLinecap="round" 
        strokeLinejoin="round"
      />
    </svg>
  )
}

// Shield icon - for local data processing disclaimer
export function ShieldIcon({ size = 24, className }: BrandIconProps) {
  return (
    <svg 
      width={size} 
      height={size} 
      viewBox="0 0 48 48" 
      fill="none" 
      xmlns="http://www.w3.org/2000/svg"
      className={cn('shrink-0', className)}
    >
      <path 
        d="M24 4L6 12V22C6 33.1 13.6 43.2 24 46C34.4 43.2 42 33.1 42 22V12L24 4Z" 
        stroke="currentColor" 
        strokeWidth="3" 
        strokeLinecap="round" 
        strokeLinejoin="round"
      />
      <path d="M16 24L22 30L32 18" stroke="currentColor" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  )
}

// Time-Sensitive/Bell icon - for urgent/time-sensitive content
export function TimeSensitiveIcon({ size = 24, className }: BrandIconProps) {
  return (
    <svg 
      width={size} 
      height={size} 
      viewBox="0 0 112 112" 
      fill="none" 
      xmlns="http://www.w3.org/2000/svg"
      className={cn('shrink-0', className)}
    >
      <path 
        d="M30.3535 44.1259C31.275 39.9047 33.212 36.0631 35.8958 32.8701M76.1034 32.8701C78.7872 36.0631 80.7243 39.9047 81.6457 44.1259M46.5512 72.25C48.4372 75.9863 51.9622 78.5 55.9996 78.5C60.0369 78.5 63.562 75.9863 65.448 72.25M75.9996 71L72.982 48.3685C71.8471 39.8568 64.5866 33.5 55.9996 33.5C47.4126 33.5 40.152 39.8568 39.0171 48.3685L35.9996 71H75.9996Z" 
        stroke="currentColor" 
        strokeWidth="5" 
        strokeLinecap="round" 
        strokeLinejoin="round"
      />
    </svg>
  )
}

// Novelty/Star icon - for genuinely novel/interesting content
export function NoveltyIcon({ size = 24, className }: BrandIconProps) {
  return (
    <svg 
      width={size} 
      height={size} 
      viewBox="0 0 112 112" 
      fill="none" 
      xmlns="http://www.w3.org/2000/svg"
      className={cn('shrink-0', className)}
    >
      <path 
        d="M48.5 66.0006L38.5 76.0006M43.5 53.5006L33.5 63.5006M66 66.0006L56 76.0006M64.75 31L69.6874 39.2043L79.0158 41.3647L72.7389 48.5957L73.5668 58.1353L64.75 54.4L55.9332 58.1353L56.7611 48.5957L50.4842 41.3647L59.8126 39.2043L64.75 31Z" 
        stroke="currentColor" 
        strokeWidth="5" 
        strokeLinecap="round" 
        strokeLinejoin="round"
      />
    </svg>
  )
}

export type { BrandIconProps }
