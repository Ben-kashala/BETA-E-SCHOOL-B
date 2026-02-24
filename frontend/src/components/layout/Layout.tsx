import { useState, useEffect } from 'react'
import { Outlet, useNavigate, useLocation } from 'react-router-dom'
import { useAuthStore } from '@/store/authStore'
import Sidebar from './Sidebar'
import Header from './Header'
import Footer from './Footer'

/** Vérification de l'inactivité toutes les 60 secondes pour déconnexion automatique. */
const INACTIVITY_CHECK_INTERVAL_MS = 60_000

export default function Layout() {
  const { user, logout, checkInactivity } = useAuthStore()
  const navigate = useNavigate()
  const location = useLocation()
  const [sidebarOpen, setSidebarOpen] = useState(false)

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

  if (!user) return null

  return (
    <div className="min-h-screen bg-gray-50 dark:bg-gray-900 transition-colors flex flex-col">
      <Header 
        user={user} 
        onLogout={handleLogout}
        onMenuClick={() => setSidebarOpen(!sidebarOpen)}
      />
      <div className="flex flex-1 relative">
        {/* Backdrop pour mobile */}
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
        <main className="flex-1 p-4 sm:p-6 bg-gray-50 dark:bg-gray-900 transition-colors w-full lg:w-auto">
          <Outlet />
        </main>
      </div>
      <Footer />
    </div>
  )
}
