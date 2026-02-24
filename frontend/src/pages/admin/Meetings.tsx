import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import api from '@/services/api'
import { Card } from '@/components/ui/Card'
import { format } from 'date-fns'
import { fr } from 'date-fns/locale'
import { Plus, X } from 'lucide-react'
import { useState } from 'react'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'
import { showErrorToast, showSuccessToast } from '@/utils/toast'
import { cn } from '@/utils/cn'

const meetingSchema = z.object({
  title: z.string().min(1, 'Le titre est requis'),
  description: z.string().min(1, 'La description est requise'),
  meeting_type: z.enum(['INDIVIDUAL', 'GROUP', 'GENERAL', 'TEACHER_MEETING', 'PARENT_MEETING']),
  teacher: z.number().min(1, 'L\'enseignant est requis'),
  parent: z.number().optional(),
  student: z.number().optional(),
  meeting_date: z.string().min(1, 'La date est requise'),
  duration_minutes: z.number().min(15).max(480).default(30),
  location: z.string().optional(),
  video_platform: z.enum(['ZOOM', 'TEAMS', 'GOOGLE_MEET', 'OTHER']).optional(),
  video_link: z.string().url('URL invalide').optional().or(z.literal('')),
  auto_generate_video_link: z.boolean().default(false),
  is_published: z.boolean().default(false),
  participant_ids: z.array(z.number()).optional(),
  student_ids: z.array(z.number()).optional(),
  parent_ids: z.array(z.number()).optional(),
  group_ids: z.array(z.number()).optional(),
})

type MeetingForm = z.infer<typeof meetingSchema>

