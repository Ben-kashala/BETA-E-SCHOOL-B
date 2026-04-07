import { useState, useEffect } from 'react'
import { useNavigate, useSearchParams } from 'react-router-dom'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import api from '@/services/api'
import { Card } from '@/components/ui/Card'
import { MessageSquare, Bell, Megaphone, Send, Plus, X, CheckCircle, Reply, Edit2, Trash2 } from 'lucide-react'
import toast from 'react-hot-toast'
import { format } from 'date-fns'
import { fr } from 'date-fns/locale'
import { cn } from '@/utils/cn'
import { useAuthStore } from '@/store/authStore'
import { getNotificationTargetPath } from '@/utils/notifications'

interface Message {
  id: number
  sender: number
  sender_name: string
  recipient: number
  recipient_name: string
  subject: string
  message: string
  is_read: boolean
  read_at: string | null
  created_at: string
}

interface Announcement {
  id: number
  title: string
  message: string
  target_audience: string
  is_published: boolean
  published_at: string | null
  created_by_name: string
  created_at: string
}

interface Notification {
  id: number
  notification_type: string
  title: string
  message: string
  is_read: boolean
  read_at: string | null
  created_at: string
}

const TARGET_LABELS: Record<string, string> = {
  ALL: 'Tous',
  STUDENTS: 'Élèves',
  PARENTS: 'Parents',
  TEACHERS: 'Enseignants',
  ADMINS: 'Administrateurs',
}

