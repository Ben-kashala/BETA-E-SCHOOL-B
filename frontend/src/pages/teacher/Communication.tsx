import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import api from '@/services/api'
import { Card } from '@/components/ui/Card'
import { MessageSquare, Bell, Megaphone, Send, Plus, X, CheckCircle, Reply } from 'lucide-react'
import toast from 'react-hot-toast'
import { format } from 'date-fns'
import { fr } from 'date-fns/locale'
import { cn } from '@/utils/cn'
import { useAuthStore } from '@/store/authStore'

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

export default function TeacherCommunication() {
  const queryClient = useQueryClient()
  const { user } = useAuthStore()
  const [activeTab, setActiveTab] = useState<'messages' | 'announcements' | 'notifications'>('messages')
  const [showMessageForm, setShowMessageForm] = useState(false)
  const [selectedMessage, setSelectedMessage] = useState<Message | null>(null)
  const [messageFilter, setMessageFilter] = useState<'all' | 'sent' | 'received'>('received')
  const [replyToMessage, setReplyToMessage] = useState<Message | null>(null)

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

  const { data: announcementsData, isLoading: announcementsLoading } = useQuery({
    queryKey: ['communication-announcements'],
    queryFn: async () => {
      const response = await api.get('/communication/announcements/')
      return response.data
    },
  })

  const announcements = Array.isArray(announcementsData) ? announcementsData : (announcementsData?.results || [])

  const { data: notificationsData, isLoading: notificationsLoading } = useQuery({
    queryKey: ['communication-notifications'],
    queryFn: async () => {
      const response = await api.get('/communication/notifications/')
      return response.data
    },
  })

  const notifications = Array.isArray(notificationsData) ? notificationsData : (notificationsData?.results || [])

  const { data: usersData, isLoading: usersLoading } = useQuery({
    queryKey: ['school-staff-for-messages'],
    queryFn: async () => {
      const response = await api.get('/auth/users/school-staff/')
      return response.data
    },
    enabled: showMessageForm,
  })

  const users = Array.isArray(usersData) ? usersData : []

  const roleLabels: Record<string, string> = {
    TEACHER: 'Enseignant',
    ADMIN: 'Administrateur',
    ACCOUNTANT: 'Comptable',
    DISCIPLINE_OFFICER: 'Chargé de discipline',
    PARENT: 'Parent',
  }

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
        if (errorData.detail) errorMessage = errorData.detail
        else if (errorData.recipient) errorMessage = `Destinataire: ${Array.isArray(errorData.recipient) ? errorData.recipient.join(', ') : errorData.recipient}`
        else if (errorData.subject) errorMessage = `Sujet: ${Array.isArray(errorData.subject) ? errorData.subject.join(', ') : errorData.subject}`
        else if (errorData.message) errorMessage = `Message: ${Array.isArray(errorData.message) ? errorData.message.join(', ') : errorData.message}`
        else if (errorData.non_field_errors) errorMessage = Array.isArray(errorData.non_field_errors) ? errorData.non_field_errors.join(', ') : errorData.non_field_errors
      }
      toast.error(errorMessage)
    },
  })

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

  const handleSendMessage = (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault()
    const formData = new FormData(e.currentTarget)
    const recipientValue = formData.get('recipient') as string
    const recipientId = recipientValue ? parseInt(recipientValue, 10) : null
    if (!recipientId || isNaN(recipientId)) {
      toast.error('Veuillez sélectionner un destinataire')
      return
    }
    sendMessageMutation.mutate({
      recipient: recipientId,
      subject: formData.get('subject') as string,
      message: formData.get('message') as string,
    })
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

  const unreadCount = notifications.filter((n: Notification) => !n.is_read).length
  const unreadMessagesCount = messages.filter((m: Message) => !m.is_read && messageFilter === 'received').length

  return (
    <div>
      <h1 className="text-3xl font-bold text-gray-900 dark:text-gray-100 mb-6">Communication</h1>

      <div className="flex space-x-1 mb-6 border-b border-gray-200 dark:border-gray-700">
        <button
          onClick={() => setActiveTab('messages')}
          className={cn(
            'px-4 py-2 font-medium text-sm transition-colors relative',
            activeTab === 'messages'
              ? 'text-blue-600 dark:text-blue-400 border-b-2 border-blue-600 dark:border-blue-400'
              : 'text-gray-600 dark:text-gray-400 hover:text-gray-900 dark:hover:text-gray-200'
          )}
        >
          <div className="flex items-center gap-2">
            <MessageSquare className="w-4 h-4" />
            Messages
            {unreadMessagesCount > 0 && (
              <span className="bg-red-500 text-white text-xs rounded-full px-2 py-0.5">{unreadMessagesCount}</span>
            )}
          </div>
        </button>
        <button
          onClick={() => setActiveTab('announcements')}
          className={cn(
            'px-4 py-2 font-medium text-sm transition-colors',
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
          onClick={() => setActiveTab('notifications')}
          className={cn(
            'px-4 py-2 font-medium text-sm transition-colors',
            activeTab === 'notifications'
              ? 'text-blue-600 dark:text-blue-400 border-b-2 border-blue-600 dark:border-blue-400'
              : 'text-gray-600 dark:text-gray-400 hover:text-gray-900 dark:hover:text-gray-200'
          )}
        >
          <div className="flex items-center gap-2">
            <Bell className="w-4 h-4" />
            Notifications
            {unreadCount > 0 && (
              <span className="bg-red-500 text-white text-xs rounded-full px-2 py-0.5">{unreadCount}</span>
            )}
          </div>
        </button>
      </div>

      {activeTab === 'messages' && (
        <div className="space-y-6">
          <div className="flex justify-between items-center">
            <div className="flex gap-2">
              <button
                onClick={() => setMessageFilter('received')}
                className={cn(
                  'px-4 py-2 rounded-lg text-sm font-medium transition-colors',
                  messageFilter === 'received' ? 'bg-blue-600 text-white' : 'bg-gray-100 dark:bg-gray-700 text-gray-700 dark:text-gray-300'
                )}
              >
                Reçus
              </button>
              <button
                onClick={() => setMessageFilter('sent')}
                className={cn(
                  'px-4 py-2 rounded-lg text-sm font-medium transition-colors',
                  messageFilter === 'sent' ? 'bg-blue-600 text-white' : 'bg-gray-100 dark:bg-gray-700 text-gray-700 dark:text-gray-300'
                )}
              >
                Envoyés
              </button>
              <button
                onClick={() => setMessageFilter('all')}
                className={cn(
                  'px-4 py-2 rounded-lg text-sm font-medium transition-colors',
                  messageFilter === 'all' ? 'bg-blue-600 text-white' : 'bg-gray-100 dark:bg-gray-700 text-gray-700 dark:text-gray-300'
                )}
              >
                Tous
              </button>
            </div>
            <button onClick={() => setShowMessageForm(true)} className="btn btn-primary flex items-center gap-2">
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
                            <span className="w-2 h-2 bg-blue-600 rounded-full" />
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
        <Card>
          {announcementsLoading ? (
            <div className="p-8 text-center text-gray-500 dark:text-gray-400">Chargement...</div>
          ) : announcements.length === 0 ? (
            <div className="p-8 text-center text-gray-500 dark:text-gray-400">Aucune annonce disponible</div>
          ) : (
            <div className="space-y-4">
              {announcements.map((announcement: Announcement) => (
                <div
                  key={announcement.id}
                  className="p-4 border border-gray-200 dark:border-gray-700 rounded-lg hover:bg-gray-50 dark:hover:bg-gray-700/50 transition-colors"
                >
                  <div className="flex items-start justify-between mb-2">
                    <h3 className="text-lg font-semibold text-gray-900 dark:text-gray-100">{announcement.title}</h3>
                    <span className="text-xs text-gray-500 dark:text-gray-400">
                      {format(new Date(announcement.created_at), 'dd MMM yyyy', { locale: fr })}
                    </span>
                  </div>
                  <p className="text-gray-700 dark:text-gray-300 mb-2">{announcement.message}</p>
                  <p className="text-xs text-gray-500 dark:text-gray-400">Par {announcement.created_by_name}</p>
                </div>
              ))}
            </div>
          )}
        </Card>
      )}

      {activeTab === 'notifications' && (
        <div className="space-y-6">
          {unreadCount > 0 && (
            <div className="flex justify-end">
              <button
                onClick={() => markAllNotificationsReadMutation.mutate()}
                className="btn btn-secondary text-sm"
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
                      if (!notification.is_read) markReadMutation.mutate(notification.id)
                    }}
                    className={cn(
                      'p-4 hover:bg-gray-50 dark:hover:bg-gray-700/50 cursor-pointer transition-colors',
                      !notification.is_read && 'bg-blue-50 dark:bg-blue-900/20'
                    )}
                  >
                    <div className="flex items-start gap-3">
                      {!notification.is_read && <span className="w-2 h-2 bg-blue-600 rounded-full mt-2" />}
                      <div className="flex-1">
                        <div className="flex items-center gap-2 mb-1">
                          <span className="font-semibold text-gray-900 dark:text-gray-100">{notification.title}</span>
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

      {showMessageForm && (
        <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
          <div className="bg-white dark:bg-gray-800 rounded-lg p-6 max-w-2xl w-full mx-4">
            <div className="flex justify-between items-center mb-4">
              <h2 className="text-xl font-bold text-gray-900 dark:text-gray-100">Nouveau message</h2>
              <button onClick={() => setShowMessageForm(false)} className="text-gray-400 hover:text-gray-600 dark:hover:text-gray-300">
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
                    Chargement du personnel...
                  </div>
                ) : users.length === 0 ? (
                  <div className="w-full px-4 py-2 border border-yellow-300 dark:border-yellow-600 rounded-lg bg-yellow-50 dark:bg-yellow-900/20 text-yellow-800 dark:text-yellow-200 text-sm">
                    Aucun destinataire disponible pour le moment.
                  </div>
                ) : (
                  <select
                    name="recipient"
                    required
                    defaultValue={replyToMessage?.sender || ''}
                    className="w-full px-4 py-2 border border-gray-300 dark:border-gray-600 rounded-lg dark:bg-gray-700 dark:text-gray-100"
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
                  defaultValue={
                    replyToMessage
                      ? replyToMessage.subject.startsWith('Re: ')
                        ? replyToMessage.subject
                        : `Re: ${replyToMessage.subject}`
                      : ''
                  }
                  className="w-full px-4 py-2 border border-gray-300 dark:border-gray-600 rounded-lg dark:bg-gray-700 dark:text-gray-100"
                />
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">Message</label>
                <textarea
                  name="message"
                  required
                  rows={6}
                  className="w-full px-4 py-2 border border-gray-300 dark:border-gray-600 rounded-lg dark:bg-gray-700 dark:text-gray-100"
                />
              </div>
              <div className="flex justify-end gap-3">
                <button
                  type="button"
                  onClick={() => {
                    setShowMessageForm(false)
                    setReplyToMessage(null)
                  }}
                  className="px-4 py-2 border border-gray-300 dark:border-gray-600 rounded-lg text-gray-700 dark:text-gray-300"
                >
                  Annuler
                </button>
                <button type="submit" disabled={sendMessageMutation.isPending} className="btn btn-primary flex items-center gap-2">
                  <Send className="w-4 h-4" />
                  {sendMessageMutation.isPending ? 'Envoi...' : 'Envoyer'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {selectedMessage && (
        <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
          <div className="bg-white dark:bg-gray-800 rounded-lg p-6 max-w-2xl w-full mx-4 max-h-[90vh] overflow-y-auto">
            <div className="flex justify-between items-center mb-4">
              <h2 className="text-xl font-bold text-gray-900 dark:text-gray-100">{selectedMessage.subject}</h2>
              <button onClick={() => setSelectedMessage(null)} className="text-gray-400 hover:text-gray-600 dark:hover:text-gray-300">
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
                  <button onClick={() => handleReply(selectedMessage)} className="btn btn-primary flex items-center gap-2">
                    <Reply className="w-4 h-4" />
                    Répondre
                  </button>
                </div>
              )}
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
