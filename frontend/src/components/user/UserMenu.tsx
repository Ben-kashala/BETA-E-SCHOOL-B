import { useState, useRef, useEffect } from 'react'
import { User, Settings, LogOut, ChevronDown } from 'lucide-react'
import { User as UserType } from '@/types'
import ProfileModal from './ProfileModal'
import PreferencesModal from './PreferencesModal'

interface UserMenuProps {
  user: UserType
  onLogout: () => void
}

export default function UserMenu({ user, onLogout }: UserMenuProps) {
  const [isOpen, setIsOpen] = useState(false)
  const [showProfile, setShowProfile] = useState(false)
  const [showPreferences, setShowPreferences] = useState(false)
  const menuRef = useRef<HTMLDivElement>(null)

  // Fermer le menu si on clique en dehors
  useEffect(() => {
    const handleClickOutside = (event: MouseEvent) => {
      if (menuRef.current && !menuRef.current.contains(event.target as Node)) {
        setIsOpen(false)
      }
    }

    if (isOpen) {
      document.addEventListener('mousedown', handleClickOutside)
    }

    return () => {
      document.removeEventListener('mousedown', handleClickOutside)
    }
  }, [isOpen])

  const handleProfileClick = () => {
    setIsOpen(false)
    setShowProfile(true)
  }

  const handlePreferencesClick = () => {
    setIsOpen(false)
    setShowPreferences(true)
  }

  const handleLogoutClick = () => {
    setIsOpen(false)
    onLogout()
  }

  return (
    <>
      <div className="relative" ref={menuRef}>
        <button
          onClick={() => setIsOpen(!isOpen)}
          className="flex items-center space-x-3 p-2 rounded-lg hover:bg-eschool-header-text/10 transition-colors focus:outline-none focus:ring-2 focus:ring-eschool-body"
        >
          {user.profile_picture ? (
            <img
              src={user.profile_picture}
              alt={[user?.first_name, user?.last_name].filter(Boolean).join(' ') || 'Avatar'}
              className="w-10 h-10 rounded-full object-cover ring-2 ring-eschool-avatar/50"
            />
          ) : (
            <div className="w-10 h-10 rounded-full bg-eschool-avatar flex items-center justify-center">
              <User className="w-5 h-5 text-eschool-avatar-text" />
            </div>
          )}
          <ChevronDown 
            className={`w-4 h-4 text-eschool-header-text transition-transform ${isOpen ? 'rotate-180' : ''}`} 
          />
        </button>

        {isOpen && (
          <div className="absolute right-0 mt-2 w-64 bg-eschool-header rounded-lg shadow-lg border border-eschool-header-text/20 py-2 z-50">
            <div className="px-4 py-3 border-b border-eschool-header-text/20">
              <p className="text-sm font-semibold text-eschool-header-text">
                {[user?.first_name, user?.last_name].filter(Boolean).join(' ') || user?.email || 'Utilisateur'}
              </p>
              <p className="text-xs text-eschool-header-text/70 mt-1">{user.email}</p>
            </div>

            <button
              onClick={handleProfileClick}
              className="w-full px-4 py-3 text-left flex items-center space-x-3 hover:bg-eschool-header-text/10 transition-colors"
            >
              <User className="w-5 h-5 text-eschool-header-text/80" />
              <span className="text-sm text-eschool-header-text">Profil</span>
            </button>

            <button
              onClick={handlePreferencesClick}
              className="w-full px-4 py-3 text-left flex items-center space-x-3 hover:bg-eschool-header-text/10 transition-colors"
            >
              <Settings className="w-5 h-5 text-eschool-header-text/80" />
              <span className="text-sm text-eschool-header-text">Préférences</span>
            </button>

            <div className="border-t border-eschool-header-text/20 my-2"></div>

            <button
              onClick={handleLogoutClick}
              className="w-full px-4 py-3 text-left flex items-center space-x-3 hover:bg-red-50 text-red-600 transition-colors"
            >
              <LogOut className="w-5 h-5" />
              <span className="text-sm font-medium">Déconnexion</span>
            </button>
          </div>
        )}
      </div>

      {showProfile && (
        <ProfileModal
          user={user}
          onClose={() => setShowProfile(false)}
        />
      )}

      {showPreferences && (
        <PreferencesModal
          onClose={() => setShowPreferences(false)}
        />
      )}
    </>
  )
}
