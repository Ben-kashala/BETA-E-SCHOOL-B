import React from 'react'
import ReactDOM from 'react-dom/client'
import { BrowserRouter } from 'react-router-dom'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { Toaster } from 'react-hot-toast'
import App from './App'
import './index.css'
import favicon from './images/logo.png'

// Initialiser le thème au chargement depuis localStorage
const initializeTheme = () => {
  try {
    const htmlElement = document.documentElement
    // Retirer la classe dark d'abord
    htmlElement.classList.remove('dark')
    
    const stored = localStorage.getItem('preferences-storage')
    let theme: string = 'light' // Par défaut, thème clair
    
    if (stored) {
      try {
        const preferences = JSON.parse(stored)
        // Zustand peut stocker dans state ou directement à la racine
        theme = preferences?.state?.theme || preferences?.theme || 'light'
        console.log('📦 Thème lu depuis localStorage:', theme)
      } catch (parseError) {
        console.error('Erreur de parsing localStorage:', parseError)
        theme = 'light'
      }
    }
    
    // Appliquer le thème
    htmlElement.classList.remove('dark')
    
    if (theme === 'dark') {
      htmlElement.classList.add('dark')
      console.log('🌙 Thème sombre initialisé')
    } else if (theme === 'light') {
      htmlElement.classList.remove('dark')
      console.log('☀️ Thème clair initialisé')
    } else {
      // System theme
      const prefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches
      if (prefersDark) {
        htmlElement.classList.add('dark')
        console.log('🖥️ Thème système initialisé (sombre)')
      } else {
        htmlElement.classList.remove('dark')
        console.log('🖥️ Thème système initialisé (clair)')
      }
    }
  } catch (error) {
    console.error('Erreur lors de l\'initialisation du thème:', error)
    // En cas d'erreur, retirer la classe dark par sécurité
    document.documentElement.classList.remove('dark')
  }
}

const setFavicon = () => {
  try {
    const existingLink = document.querySelector<HTMLLinkElement>("link[rel~='icon']")
    const link = existingLink ?? document.createElement('link')

    link.rel = 'icon'
    link.type = 'image/png'
    link.href = favicon

    if (!existingLink) {
      document.head.appendChild(link)
    }
  } catch (error) {
    console.error('Erreur lors de la mise à jour du favicon:', error)
  }
}

// Écouter les changements de préférence système
window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', () => {
  try {
    const htmlElement = document.documentElement
    const stored = localStorage.getItem('preferences-storage')
    if (stored) {
      const preferences = JSON.parse(stored)
      const theme = preferences?.state?.theme || preferences?.theme || 'system'
      if (theme === 'system') {
        // Retirer d'abord
        htmlElement.classList.remove('dark')
        const prefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches
        if (prefersDark) {
          htmlElement.classList.add('dark')
        } else {
          htmlElement.classList.remove('dark')
        }
      }
    }
  } catch (error) {
    console.error('Erreur lors de la mise à jour du thème:', error)
  }
})

initializeTheme()
setFavicon()

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      refetchOnWindowFocus: false,
      retry: 1,
      staleTime: 5 * 60 * 1000, // 5 minutes
    },
  },
})

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <QueryClientProvider client={queryClient}>
      <BrowserRouter
        future={{
          v7_startTransition: true,
          v7_relativeSplatPath: true,
        }}
      >
        <App />
        <Toaster
          position="top-right"
          reverseOrder={false}
          gutter={12}
          containerClassName="toast-container"
          containerStyle={{
            top: 20,
            right: 20,
            zIndex: 9999,
          }}
          toastOptions={{
            duration: 5000,
            className: 'toast-notification',
            style: {
              background: '#fff',
              color: '#1f2937',
              padding: '18px 22px',
              borderRadius: '12px',
              boxShadow: '0 10px 25px -5px rgba(0, 0, 0, 0.15), 0 4px 6px -2px rgba(0, 0, 0, 0.05)',
              border: '1px solid rgba(0, 0, 0, 0.08)',
              fontSize: '15px',
              fontWeight: '500',
              maxWidth: '420px',
              minWidth: '320px',
              lineHeight: '1.5',
              display: 'flex',
              alignItems: 'center',
              gap: '14px',
              fontFamily: 'system-ui, -apple-system, sans-serif',
            },
            success: {
              duration: 4000,
              iconTheme: {
                primary: '#10b981',
                secondary: '#fff',
              },
              className: 'toast-success',
              style: {
                borderLeft: '4px solid #10b981',
                background: 'linear-gradient(to right, #f0fdf4 0%, #ffffff 8%)',
                color: '#065f46',
                boxShadow: '0 10px 25px -5px rgba(16, 185, 129, 0.2), 0 4px 6px -2px rgba(16, 185, 129, 0.1)',
                padding: '18px 22px',
                borderRadius: '12px',
                fontSize: '15px',
                fontWeight: '500',
                maxWidth: '420px',
                minWidth: '320px',
                lineHeight: '1.5',
              },
            },
            error: {
              duration: 6000,
              iconTheme: {
                primary: '#ef4444',
                secondary: '#fff',
              },
              className: 'toast-error',
              style: {
                borderLeft: '4px solid #ef4444',
                background: 'linear-gradient(to right, #fef2f2 0%, #ffffff 8%)',
                color: '#991b1b',
                boxShadow: '0 10px 25px -5px rgba(239, 68, 68, 0.2), 0 4px 6px -2px rgba(239, 68, 68, 0.1)',
                padding: '18px 22px',
                borderRadius: '12px',
                fontSize: '15px',
                fontWeight: '500',
                maxWidth: '420px',
                minWidth: '320px',
                lineHeight: '1.5',
              },
            },
            loading: {
              iconTheme: {
                primary: '#3b82f6',
                secondary: '#fff',
              },
              className: 'toast-loading',
              style: {
                borderLeft: '4px solid #3b82f6',
                background: 'linear-gradient(to right, #eff6ff 0%, #ffffff 8%)',
                color: '#1e40af',
                boxShadow: '0 10px 25px -5px rgba(59, 130, 246, 0.2), 0 4px 6px -2px rgba(59, 130, 246, 0.1)',
                padding: '18px 22px',
                borderRadius: '12px',
                fontSize: '15px',
                fontWeight: '500',
                maxWidth: '420px',
                minWidth: '320px',
                lineHeight: '1.5',
              },
            },
          }}
        />
      </BrowserRouter>
    </QueryClientProvider>
  </React.StrictMode>,
)
