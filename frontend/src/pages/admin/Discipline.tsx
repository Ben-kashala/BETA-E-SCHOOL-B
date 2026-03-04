import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import api from '@/services/api'
import { Card } from '@/components/ui/Card'
import { format } from 'date-fns'
import { fr } from 'date-fns/locale'
import { Plus, CheckCircle, XCircle, Eye, MessageSquare, Check, X, AlertCircle } from 'lucide-react'
import { showErrorToast, showSuccessToast } from '@/utils/toast'
import { cn } from '@/utils/cn'
import { useAuthStore } from '@/store/authStore'

interface DisciplineRecord {
  id: number
  student: number
  student_name: string
  student_id: string
  school_class: number
  class_name: string
  type: 'POSITIVE' | 'NEGATIVE'
  severity: 'LOW' | 'MEDIUM' | 'HIGH'
  description: string
  action_taken: string | null
  recorded_by: number | null
  recorded_by_name: string
  status: 'OPEN' | 'RESOLVED' | 'CLOSED'
  resolution_notes: string | null
  resolved_by: number | null
  resolved_by_name: string
  resolved_at: string | null
  closed_by: number | null
  closed_by_name: string
  closed_at: string | null
  date: string
  created_at: string
  updated_at: string
}

interface DisciplineRequest {
  id: number
  discipline_record: number
  discipline_record_detail: {
    id: number
    student_name: string
    student_id: string
    class_name: string
    date: string
    type: string
    type_display: string
    severity: string
    severity_display: string
    description: string
    action_taken: string | null
    status: string
    status_display: string
    recorded_by_name: string
  }
  parent: number
  parent_name: string
  request_type: 'APOLOGY' | 'PUNISHMENT_LIFT' | 'APPEAL' | 'DISCUSSION'
  message: string
  status: 'PENDING' | 'APPROVED' | 'REJECTED'
  response: string | null
  responded_by: number | null
  responded_by_name: string
  responded_at: string | null
  created_at: string
  updated_at: string
}

