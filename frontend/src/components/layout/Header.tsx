import { useState, useRef, useEffect } from 'react'
import { Bell, Menu, MessageSquare } from 'lucide-react'
import { Link } from 'react-router-dom'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import api from '@/services/api'
import { User as UserType } from '@/types'
import logoImage from '@/images/logo.png'
import UserMenu from '@/components/user/UserMenu'
import { format } from 'date-fns'
import { fr } from 'date-fns/locale'
import { getNotificationTargetPath } from '@/utils/notifications'

interface HeaderProps {
  user: UserType
  onLogout: () => void
  onMenuClick: () => void
}

const ROLE_COMMUNICATION_PATH: Record<string, string> = {
  ADMIN: '/admin/communication',
  TEACHER: '/teacher/communication',
  PARENT: '/parent/communication',
  STUDENT: '/student/communication',
  ACCOUNTANT: '/accountant',
  DISCIPLINE_OFFICER: '/discipline-officer/communication',
}

interface NotificationItem {
  id: number
  title: string
  message: string
  is_read: boolean
  created_at: string
  notification_type?: string | null
}

export default function Header({ user, onLogout, onMenuClick }: HeaderProps) {
  const [notificationOpen, setNotificationOpen] = useState(false)
  const notificationRef = useRef<HTMLDivElement>(null)
  const queryClient = useQueryClient()

  const { data: notificationsData } = useQuery({
    queryKey: ['header-notifications'],
    queryFn: async () => {
      const res = await api.get('/communication/notifications/', { params: { page_size: 10 } })
      return res.data
    },
  })

  const markAllReadMutation = useMutation({
    mutationFn: () => api.post('/communication/notifications/mark_all_read/'),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['header-notifications'] })
      queryClient.invalidateQueries({ queryKey: ['communication-notifications'] })
    },
  })

  const markOneReadMutation = useMutation({
    mutationFn: (id: number) => api.post(`/communication/notifications/${id}/mark_read/`),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['header-notifications'] })
      queryClient.invalidateQueries({ queryKey: ['communication-notifications'] })
    },
  })

  const notifications: NotificationItem[] = Array.isArray(notificationsData)
    ? notificationsData
    : (notificationsData?.results ?? [])
  const unreadCount = notifications.filter((n) => !n.is_read).length

  const handleNotificationClick = (n: NotificationItem) => {
    setNotificationOpen(false)
    if (!n.is_read) markOneReadMutation.mutate(n.id)
  }

  useEffect(() => {
    const handleClickOutside = (e: MouseEvent) => {
      if (notificationRef.current && !notificationRef.current.contains(e.target as Node)) {
        setNotificationOpen(false)
      }
    }
    if (notificationOpen) document.addEventListener('mousedown', handleClickOutside)
    return () => document.removeEventListener('mousedown', handleClickOutside)
  }, [notificationOpen])

  const communicationPath = ROLE_COMMUNICATION_PATH[user.role] || '/'

  const roleLabels: Record<string, string> = {
    ADMIN: 'Administrateur',
    TEACHER: 'Enseignant',
    PARENT: 'Parent',
    STUDENT: 'Élève',
    ACCOUNTANT: 'Comptable',
    DISCIPLINE_OFFICER: 'Officier de discipline',
  }

  // Nom de l'école ou fallback
  const schoolName = user.school?.name || 'École'
  
  // Logo de l'école - vérifier que c'est une URL valide
  const schoolLogoValue = user.school?.logo
  const hasSchoolLogo = schoolLogoValue && 
                        typeof schoolLogoValue === 'string' && 
                        schoolLogoValue.trim() !== '' &&
                        (schoolLogoValue.startsWith('http') || schoolLogoValue.startsWith('/'))
  
  const schoolLogo = hasSchoolLogo ? schoolLogoValue : null

  return (
    <header className="bg-eschool-header border-b border-eschool-header-text/20 sticky top-0 z-50 transition-colors">
      <div className="px-3 sm:px-6 py-3 sm:py-4 flex items-center justify-between">
        <div className="flex items-center space-x-2 sm:space-x-4 min-w-0 flex-1">
          {/* Bouton menu hamburger pour mobile */}
          <button
            onClick={onMenuClick}
            className="lg:hidden p-2 text-eschool-header-text hover:opacity-80 transition-colors flex-shrink-0"
            aria-label="Toggle menu"
          >
            <Menu className="w-6 h-6" />
          </button>
          
          {/* Logo E-School (logo par défaut) */}
          <img 
            src={logoImage} 
            alt="E-School" 
            className="h-10 sm:h-12 lg:h-16 w-auto flex-shrink-0"
          />
          
          {/* Nom et logo de l'école */}
          {user.school && (
            <div className="flex items-center space-x-2 sm:space-x-3 border-l border-eschool-header-text/30 pl-2 sm:pl-4 min-w-0 flex-1">
              {schoolLogo ? (
                <img 
                  src={schoolLogo} 
                  alt={schoolName}
                  className="h-8 sm:h-10 lg:h-12 w-auto max-w-[120px] sm:max-w-[150px] lg:max-w-[180px] object-contain flex-shrink-0"
                  onError={(e) => {
                    const target = e.currentTarget
                    target.style.display = 'none'
                    const placeholder = target.nextElementSibling as HTMLElement
                    if (placeholder) {
                      placeholder.style.display = 'flex'
                    }
                  }}
                />
              ) : null}
              <div 
                className={`h-8 sm:h-10 lg:h-12 w-8 sm:w-10 lg:w-12 rounded-full bg-eschool-avatar flex items-center justify-center shadow-md flex-shrink-0 ${schoolLogo ? 'hidden' : ''}`}
              >
                <span className="text-eschool-avatar-text font-bold text-sm sm:text-base lg:text-lg">
                  {schoolName.charAt(0).toUpperCase()}
                </span>
              </div>
              <span className="text-sm sm:text-base lg:text-lg font-bold text-eschool-header-text uppercase tracking-wider leading-tight truncate">
                {schoolName}
              </span>
            </div>
          )}
        </div>
        
        <div className="flex items-center space-x-2 sm:space-x-4 flex-shrink-0">
          <div className="relative" ref={notificationRef}>
            <button
              type="button"
              onClick={() => setNotificationOpen((o) => !o)}
              className="p-2 text-eschool-header-text hover:opacity-80 relative transition-colors rounded-lg hover:bg-eschool-header-text/10"
              aria-label="Notifications"
            >
              <Bell className="w-5 h-5" />
              {unreadCount > 0 && (
                <span className="absolute top-0.5 right-0.5 min-w-[18px] h-[18px] px-1 flex items-center justify-center bg-red-500 text-white text-xs font-medium rounded-full">
                  {unreadCount > 99 ? '99+' : unreadCount}
                </span>
              )}
            </button>
            {notificationOpen && (
              <div className="absolute right-0 mt-2 w-80 sm:w-96 bg-eschool-header rounded-lg shadow-lg border border-eschool-header-text/20 py-2 z-50 max-h-[80vh] overflow-hidden flex flex-col">
                <div className="px-4 py-2 border-b border-eschool-header-text/20 flex items-center justify-between">
                  <span className="font-semibold text-eschool-header-text">Notifications</span>
                  {unreadCount > 0 && (
                    <button
                      type="button"
                      onClick={() => markAllReadMutation.mutate()}
                      disabled={markAllReadMutation.isPending}
                      className="text-xs text-eschool-body hover:underline"
                    >
                      Tout marquer lu
                    </button>
                  )}
                </div>
                <div className="overflow-y-auto flex-1">
                  {notifications.length === 0 ? (
                    <p className="px-4 py-6 text-sm text-eschool-header-text/70 text-center">
                      Aucune notification
                    </p>
                  ) : (
                    notifications.map((n) => {
                      const targetPath = getNotificationTargetPath(user.role, n.notification_type ?? null)
                      return (
                        <Link
                          key={n.id}
                          to={targetPath}
                          onClick={() => handleNotificationClick(n)}
                          className={`block px-4 py-3 hover:bg-eschool-header-text/10 border-b border-eschool-header-text/10 last:border-0 ${!n.is_read ? 'bg-eschool-body/10' : ''}`}
                        >
                          <p className="font-medium text-eschool-header-text text-sm">{n.title}</p>
                          <p className="text-xs text-eschool-header-text/80 line-clamp-2 mt-0.5">{n.message}</p>
                          <p className="text-xs text-eschool-header-text/60 mt-1">
                            {format(new Date(n.created_at), 'dd MMM à HH:mm', { locale: fr })}
                          </p>
                        </Link>
                      )
                    })
                  )}
                </div>
                <Link
                  to={communicationPath}
                  onClick={() => setNotificationOpen(false)}
                  className="flex items-center justify-center gap-2 px-4 py-3 text-sm font-medium text-eschool-body hover:bg-eschool-header-text/10 border-t border-eschool-header-text/20"
                >
                  <MessageSquare className="w-4 h-4" />
                  Voir toute la communication
                </Link>
              </div>
            )}
          </div>
          
          <div className="flex items-center space-x-2 sm:space-x-3">
            <div className="text-right hidden sm:block">
              <p className="text-sm font-medium text-eschool-header-text truncate max-w-[120px] lg:max-w-none">
                {user.first_name} {user.last_name}
              </p>
              <p className="text-xs text-eschool-header-text/70">{roleLabels[user.role] || user.role}</p>
            </div>
            <UserMenu user={user} onLogout={onLogout} />
          </div>
        </div>
      </div>
    </header>
  )
}