export default function AdminMeetings() {
  const [showForm, setShowForm] = useState(false)
  const [selectedStudents, setSelectedStudents] = useState<number[]>([])
  const [selectedParents, setSelectedParents] = useState<number[]>([])
  const [selectedGroups, setSelectedGroups] = useState<number[]>([])
  const [selectedTeachers, setSelectedTeachers] = useState<number[]>([])
  const queryClient = useQueryClient()
  const { register, handleSubmit, formState: { errors }, reset, watch } = useForm<MeetingForm>({
    resolver: zodResolver(meetingSchema),
    defaultValues: {
      duration_minutes: 30,
      auto_generate_video_link: false,
      is_published: false,
    }
  })

  const meetingType = watch('meeting_type')
  const videoPlatform = watch('video_platform')
  const autoGenerateVideo = watch('auto_generate_video_link')

  const { data: meetings, isLoading, error } = useQuery({
    queryKey: ['meetings'],
    queryFn: async () => {
      const response = await api.get('/meetings/')
      return response.data
    },
    retry: 1,
  })

  const { data: teachers } = useQuery({
    queryKey: ['teachers'],
    queryFn: async () => {
      const response = await api.get('/auth/teachers/')
      return response.data
    },
  })

  const { data: students } = useQuery({
    queryKey: ['students'],
    queryFn: async () => {
      const response = await api.get('/accounts/students/', { params: { page_size: 500 } })
      return response.data
    },
  })

  const { data: parents } = useQuery({
    queryKey: ['parents'],
    queryFn: async () => {
      const response = await api.get('/accounts/parents/', { params: { page_size: 500 } })
      return response.data
    },
  })

  const { data: classes } = useQuery({
    queryKey: ['school-classes'],
    queryFn: async () => {
      const response = await api.get('/schools/classes/')
      return response.data
    },
  })

  const createMutation = useMutation({
    mutationFn: (data: MeetingForm) => {
      const submitData = {
        ...data,
        student_ids: selectedStudents,
        parent_ids: selectedParents,
        group_ids: selectedGroups,
        participant_ids: selectedTeachers, // Enseignants supplémentaires pour TEACHER_MEETING
      }
      return api.post('/meetings/', submitData)
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['meetings'] })
      showSuccessToast('Réunion créée avec succès')
      setShowForm(false)
      reset()
      setSelectedStudents([])
      setSelectedParents([])
      setSelectedGroups([])
      setSelectedTeachers([])
    },
    onError: (error: any) => {
      showErrorToast(error, 'Erreur lors de la création de la réunion')
    },
  })

  const onSubmit = (data: MeetingForm) => {
    createMutation.mutate(data)
  }

  const toggleStudent = (studentId: number) => {
    setSelectedStudents(prev =>
      prev.includes(studentId)
        ? prev.filter(id => id !== studentId)
        : [...prev, studentId]
    )
  }

  const toggleParent = (parentId: number) => {
    setSelectedParents(prev =>
      prev.includes(parentId)
        ? prev.filter(id => id !== parentId)
        : [...prev, parentId]
    )
  }

  const toggleGroup = (groupId: number) => {
    setSelectedGroups(prev =>
      prev.includes(groupId)
        ? prev.filter(id => id !== groupId)
        : [...prev, groupId]
    )
  }

  const getStatusBadge = (status: string) => {
    const badges: Record<string, string> = {
      SCHEDULED: 'badge-info',
      COMPLETED: 'badge-success',
      CANCELLED: 'badge-danger',
      IN_PROGRESS: 'badge-warning',
    }
    return badges[status] || 'badge-info'
  }

  const getStatusLabel = (status: string) => {
    const labels: Record<string, string> = {
      SCHEDULED: 'Planifiée',
      COMPLETED: 'Terminée',
      CANCELLED: 'Annulée',
      IN_PROGRESS: 'En cours',
    }
    return labels[status] || status
  }

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <h1 className="text-3xl font-bold text-gray-900 dark:text-gray-100">Gestion des Réunions</h1>
        <button
          onClick={() => setShowForm(!showForm)}
          className="btn btn-primary flex items-center gap-2"
        >
          <Plus className="w-5 h-5" />
          Nouvelle réunion
        </button>
      </div>

      {showForm && (
        <Card className="mb-6">
          <h2 className="text-xl font-semibold mb-4 text-gray-900 dark:text-gray-100">Nouvelle réunion</h2>
          <form onSubmit={handleSubmit(onSubmit)} className="space-y-6">
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div>
                <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
                  Titre <span className="text-red-500">*</span>
                </label>
                <input
                  {...register('title')}
                  className="input"
                  placeholder="Titre de la réunion"
                />
                {errors.title && (
                  <p className="mt-1 text-sm text-red-600">{errors.title.message}</p>
                )}
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
                  Type <span className="text-red-500">*</span>
                </label>
                <select {...register('meeting_type')} className="input">
                  <option value="">Sélectionner</option>
                  <option value="INDIVIDUAL">Individuelle</option>
                  <option value="GROUP">Groupe</option>
                  <option value="GENERAL">Générale</option>
                  <option value="TEACHER_MEETING">Réunion avec enseignant</option>
                  <option value="PARENT_MEETING">Réunion avec parent</option>
                </select>
                {errors.meeting_type && (
                  <p className="mt-1 text-sm text-red-600">{errors.meeting_type.message}</p>
                )}
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
                  Enseignant <span className="text-red-500"></span>
                </label>
                <select {...register('teacher', { valueAsNumber: true })} className="input">
                  <option value="">Sélectionner un enseignant</option>
                  {teachers?.results?.map((teacher: any) => (
                    <option key={teacher.id} value={teacher.id}>
                      {[teacher.user?.first_name, teacher.user?.last_name, teacher.user?.middle_name].filter(Boolean).join(' ')}
                    </option>
                  ))}
                </select>
                {errors.teacher && (
                  <p className="mt-1 text-sm text-red-600">{errors.teacher.message}</p>
                )}
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
                  Date et heure <span className="text-red-500">*</span>
                </label>
                <input
                  {...register('meeting_date')}
                  type="datetime-local"
                  className="input"
                />
                {errors.meeting_date && (
                  <p className="mt-1 text-sm text-red-600">{errors.meeting_date.message}</p>
                )}
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
                  Durée (minutes)
                </label>
                <input
                  {...register('duration_minutes', { valueAsNumber: true })}
                  type="number"
                  min="15"
                  max="480"
                  className="input"
                  defaultValue={30}
                />
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
                  Lieu
                </label>
                <input
                  {...register('location')}
                  className="input"
                  placeholder="Lieu de la réunion"
                />
              </div>
            </div>

            {/* Participants - Parents */}
            {(meetingType === 'GROUP' || meetingType === 'GENERAL' || meetingType === 'TEACHER_MEETING' || meetingType === 'PARENT_MEETING') && (
              <div>
                <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
                  {meetingType === 'PARENT_MEETING' ? 'Parents (sélectionnez les parents à inviter)' : 'Parents'}
                </label>
                {meetingType === 'PARENT_MEETING' && (
                  <p className="text-sm text-gray-600 dark:text-gray-400 mb-2">
                    Sélectionnez les parents qui doivent participer à cette réunion.
                  </p>
                )}
                <div className="max-h-40 overflow-y-auto border border-gray-300 dark:border-gray-600 rounded-lg p-2">
                  <div className="space-y-1">
                    {parents?.results?.slice(0, 50).map((parent: any) => (
                      <label key={parent.id} className="flex items-center space-x-2 cursor-pointer hover:bg-gray-100 dark:hover:bg-gray-700 p-2 rounded">
                        <input
                          type="checkbox"
                          checked={selectedParents.includes(parent.id)}
                          onChange={() => toggleParent(parent.id)}
                          className="rounded"
                        />
                        <span className="text-sm text-gray-900 dark:text-gray-100">
                          {[parent.user?.first_name, parent.user?.last_name, parent.user?.middle_name].filter(Boolean).join(' ')}
                        </span>
                      </label>
                    ))}
                  </div>
                </div>
                {selectedParents.length > 0 && (
                  <div className="mt-2 flex flex-wrap gap-2">
                    {selectedParents.map(parentId => {
                      const parent = parents?.results?.find((p: any) => p.id === parentId)
                      return parent ? (
                        <span key={parentId} className="badge badge-info flex items-center gap-1">
                          {[parent.user?.first_name, parent.user?.last_name, parent.user?.middle_name].filter(Boolean).join(' ')}
                          <button
                            type="button"
                            onClick={() => toggleParent(parentId)}
                            className="ml-1"
                          >
                            <X className="w-3 h-3" />
                          </button>
                        </span>
                      ) : null
                    })}
                  </div>
                )}
              </div>
            )}

            {/* Réunion individuelle ou avec enseignant/parent spécifique */}
            {meetingType === 'INDIVIDUAL' && (
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                <div>
                  <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
                    Parent
                  </label>
                  <select {...register('parent', { valueAsNumber: true })} className="input">
                    <option value="">Sélectionner un parent</option>
                    {parents?.results?.map((parent: any) => (
                      <option key={parent.id} value={parent.id}>
                        {[parent.user?.first_name, parent.user?.last_name, parent.user?.middle_name].filter(Boolean).join(' ')}
                      </option>
                    ))}
                  </select>
                </div>
                <div>
                  <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
                    Élève
                  </label>
                  <select {...register('student', { valueAsNumber: true })} className="input">
                    <option value="">Sélectionner un élève</option>
                    {students?.results?.map((student: any) => (
                      <option key={student.id} value={student.id}>
                        {[student.user?.first_name, student.user?.last_name, student.user?.middle_name].filter(Boolean).join(' ')} - {student.student_id}
                      </option>
                    ))}
                  </select>
                </div>
              </div>
            )}

            {/* Réunion avec enseignant - sélection d'enseignants supplémentaires */}
            {meetingType === 'TEACHER_MEETING' && (
              <div>
                <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
                  Enseignants supplémentaires (optionnel)
                </label>
                <p className="text-sm text-gray-600 dark:text-gray-400 mb-2">
                  L'enseignant principal est déjà sélectionné ci-dessus. Vous pouvez ajouter d'autres enseignants comme participants.
                </p>
                <div className="max-h-40 overflow-y-auto border border-gray-300 dark:border-gray-600 rounded-lg p-2">
                  <div className="space-y-1">
                    {teachers?.results?.map((teacher: any) => (
                      <label key={teacher.id} className="flex items-center space-x-2 cursor-pointer hover:bg-gray-100 dark:hover:bg-gray-700 p-2 rounded">
                        <input
                          type="checkbox"
                          checked={selectedTeachers.includes(teacher.id)}
                          onChange={() => {
                            setSelectedTeachers(prev =>
                              prev.includes(teacher.id)
                                ? prev.filter(id => id !== teacher.id)
                                : [...prev, teacher.id]
                            )
                          }}
                          className="rounded"
                        />
                        <span className="text-sm text-gray-900 dark:text-gray-100">
                          {[teacher.user?.first_name, teacher.user?.last_name, teacher.user?.middle_name].filter(Boolean).join(' ')}
                        </span>
                      </label>
                    ))}
                  </div>
                </div>
                {selectedTeachers.length > 0 && (
                  <div className="mt-2 flex flex-wrap gap-2">
                    {selectedTeachers.map(teacherId => {
                      const teacher = teachers?.results?.find((t: any) => t.id === teacherId)
                      return teacher ? (
                        <span key={teacherId} className="badge badge-info flex items-center gap-1">
                          {[teacher.user?.first_name, teacher.user?.last_name, teacher.user?.middle_name].filter(Boolean).join(' ')}
                          <button
                            type="button"
                            onClick={() => {
                              setSelectedTeachers(prev => prev.filter(id => id !== teacherId))
                            }}
                            className="ml-1"
                          >
                            <X className="w-3 h-3" />
                          </button>
                        </span>
                      ) : null
                    })}
                  </div>
                )}
              </div>
            )}

            {/* Réunion avec parent - sélection de parents supplémentaires */}
            {meetingType === 'PARENT_MEETING' && (
              <div>
                <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
                  Parents (sélectionnez les parents à inviter)
                </label>
                <p className="text-sm text-gray-600 dark:text-gray-400 mb-2">
                  Sélectionnez les parents qui doivent participer à cette réunion.
                </p>
                <div className="max-h-40 overflow-y-auto border border-gray-300 dark:border-gray-600 rounded-lg p-2">
                  <div className="space-y-1">
                    {parents?.results?.map((parent: any) => (
                      <label key={parent.id} className="flex items-center space-x-2 cursor-pointer hover:bg-gray-100 dark:hover:bg-gray-700 p-2 rounded">
                        <input
                          type="checkbox"
                          checked={selectedParents.includes(parent.id)}
                          onChange={() => toggleParent(parent.id)}
                          className="rounded"
                        />
                        <span className="text-sm text-gray-900 dark:text-gray-100">
                          {[parent.user?.first_name, parent.user?.last_name, parent.user?.middle_name].filter(Boolean).join(' ')}
                        </span>
                      </label>
                    ))}
                  </div>
                </div>
                {selectedParents.length > 0 && (
                  <div className="mt-2 flex flex-wrap gap-2">
                    {selectedParents.map(parentId => {
                      const parent = parents?.results?.find((p: any) => p.id === parentId)
                      return parent ? (
                        <span key={parentId} className="badge badge-info flex items-center gap-1">
                          {[parent.user?.first_name, parent.user?.last_name, parent.user?.middle_name].filter(Boolean).join(' ')}
                          <button
                            type="button"
                            onClick={() => toggleParent(parentId)}
                            className="ml-1"
                          >
                            <X className="w-3 h-3" />
                          </button>
                        </span>
                      ) : null
                    })}
                  </div>
                )}
              </div>
            )}

            {/* Réunion individuelle */}
            {meetingType === 'INDIVIDUAL' && (
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                <div>
                  <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
                    Parent
                  </label>
                  <select {...register('parent', { valueAsNumber: true })} className="input">
                    <option value="">Sélectionner un parent</option>
                    {parents?.results?.map((parent: any) => (
                      <option key={parent.id} value={parent.id}>
                        {[parent.user?.first_name, parent.user?.last_name, parent.user?.middle_name].filter(Boolean).join(' ')}
                      </option>
                    ))}
                  </select>
                </div>
                <div>
                  <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
                    Élève
                  </label>
                  <select {...register('student', { valueAsNumber: true })} className="input">
                    <option value="">Sélectionner un élève</option>
                    {students?.results?.map((student: any) => (
                      <option key={student.id} value={student.id}>
                        {[student.user?.first_name, student.user?.last_name, student.user?.middle_name].filter(Boolean).join(' ')} - {student.student_id}
                      </option>
                    ))}
                  </select>
                </div>
              </div>
            )}

            {/* Visioconférence */}
            <div className="border-t border-gray-200 dark:border-gray-700 pt-4">
              <h3 className="text-lg font-semibold text-gray-900 dark:text-gray-100 mb-4">Visioconférence</h3>
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                <div>
                  <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
                    Plateforme
                  </label>
                  <select {...register('video_platform')} className="input">
                    <option value="">Sélectionner une plateforme</option>
                    <option value="GOOGLE_MEET">Google Meet</option>
                    <option value="ZOOM">Zoom</option>
                    <option value="TEAMS">Microsoft Teams</option>
                    <option value="OTHER">Autre</option>
                  </select>
                </div>
                <div>
                  <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
                    Générer automatiquement le lien
                  </label>
                  <label className="flex items-center space-x-2 cursor-pointer">
                    <input
                      {...register('auto_generate_video_link')}
                      type="checkbox"
                      className="rounded"
                      disabled={!videoPlatform || videoPlatform === 'OTHER'}
                    />
                    <span className="text-sm text-gray-700 dark:text-gray-300">
                      Générer le lien {videoPlatform === 'GOOGLE_MEET' ? 'Google Meet' : videoPlatform === 'ZOOM' ? 'Zoom' : ''}
                    </span>
                  </label>
                  {videoPlatform && videoPlatform !== 'OTHER' && !autoGenerateVideo && (
                    <div className="mt-2">
                      <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
                        Lien vidéo
                      </label>
                      <input
                        {...register('video_link')}
                        type="url"
                        className="input"
                        placeholder="https://..."
                      />
                    </div>
                  )}
                </div>
              </div>
            </div>

            {/* Description */}
            <div>
              <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
                Description <span className="text-red-500">*</span>
              </label>
              <textarea
                {...register('description')}
                className="input"
                rows={4}
                placeholder="Description de la réunion"
              />
              {errors.description && (
                <p className="mt-1 text-sm text-red-600">{errors.description.message}</p>
              )}
            </div>

            {/* Publication */}
            <div className="border-t border-gray-200 dark:border-gray-700 pt-4">
              <label className="flex items-center space-x-2 cursor-pointer">
                <input
                  {...register('is_published')}
                  type="checkbox"
                  className="rounded"
                />
                <span className="text-sm font-medium text-gray-700 dark:text-gray-300">
                  Publier la réunion (les participants pourront la voir)
                </span>
              </label>
            </div>

            <div className="flex justify-end gap-4 pt-4 border-t border-gray-200 dark:border-gray-700">
              <button
                type="button"
                onClick={() => {
                  setShowForm(false)
                  reset()
                  setSelectedStudents([])
                  setSelectedParents([])
                  setSelectedGroups([])
                }}
                className="btn btn-secondary"
              >
                Annuler
              </button>
              <button
                type="submit"
                disabled={createMutation.isPending}
                className="btn btn-primary"
              >
                {createMutation.isPending ? 'Création...' : 'Créer la réunion'}
              </button>
            </div>
          </form>
        </Card>
      )}

      <Card>
        <div className="overflow-x-auto">
          <table className="w-full">
            <thead className="bg-gray-50 dark:bg-gray-700/50">
              <tr>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-700 dark:text-gray-300 uppercase">Titre</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-700 dark:text-gray-300 uppercase">Type</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-700 dark:text-gray-300 uppercase">Enseignant</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-700 dark:text-gray-300 uppercase">Parent</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-700 dark:text-gray-300 uppercase">Date</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-700 dark:text-gray-300 uppercase">Statut</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-700 dark:text-gray-300 uppercase">Publié</th>
              </tr>
            </thead>
            <tbody className="bg-white dark:bg-gray-800 divide-y divide-gray-200 dark:divide-gray-700">
              {isLoading ? (
                <tr>
                  <td colSpan={7} className="px-6 py-4 text-center">Chargement...</td>
                </tr>
              ) : error ? (
                <tr>
                  <td colSpan={7} className="px-6 py-4 text-center text-red-600">
                    Erreur lors du chargement des réunions
                  </td>
                </tr>
              ) : !meetings?.results || meetings?.results?.length === 0 ? (
                <tr>
                  <td colSpan={7} className="px-6 py-4 text-center text-gray-500">
                    Aucune réunion trouvée
                  </td>
                </tr>
              ) : (
                meetings?.results?.map((meeting: any) => (
                  <tr key={meeting.id} className="hover:bg-gray-50 dark:hover:bg-gray-700/50">
                    <td className="px-6 py-4 whitespace-nowrap">
                      <div className="text-sm font-medium text-gray-900 dark:text-gray-100">{meeting.title}</div>
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500 dark:text-gray-400">
                      {meeting.meeting_type === 'INDIVIDUAL' ? 'Individuelle' 
                       : meeting.meeting_type === 'GROUP' ? 'Groupe' 
                       : meeting.meeting_type === 'GENERAL' ? 'Générale'
                       : meeting.meeting_type === 'TEACHER_MEETING' ? 'Réunion avec enseignant'
                       : meeting.meeting_type === 'PARENT_MEETING' ? 'Réunion avec parent'
                       : meeting.meeting_type}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900 dark:text-gray-100">
                      {meeting.teacher_name || 'N/A'}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900 dark:text-gray-100">
                      {meeting.parent_name || 'N/A'}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500 dark:text-gray-400">
                      {meeting.meeting_date
                        ? format(new Date(meeting.meeting_date), 'dd MMM yyyy HH:mm', { locale: fr })
                        : 'N/A'}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap">
                      <span className={cn('badge', getStatusBadge(meeting.status))}>
                        {getStatusLabel(meeting.status)}
                      </span>
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap">
                      {meeting.is_published ? (
                        <span className="badge badge-success">Oui</span>
                      ) : (
                        <span className="badge badge-secondary">Non</span>
                      )}
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </Card>
    </div>
  )
}
