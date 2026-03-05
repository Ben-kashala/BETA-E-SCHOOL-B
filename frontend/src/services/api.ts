import axios, { AxiosError, InternalAxiosRequestConfig } from 'axios'
import toast from 'react-hot-toast'

const API_BASE_URL = import.meta.env.VITE_API_URL || 'http://localhost:8000/api'

const api = axios.create({
  baseURL: API_BASE_URL,
  headers: {
    'Content-Type': 'application/json',
  },
})

// Request interceptor
api.interceptors.request.use(
  (config: InternalAxiosRequestConfig) => {
    const token = localStorage.getItem('access_token')
    const schoolCode = localStorage.getItem('school_code')
    
    if (token && config.headers) {
      config.headers.Authorization = `Bearer ${token}`
    }
    
    if (schoolCode && config.headers) {
      config.headers['X-School-Code'] = schoolCode
    }
    
    // Mise à jour de la dernière activité (déconnexion automatique après inactivité)
    if (token) {
      localStorage.setItem('last_activity_at', String(Date.now()))
    }
    
    return config
  },
  (error) => {
    return Promise.reject(error)
  }
)

// Response interceptor
api.interceptors.response.use(
  (response) => response,
  async (error: AxiosError) => {
    const originalRequest = error.config as InternalAxiosRequestConfig & { _retry?: boolean }
    
    // Ne pas essayer de rafraîchir le token pour les endpoints d'authentification
    const isAuthEndpoint = originalRequest?.url?.includes('/auth/login/') || 
                          originalRequest?.url?.includes('/auth/token/refresh/') ||
                          originalRequest?.url?.includes('/auth/users/register/')
    
    if (error.response?.status === 401 && !originalRequest._retry && !isAuthEndpoint) {
      originalRequest._retry = true
      
      try {
        const refreshToken = localStorage.getItem('refresh_token')
        if (refreshToken) {
          const response = await axios.post(`${API_BASE_URL}/auth/token/refresh/`, {
            refresh: refreshToken,
          })
          
          const { access } = response.data
          localStorage.setItem('access_token', access)
          
          if (originalRequest.headers) {
            originalRequest.headers.Authorization = `Bearer ${access}`
          }
          
          return api(originalRequest)
        }
      } catch (refreshError) {
        // Refresh failed, logout
        localStorage.removeItem('access_token')
        localStorage.removeItem('refresh_token')
        localStorage.removeItem('user')
        localStorage.removeItem('school_code')
        localStorage.removeItem('last_activity_at')
        window.location.href = '/login'
        return Promise.reject(refreshError)
      }
    }
    
    // Handle errors with detailed messages
    // Ne pas afficher de notification pour les erreurs 401 sur les endpoints d'authentification
    // (elles sont déjà gérées par les composants de login)
    // isAuthEndpoint est déjà défini plus haut
    
    if (error.response) {
      const data = error.response.data as any
      let message = data?.error || data?.detail || data?.message || 'Une erreur est survenue'
      
      // Extract field-specific errors
      if (data?.non_field_errors && Array.isArray(data.non_field_errors)) {
        message = data.non_field_errors.join(', ')
      } else if (typeof data === 'object' && !data.detail && !data.message) {
        // Multiple field errors
        const fieldErrors: string[] = []
        Object.keys(data).forEach((key) => {
          if (Array.isArray(data[key])) {
            fieldErrors.push(`${key}: ${data[key].join(', ')}`)
          } else if (typeof data[key] === 'string') {
            fieldErrors.push(`${key}: ${data[key]}`)
          }
        })
        if (fieldErrors.length > 0) {
          message = fieldErrors.join(' | ')
        }
      }
      
      // Add status code context for better debugging
      const statusCode = error.response.status
      const errorStyle = {
        borderLeft: '5px solid #ef4444',
        background: 'linear-gradient(to right, #fef2f2 0%, #ffffff 5%)',
        color: '#991b1b',
        boxShadow: '0 20px 25px -5px rgba(239, 68, 68, 0.1), 0 10px 10px -5px rgba(239, 68, 68, 0.04)',
        padding: '16px 20px',
        borderRadius: '16px',
        fontSize: '14px',
        fontWeight: '500',
        maxWidth: '480px',
        minWidth: '340px',
        lineHeight: '1.6',
      }
      const errorIconTheme = {
        primary: '#ef4444',
        secondary: '#fff',
      }
      
      // Ne pas afficher de notification pour les erreurs 401 sur les endpoints d'authentification
      // (elles sont gérées par les composants de login)
      if (statusCode === 401 && isAuthEndpoint) {
        // Laisser les composants gérer l'affichage des erreurs de login
        return Promise.reject(error)
      }
      
      if (statusCode === 400) {
        toast.error(`Erreur de validation: ${message}`, {
          duration: 6000,
          style: errorStyle,
          iconTheme: errorIconTheme,
        })
      } else if (statusCode === 401) {
        toast.error('Session expirée. Veuillez vous reconnecter.', {
          duration: 5000,
          style: errorStyle,
          iconTheme: errorIconTheme,
        })
      } else if (statusCode === 403) {
        toast.error('Accès refusé. Vous n\'avez pas les permissions nécessaires.', {
          duration: 5000,
          style: errorStyle,
          iconTheme: errorIconTheme,
        })
      } else if (statusCode === 404) {
        toast.error('Ressource introuvable.', {
          duration: 4000,
          style: errorStyle,
          iconTheme: errorIconTheme,
        })
      } else if (statusCode === 500) {
        toast.error('Erreur serveur. Veuillez réessayer plus tard.', {
          duration: 6000,
          style: errorStyle,
          iconTheme: errorIconTheme,
        })
      } else {
        toast.error(message, {
          duration: 5000,
          style: errorStyle,
          iconTheme: errorIconTheme,
        })
      }
    } else if (error.request) {
      toast.error('Pas de réponse du serveur. Vérifiez votre connexion internet.', {
        duration: 5000,
        icon: '⚠️',
        style: {
          borderLeft: '5px solid #f59e0b',
          background: 'linear-gradient(to right, #fffbeb 0%, #ffffff 5%)',
          color: '#92400e',
          boxShadow: '0 20px 25px -5px rgba(245, 158, 11, 0.1), 0 10px 10px -5px rgba(245, 158, 11, 0.04)',
          padding: '16px 20px',
          borderRadius: '16px',
          fontSize: '14px',
          fontWeight: '500',
          maxWidth: '480px',
          minWidth: '340px',
          lineHeight: '1.6',
        },
        iconTheme: {
          primary: '#f59e0b',
          secondary: '#fff',
        },
      })
    } else {
      toast.error('Une erreur inattendue est survenue. Veuillez réessayer.', {
        duration: 5000,
        style: {
          borderLeft: '5px solid #ef4444',
          background: 'linear-gradient(to right, #fef2f2 0%, #ffffff 5%)',
          color: '#991b1b',
          boxShadow: '0 20px 25px -5px rgba(239, 68, 68, 0.1), 0 10px 10px -5px rgba(239, 68, 68, 0.04)',
          padding: '16px 20px',
          borderRadius: '16px',
          fontSize: '14px',
          fontWeight: '500',
          maxWidth: '480px',
          minWidth: '340px',
          lineHeight: '1.6',
        },
        iconTheme: {
          primary: '#ef4444',
          secondary: '#fff',
        },
      })
    }
    
    return Promise.reject(error)
  }
)

export default api