export default function AdminCommunication() {
  const queryClient = useQueryClient()
  const navigate = useNavigate()
  const [searchParams, setSearchParams] = useSearchParams()
  const { user } = useAuthStore()
  const [activeTab, setActiveTab] = useState<'messages' | 'announcements' | 'notifications' | 'inter_school'>('announcements')
  const [showMessageForm, setShowMessageForm] = useState(false)

  // Ouvrir l'onglet indiqué par l'URL (?tab=messages | announcements | notifications)
  useEffect(() => {
    const tab = searchParams.get('tab')
    if (tab === 'messages' || tab === 'announcements' || tab === 'notifications' || tab === 'inter_school') {
      setActiveTab(tab)
    }
  }, [searchParams])
  const [showAnnouncementForm, setShowAnnouncementForm] = useState(false)
  const [selectedMessage, setSelectedMessage] = useState<Message | null>(null)
  const [selectedAnnouncement, setSelectedAnnouncement] = useState<Announcement | null>(null)
  const [messageFilter, setMessageFilter] = useState<'all' | 'sent' | 'received'>('received')
  const [replyToMessage, setReplyToMessage] = useState<Message | null>(null)
  const [announcementFilter, setAnnouncementFilter] = useState<'all' | 'published' | 'draft'>('all')
  const [selectedInterSchoolId, setSelectedInterSchoolId] = useState<string>('')
  const [interSchoolSubject, setInterSchoolSubject] = useState('')
  const [interSchoolBody, setInterSchoolBody] = useState('')

  // Récupérer les messages
  const { data: messagesData, isLoading: messagesLoading } = useQuery({
    queryKey: ['communication-messages', messageFilter],
    queryFn: async () => {
      const response = await api.get('/communication/messages/')
      return response.data
    },
  })

  const messages = Array.isArray(messagesData) ? messagesData : (messagesData?.results || [])
  const filteredMessages = messages.filter((msg: Message) => {
    if (!user) return false
    if (messageFilter === 'sent') return msg.sender === user.id
    if (messageFilter === 'received') return msg.recipient === user.id
    return true
  })

  // Récupérer les annonces
  const { data: announcementsData, isLoading: announcementsLoading } = useQuery({
    queryKey: ['communication-announcements'],
    queryFn: async () => {
      const response = await api.get('/communication/announcements/')
      return response.data
    },
  })

  const announcements = Array.isArray(announcementsData) ? announcementsData : (announcementsData?.results || [])
  const filteredAnnouncements = announcements.filter((ann: Announcement) => {
    if (announcementFilter === 'published') return ann.is_published
    if (announcementFilter === 'draft') return !ann.is_published
    return true
  })

  // Récupérer les notifications
  const { data: notificationsData, isLoading: notificationsLoading } = useQuery({
    queryKey: ['communication-notifications'],
    queryFn: async () => {
      const response = await api.get('/communication/notifications/')
      return response.data
    },
  })

  const notifications = Array.isArray(notificationsData) ? notificationsData : (notificationsData?.results || [])

  // Récupérer les utilisateurs pour envoyer des messages (l'admin peut voir tous les utilisateurs de l'école)
  const { data: usersData, isLoading: usersLoading } = useQuery({
    queryKey: ['users-for-messages'],
    queryFn: async () => {
      const allUsers: any[] = []
      let nextUrl: string | null = '/auth/users/?is_active=true&page_size=200'
      let guard = 0

      // Récupère toutes les pages pour éviter de perdre des destinataires
      // (ex: enseignants au-delà de la première page).
      while (nextUrl && guard < 50) {
        const response: any = await api.get(nextUrl)
        const data: any = response.data

        if (Array.isArray(data)) {
          allUsers.push(...data)
          nextUrl = null
        } else {
          const pageItems = Array.isArray(data?.results) ? data.results : []
          allUsers.push(...pageItems)
          nextUrl = typeof data?.next === 'string' ? data.next : null
        }
        guard += 1
      }

      return allUsers
    },
    enabled: showMessageForm,
  })

  const rawUsers = Array.isArray(usersData) ? usersData : []

  // Pour le promoteur, limiter les destinataires au personnel (pas d'élèves ni de parents)
  const users = rawUsers.filter((u: any) => {
    if (!user) return false
    if (user.role === 'PROMOTER') {
      return u.role !== 'STUDENT' && u.role !== 'PARENT'
    }
    return true
  })
  
  const roleLabels: Record<string, string> = {
    TEACHER: 'Enseignant',
    ADMIN: 'Administrateur',
    ACCOUNTANT: 'Comptable',
    DISCIPLINE_OFFICER: 'Chargé de discipline',
    PARENT: 'Parent',
    STUDENT: 'Élève',
  }

  // Écoles pour la collaboration inter-école
  const { data: schoolsData, isLoading: schoolsLoading } = useQuery({
    queryKey: ['all-schools-for-transfer'],
    queryFn: async () => {
      const response = await api.get('/schools/all-for-transfer/')
      return response.data
    },
    enabled: activeTab === 'inter_school' && !!user,
  })

  const schools = Array.isArray(schoolsData) ? schoolsData : (schoolsData?.results || [])

  // Envoyer un message
  const sendMessageMutation = useMutation({
    mutationFn: async (data: any) => {
      const response = await api.post('/communication/messages/', data)
      return response.data
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['communication-messages'] })
      setShowMessageForm(false)
      setReplyToMessage(null)
      toast.success('Message envoyé avec succès')
    },
    onError: (error: any) => {
      const errorData = error?.response?.data
      let errorMessage = 'Erreur lors de l\'envoi du message'
      
      if (errorData) {
        if (errorData.detail) {
          errorMessage = errorData.detail
        } else if (errorData.recipient) {
          errorMessage = `Destinataire: ${Array.isArray(errorData.recipient) ? errorData.recipient.join(', ') : errorData.recipient}`
        } else if (errorData.subject) {
          errorMessage = `Sujet: ${Array.isArray(errorData.subject) ? errorData.subject.join(', ') : errorData.subject}`
        } else if (errorData.message) {
          errorMessage = `Message: ${Array.isArray(errorData.message) ? errorData.message.join(', ') : errorData.message}`
        } else if (errorData.non_field_errors) {
          errorMessage = Array.isArray(errorData.non_field_errors) ? errorData.non_field_errors.join(', ') : errorData.non_field_errors
        }
      }
      
      toast.error(errorMessage)
      console.error('Erreur envoi message:', errorData || error)
    },
  })

  // Envoyer un message inter-école
  const sendInterSchoolMutation = useMutation({
    mutationFn: async () => {
      const payload = {
        target_school: selectedInterSchoolId,
        subject: interSchoolSubject,
        message: interSchoolBody,
      }
      const response = await api.post('/communication/messages/inter-school/', payload)
      return response.data
    },
    onSuccess: () => {
      setInterSchoolBody('')
      setInterSchoolSubject('')
      setSelectedInterSchoolId('')
      toast.success('Message inter-école envoyé avec succès')
      queryClient.invalidateQueries({ queryKey: ['communication-messages'] })
    },
    onError: (error: any) => {
      const errorData = error?.response?.data
      let errorMessage = "Erreur lors de l'envoi du message inter-école"
      if (errorData?.detail) {
        errorMessage = errorData.detail
      } else if (typeof errorData === 'object') {
        const firstKey = Object.keys(errorData)[0]
        if (firstKey) {
          const val = errorData[firstKey]
          errorMessage =
            Array.isArray(val) ? val.join(', ') : typeof val === 'string' ? val : errorMessage
        }
      }
      toast.error(errorMessage)
      console.error('Erreur envoi message inter-école:', errorData || error)
    },
  })

  // Marquer un message comme lu
  const markReadMutation = useMutation({
    mutationFn: async (id: number) => {
      const response = await api.post(`/communication/messages/${id}/mark_read/`)
      return response.data
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['communication-messages'] })
      queryClient.invalidateQueries({ queryKey: ['communication-notifications'] })
    },
  })

  // Marquer une notification comme lue (au clic sur une notification)
  const markNotificationReadMutation = useMutation({
    mutationFn: async (id: number) => {
      const response = await api.post(`/communication/notifications/${id}/mark_read/`)
      return response.data
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['communication-notifications'] })
      queryClient.invalidateQueries({ queryKey: ['header-notifications'] })
    },
  })

  // Marquer toutes les notifications comme lues
  const markAllNotificationsReadMutation = useMutation({
    mutationFn: async () => {
      const response = await api.post('/communication/notifications/mark_all_read/')
      return response.data
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['communication-notifications'] })
      toast.success('Toutes les notifications ont été marquées comme lues')
    },
  })

  // Créer une annonce
  const createAnnouncementMutation = useMutation({
    mutationFn: (data: any) => api.post('/communication/announcements/', data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['communication-announcements'] })
      toast.success('Annonce créée avec succès')
      setShowAnnouncementForm(false)
      setSelectedAnnouncement(null)
    },
    onError: (e: any) => {
      const errorMsg = e?.response?.data?.detail || e?.response?.data?.message || 'Erreur lors de la création de l\'annonce'
      toast.error(errorMsg)
    },
  })

  // Modifier une annonce
  const updateAnnouncementMutation = useMutation({
    mutationFn: ({ id, data }: { id: number; data: any }) => api.patch(`/communication/announcements/${id}/`, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['communication-announcements'] })
      toast.success('Annonce modifiée avec succès')
      setShowAnnouncementForm(false)
      setSelectedAnnouncement(null)
    },
    onError: (e: any) => {
      const errorMsg = e?.response?.data?.detail || e?.response?.data?.message || 'Erreur lors de la modification de l\'annonce'
      toast.error(errorMsg)
    },
  })

  // Publier une annonce
  const publishAnnouncementMutation = useMutation({
    mutationFn: (id: number) => api.post(`/communication/announcements/${id}/publish/`),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['communication-announcements'] })
      toast.success('Annonce publiée avec succès')
    },
    onError: (e: any) => {
      const errorMsg = e?.response?.data?.detail || e?.response?.data?.message || 'Erreur lors de la publication'
      toast.error(errorMsg)
    },
  })

  // Supprimer une annonce
  const deleteAnnouncementMutation = useMutation({
    mutationFn: (id: number) => api.delete(`/communication/announcements/${id}/`),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['communication-announcements'] })
      toast.success('Annonce supprimée avec succès')
    },
    onError: (e: any) => {
      const errorMsg = e?.response?.data?.detail || e?.response?.data?.message || 'Erreur lors de la suppression'
      toast.error(errorMsg)
    },
  })

  const handleSendMessage = (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault()
    const formData = new FormData(e.currentTarget)
    const recipientValue = formData.get('recipient') as string
    const recipientId = recipientValue ? parseInt(recipientValue, 10) : null
    
    if (!recipientId || isNaN(recipientId)) {
      toast.error('Veuillez sélectionner un destinataire')
      return
    }
    
    const messageData = {
      recipient: recipientId,
      subject: formData.get('subject') as string,
      message: formData.get('message') as string,
    }
    sendMessageMutation.mutate(messageData)
  }

  const handleViewMessage = (message: Message) => {
    setSelectedMessage(message)
    if (!message.is_read && messageFilter === 'received') {
      markReadMutation.mutate(message.id)
    }
  }

  const handleReply = (message: Message) => {
    setSelectedMessage(null)
    setReplyToMessage(message)
    setShowMessageForm(true)
  }

  const handleCreateAnnouncement = (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault()
    const form = e.currentTarget
    const data = {
      title: (form.querySelector('[name="title"]') as HTMLInputElement).value,
      message: (form.querySelector('[name="message"]') as HTMLTextAreaElement).value,
      target_audience: (form.querySelector('[name="target_audience"]') as HTMLSelectElement).value,
      send_notification: (form.querySelector('[name="send_notification"]') as HTMLInputElement).checked,
    }
    
    if (selectedAnnouncement) {
      updateAnnouncementMutation.mutate({ id: selectedAnnouncement.id, data })
    } else {
      createAnnouncementMutation.mutate(data)
    }
  }

  const handleEditAnnouncement = (announcement: Announcement) => {
    setSelectedAnnouncement(announcement)
    setShowAnnouncementForm(true)
  }

  const handleDeleteAnnouncement = (id: number) => {
    if (confirm('Êtes-vous sûr de vouloir supprimer cette annonce ?')) {
      deleteAnnouncementMutation.mutate(id)
    }
  }

  const unreadCount = notifications.filter((n: Notification) => !n.is_read).length
  const unreadMessagesCount = messages.filter((m: Message) => !m.is_read && messageFilter === 'received').length

  return (
    <div>
      <h1 className="text-2xl sm:text-3xl font-bold text-gray-900 dark:text-gray-100 mb-4 sm:mb-6">Communication</h1>

      {/* Onglets */}
      <div className="flex space-x-1 mb-6 border-b border-gray-200 dark:border-gray-700 overflow-x-auto">
        <button
          onClick={() => {
            setActiveTab('messages')
            setSearchParams({ tab: 'messages' })
          }}
          className={cn(
            'px-4 py-2 font-medium text-sm transition-colors relative whitespace-nowrap',
            activeTab === 'messages'
              ? 'text-blue-600 dark:text-blue-400 border-b-2 border-blue-600 dark:border-blue-400'
              : 'text-gray-600 dark:text-gray-400 hover:text-gray-900 dark:hover:text-gray-200'
          )}
        >
          <div className="flex items-center gap-2">
            <MessageSquare className="w-4 h-4" />
            Messages
            {unreadMessagesCount > 0 && (
              <span className="bg-red-500 text-white text-xs rounded-full px-2 py-0.5">
                {unreadMessagesCount}
              </span>
            )}
          </div>
        </button>
        <button
          onClick={() => {
            setActiveTab('announcements')
            setSearchParams({ tab: 'announcements' })
          }}
          className={cn(
            'px-4 py-2 font-medium text-sm transition-colors whitespace-nowrap',
            activeTab === 'announcements'
              ? 'text-blue-600 dark:text-blue-400 border-b-2 border-blue-600 dark:border-blue-400'
              : 'text-gray-600 dark:text-gray-400 hover:text-gray-900 dark:hover:text-gray-200'
          )}
        >
          <div className="flex items-center gap-2">
            <Megaphone className="w-4 h-4" />
            Annonces
          </div>
        </button>
        <button
          onClick={() => {
            setActiveTab('inter_school')
            setSearchParams({ tab: 'inter_school' })
          }}
          className={cn(
            'px-4 py-2 font-medium text-sm transition-colors whitespace-nowrap',
            activeTab === 'inter_school'
              ? 'text-blue-600 dark:text-blue-400 border-b-2 border-blue-600 dark:border-blue-400'
              : 'text-gray-600 dark:text-gray-400 hover:text-gray-900 dark:hover:text-gray-200'
          )}
        >
          <div className="flex items-center gap-2">
            <MessageSquare className="w-4 h-4" />
            Collaboration inter-école
          </div>
        </button>
        <button
          onClick={() => {
            setActiveTab('notifications')
            setSearchParams({ tab: 'notifications' })
          }}
          className={cn(
            'px-4 py-2 font-medium text-sm transition-colors whitespace-nowrap',
            activeTab === 'notifications'
              ? 'text-blue-600 dark:text-blue-400 border-b-2 border-blue-600 dark:border-blue-400'
              : 'text-gray-600 dark:text-gray-400 hover:text-gray-900 dark:hover:text-gray-200'
          )}
        >
          <div className="flex items-center gap-2">
            <Bell className="w-4 h-4" />
            Notifications
            {unreadCount > 0 && (
              <span className="bg-red-500 text-white text-xs rounded-full px-2 py-0.5">
                {unreadCount}
              </span>
            )}
          </div>
        </button>
      </div>

      {/* Contenu des onglets */}
      {activeTab === 'messages' && (
        <div className="space-y-6">
          <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
            <div className="flex gap-2 flex-wrap">
              <button
                onClick={() => setMessageFilter('received')}
                className={cn(
                  'px-4 py-2 rounded-lg text-sm font-medium transition-colors',
                  messageFilter === 'received'
                    ? 'bg-blue-600 text-white'
                    : 'bg-gray-100 dark:bg-gray-700 text-gray-700 dark:text-gray-300'
                )}
              >
                Reçus
              </button>
              <button
                onClick={() => setMessageFilter('sent')}
                className={cn(
                  'px-4 py-2 rounded-lg text-sm font-medium transition-colors',
                  messageFilter === 'sent'
                    ? 'bg-blue-600 text-white'
                    : 'bg-gray-100 dark:bg-gray-700 text-gray-700 dark:text-gray-300'
                )}
              >
                Envoyés
              </button>
              <button
                onClick={() => setMessageFilter('all')}
                className={cn(
                  'px-4 py-2 rounded-lg text-sm font-medium transition-colors',
                  messageFilter === 'all'
                    ? 'bg-blue-600 text-white'
                    : 'bg-gray-100 dark:bg-gray-700 text-gray-700 dark:text-gray-300'
                )}
              >
                Tous
              </button>
            </div>
            <button
              onClick={() => {
                setShowMessageForm(true)
                setReplyToMessage(null)
              }}
              className="btn btn-primary flex items-center gap-2"
            >
              <Plus className="w-4 h-4" />
              Nouveau message
            </button>
          </div>

          <Card>
            {messagesLoading ? (
              <div className="p-8 text-center text-gray-500 dark:text-gray-400">Chargement...</div>
            ) : filteredMessages.length === 0 ? (
              <div className="p-8 text-center text-gray-500 dark:text-gray-400">
                Aucun message {messageFilter === 'received' ? 'reçu' : messageFilter === 'sent' ? 'envoyé' : ''}
              </div>
            ) : (
              <div className="divide-y divide-gray-200 dark:divide-gray-700">
                {filteredMessages.map((message: Message) => (
                  <div
                    key={message.id}
                    onClick={() => handleViewMessage(message)}
                    className={cn(
                      'p-4 hover:bg-gray-50 dark:hover:bg-gray-700/50 cursor-pointer transition-colors',
                      !message.is_read && messageFilter === 'received' && 'bg-blue-50 dark:bg-blue-900/20'
                    )}
                  >
                    <div className="flex items-start justify-between">
                      <div className="flex-1">
                        <div className="flex items-center gap-2 mb-1">
                          <span className="font-semibold text-gray-900 dark:text-gray-100">
                            {messageFilter === 'received' ? message.sender_name : message.recipient_name}
                          </span>
                          {!message.is_read && messageFilter === 'received' && (
                            <span className="w-2 h-2 bg-blue-600 rounded-full"></span>
                          )}
                        </div>
                        <p className="font-medium text-gray-900 dark:text-gray-100 mb-1">{message.subject}</p>
                        <p className="text-sm text-gray-600 dark:text-gray-400 line-clamp-2">{message.message}</p>
                        <p className="text-xs text-gray-500 dark:text-gray-500 mt-2">
                          {format(new Date(message.created_at), 'dd MMM yyyy à HH:mm', { locale: fr })}
                        </p>
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </Card>
        </div>
      )}

      {activeTab === 'announcements' && (
        <div className="space-y-6">
          <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
            <div className="flex gap-2 flex-wrap">
              <button
                onClick={() => setAnnouncementFilter('all')}
                className={cn(
                  'px-4 py-2 rounded-lg text-sm font-medium transition-colors',
                  announcementFilter === 'all'
                    ? 'bg-blue-600 text-white'
                    : 'bg-gray-100 dark:bg-gray-700 text-gray-700 dark:text-gray-300'
                )}
              >
                Toutes
              </button>
              <button
                onClick={() => setAnnouncementFilter('published')}
                className={cn(
                  'px-4 py-2 rounded-lg text-sm font-medium transition-colors',
                  announcementFilter === 'published'
                    ? 'bg-blue-600 text-white'
                    : 'bg-gray-100 dark:bg-gray-700 text-gray-700 dark:text-gray-300'
                )}
              >
                Publiées
              </button>
              <button
                onClick={() => setAnnouncementFilter('draft')}
                className={cn(
                  'px-4 py-2 rounded-lg text-sm font-medium transition-colors',
                  announcementFilter === 'draft'
                    ? 'bg-blue-600 text-white'
                    : 'bg-gray-100 dark:bg-gray-700 text-gray-700 dark:text-gray-300'
                )}
              >
                Brouillons
              </button>
            </div>
            <button
              onClick={() => {
                setShowAnnouncementForm(true)
                setSelectedAnnouncement(null)
              }}
              className="btn btn-primary flex items-center gap-2"
            >
              <Plus className="w-4 h-4" />
              Nouvelle annonce
            </button>
          </div>

          <Card>
            {announcementsLoading ? (
              <div className="p-8 text-center text-gray-500 dark:text-gray-400">Chargement...</div>
            ) : filteredAnnouncements.length === 0 ? (
              <div className="p-8 text-center text-gray-500 dark:text-gray-400">Aucune annonce disponible</div>
            ) : (
              <div className="space-y-4">
                {filteredAnnouncements.map((announcement: Announcement) => (
                  <div
                    key={announcement.id}
                    className="p-4 border border-gray-200 dark:border-gray-700 rounded-lg hover:bg-gray-50 dark:hover:bg-gray-700/50 transition-colors"
                  >
                    <div className="flex items-start justify-between mb-2">
                      <div className="flex-1">
                        <div className="flex items-center gap-2 mb-1">
                          <h3 className="text-lg font-semibold text-gray-900 dark:text-gray-100">{announcement.title}</h3>
                          {announcement.is_published ? (
                            <span className="badge badge-success">Publiée</span>
                          ) : (
                            <span className="badge badge-warning">Brouillon</span>
                          )}
                          <span className="text-xs text-gray-500 dark:text-gray-400">
                            {TARGET_LABELS[announcement.target_audience] || announcement.target_audience}
                          </span>
                        </div>
                        <p className="text-gray-700 dark:text-gray-300 mb-2">{announcement.message}</p>
                        <p className="text-xs text-gray-500 dark:text-gray-400">
                          Par {announcement.created_by_name} • {format(new Date(announcement.created_at), 'dd MMM yyyy à HH:mm', { locale: fr })}
                          {announcement.published_at && (
                            <> • Publiée le {format(new Date(announcement.published_at), 'dd MMM yyyy à HH:mm', { locale: fr })}</>
                          )}
                        </p>
                      </div>
                    </div>
                    <div className="flex gap-2 mt-3 pt-3 border-t border-gray-200 dark:border-gray-700">
                      {!announcement.is_published && (
                        <button
                          onClick={() => publishAnnouncementMutation.mutate(announcement.id)}
                          disabled={publishAnnouncementMutation.isPending}
                          className="btn btn-primary text-sm flex items-center gap-2"
                        >
                          <CheckCircle className="w-4 h-4" />
                          Publier
                        </button>
                      )}
                      <button
                        onClick={() => handleEditAnnouncement(announcement)}
                        className="btn btn-secondary text-sm flex items-center gap-2"
                      >
                        <Edit2 className="w-4 h-4" />
                        Modifier
                      </button>
                      <button
                        onClick={() => handleDeleteAnnouncement(announcement.id)}
                        disabled={deleteAnnouncementMutation.isPending}
                        className="btn btn-danger text-sm flex items-center gap-2"
                      >
                        <Trash2 className="w-4 h-4" />
                        Supprimer
                      </button>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </Card>
        </div>
      )}

      {activeTab === 'notifications' && (
        <div className="space-y-6">
          {unreadCount > 0 && (
            <div className="flex justify-end">
              <button
                onClick={() => markAllNotificationsReadMutation.mutate()}
                className="btn btn-secondary text-sm flex items-center gap-2"
                disabled={markAllNotificationsReadMutation.isPending}
              >
                <CheckCircle className="w-4 h-4" />
                Marquer tout comme lu
              </button>
            </div>
          )}

          <Card>
            {notificationsLoading ? (
              <div className="p-8 text-center text-gray-500 dark:text-gray-400">Chargement...</div>
            ) : notifications.length === 0 ? (
              <div className="p-8 text-center text-gray-500 dark:text-gray-400">Aucune notification</div>
            ) : (
              <div className="divide-y divide-gray-200 dark:divide-gray-700">
                {notifications.map((notification: Notification) => (
                  <div
                    key={notification.id}
                    onClick={() => {
                      if (!notification.is_read) {
                        markNotificationReadMutation.mutate(notification.id)
                      }
                      navigate(getNotificationTargetPath(user?.role ?? '', notification.notification_type))
                    }}
                    className={cn(
                      'p-4 hover:bg-gray-50 dark:hover:bg-gray-700/50 cursor-pointer transition-colors',
                      !notification.is_read && 'bg-blue-50 dark:bg-blue-900/20'
                    )}
                  >
                    <div className="flex items-start gap-3">
                      {!notification.is_read && <span className="w-2 h-2 bg-blue-600 rounded-full mt-2"></span>}
                      <div className="flex-1">
                        <div className="flex items-center gap-2 mb-1">
                          <span className="font-semibold text-gray-900 dark:text-gray-100">
                            {notification.title}
                          </span>
                        </div>
                        <p className="text-gray-700 dark:text-gray-300">{notification.message}</p>
                        <p className="text-xs text-gray-500 dark:text-gray-500 mt-2">
                          {format(new Date(notification.created_at), 'dd MMM yyyy à HH:mm', { locale: fr })}
                        </p>
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </Card>
        </div>
      )}

      {activeTab === 'inter_school' && (
        <div className="space-y-6">
          <Card className="p-4 sm:p-6">
            <h2 className="text-lg font-semibold text-gray-900 dark:text-gray-100 mb-4">
              Envoyer un message à une autre école
            </h2>
            <p className="text-sm text-gray-600 dark:text-gray-400 mb-4">
              Sélectionnez une école de la plateforme et envoyez un message aux administrateurs de
              cette école. Les réponses arriveront dans l&apos;onglet <strong>Messages</strong>.
            </p>
            <form
              className="space-y-4"
              onSubmit={(e) => {
                e.preventDefault()
                if (!selectedInterSchoolId) {
                  toast.error("Veuillez sélectionner l'école cible.")
                  return
                }
                if (!interSchoolSubject.trim() || !interSchoolBody.trim()) {
                  toast.error('Sujet et message sont obligatoires.')
                  return
                }
                sendInterSchoolMutation.mutate()
              }}
            >
              <div>
                <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                  École cible <span className="text-red-500">*</span>
                </label>
                {schoolsLoading ? (
                  <div className="input">Chargement des écoles...</div>
                ) : schools.length === 0 ? (
                  <div className="text-sm text-gray-500 dark:text-gray-400">
                    Aucune autre école disponible ou accès restreint.
                  </div>
                ) : (
                  <select
                    className="input"
                    value={selectedInterSchoolId}
                    onChange={(e) => setSelectedInterSchoolId(e.target.value)}
                    required
                  >
                    <option value="">Sélectionner une école</option>
                    {schools.map((s: any) => (
                      <option key={s.id} value={s.id}>
                        {s.name} {s.city ? `(${s.city})` : ''} {s.code ? `- ${s.code}` : ''}
                      </option>
                    ))}
                  </select>
                )}
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                  Sujet <span className="text-red-500">*</span>
                </label>
                <input
                  type="text"
                  className="input"
                  value={interSchoolSubject}
                  onChange={(e) => setInterSchoolSubject(e.target.value)}
                  placeholder="Objet de la collaboration"
                  required
                />
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                  Message <span className="text-red-500">*</span>
                </label>
                <textarea
                  className="input"
                  rows={6}
                  value={interSchoolBody}
                  onChange={(e) => setInterSchoolBody(e.target.value)}
                  placeholder="Contenu du message..."
                  required
                />
              </div>
              <div className="flex justify-end">
                <button
                  type="submit"
                  disabled={sendInterSchoolMutation.isPending}
                  className="btn btn-primary flex items-center gap-2"
                >
                  <Send className="w-4 h-4" />
                  {sendInterSchoolMutation.isPending ? 'Envoi...' : 'Envoyer'}
                </button>
              </div>
            </form>
          </Card>
        </div>
      )}

      {/* Modal pour envoyer un message */}
      {showMessageForm && (
        <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50 p-4">
          <div className="bg-white dark:bg-gray-800 rounded-lg p-6 max-w-2xl w-full max-h-[90vh] overflow-y-auto">
            <div className="flex justify-between items-center mb-4">
              <h2 className="text-xl font-bold text-gray-900 dark:text-gray-100">Nouveau message</h2>
              <button
                onClick={() => {
                  setShowMessageForm(false)
                  setReplyToMessage(null)
                }}
                className="text-gray-400 hover:text-gray-600 dark:hover:text-gray-300"
              >
                <X className="w-6 h-6" />
              </button>
            </div>
            <form onSubmit={handleSendMessage} className="space-y-4">
              <div>
                <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                  Destinataire <span className="text-red-500">*</span>
                </label>
                {usersLoading ? (
                  <div className="w-full px-4 py-2 border border-gray-300 dark:border-gray-600 rounded-lg dark:bg-gray-700 text-gray-500">
                    Chargement...
                  </div>
                ) : users.length === 0 ? (
                  <div className="w-full px-4 py-2 border border-yellow-300 dark:border-yellow-600 rounded-lg bg-yellow-50 dark:bg-yellow-900/20 text-yellow-800 dark:text-yellow-200 text-sm">
                    Aucun utilisateur disponible
                  </div>
                ) : (
                  <select
                    name="recipient"
                    required
                    defaultValue={replyToMessage?.sender || ''}
                    className="input"
                  >
                    <option value="">Sélectionner un destinataire</option>
                    {users
                      .filter((u: any) => u.id !== user?.id)
                      .map((userOption: any) => (
                        <option key={userOption.id} value={userOption.id}>
                          {userOption.first_name} {userOption.last_name} ({roleLabels[userOption.role] || userOption.role})
                        </option>
                      ))}
                  </select>
                )}
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">Sujet</label>
                <input
                  type="text"
                  name="subject"
                  required
                  defaultValue={replyToMessage ? (replyToMessage.subject.startsWith('Re: ') ? replyToMessage.subject : `Re: ${replyToMessage.subject}`) : ''}
                  className="input"
                />
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">Message</label>
                <textarea
                  name="message"
                  required
                  rows={6}
                  className="input"
                />
              </div>
              <div className="flex justify-end gap-3">
                <button
                  type="button"
                  onClick={() => {
                    setShowMessageForm(false)
                    setReplyToMessage(null)
                  }}
                  className="btn btn-secondary"
                >
                  Annuler
                </button>
                <button
                  type="submit"
                  disabled={sendMessageMutation.isPending}
                  className="btn btn-primary flex items-center gap-2"
                >
                  <Send className="w-4 h-4" />
                  {sendMessageMutation.isPending ? 'Envoi...' : 'Envoyer'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* Modal pour voir un message */}
      {selectedMessage && (
        <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50 p-4">
          <div className="bg-white dark:bg-gray-800 rounded-lg p-6 max-w-2xl w-full max-h-[90vh] overflow-y-auto">
            <div className="flex justify-between items-center mb-4">
              <h2 className="text-xl font-bold text-gray-900 dark:text-gray-100">{selectedMessage.subject}</h2>
              <button
                onClick={() => setSelectedMessage(null)}
                className="text-gray-400 hover:text-gray-600 dark:hover:text-gray-300"
              >
                <X className="w-6 h-6" />
              </button>
            </div>
            <div className="space-y-4">
              <div>
                <span className="text-sm text-gray-600 dark:text-gray-400">De: </span>
                <span className="font-medium text-gray-900 dark:text-gray-100">{selectedMessage.sender_name}</span>
              </div>
              <div>
                <span className="text-sm text-gray-600 dark:text-gray-400">À: </span>
                <span className="font-medium text-gray-900 dark:text-gray-100">{selectedMessage.recipient_name}</span>
              </div>
              <div>
                <span className="text-sm text-gray-600 dark:text-gray-400">Date: </span>
                <span className="text-gray-900 dark:text-gray-100">
                  {format(new Date(selectedMessage.created_at), 'dd MMM yyyy à HH:mm', { locale: fr })}
                </span>
              </div>
              <div className="pt-4 border-t border-gray-200 dark:border-gray-700">
                <p className="text-gray-900 dark:text-gray-100 whitespace-pre-wrap">{selectedMessage.message}</p>
              </div>
              {messageFilter === 'received' && (
                <div className="pt-4 border-t border-gray-200 dark:border-gray-700 flex justify-end">
                  <button
                    onClick={() => handleReply(selectedMessage)}
                    className="btn btn-primary flex items-center gap-2"
                  >
                    <Reply className="w-4 h-4" />
                    Répondre
                  </button>
                </div>
              )}
            </div>
          </div>
        </div>
      )}

      {/* Modal pour créer/modifier une annonce */}
      {showAnnouncementForm && (
        <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50 p-4">
          <div className="bg-white dark:bg-gray-800 rounded-lg p-6 max-w-2xl w-full max-h-[90vh] overflow-y-auto">
            <div className="flex justify-between items-center mb-4">
              <h2 className="text-xl font-bold text-gray-900 dark:text-gray-100">
                {selectedAnnouncement ? 'Modifier l\'annonce' : 'Nouvelle annonce'}
              </h2>
              <button
                onClick={() => {
                  setShowAnnouncementForm(false)
                  setSelectedAnnouncement(null)
                }}
                className="text-gray-400 hover:text-gray-600 dark:hover:text-gray-300"
              >
                <X className="w-6 h-6" />
              </button>
            </div>
            <form onSubmit={handleCreateAnnouncement} className="space-y-4">
              <div>
                <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                  Titre <span className="text-red-500">*</span>
                </label>
                <input
                  type="text"
                  name="title"
                  required
                  defaultValue={selectedAnnouncement?.title || ''}
                  className="input"
                  placeholder="Titre de l'annonce"
                />
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                  Message <span className="text-red-500">*</span>
                </label>
                <textarea
                  name="message"
                  required
                  rows={6}
                  defaultValue={selectedAnnouncement?.message || ''}
                  className="input"
                  placeholder="Contenu de l'annonce"
                />
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                  Audience cible <span className="text-red-500">*</span>
                </label>
                <select
                  name="target_audience"
                  required
                  defaultValue={selectedAnnouncement?.target_audience || 'ALL'}
                  className="input"
                >
                  {Object.entries(TARGET_LABELS).map(([value, label]) => (
                    <option key={value} value={value}>
                      {label}
                    </option>
                  ))}
                </select>
              </div>
              <div className="flex items-center">
                <input
                  type="checkbox"
                  name="send_notification"
                  id="send_notification"
                  defaultChecked={true}
                  className="w-4 h-4 text-blue-600 bg-gray-100 border-gray-300 rounded focus:ring-blue-500"
                />
                <label htmlFor="send_notification" className="ml-2 text-sm text-gray-700 dark:text-gray-300">
                  Envoyer une notification aux destinataires
                </label>
              </div>
              <div className="flex justify-end gap-3 pt-4 border-t border-gray-200 dark:border-gray-700">
                <button
                  type="button"
                  onClick={() => {
                    setShowAnnouncementForm(false)
                    setSelectedAnnouncement(null)
                  }}
                  className="btn btn-secondary"
                >
                  Annuler
                </button>
                <button
                  type="submit"
                  disabled={createAnnouncementMutation.isPending || updateAnnouncementMutation.isPending}
                  className="btn btn-primary"
                >
                  {createAnnouncementMutation.isPending || updateAnnouncementMutation.isPending
                    ? 'Enregistrement...'
                    : selectedAnnouncement
                    ? 'Modifier'
                    : 'Créer'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  )
}
