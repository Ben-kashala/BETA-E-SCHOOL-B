import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import api from '@/services/api'
import { Card } from '@/components/ui/Card'
import { format } from 'date-fns'
import { fr } from 'date-fns/locale'
import { CheckCircle, Eye, X, XCircle } from 'lucide-react'
import { showErrorToast, showSuccessToast } from '@/utils/toast'
import { cn } from '@/utils/cn'

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
  date: string
  created_at: string
  updated_at: string
}

export default function TeacherDiscipline() {
  const queryClient = useQueryClient()
  const [selectedRecord, setSelectedRecord] = useState<DisciplineRecord | null>(null)
  const [showDetails, setShowDetails] = useState(false)
  const [showResolveModal, setShowResolveModal] = useState(false)
  const [recordToResolve, setRecordToResolve] = useState<DisciplineRecord | null>(null)
  const [resolutionNotes, setResolutionNotes] = useState('')

  // Récupérer les fiches de discipline
  const { data: records, isLoading, error } = useQuery({
    queryKey: ['discipline-records'],
    queryFn: async () => {
      const response = await api.get('/academics/discipline/')
      return response.data
    },
    retry: 1,
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

  return (
    <div>
      <div className="flex justify-between items-center mb-6">
        <h1 className="text-3xl font-bold text-gray-900 dark:text-gray-100">Fiches de Discipline</h1>
        <p className="text-sm text-gray-500 dark:text-gray-400">Consultation uniquement — le chargé de discipline gère les fiches.</p>
      </div>

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