export default function AdminDiscipline() {
  const queryClient = useQueryClient()
  const { user } = useAuthStore()
  const canCreateRecords = user?.role === 'DISCIPLINE_OFFICER' // Seul le chargé de discipline crée les fiches
  const [showForm, setShowForm] = useState(false)
  const [selectedRecord, setSelectedRecord] = useState<DisciplineRecord | null>(null)
  const [showDetails, setShowDetails] = useState(false)
  const [activeTab, setActiveTab] = useState<'records' | 'requests'>('records')
  const [selectedRequest, setSelectedRequest] = useState<DisciplineRequest | null>(null)
  const [showRequestDetails, setShowRequestDetails] = useState(false)
  const [responseText, setResponseText] = useState('')
  const [showResolveModal, setShowResolveModal] = useState(false)
  const [recordToResolve, setRecordToResolve] = useState<DisciplineRecord | null>(null)
  const [resolutionNotes, setResolutionNotes] = useState('')
  const [formData, setFormData] = useState({
    student: '',
    school_class: '',
    type: 'NEGATIVE' as 'POSITIVE' | 'NEGATIVE',
    severity: 'LOW' as 'LOW' | 'MEDIUM' | 'HIGH',
    description: '',
    action_taken: '',
    date: new Date().toISOString().split('T')[0],
  })

  // Récupérer les fiches de discipline
  const { data: records, isLoading, error } = useQuery({
    queryKey: ['discipline-records'],
    queryFn: async () => {
      const response = await api.get('/academics/discipline/')
      return response.data
    },
    retry: 1,
  })

  // Récupérer les élèves de la classe sélectionnée (uniquement quand une classe est choisie)
  const { data: students } = useQuery({
    queryKey: ['students', formData.school_class],
    queryFn: async () => {
      const response = await api.get('/accounts/students/', {
        params: { school_class: formData.school_class },
      })
      return response.data
    },
    enabled: canCreateRecords && showForm && !!formData.school_class,
  })

  // Récupérer les classes
  const { data: classes } = useQuery({
    queryKey: ['classes'],
    queryFn: async () => {
      const response = await api.get('/schools/classes/')
      return response.data
    },
  })

  // Créer une fiche
  const createMutation = useMutation({
    mutationFn: (data: any) => api.post('/academics/discipline/', data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['discipline-records'] })
      showSuccessToast('Fiche de discipline créée avec succès')
      setShowForm(false)
      setFormData({
        student: '',
        school_class: '',
        type: 'NEGATIVE',
        severity: 'LOW',
        description: '',
        action_taken: '',
        date: new Date().toISOString().split('T')[0],
      })
    },
    onError: (error: any) => {
      showErrorToast(error, 'Erreur lors de la création de la fiche')
    },
  })

  // Résoudre une fiche
  const resolveMutation = useMutation({
    mutationFn: ({ id, resolution_notes }: { id: number; resolution_notes: string }) =>
      api.post(`/academics/discipline/${id}/resolve/`, { resolution_notes }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['discipline-records'] })
      showSuccessToast('Fiche résolue avec succès')
      setShowDetails(false)
      setSelectedRecord(null)
      closeResolveModal()
    },
    onError: (error: any) => {
      showErrorToast(error, 'Erreur lors de la résolution de la fiche')
    },
  })

  // Fermer une fiche
  const closeMutation = useMutation({
    mutationFn: (id: number) => api.post(`/academics/discipline/${id}/close/`),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['discipline-records'] })
      showSuccessToast('Fiche fermée avec succès')
      setShowDetails(false)
      setSelectedRecord(null)
    },
    onError: (error: any) => {
      showErrorToast(error, 'Erreur lors de la fermeture de la fiche')
    },
  })

  const getStatusBadge = (status: string) => {
    const badges: Record<string, string> = {
      OPEN: 'bg-yellow-100 dark:bg-yellow-900/30 text-yellow-800 dark:text-yellow-300',
      RESOLVED: 'bg-blue-100 dark:bg-blue-900/30 text-blue-800 dark:text-blue-300',
      CLOSED: 'bg-green-100 dark:bg-green-900/30 text-green-800 dark:text-green-300',
    }
    return badges[status] || 'bg-gray-100 dark:bg-gray-900/30 text-gray-800 dark:text-gray-300'
  }

  const getTypeBadge = (type: string) => {
    return type === 'POSITIVE'
      ? 'bg-green-100 dark:bg-green-900/30 text-green-800 dark:text-green-300'
      : 'bg-red-100 dark:bg-red-900/30 text-red-800 dark:text-red-300'
  }

  const getSeverityBadge = (severity: string) => {
    const badges: Record<string, string> = {
      LOW: 'bg-blue-100 dark:bg-blue-900/30 text-blue-800 dark:text-blue-300',
      MEDIUM: 'bg-yellow-100 dark:bg-yellow-900/30 text-yellow-800 dark:text-yellow-300',
      HIGH: 'bg-red-100 dark:bg-red-900/30 text-red-800 dark:text-red-300',
    }
    return badges[severity] || 'bg-gray-100 dark:bg-gray-900/30 text-gray-800 dark:text-gray-300'
  }

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault()
    createMutation.mutate(formData)
  }

  const handleResolve = (id: number, resolutionNotes: string) => {
    resolveMutation.mutate({ id, resolution_notes: resolutionNotes })
  }

  const openResolveModal = (record: DisciplineRecord) => {
    setRecordToResolve(record)
    setResolutionNotes('')
    setShowResolveModal(true)
  }

  const closeResolveModal = () => {
    setShowResolveModal(false)
    setRecordToResolve(null)
    setResolutionNotes('')
  }

  const submitResolution = () => {
    if (!recordToResolve) return
    if (!resolutionNotes.trim()) {
      showErrorToast('Veuillez saisir des notes de résolution')
      return
    }
    handleResolve(recordToResolve.id, resolutionNotes.trim())
    closeResolveModal()
  }

  const handleClose = (id: number) => {
    if (window.confirm('Êtes-vous sûr de vouloir fermer cette fiche de discipline ?')) {
      closeMutation.mutate(id)
    }
  }

  // Récupérer les demandes
  const { data: requests, isLoading: requestsLoading } = useQuery({
    queryKey: ['discipline-requests'],
    queryFn: async () => {
      const response = await api.get('/academics/discipline-requests/')
      return response.data
    },
  })

  // Approuver une demande
  const approveRequestMutation = useMutation({
    mutationFn: ({ id, response }: { id: number; response: string }) =>
      api.post(`/academics/discipline-requests/${id}/approve/`, { response }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['discipline-requests'] })
      showSuccessToast('Demande approuvée avec succès')
      setShowRequestDetails(false)
      setSelectedRequest(null)
      setResponseText('')
    },
    onError: (error: any) => {
      showErrorToast(error, 'Erreur lors de l\'approbation de la demande')
    },
  })

  // Rejeter une demande
  const rejectRequestMutation = useMutation({
    mutationFn: ({ id, response }: { id: number; response: string }) =>
      api.post(`/academics/discipline-requests/${id}/reject/`, { response }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['discipline-requests'] })
      showSuccessToast('Demande rejetée')
      setShowRequestDetails(false)
      setSelectedRequest(null)
      setResponseText('')
    },
    onError: (error: any) => {
      showErrorToast(error, 'Erreur lors du rejet de la demande')
    },
  })

  const getRequestStatusBadge = (status: string) => {
    const badges: Record<string, string> = {
      PENDING: 'bg-yellow-100 dark:bg-yellow-900/30 text-yellow-800 dark:text-yellow-300',
      APPROVED: 'bg-green-100 dark:bg-green-900/30 text-green-800 dark:text-green-300',
      REJECTED: 'bg-red-100 dark:bg-red-900/30 text-red-800 dark:text-red-300',
    }
    return badges[status] || 'bg-gray-100 dark:bg-gray-900/30 text-gray-800 dark:text-gray-300'
  }

  const getRequestTypeLabel = (type: string) => {
    const labels: Record<string, string> = {
      APOLOGY: 'Demande d\'excuse',
      PUNISHMENT_LIFT: 'Demande de levée de punition',
      APPEAL: 'Recours',
      DISCUSSION: 'Discussion',
    }
    return labels[type] || type
  }

  return (
    <div>
      <div className="flex justify-between items-center mb-6">
        <h1 className="text-3xl font-bold text-gray-900 dark:text-gray-100">Fiches de Discipline</h1>
        {canCreateRecords && activeTab === 'records' && (
          <button
            onClick={() => setShowForm(!showForm)}
            className="btn btn-primary flex items-center space-x-2"
          >
            <Plus className="w-5 h-5" />
            <span>Nouvelle fiche</span>
          </button>
        )}
      </div>

      {/* Onglets */}
      <div className="mb-6 border-b border-gray-200 dark:border-gray-700">
        <nav className="-mb-px flex space-x-8">
          <button
            onClick={() => setActiveTab('records')}
            className={cn(
              'py-4 px-1 border-b-2 font-medium text-sm',
              activeTab === 'records'
                ? 'border-primary-500 text-primary-600 dark:text-primary-400'
                : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300 dark:text-gray-400 dark:hover:text-gray-300'
            )}
          >
            Fiches de discipline
          </button>
          <button
            onClick={() => setActiveTab('requests')}
            className={cn(
              'py-4 px-1 border-b-2 font-medium text-sm flex items-center space-x-2',
              activeTab === 'requests'
                ? 'border-primary-500 text-primary-600 dark:text-primary-400'
                : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300 dark:text-gray-400 dark:hover:text-gray-300'
            )}
          >
            <MessageSquare className="w-4 h-4" />
            <span>Demandes des parents</span>
            {requests?.results?.filter((r: DisciplineRequest) => r.status === 'PENDING').length > 0 && (
              <span className="badge bg-red-100 dark:bg-red-900/30 text-red-800 dark:text-red-300">
                {requests.results.filter((r: DisciplineRequest) => r.status === 'PENDING').length}
              </span>
            )}
          </button>
        </nav>
      </div>

      {/* Contenu selon l'onglet actif */}
      {activeTab === 'requests' ? (
        <Card>
          <div className="overflow-x-auto">
            <table className="w-full">
              <thead className="bg-gray-50 dark:bg-gray-700/50">
                <tr>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-700 dark:text-gray-300 uppercase">Parent</th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-700 dark:text-gray-300 uppercase">Élève</th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-700 dark:text-gray-300 uppercase">Fiche de discipline</th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-700 dark:text-gray-300 uppercase">Type de demande</th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-700 dark:text-gray-300 uppercase">Statut</th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-700 dark:text-gray-300 uppercase">Date</th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-700 dark:text-gray-300 uppercase">Actions</th>
                </tr>
              </thead>
              <tbody className="bg-white dark:bg-gray-800 divide-y divide-gray-200 dark:divide-gray-700">
                {requestsLoading ? (
                  <tr>
                    <td colSpan={7} className="px-6 py-4 text-center text-gray-600 dark:text-gray-400">Chargement...</td>
                  </tr>
                ) : !requests?.results || requests?.results?.length === 0 ? (
                  <tr>
                    <td colSpan={7} className="px-6 py-4 text-center text-gray-600 dark:text-gray-400">
                      Aucune demande trouvée
                    </td>
                  </tr>
                ) : (
                  requests?.results?.map((request: DisciplineRequest) => (
                    <tr key={request.id} className="hover:bg-gray-50 dark:hover:bg-gray-700/50">
                      <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900 dark:text-gray-100">
                        {request.parent_name}
                      </td>
                      <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900 dark:text-gray-100">
                        {request.discipline_record_detail?.student_name || '-'}
                      </td>
                      <td className="px-6 py-4 text-sm text-gray-900 dark:text-gray-100">
                        <div className="space-y-1">
                          <div className="flex items-center space-x-2">
                            <span className="font-medium">#{request.discipline_record_detail?.id || '-'}</span>
                            <span className={cn('badge text-xs',
                              request.discipline_record_detail?.type === 'POSITIVE'
                                ? 'bg-green-100 dark:bg-green-900/30 text-green-800 dark:text-green-300'
                                : 'bg-red-100 dark:bg-red-900/30 text-red-800 dark:text-red-300'
                            )}>
                              {request.discipline_record_detail?.type_display || '-'}
                            </span>
                          </div>
                          <div className="text-xs text-gray-500 dark:text-gray-400">
                            {request.discipline_record_detail?.date
                              ? format(new Date(request.discipline_record_detail.date), 'dd MMM yyyy', { locale: fr })
                              : '-'}
                          </div>
                          {request.discipline_record_detail?.description && (
                            <div className="text-xs text-gray-600 dark:text-gray-400 truncate max-w-xs" title={request.discipline_record_detail.description}>
                              {request.discipline_record_detail.description.substring(0, 50)}
                              {request.discipline_record_detail.description.length > 50 ? '...' : ''}
                            </div>
                          )}
                        </div>
                      </td>
                      <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900 dark:text-gray-100">
                        {getRequestTypeLabel(request.request_type)}
                      </td>
                      <td className="px-6 py-4 whitespace-nowrap">
                        <span className={cn('badge', getRequestStatusBadge(request.status))}>
                          {request.status === 'PENDING' ? 'En attente' : request.status === 'APPROVED' ? 'Approuvée' : 'Rejetée'}
                        </span>
                      </td>
                      <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-600 dark:text-gray-400">
                        {format(new Date(request.created_at), 'dd MMM yyyy', { locale: fr })}
                      </td>
                      <td className="px-6 py-4 whitespace-nowrap text-sm font-medium space-x-2">
                        <button
                          onClick={() => {
                            setSelectedRequest(request)
                            setShowRequestDetails(true)
                            setResponseText(request.response || '')
                          }}
                          className="text-blue-600 dark:text-blue-400 hover:text-blue-900 dark:hover:text-blue-300"
                          title="Voir les détails"
                        >
                          <Eye className="w-5 h-5" />
                        </button>
                        {request.status === 'PENDING' && (
                          <>
                            <button
                              onClick={() => {
                                setSelectedRequest(request)
                                setShowRequestDetails(true)
                                setResponseText('')
                              }}
                              className="text-green-600 dark:text-green-400 hover:text-green-900 dark:hover:text-green-300"
                              title="Approuver"
                            >
                              <Check className="w-5 h-5" />
                            </button>
                            <button
                              onClick={() => {
                                setSelectedRequest(request)
                                setShowRequestDetails(true)
                                setResponseText('')
                              }}
                              className="text-red-600 dark:text-red-400 hover:text-red-900 dark:hover:text-red-300"
                              title="Rejeter"
                            >
                              <X className="w-5 h-5" />
                            </button>
                          </>
                        )}
                      </td>
                    </tr>
                  ))
                )}
              </tbody>
            </table>
          </div>
        </Card>
      ) : (
        <>
          {/* Formulaire de création (chargé de discipline uniquement) */}
      {canCreateRecords && showForm && (
        <Card className="mb-6">
          <h2 className="text-xl font-semibold text-gray-900 dark:text-gray-100 mb-4">Créer une fiche de discipline</h2>
          <form onSubmit={handleSubmit} className="space-y-4">
            <div className="grid grid-cols-2 gap-4">
              <div>
                <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                  Classe *
                </label>
                <select
                  required
                  value={formData.school_class}
                  onChange={(e) =>
                    setFormData({ ...formData, school_class: e.target.value, student: '' })
                  }
                  className="w-full px-3 py-2 border border-gray-300 dark:border-gray-600 rounded-lg bg-white dark:bg-gray-700 text-gray-900 dark:text-gray-100"
                >
                  <option value="">Sélectionner une classe</option>
                  {classes?.results?.map((cls: any) => (
                    <option key={cls.id} value={cls.id}>
                      {cls.name}
                    </option>
                  ))}
                </select>
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                  Élève *
                </label>
                <select
                  required
                  value={formData.student}
                  onChange={(e) => setFormData({ ...formData, student: e.target.value })}
                  disabled={!formData.school_class}
                  className="w-full px-3 py-2 border border-gray-300 dark:border-gray-600 rounded-lg bg-white dark:bg-gray-700 text-gray-900 dark:text-gray-100 disabled:opacity-60 disabled:cursor-not-allowed"
                >
                  <option value="">
                    {formData.school_class ? 'Sélectionner un élève' : 'Sélectionner une classe d\'abord'}
                  </option>
                  {(formData.school_class ? students?.results ?? [] : []).map((student: any) => (
                    <option key={student.id} value={student.id}>
                      {[student.user?.first_name, student.user?.last_name, student.user?.middle_name].filter(Boolean).join(' ')} - {student.student_id}
                    </option>
                  ))}
                </select>
              </div>
            </div>
            <div className="grid grid-cols-2 gap-4">
              <div>
                <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                  Type *
                </label>
                <select
                  required
                  value={formData.type}
                  onChange={(e) => setFormData({ ...formData, type: e.target.value as 'POSITIVE' | 'NEGATIVE' })}
                  className="w-full px-3 py-2 border border-gray-300 dark:border-gray-600 rounded-lg bg-white dark:bg-gray-700 text-gray-900 dark:text-gray-100"
                >
                  <option value="POSITIVE">Comportement positif</option>
                  <option value="NEGATIVE">Comportement négatif</option>
                </select>
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                  Sévérité *
                </label>
                <select
                  required
                  value={formData.severity}
                  onChange={(e) => setFormData({ ...formData, severity: e.target.value as 'LOW' | 'MEDIUM' | 'HIGH' })}
                  className="w-full px-3 py-2 border border-gray-300 dark:border-gray-600 rounded-lg bg-white dark:bg-gray-700 text-gray-900 dark:text-gray-100"
                >
                  <option value="LOW">Faible</option>
                  <option value="MEDIUM">Moyen</option>
                  <option value="HIGH">Élevé</option>
                </select>
              </div>
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                Description *
              </label>
              <textarea
                required
                value={formData.description}
                onChange={(e) => setFormData({ ...formData, description: e.target.value })}
                rows={4}
                className="w-full px-3 py-2 border border-gray-300 dark:border-gray-600 rounded-lg bg-white dark:bg-gray-700 text-gray-900 dark:text-gray-100"
              />
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                Action prise
              </label>
              <textarea
                value={formData.action_taken}
                onChange={(e) => setFormData({ ...formData, action_taken: e.target.value })}
                rows={3}
                className="w-full px-3 py-2 border border-gray-300 dark:border-gray-600 rounded-lg bg-white dark:bg-gray-700 text-gray-900 dark:text-gray-100"
              />
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                Date *
              </label>
              <input
                type="date"
                required
                value={formData.date}
                onChange={(e) => setFormData({ ...formData, date: e.target.value })}
                className="w-full px-3 py-2 border border-gray-300 dark:border-gray-600 rounded-lg bg-white dark:bg-gray-700 text-gray-900 dark:text-gray-100"
              />
            </div>
            <div className="flex space-x-2">
              <button type="submit" className="btn btn-primary" disabled={createMutation.isPending}>
                {createMutation.isPending ? 'Création...' : 'Créer'}
              </button>
              <button
                type="button"
                onClick={() => setShowForm(false)}
                className="btn btn-secondary"
              >
                Annuler
              </button>
            </div>
          </form>
        </Card>
      )}

      {/* Liste des fiches */}
      <Card>
        <div className="overflow-x-auto">
          <table className="w-full">
            <thead className="bg-gray-50 dark:bg-gray-700/50">
              <tr>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-700 dark:text-gray-300 uppercase">Élève</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-700 dark:text-gray-300 uppercase">Classe</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-700 dark:text-gray-300 uppercase">Type</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-700 dark:text-gray-300 uppercase">Sévérité</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-700 dark:text-gray-300 uppercase">Statut</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-700 dark:text-gray-300 uppercase">Date</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-700 dark:text-gray-300 uppercase">Actions</th>
              </tr>
            </thead>
            <tbody className="bg-white dark:bg-gray-800 divide-y divide-gray-200 dark:divide-gray-700">
              {isLoading ? (
                <tr>
                  <td colSpan={7} className="px-6 py-4 text-center text-gray-600 dark:text-gray-400">Chargement...</td>
                </tr>
              ) : error ? (
                <tr>
                  <td colSpan={7} className="px-6 py-4 text-center text-red-600 dark:text-red-400">
                    Erreur lors du chargement des fiches
                  </td>
                </tr>
              ) : !records?.results || records?.results?.length === 0 ? (
                <tr>
                  <td colSpan={7} className="px-6 py-4 text-center text-gray-600 dark:text-gray-400">
                    Aucune fiche de discipline trouvée
                  </td>
                </tr>
              ) : (
                records?.results?.map((record: DisciplineRecord) => (
                  <tr key={record.id} className="hover:bg-gray-50 dark:hover:bg-gray-700/50">
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900 dark:text-gray-100">
                      {record.student_name}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900 dark:text-gray-100">
                      {record.class_name}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap">
                      <span className={cn('badge', getTypeBadge(record.type))}>
                        {record.type === 'POSITIVE' ? 'Positif' : 'Négatif'}
                      </span>
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap">
                      <span className={cn('badge', getSeverityBadge(record.severity))}>
                        {record.severity === 'LOW' ? 'Faible' : record.severity === 'MEDIUM' ? 'Moyen' : 'Élevé'}
                      </span>
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap">
                      <span className={cn('badge', getStatusBadge(record.status))}>
                        {record.status === 'OPEN' ? 'Ouvert' : record.status === 'RESOLVED' ? 'Résolu' : 'Fermé'}
                      </span>
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-600 dark:text-gray-400">
                      {format(new Date(record.date), 'dd MMM yyyy', { locale: fr })}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm font-medium space-x-2">
                      <button
                        onClick={() => {
                          setSelectedRecord(record)
                          setShowDetails(true)
                        }}
                        className="text-blue-600 dark:text-blue-400 hover:text-blue-900 dark:hover:text-blue-300"
                        title="Voir les détails"
                      >
                        <Eye className="w-5 h-5" />
                      </button>
                      {record.status === 'OPEN' && (
                        <button
                          onClick={() => openResolveModal(record)}
                          className="text-green-600 dark:text-green-400 hover:text-green-900 dark:hover:text-green-300"
                          title="Résoudre"
                        >
                          <CheckCircle className="w-5 h-5" />
                        </button>
                      )}
                      {record.status === 'RESOLVED' && (
                        <button
                          onClick={() => handleClose(record.id)}
                          className="text-purple-600 dark:text-purple-400 hover:text-purple-900 dark:hover:text-purple-300"
                          title="Fermer"
                        >
                          <XCircle className="w-5 h-5" />
                        </button>
                      )}
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </Card>

      {/* Modal de détails */}
      {showDetails && selectedRecord && (
        <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
          <div className="bg-white dark:bg-gray-800 rounded-lg p-6 max-w-2xl w-full mx-4 max-h-[90vh] overflow-y-auto">
            <div className="flex justify-between items-start mb-4">
              <h2 className="text-2xl font-bold text-gray-900 dark:text-gray-100">Détails de la fiche</h2>
              <button
                onClick={() => {
                  setShowDetails(false)
                  setSelectedRecord(null)
                }}
                className="text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-200"
              >
                <XCircle className="w-6 h-6" />
              </button>
            </div>
            <div className="space-y-4">
              <div>
                <label className="text-sm font-medium text-gray-700 dark:text-gray-300">Élève</label>
                <p className="text-gray-900 dark:text-gray-100">{selectedRecord.student_name}</p>
              </div>
              <div>
                <label className="text-sm font-medium text-gray-700 dark:text-gray-300">Classe</label>
                <p className="text-gray-900 dark:text-gray-100">{selectedRecord.class_name}</p>
              </div>
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="text-sm font-medium text-gray-700 dark:text-gray-300">Type</label>
                  <p>
                    <span className={cn('badge', getTypeBadge(selectedRecord.type))}>
                      {selectedRecord.type === 'POSITIVE' ? 'Positif' : 'Négatif'}
                    </span>
                  </p>
                </div>
                <div>
                  <label className="text-sm font-medium text-gray-700 dark:text-gray-300">Sévérité</label>
                  <p>
                    <span className={cn('badge', getSeverityBadge(selectedRecord.severity))}>
                      {selectedRecord.severity === 'LOW' ? 'Faible' : selectedRecord.severity === 'MEDIUM' ? 'Moyen' : 'Élevé'}
                    </span>
                  </p>
                </div>
              </div>
              <div>
                <label className="text-sm font-medium text-gray-700 dark:text-gray-300">Description</label>
                <p className="text-gray-900 dark:text-gray-100">{selectedRecord.description}</p>
              </div>
              {selectedRecord.action_taken && (
                <div>
                  <label className="text-sm font-medium text-gray-700 dark:text-gray-300">Action prise</label>
                  <p className="text-gray-900 dark:text-gray-100">{selectedRecord.action_taken}</p>
                </div>
              )}
              {selectedRecord.resolution_notes && (
                <div>
                  <label className="text-sm font-medium text-gray-700 dark:text-gray-300">Notes de résolution</label>
                  <p className="text-gray-900 dark:text-gray-100">{selectedRecord.resolution_notes}</p>
                </div>
              )}
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="text-sm font-medium text-gray-700 dark:text-gray-300">Enregistré par</label>
                  <p className="text-gray-900 dark:text-gray-100">{selectedRecord.recorded_by_name || '-'}</p>
                </div>
                <div>
                  <label className="text-sm font-medium text-gray-700 dark:text-gray-300">Date</label>
                  <p className="text-gray-900 dark:text-gray-100">
                    {format(new Date(selectedRecord.date), 'dd MMM yyyy', { locale: fr })}
                  </p>
                </div>
              </div>
              {selectedRecord.resolved_by_name && (
                <div>
                  <label className="text-sm font-medium text-gray-700 dark:text-gray-300">Résolu par</label>
                  <p className="text-gray-900 dark:text-gray-100">
                    {selectedRecord.resolved_by_name} le{' '}
                    {selectedRecord.resolved_at
                      ? format(new Date(selectedRecord.resolved_at), 'dd MMM yyyy à HH:mm', { locale: fr })
                      : '-'}
                  </p>
                </div>
              )}
              {selectedRecord.closed_by_name && (
                <div>
                  <label className="text-sm font-medium text-gray-700 dark:text-gray-300">Fermé par</label>
                  <p className="text-gray-900 dark:text-gray-100">
                    {selectedRecord.closed_by_name} le{' '}
                    {selectedRecord.closed_at
                      ? format(new Date(selectedRecord.closed_at), 'dd MMM yyyy à HH:mm', { locale: fr })
                      : '-'}
                  </p>
                </div>
              )}
            </div>
          </div>
        </div>
      )}
        </>
      )}

      {/* Modal de détails de demande - visible pour tous les onglets */}
      {showRequestDetails && selectedRequest && (
        <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
          <div className="bg-white dark:bg-gray-800 rounded-lg p-6 max-w-2xl w-full mx-4 max-h-[90vh] overflow-y-auto">
            <div className="flex justify-between items-start mb-4">
              <h2 className="text-2xl font-bold text-gray-900 dark:text-gray-100">Détails de la demande</h2>
              <button
                onClick={() => {
                  setShowRequestDetails(false)
                  setSelectedRequest(null)
                  setResponseText('')
                }}
                className="text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-200"
              >
                <XCircle className="w-6 h-6" />
              </button>
            </div>
            <div className="space-y-4">
              <div>
                <label className="text-sm font-medium text-gray-700 dark:text-gray-300">Parent</label>
                <p className="text-gray-900 dark:text-gray-100">{selectedRequest.parent_name}</p>
              </div>
              {/* Section Fiche de discipline */}
              <div className="mt-6 pt-6 border-t border-gray-200 dark:border-gray-700">
                <h3 className="text-lg font-semibold text-gray-900 dark:text-gray-100 mb-4 flex items-center space-x-2">
                  <AlertCircle className="w-5 h-5" />
                  <span>Fiche de discipline concernée</span>
                  {selectedRequest.discipline_record_detail?.id && (
                    <span className="text-sm font-normal text-gray-500 dark:text-gray-400">
                      (ID: #{selectedRequest.discipline_record_detail.id})
                    </span>
                  )}
                </h3>
                <div className="bg-gray-50 dark:bg-gray-700/50 p-4 rounded-lg space-y-3">
                  <div className="grid grid-cols-2 gap-4">
                    <div>
                      <label className="text-xs font-medium text-gray-600 dark:text-gray-400">Élève</label>
                      <p className="text-sm font-medium text-gray-900 dark:text-gray-100">
                        {selectedRequest.discipline_record_detail?.student_name || '-'}
                        {selectedRequest.discipline_record_detail?.student_id && (
                          <span className="text-gray-500 dark:text-gray-400 ml-2">
                            ({selectedRequest.discipline_record_detail.student_id})
                          </span>
                        )}
                      </p>
                    </div>
                    <div>
                      <label className="text-xs font-medium text-gray-600 dark:text-gray-400">Classe</label>
                      <p className="text-sm text-gray-900 dark:text-gray-100">
                        {selectedRequest.discipline_record_detail?.class_name || '-'}
                      </p>
                    </div>
                  </div>
                  <div className="grid grid-cols-2 gap-4">
                    <div>
                      <label className="text-xs font-medium text-gray-600 dark:text-gray-400">Date de la fiche</label>
                      <p className="text-sm text-gray-900 dark:text-gray-100">
                        {selectedRequest.discipline_record_detail?.date
                          ? format(new Date(selectedRequest.discipline_record_detail.date), 'dd MMM yyyy', { locale: fr })
                          : '-'}
                      </p>
                    </div>
                    <div>
                      <label className="text-xs font-medium text-gray-600 dark:text-gray-400">Enregistré par</label>
                      <p className="text-sm text-gray-900 dark:text-gray-100">
                        {selectedRequest.discipline_record_detail?.recorded_by_name || '-'}
                      </p>
                    </div>
                  </div>
                  <div className="grid grid-cols-2 gap-4">
                    <div>
                      <label className="text-xs font-medium text-gray-600 dark:text-gray-400">Type</label>
                      <p>
                        <span className={cn('badge', 
                          selectedRequest.discipline_record_detail?.type === 'POSITIVE'
                            ? 'bg-green-100 dark:bg-green-900/30 text-green-800 dark:text-green-300'
                            : 'bg-red-100 dark:bg-red-900/30 text-red-800 dark:text-red-300'
                        )}>
                          {selectedRequest.discipline_record_detail?.type_display || '-'}
                        </span>
                      </p>
                    </div>
                    <div>
                      <label className="text-xs font-medium text-gray-600 dark:text-gray-400">Sévérité</label>
                      <p>
                        <span className={cn('badge',
                          selectedRequest.discipline_record_detail?.severity === 'LOW'
                            ? 'bg-blue-100 dark:bg-blue-900/30 text-blue-800 dark:text-blue-300'
                            : selectedRequest.discipline_record_detail?.severity === 'MEDIUM'
                            ? 'bg-yellow-100 dark:bg-yellow-900/30 text-yellow-800 dark:text-yellow-300'
                            : 'bg-red-100 dark:bg-red-900/30 text-red-800 dark:text-red-300'
                        )}>
                          {selectedRequest.discipline_record_detail?.severity_display || '-'}
                        </span>
                      </p>
                    </div>
                  </div>
                  <div>
                    <label className="text-xs font-medium text-gray-600 dark:text-gray-400">Description</label>
                    <p className="text-sm text-gray-900 dark:text-gray-100 mt-1">
                      {selectedRequest.discipline_record_detail?.description || '-'}
                    </p>
                  </div>
                  {selectedRequest.discipline_record_detail?.action_taken && (
                    <div>
                      <label className="text-xs font-medium text-gray-600 dark:text-gray-400">Action prise</label>
                      <p className="text-sm text-gray-900 dark:text-gray-100 mt-1 whitespace-pre-line">
                        {selectedRequest.discipline_record_detail.action_taken}
                      </p>
                    </div>
                  )}
                  <div>
                    <label className="text-xs font-medium text-gray-600 dark:text-gray-400">Statut de la fiche</label>
                    <p>
                      <span className={cn('badge',
                        selectedRequest.discipline_record_detail?.status === 'OPEN'
                          ? 'bg-yellow-100 dark:bg-yellow-900/30 text-yellow-800 dark:text-yellow-300'
                          : selectedRequest.discipline_record_detail?.status === 'RESOLVED'
                          ? 'bg-blue-100 dark:bg-blue-900/30 text-blue-800 dark:text-blue-300'
                          : 'bg-green-100 dark:bg-green-900/30 text-green-800 dark:text-green-300'
                      )}>
                        {selectedRequest.discipline_record_detail?.status_display || '-'}
                      </span>
                    </p>
                  </div>
                </div>
              </div>

              {/* Section Demande du parent */}
              <div className="mt-6 pt-6 border-t border-gray-200 dark:border-gray-700">
                <h3 className="text-lg font-semibold text-gray-900 dark:text-gray-100 mb-4">Demande du parent</h3>
                <div>
                  <label className="text-sm font-medium text-gray-700 dark:text-gray-300">Parent</label>
                  <p className="text-gray-900 dark:text-gray-100">{selectedRequest.parent_name}</p>
                </div>
                <div className="mt-3">
                  <label className="text-sm font-medium text-gray-700 dark:text-gray-300">Type de demande</label>
                  <p className="text-gray-900 dark:text-gray-100">{getRequestTypeLabel(selectedRequest.request_type)}</p>
                </div>
              </div>
              <div>
                <label className="text-sm font-medium text-gray-700 dark:text-gray-300">Message</label>
                <p className="text-gray-900 dark:text-gray-100 bg-gray-50 dark:bg-gray-700/50 p-3 rounded">
                  {selectedRequest.message}
                </p>
              </div>
              <div>
                <label className="text-sm font-medium text-gray-700 dark:text-gray-300">Statut</label>
                <p>
                  <span className={cn('badge', getRequestStatusBadge(selectedRequest.status))}>
                    {selectedRequest.status === 'PENDING' ? 'En attente' : selectedRequest.status === 'APPROVED' ? 'Approuvée' : 'Rejetée'}
                  </span>
                </p>
              </div>
              {selectedRequest.response && (
                <div>
                  <label className="text-sm font-medium text-gray-700 dark:text-gray-300">Réponse précédente</label>
                  <p className="text-gray-900 dark:text-gray-100 bg-gray-50 dark:bg-gray-700/50 p-3 rounded">
                    {selectedRequest.response}
                  </p>
                </div>
              )}
              {selectedRequest.status === 'PENDING' && (
                <div>
                  <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                    Réponse de l'école *
                  </label>
                  <textarea
                    value={responseText}
                    onChange={(e) => setResponseText(e.target.value)}
                    rows={4}
                    placeholder="Votre réponse..."
                    className="w-full px-3 py-2 border border-gray-300 dark:border-gray-600 rounded-lg bg-white dark:bg-gray-700 text-gray-900 dark:text-gray-100"
                  />
                  <div className="flex space-x-2 mt-4">
                    <button
                      onClick={() => {
                        if (!responseText.trim()) {
                          showErrorToast(null, 'Veuillez saisir une réponse')
                          return
                        }
                        approveRequestMutation.mutate({ id: selectedRequest.id, response: responseText })
                      }}
                      className="btn btn-primary flex items-center space-x-2"
                      disabled={approveRequestMutation.isPending}
                    >
                      <Check className="w-4 h-4" />
                      <span>Approuver</span>
                    </button>
                    <button
                      onClick={() => {
                        if (!responseText.trim()) {
                          showErrorToast(null, 'Veuillez saisir une réponse')
                          return
                        }
                        rejectRequestMutation.mutate({ id: selectedRequest.id, response: responseText })
                      }}
                      className="btn btn-danger flex items-center space-x-2"
                      disabled={rejectRequestMutation.isPending}
                    >
                      <X className="w-4 h-4" />
                      <span>Rejeter</span>
                    </button>
                  </div>
                </div>
              )}
            </div>
          </div>
        </div>
      )}

      {/* Modal de résolution améliorée */}
      {showResolveModal && recordToResolve && (
        <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
          <div className="bg-white dark:bg-gray-800 rounded-lg p-6 max-w-2xl w-full mx-4 max-h-[90vh] overflow-y-auto">
            <div className="flex justify-between items-center mb-6">
              <h2 className="text-2xl font-bold text-gray-900 dark:text-gray-100">
                Résoudre la fiche de discipline
              </h2>
              <button
                onClick={closeResolveModal}
                className="text-gray-400 hover:text-gray-600 dark:hover:text-gray-300"
              >
                <X className="w-6 h-6" />
              </button>
            </div>

            {/* Informations de la fiche */}
            <div className="mb-6 p-4 bg-gray-50 dark:bg-gray-700/50 rounded-lg">
              <h3 className="text-lg font-semibold text-gray-900 dark:text-gray-100 mb-4">
                Informations de la fiche
              </h3>
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                <div>
                  <label className="text-sm font-medium text-gray-600 dark:text-gray-400">Élève</label>
                  <p className="text-gray-900 dark:text-gray-100 font-medium">
                    {recordToResolve.student_name} ({recordToResolve.student_id})
                  </p>
                </div>
                <div>
                  <label className="text-sm font-medium text-gray-600 dark:text-gray-400">Classe</label>
                  <p className="text-gray-900 dark:text-gray-100 font-medium">{recordToResolve.class_name}</p>
                </div>
                <div>
                  <label className="text-sm font-medium text-gray-600 dark:text-gray-400">Type</label>
                  <span
                    className={cn(
                      'inline-block px-2 py-1 rounded text-sm font-medium',
                      getTypeBadge(recordToResolve.type)
                    )}
                  >
                    {recordToResolve.type === 'POSITIVE' ? 'Comportement positif' : 'Comportement négatif'}
                  </span>
                </div>
                <div>
                  <label className="text-sm font-medium text-gray-600 dark:text-gray-400">Sévérité</label>
                  <span
                    className={cn(
                      'inline-block px-2 py-1 rounded text-sm font-medium',
                      getSeverityBadge(recordToResolve.severity)
                    )}
                  >
                    {recordToResolve.severity === 'LOW'
                      ? 'Faible'
                      : recordToResolve.severity === 'MEDIUM'
                        ? 'Moyen'
                        : 'Élevé'}
                  </span>
                </div>
                <div className="md:col-span-2">
                  <label className="text-sm font-medium text-gray-600 dark:text-gray-400">Description</label>
                  <p className="text-gray-900 dark:text-gray-100 mt-1">{recordToResolve.description}</p>
                </div>
                {recordToResolve.action_taken && (
                  <div className="md:col-span-2">
                    <label className="text-sm font-medium text-gray-600 dark:text-gray-400">Action prise</label>
                    <p className="text-gray-900 dark:text-gray-100 mt-1">{recordToResolve.action_taken}</p>
                  </div>
                )}
                <div>
                  <label className="text-sm font-medium text-gray-600 dark:text-gray-400">Date</label>
                  <p className="text-gray-900 dark:text-gray-100">
                    {format(new Date(recordToResolve.date), 'dd MMM yyyy', { locale: fr })}
                  </p>
                </div>
                <div>
                  <label className="text-sm font-medium text-gray-600 dark:text-gray-400">Enregistré par</label>
                  <p className="text-gray-900 dark:text-gray-100">{recordToResolve.recorded_by_name || '-'}</p>
                </div>
              </div>
            </div>

            {/* Formulaire de résolution */}
            <div className="mb-6">
              <label htmlFor="resolution-notes" className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
                Notes de résolution <span className="text-red-500">*</span>
              </label>
              <textarea
                id="resolution-notes"
                value={resolutionNotes}
                onChange={(e) => setResolutionNotes(e.target.value)}
                rows={6}
                className="w-full px-4 py-2 border border-gray-300 dark:border-gray-600 rounded-lg focus:ring-2 focus:ring-green-500 focus:border-transparent dark:bg-gray-700 dark:text-gray-100"
                placeholder="Décrivez les actions prises pour résoudre cette fiche de discipline..."
              />
              <p className="mt-2 text-sm text-gray-500 dark:text-gray-400">
                Veuillez fournir des détails sur la manière dont cette fiche a été résolue.
              </p>
            </div>

            {/* Boutons d'action */}
            <div className="flex justify-end gap-3">
              <button
                onClick={closeResolveModal}
                className="px-4 py-2 border border-gray-300 dark:border-gray-600 rounded-lg text-gray-700 dark:text-gray-300 hover:bg-gray-50 dark:hover:bg-gray-700 transition-colors"
                disabled={resolveMutation.isPending}
              >
                Annuler
              </button>
              <button
                onClick={submitResolution}
                disabled={resolveMutation.isPending || !resolutionNotes.trim()}
                className="px-4 py-2 bg-green-600 text-white rounded-lg hover:bg-green-700 disabled:bg-gray-400 disabled:cursor-not-allowed transition-colors flex items-center gap-2"
              >
                {resolveMutation.isPending ? (
                  <>
                    <div className="w-4 h-4 border-2 border-white border-t-transparent rounded-full animate-spin" />
                    <span>Résolution...</span>
                  </>
                ) : (
                  <>
                    <CheckCircle className="w-4 h-4" />
                    <span>Résoudre la fiche</span>
                  </>
                )}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
