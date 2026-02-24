import { create } from 'zustand'
import { persist, createJSONStorage } from 'zustand/middleware'
import { User } from '@/types'
import api from '@/services/api'

/** Clé localStorage pour la dernière activité (timestamp ms) */
export const LAST_ACTIVITY_KEY = 'last_activity_at'

/** Délai d'inactivité avant déconnexion automatique (en heures). Configurable via VITE_INACTIVITY_TIMEOUT_HOURS. */
const INACTIVITY_HOURS = Number(import.meta.env.VITE_INACTIVITY_TIMEOUT_HOURS) || 1
export const INACTIVITY_TIMEOUT_MS = INACTIVITY_HOURS * 60 * 60 * 1000

function isSessionExpired(): boolean {
  const last = localStorage.getItem(LAST_ACTIVITY_KEY)
  if (!last) return true
  const lastMs = parseInt(last, 10)
  if (Number.isNaN(lastMs)) return true
  return Date.now() - lastMs > INACTIVITY_TIMEOUT_MS
}

function clearSessionAndRedirect(): void {
  localStorage.removeItem('access_token')
  localStorage.removeItem('refresh_token')
  localStorage.removeItem('user')
  localStorage.removeItem('school_code')
  localStorage.removeItem(LAST_ACTIVITY_KEY)
  window.location.href = '/login'
}

interface AuthState {
  user: User | null
  isAuthenticated: boolean
  isLoading: boolean
  login: (username: string, password: string) => Promise<User>
  logout: () => void
  setUser: (user: User) => void
  checkAuth: () => Promise<void>
  /** Vérifie l'inactivité et déconnecte si le délai est dépassé. À appeler périodiquement. */
  checkInactivity: () => void
}

export const useAuthStore = create<AuthState>()(
  persist(
    (set) => ({
      user: null,
      isAuthenticated: false,
      isLoading: false,
      
      login: async (username: string, password: string): Promise<User> => {
        set({ isLoading: true })
        try {
          const response = await api.post('/auth/login/', { username, password })
          const { access, refresh } = response.data
          
          localStorage.setItem('access_token', access)
          localStorage.setItem('refresh_token', refresh)
          localStorage.setItem(LAST_ACTIVITY_KEY, String(Date.now()))
          
          // Get user profile
          const userResponse = await api.get('/auth/users/me/')
          const user = userResponse.data
          
          if (user?.school?.code) {
            localStorage.setItem('school_code', user.school.code)
          }
          
          set({ user, isAuthenticated: true, isLoading: false })
          return user
        } catch (error) {
          set({ isLoading: false })
          throw error
        }
      },
      
      logout: () => {
        localStorage.removeItem('access_token')
        localStorage.removeItem('refresh_token')
        localStorage.removeItem('user')
        localStorage.removeItem('school_code')
        localStorage.removeItem(LAST_ACTIVITY_KEY)
        set({ user: null, isAuthenticated: false })
      },
      
      setUser: (user: User) => {
        set({ user, isAuthenticated: true })
      },
      
      checkAuth: async () => {
        const token = localStorage.getItem('access_token')
        if (!token) {
          set({ user: null, isAuthenticated: false })
          return
        }
        if (isSessionExpired()) {
          clearSessionAndRedirect()
          set({ user: null, isAuthenticated: false })
          return
        }
        try {
          const response = await api.get('/auth/users/me/')
          localStorage.setItem(LAST_ACTIVITY_KEY, String(Date.now()))
          set({ user: response.data, isAuthenticated: true })
        } catch (error: any) {
          if (error?.response?.status === 401) {
            localStorage.removeItem('access_token')
            localStorage.removeItem('refresh_token')
            localStorage.removeItem('user')
            localStorage.removeItem('school_code')
            localStorage.removeItem(LAST_ACTIVITY_KEY)
          }
          set({ user: null, isAuthenticated: false })
        }
      },
      checkInactivity: () => {
        if (!localStorage.getItem('access_token')) return
        if (isSessionExpired()) {
          set({ user: null, isAuthenticated: false })
          clearSessionAndRedirect()
        }
      },
    }),
    {
      name: 'auth-storage',
      storage: createJSONStorage(() => localStorage),
      partialize: (state) => ({ user: state.user, isAuthenticated: state.isAuthenticated }),
    }
  )
)
