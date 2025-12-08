const ELEVENLABS_TOKEN_URL = 'https://api.elevenlabs.io/v1/single-use-token/realtime_scribe'

export interface TokenResponse {
  token: string
}

export interface TokenError {
  detail?: string
  message?: string
}

export async function fetchToken(apiKey: string): Promise<string> {
  if (!apiKey) {
    throw new Error('API key is required')
  }

  const response = await fetch(ELEVENLABS_TOKEN_URL, {
    method: 'POST',
    headers: {
      'xi-api-key': apiKey,
      'Content-Type': 'application/json',
    },
  })

  if (!response.ok) {
    const errorData: TokenError = await response.json().catch(() => ({}))
    const errorMessage = errorData.detail || errorData.message || `HTTP ${response.status}`
    throw new Error(`Failed to fetch token: ${errorMessage}`)
  }

  const data: TokenResponse = await response.json()
  
  if (!data.token) {
    throw new Error('No token received from API')
  }

  return data.token
}

