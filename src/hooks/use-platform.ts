import { useState, useEffect } from 'react'

declare global {
  interface Window {
    __TAURI__?: unknown
  }
}

export type Platform = 'ios' | 'android' | 'macos' | 'windows' | 'linux' | 'web'

/**
 * Detects if running on a mobile device (iOS or Android) within Tauri
 * This is different from useIsMobile which just checks screen width
 */
export function usePlatform() {
  const [platform, setPlatform] = useState<Platform>('web')
  const [isLoading, setIsLoading] = useState(true)

  useEffect(() => {
    const detectPlatform = async () => {
      try {
        // Check if we're in Tauri
        if (window.__TAURI__) {
          const { platform: tauriPlatform } = await import('@tauri-apps/plugin-os')
          const detected = await tauriPlatform()
          
          // Map Tauri platform names to our Platform type
          switch (detected) {
            case 'ios':
              setPlatform('ios')
              break
            case 'android':
              setPlatform('android')
              break
            case 'macos':
              setPlatform('macos')
              break
            case 'windows':
              setPlatform('windows')
              break
            case 'linux':
              setPlatform('linux')
              break
            default:
              setPlatform('web')
          }
        } else {
          // Fallback to web detection
          const userAgent = navigator.userAgent.toLowerCase()
          if (/iphone|ipad|ipod/.test(userAgent)) {
            setPlatform('ios')
          } else if (/android/.test(userAgent)) {
            setPlatform('android')
          } else {
            setPlatform('web')
          }
        }
      } catch {
        // Default to web if detection fails
        setPlatform('web')
      } finally {
        setIsLoading(false)
      }
    }

    detectPlatform()
  }, [])

  return {
    platform,
    isLoading,
    isMobile: platform === 'ios' || platform === 'android',
    isDesktop: platform === 'macos' || platform === 'windows' || platform === 'linux',
    isIOS: platform === 'ios',
    isAndroid: platform === 'android',
    isMacOS: platform === 'macos',
  }
}

// Sync check for initial render (may not be accurate until hydration)
export function getInitialPlatform(): Platform {
  if (typeof window === 'undefined') return 'web'
  
  const userAgent = navigator.userAgent.toLowerCase()
  if (/iphone|ipad|ipod/.test(userAgent)) return 'ios'
  if (/android/.test(userAgent)) return 'android'
  if (/macintosh|mac os x/.test(userAgent)) return 'macos'
  if (/windows/.test(userAgent)) return 'windows'
  if (/linux/.test(userAgent)) return 'linux'
  return 'web'
}

