import { useState, useEffect } from 'react'
import { Outlet, useNavigate, useLocation } from 'react-router-dom'
import { useAuthStore } from '@/store/authStore'
import Sidebar from './Sidebar'
import Header from './Header'
import Footer from './Footer'

/** Vérification de l'inactivité toutes les 60 secondes pour déconnexion automatique. */
const INACTIVITY_CHECK_INTERVAL_MS = 60_000

export default function Layout() {
  const { user, isAuthenticated, logout, checkInactivity, checkAuth } = useAuthStore()
  const navigate = useNavigate()
  const location = useLocation()
  const [sidebarOpen, setSidebarOpen] = useState(false)
  const [userLoaded, setUserLoaded] = useState(false)

  const handleLogout = () => {
    logout()
    navigate('/login')
  }

  useEffect(() => {
    const interval = setInterval(() => {
      checkInactivity()
    }, INACTIVITY_CHECK_INTERVAL_MS)
    return () => clearInterval(interval)
  }, [checkInactivity])

  // Fermer la sidebar lors du changement de route sur mobile
  useEffect(() => {
    setSidebarOpen(false)
  }, [location.pathname])

  // Fermer la sidebar lors du redimensionnement vers desktop
  useEffect(() => {
    const handleResize = () => {
      if (window.innerWidth >= 1024) {
        setSidebarOpen(false)
      }
    }
    window.addEventListener('resize', handleResize)
    return () => window.removeEventListener('resize', handleResize)
  }, [])

  // Si on est authentifié mais user pas encore dispo (ex. après login, rehydration retardée), charger le profil
  useEffect(() => {
    if (user) {
      setUserLoaded(true)
      return
    }
    const token = localStorage.getItem('access_token')
    if (!token || !isAuthenticated) {
      setUserLoaded(true)
      return
    }
    let cancelled = false
    checkAuth().finally(() => {
      if (!cancelled) setUserLoaded(true)
    })
    return () => { cancelled = true }
  }, [user, isAuthenticated, checkAuth])

  // Éviter une page blanche : afficher un chargement si user pas encore prêt
  if (!user && isAuthenticated && !userLoaded) {
    return (
      <div className="flex items-center justify-center min-h-screen">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-primary-600" aria-label="Chargement" />
      </div>
    )
  }

  if (!user) return null

  return (
    <div className="min-h-screen flex flex-col">
      <Header 
        user={user} 
        onLogout={handleLogout}
        onMenuClick={() => setSidebarOpen(!sidebarOpen)}
      />
      <div className="flex flex-1 relative">
        {sidebarOpen && (
          <div 
            className="fixed inset-0 bg-black bg-opacity-50 z-40 lg:hidden transition-opacity"
            onClick={() => setSidebarOpen(false)}
          />
        )}
        <Sidebar 
          user={user} 
          currentPath={location.pathname}
          isOpen={sidebarOpen}
          onClose={() => setSidebarOpen(false)}
        />
        <main className="layout-main flex-1 p-4 sm:p-6 w-full lg:w-auto">
          <Outlet />
        </main>
      </div>
      <Footer />
    </div>
  )
}
