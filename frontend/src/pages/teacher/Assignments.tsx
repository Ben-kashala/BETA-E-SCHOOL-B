import { useState, useEffect } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import api from '@/services/api'
import { Card } from '@/components/ui/Card'
import { Plus, FileText, Calendar, Users, X, Upload, Pencil, Trash2, GraduationCap, ChevronDown } from 'lucide-react'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'
import { showErrorToast, showSuccessToast } from '@/utils/toast'
import { useAcademicYears } from '@/hooks/useAcademicYears'

const assignmentSchema = z.object({
  title: z.string().min(1, 'Le titre est requis'),
  description: z.string().min(1, 'La description est requise'),
  subject: z.number().min(1, 'La matière est requise'),
  school_class: z.number().min(1, 'La classe est requise'),
  academic_year: z.string().min(1, 'L\'année scolaire est requise'),
  due_date: z.string().min(1, 'La date limite est requise'),
  total_points: z.number().min(0, 'Les points doivent être positifs').default(20),
  is_published: z.boolean().default(false),
})

type AssignmentForm = z.infer<typeof assignmentSchema>

const QUESTION_TYPES = [
  { value: 'SINGLE_CHOICE', label: 'Choix unique' },
  { value: 'MULTIPLE_CHOICE', label: 'Choix multiple' },
  { value: 'TEXT', label: 'Texte' },
  { value: 'NUMBER', label: 'Nombre' },
] as const

export default function TeacherAssignments() {
  const [showForm, setShowForm] = useState(false)
  const [selectedFile, setSelectedFile] = useState<File | null>(null)
  const [selectedAssignmentId, setSelectedAssignmentId] = useState<number | null>(null)
  const [editingQuestionId, setEditingQuestionId] = useState<number | null>(null)
  const [showAddQuestion, setShowAddQuestion] = useState(false)
  const queryClient = useQueryClient()
  const { years: academicYears, current: currentAcademicYear } = useAcademicYears()
  
  const { register, handleSubmit, formState: { errors }, reset } = useForm<AssignmentForm>({
    resolver: zodResolver(assignmentSchema),
    defaultValues: {
      is_published: false,
      total_points: 20,
    },
  })

  const { data: assignments, isLoading, error } = useQuery({
    queryKey: ['assignments'],
    queryFn: async () => {
      const response = await api.get('/elearning/assignments/')
      return response.data
    },
    retry: 1,
  })

  const { data: subjects } = useQuery({
    queryKey: ['subjects'],
    queryFn: async () => {
      const response = await api.get('/schools/subjects/')
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
    mutationFn: async (data: AssignmentForm) => {
      const formData = new FormData()
      
      // Ajouter les champs requis
      formData.append('title', data.title)
      formData.append('description', data.description)
      formData.append('subject', data.subject.toString())
      formData.append('school_class', data.school_class.toString())
      formData.append('academic_year', data.academic_year)
      formData.append('total_points', data.total_points.toString())
      formData.append('is_published', data.is_published.toString())
      
      // Convertir la date locale en format ISO pour le backend
      if (data.due_date) {
        const date = new Date(data.due_date)
        formData.append('due_date', date.toISOString())
      }
      
      // Ajouter le fichier si sélectionné
      if (selectedFile) {
        formData.append('assignment_file', selectedFile)
      }
      
      return api.post('/elearning/assignments/', formData, {
        headers: {
          'Content-Type': 'multipart/form-data',
        },
      })
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['assignments'] })
      showSuccessToast('Devoir créé avec succès')
      setShowForm(false)
      reset()
      setSelectedFile(null)
    },
    onError: (error: any) => {
      showErrorToast(error, 'Erreur lors de la création du devoir')
    },
  })

  const onSubmit = (data: AssignmentForm) => {
    createMutation.mutate(data)
  }

  const { data: selectedAssignment, isLoading: loadingAssignment } = useQuery({
    queryKey: ['assignment', selectedAssignmentId],
    queryFn: async () => {
      const res = await api.get(`/elearning/assignments/${selectedAssignmentId}/`)
      return res.data
    },
    enabled: !!selectedAssignmentId,
  })

  const { data: submissions = [], refetch: refetchSubmissions } = useQuery({
    queryKey: ['assignment-submissions', selectedAssignmentId],
    queryFn: async () => {
      const res = await api.get('/elearning/submissions/', { params: { assignment: selectedAssignmentId } })
      return (res.data?.results ?? res.data ?? []) as any[]
    },
    enabled: !!selectedAssignmentId,
  })

  const gradeMutation = useMutation({
    mutationFn: async ({
      id,
      payload,
    }: {
      id: number
      payload: { answers?: { question_id: number; points_earned: number; teacher_feedback: string }[]; score?: number; feedback: string }
    }) => api.post(`/elearning/submissions/${id}/grade/`, payload),
    onSuccess: () => {
      refetchSubmissions()
      queryClient.invalidateQueries({ queryKey: ['assignments'] })
      queryClient.invalidateQueries({ queryKey: ['student-submissions'] })
      queryClient.invalidateQueries({ queryKey: ['student-elearning-grades'] })
      showSuccessToast('Notation enregistrée')
    },
    onError: (e: any) => showErrorToast(e, 'Erreur lors de la notation'),
  })

  const allowResubmitMutation = useMutation({
    mutationFn: (submissionId: number) => api.post(`/elearning/submissions/${submissionId}/allow_resubmit/`),
    onSuccess: () => {
      refetchSubmissions()
      queryClient.invalidateQueries({ queryKey: ['student-submissions'] })
      showSuccessToast('L\'élève peut soumettre à nouveau ce devoir.')
    },
    onError: (e: any) => showErrorToast(e, 'Erreur lors de l\'autorisation'),
  })

  const { data: assignmentQuestions = [], refetch: refetchQuestions } = useQuery({
    queryKey: ['assignment-questions', selectedAssignmentId],
    queryFn: async () => {
      const res = await api.get(`/elearning/assignments/${selectedAssignmentId}/questions/`)
      return res.data as any[]
    },
    enabled: !!selectedAssignmentId,
  })

  const updateMutation = useMutation({
    mutationFn: async ({ id, data }: { id: number; data: Partial<AssignmentForm> }) => {
      const formData = new FormData()
      Object.entries(data).forEach(([k, v]) => {
        if (v !== undefined && v !== null)
          formData.append(k, typeof v === 'boolean' ? String(v) : String(v))
      })
      if (selectedFile) formData.append('assignment_file', selectedFile)
      return api.patch(`/elearning/assignments/${id}/`, formData, {
        headers: selectedFile ? { 'Content-Type': 'multipart/form-data' } : {},
      })
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['assignments'] })
      queryClient.invalidateQueries({ queryKey: ['assignment', selectedAssignmentId] })
      showSuccessToast('Devoir mis à jour')
    },
    onError: (e: any) => showErrorToast(e, 'Erreur lors de la mise à jour'),
  })

  const addQuestionMutation = useMutation({
    mutationFn: async (body: any) =>
      api.post(`/elearning/assignments/${selectedAssignmentId}/questions/`, body),
    onSuccess: () => {
      refetchQuestions()
      setShowAddQuestion(false)
      showSuccessToast('Question ajoutée')
    },
    onError: (e: any) => showErrorToast(e, 'Erreur'),
  })

  const updateQuestionMutation = useMutation({
    mutationFn: async ({ id, body }: { id: number; body: any }) =>
      api.patch(`/elearning/assignment-questions/${id}/`, body),
    onSuccess: () => {
      refetchQuestions()
      setEditingQuestionId(null)
      showSuccessToast('Question mise à jour')
    },
    onError: (e: any) => showErrorToast(e, 'Erreur'),
  })

  const deleteQuestionMutation = useMutation({
    mutationFn: (id: number) => api.delete(`/elearning/assignment-questions/${id}/`),
    onSuccess: () => {
      refetchQuestions()
      showSuccessToast('Question supprimée')
    },
    onError: (e: any) => showErrorToast(e, 'Erreur'),
  })

  const onUpdateAssignment = (data: AssignmentForm) => {
    if (!selectedAssignmentId) return
    updateMutation.mutate({
      id: selectedAssignmentId,
      data: {
        ...data,
        due_date: data.due_date ? new Date(data.due_date).toISOString() : undefined,
      },
    })
  }

  useEffect(() => {
    if (selectedAssignment) {
      const d = selectedAssignment as any
      const due = d.due_date ? new Date(d.due_date) : null
      reset({
        title: d.title ?? '',
        description: d.description ?? '',
        subject: d.subject ?? 0,
        school_class: d.school_class ?? 0,
        academic_year: d.academic_year ?? '',
        due_date: due ? `${due.getFullYear()}-${String(due.getMonth() + 1).padStart(2, '0')}-${String(due.getDate()).padStart(2, '0')}T${String(due.getHours()).padStart(2, '0')}:${String(due.getMinutes()).padStart(2, '0')}` : '',
        total_points: d.total_points ?? 20,
        is_published: d.is_published ?? false,
      })
    }
  }, [selectedAssignment, reset])

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <h1 className="text-3xl font-bold text-gray-900 dark:text-white">Gestion des Devoirs</h1>
        <button 
          onClick={() => setShowForm(!showForm)}
          className="btn btn-primary flex items-center space-x-2"
        >
          <Plus className="w-4 h-4" />
          <span>Nouveau devoir</span>
        </button>
      </div>

      {showForm && (
        <Card className="mb-6 p-6">
          <div className="flex items-center justify-between mb-4">
            <h2 className="text-xl font-semibold">Nouveau devoir</h2>
            <button
              onClick={() => {
                setShowForm(false)
                reset()
                setSelectedFile(null)
              }}
              className="text-gray-500 hover:text-gray-700 dark:hover:text-gray-300"
            >
              <X className="w-5 h-5" />
            </button>
          </div>
          <form onSubmit={handleSubmit(onSubmit)} className="space-y-4">
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div>
                <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
                  Titre <span className="text-red-500">*</span>
                </label>
                <input
                  {...register('title')}
                  className="input"
                  placeholder="Titre du devoir"
                />
                {errors.title && (
                  <p className="mt-1 text-sm text-red-600">{errors.title.message}</p>
                )}
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
                  Matière <span className="text-red-500">*</span>
                </label>
                <select {...register('subject', { valueAsNumber: true })} className="input">
                  <option value="">Sélectionner une matière</option>
                  {subjects?.results?.map((subject: any) => (
                    <option key={subject.id} value={subject.id}>
                      {subject.name}
                    </option>
                  ))}
                </select>
                {errors.subject && (
                  <p className="mt-1 text-sm text-red-600">{errors.subject.message}</p>
                )}
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
                  Classe <span className="text-red-500">*</span>
                </label>
                <select {...register('school_class', { valueAsNumber: true })} className="input">
                  <option value="">Sélectionner une classe</option>
                  {classes?.results?.map((cls: any) => (
                    <option key={cls.id} value={cls.id}>
                      {cls.name}
                    </option>
                  ))}
                </select>
                {errors.school_class && (
                  <p className="mt-1 text-sm text-red-600">{errors.school_class.message}</p>
                )}
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
                  Année scolaire <span className="text-red-500">*</span>
                </label>
                {academicYears.length > 0 ? (
                  <select {...register('academic_year')} className="input">
                    <option value="">
                      {currentAcademicYear
                        ? `Sélectionner (par défaut ${currentAcademicYear})`
                        : 'Sélectionner une année'}
                    </option>
                    {academicYears.map((year) => (
                      <option key={year} value={year}>
                        {year}
                      </option>
                    ))}
                  </select>
                ) : (
                  <input
                    {...register('academic_year')}
                    className="input"
                    placeholder="Ex: 2024-2025"
                  />
                )}
                {errors.academic_year && (
                  <p className="mt-1 text-sm text-red-600">{errors.academic_year.message}</p>
                )}
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
                  Date limite <span className="text-red-500">*</span>
                </label>
                <input
                  {...register('due_date')}
                  type="datetime-local"
                  className="input"
                />
                {errors.due_date && (
                  <p className="mt-1 text-sm text-red-600">{errors.due_date.message}</p>
                )}
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
                  Points totaux
                </label>
                <input
                  {...register('total_points', { valueAsNumber: true })}
                  type="number"
                  min="0"
                  step="0.01"
                  className="input"
                />
                {errors.total_points && (
                  <p className="mt-1 text-sm text-red-600">{errors.total_points.message}</p>
                )}
              </div>
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
                Description <span className="text-red-500">*</span>
              </label>
              <textarea
                {...register('description')}
                className="input"
                rows={4}
                placeholder="Description du devoir"
              />
              {errors.description && (
                <p className="mt-1 text-sm text-red-600">{errors.description.message}</p>
              )}
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
                Fichier du devoir (optionnel)
              </label>
              <div className="flex items-center gap-2">
                <label className="btn btn-secondary flex items-center gap-2 cursor-pointer">
                  <Upload className="w-4 h-4" />
                  {selectedFile ? selectedFile.name : 'Choisir un fichier'}
                  <input
                    type="file"
                    className="hidden"
                    onChange={(e) => {
                      const file = e.target.files?.[0]
                      if (file) {
                        setSelectedFile(file)
                      }
                    }}
                  />
                </label>
                {selectedFile && (
                  <button
                    type="button"
                    onClick={() => setSelectedFile(null)}
                    className="text-sm text-red-600 hover:text-red-700"
                  >
                    Supprimer
                  </button>
                )}
              </div>
            </div>
            <div className="flex items-center gap-4">
              <label className="flex items-center gap-2 cursor-pointer">
                <input
                  {...register('is_published')}
                  type="checkbox"
                  className="checkbox"
                />
                <span className="text-sm text-gray-700 dark:text-gray-300">Publier immédiatement</span>
              </label>
            </div>
            <div className="flex gap-2">
              <button
                type="submit"
                className="btn btn-primary"
                disabled={createMutation.isPending}
              >
                {createMutation.isPending ? 'Création...' : 'Créer le devoir'}
              </button>
              <button
                type="button"
                onClick={() => {
                  setShowForm(false)
                  reset()
                  setSelectedFile(null)
                }}
                className="btn btn-secondary"
              >
                Annuler
              </button>
            </div>
          </form>
        </Card>
      )}

      {isLoading ? (
        <Card>
          <div className="text-center py-12">
            <div className="inline-block animate-spin rounded-full h-8 w-8 border-b-2 border-primary-600"></div>
            <p className="mt-4 text-gray-600 dark:text-gray-400">Chargement des devoirs...</p>
          </div>
        </Card>
      ) : error ? (
        <Card>
          <div className="text-center py-12 text-red-600">
            Erreur lors du chargement des devoirs
          </div>
        </Card>
      ) : !assignments?.results || assignments?.results?.length === 0 ? (
        <Card>
          <div className="text-center py-12 text-gray-500">
            <FileText className="mx-auto h-12 w-12 text-gray-400 mb-4" />
            <p>Aucun devoir trouvé</p>
          </div>
        </Card>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
          {assignments?.results?.map((assignment: any) => (
            <Card
              key={assignment.id}
              className="hover:shadow-lg transition-shadow cursor-pointer"
              onClick={() => setSelectedAssignmentId(assignment.id)}
            >
              <div className="flex items-start justify-between mb-3">
                <h3 className="text-lg font-semibold text-gray-900 dark:text-white flex-1">
                  {assignment.title}
                </h3>
                <span className="flex items-center gap-1 text-gray-500 hover:text-primary-600" title="Ouvrir / Modifier">
                  <Pencil className="w-4 h-4" />
                </span>
                {!assignment.is_published && (
                  <span className="badge badge-warning ml-2">Brouillon</span>
                )}
              </div>
              
              <p className="text-sm text-gray-600 dark:text-gray-400 mb-4 line-clamp-3">
                {assignment.description}
              </p>
              
              <div className="space-y-2 mb-4">
                <div className="flex items-center gap-2 text-sm text-gray-600 dark:text-gray-400">
                  <Calendar className="w-4 h-4" />
                  <span>Échéance: {new Date(assignment.due_date).toLocaleDateString('fr-FR')}</span>
                </div>
                {assignment.class_name && (
                  <div className="flex items-center gap-2 text-sm text-gray-600 dark:text-gray-400">
                    <Users className="w-4 h-4" />
                    <span>{assignment.class_name}</span>
                  </div>
                )}
                {assignment.subject_name && (
                  <div className="text-sm text-gray-600 dark:text-gray-400">
                    <span className="badge badge-info">{assignment.subject_name}</span>
                  </div>
                )}
              </div>
              
              <div className="flex items-center justify-between pt-4 border-t border-gray-200 dark:border-gray-700">
                <span className="badge badge-info text-sm">
                  {assignment.total_points || 0} pts
                </span>
                {assignment.submission_count !== undefined && (
                  <span className="text-sm text-gray-500 dark:text-gray-400">
                    {assignment.submission_count} soumission(s)
                  </span>
                )}
              </div>
            </Card>
          ))}
        </div>
      )}

      {/* Modal Ouvrir / Modifier le devoir */}
      {selectedAssignmentId && (
        <div
          className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4"
          onClick={() => {
            setSelectedAssignmentId(null)
            setShowAddQuestion(false)
            setEditingQuestionId(null)
          }}
        >
          <div
            className="bg-white dark:bg-gray-900 rounded-xl shadow-xl max-w-3xl w-full max-h-[90vh] overflow-y-auto"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex items-center justify-between p-4 border-b border-gray-200 dark:border-gray-700 sticky top-0 bg-white dark:bg-gray-900 z-10">
              <h2 className="text-xl font-bold text-gray-900 dark:text-white">
                {selectedAssignment ? (selectedAssignment as any).title : 'Chargement...'}
              </h2>
              <button
                type="button"
                onClick={() => {
                  setSelectedAssignmentId(null)
                  setShowAddQuestion(false)
                  setEditingQuestionId(null)
                }}
                className="p-2 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-800 text-gray-500"
              >
                <X className="w-5 h-5" />
              </button>
            </div>
            <div className="p-4 space-y-6">
              {loadingAssignment ? (
                <div className="py-8 text-center text-gray-500">Chargement...</div>
              ) : selectedAssignment ? (
                <>
                  <section>
                    <h3 className="text-sm font-semibold text-gray-700 dark:text-gray-300 mb-3">Modifier le devoir</h3>
                    <form onSubmit={handleSubmit(onUpdateAssignment)} className="space-y-4">
                      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                        <div>
                          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">Titre</label>
                          <input {...register('title')} className="input w-full" />
                          {errors.title && <p className="text-sm text-red-600">{errors.title.message}</p>}
                        </div>
                        <div>
                          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">Matière</label>
                          <select {...register('subject', { valueAsNumber: true })} className="input w-full">
                            {subjects?.results?.map((s: any) => (
                              <option key={s.id} value={s.id}>{s.name}</option>
                            ))}
                          </select>
                        </div>
                        <div>
                          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">Classe</label>
                          <select {...register('school_class', { valueAsNumber: true })} className="input w-full">
                            {classes?.results?.map((c: any) => (
                              <option key={c.id} value={c.id}>{c.name}</option>
                            ))}
                          </select>
                        </div>
                        <div>
                          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">Année scolaire</label>
                          <input {...register('academic_year')} className="input w-full" />
                        </div>
                        <div>
                          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">Date limite</label>
                          <input {...register('due_date')} type="datetime-local" className="input w-full" />
                        </div>
                        <div>
                          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">Points totaux</label>
                          <input {...register('total_points', { valueAsNumber: true })} type="number" min={0} step={0.01} className="input w-full" />
                        </div>
                      </div>
                      <div>
                        <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">Description</label>
                        <textarea {...register('description')} className="input w-full" rows={3} />
                      </div>
                      <div className="flex items-center gap-2">
                        <label className="flex items-center gap-2 cursor-pointer">
                          <input {...register('is_published')} type="checkbox" className="checkbox" />
                          <span className="text-sm">Publier</span>
                        </label>
                        <button type="submit" className="btn btn-primary" disabled={updateMutation.isPending}>
                          {updateMutation.isPending ? 'Enregistrement...' : 'Enregistrer les modifications'}
                        </button>
                      </div>
                    </form>
                  </section>

                  <section>
                    <div className="flex items-center justify-between mb-3">
                      <h3 className="text-sm font-semibold text-gray-700 dark:text-gray-300">Questions du devoir</h3>
                      <button
                        type="button"
                        onClick={() => setShowAddQuestion(true)}
                        className="btn btn-secondary text-sm flex items-center gap-1"
                      >
                        <Plus className="w-4 h-4" /> Ajouter une question
                      </button>
                    </div>
                    {assignmentQuestions.length === 0 && !showAddQuestion && (
                      <p className="text-sm text-gray-500 dark:text-gray-400">Aucune question. Cliquez sur « Ajouter une question ».</p>
                    )}
                    <ul className="space-y-2">
                      {assignmentQuestions.map((q: any) => (
                        <li key={q.id} className="flex items-start justify-between gap-2 p-3 rounded-lg bg-gray-50 dark:bg-gray-800">
                          <div className="flex-1 min-w-0">
                            <span className="text-xs text-gray-500 dark:text-gray-400 font-medium">
                              {QUESTION_TYPES.find(t => t.value === q.question_type)?.label ?? q.question_type} • {q.points} pts
                            </span>
                            <p className="text-sm text-gray-900 dark:text-white mt-0.5">{q.question_text}</p>
                          </div>
                          <div className="flex gap-1">
                            <button
                              type="button"
                              onClick={() => setEditingQuestionId(editingQuestionId === q.id ? null : q.id)}
                              className="p-1.5 rounded hover:bg-gray-200 dark:hover:bg-gray-700 text-gray-600"
                              title="Modifier"
                            >
                              <Pencil className="w-4 h-4" />
                            </button>
                            <button
                              type="button"
                              onClick={() => {
                                if (window.confirm('Supprimer cette question ?')) deleteQuestionMutation.mutate(q.id)
                              }}
                              className="p-1.5 rounded hover:bg-red-100 dark:hover:bg-red-900/30 text-red-600"
                              title="Supprimer"
                            >
                              <Trash2 className="w-4 h-4" />
                            </button>
                          </div>
                        </li>
                      ))}
                    </ul>
                    {showAddQuestion && (
                      <QuestionForm
                        types={QUESTION_TYPES}
                        onSave={(body) => addQuestionMutation.mutate(body)}
                        onCancel={() => setShowAddQuestion(false)}
                        isPending={addQuestionMutation.isPending}
                      />
                    )}
                    {editingQuestionId && (() => {
                      const q = assignmentQuestions.find((x: any) => x.id === editingQuestionId)
                      if (!q) return null
                      return (
                        <QuestionForm
                          types={QUESTION_TYPES}
                          initial={q}
                          onSave={(body) => updateQuestionMutation.mutate({ id: q.id, body })}
                          onCancel={() => setEditingQuestionId(null)}
                          isPending={updateQuestionMutation.isPending}
                        />
                      )
                    })()}
                  </section>

                  <section>
                    <h3 className="text-sm font-semibold text-gray-700 dark:text-gray-300 mb-3 flex items-center gap-2">
                      <GraduationCap className="w-4 h-4" />
                      Soumissions des élèves ({submissions.length})
                    </h3>
                    {submissions.length === 0 ? (
                      <p className="text-sm text-gray-500 dark:text-gray-400">Aucune soumission pour le moment.</p>
                    ) : (
                      <div className="space-y-3">
                        {submissions.map((sub: any) => (
                          <SubmissionCard
                            key={sub.id}
                            submission={sub}
                            assignmentQuestions={assignmentQuestions}
                            totalPoints={Number(selectedAssignment?.total_points ?? 20)}
                            onGrade={(payload) => gradeMutation.mutate({ id: sub.id, payload })}
                            isGrading={gradeMutation.isPending}
                            onAllowResubmit={() => allowResubmitMutation.mutate(sub.id)}
                            isAllowingResubmit={allowResubmitMutation.isPending}
                          />
                        ))}
                      </div>
                    )}
                  </section>
                </>
              ) : null}
            </div>
          </div>
        </div>
      )}
    </div>
  )
}

function SubmissionCard({
  submission,
  assignmentQuestions,
  totalPoints = 20,
  onGrade,
  isGrading,
  onAllowResubmit,
  isAllowingResubmit,
}: {
  submission: any
  assignmentQuestions: any[]
  totalPoints?: number
  onGrade: (payload: {
    answers?: { question_id: number; points_earned: number; teacher_feedback: string }[]
    score?: number
    feedback: string
  }) => void
  isGrading: boolean
  onAllowResubmit?: () => void
  isAllowingResubmit?: boolean
}) {
  const [expanded, setExpanded] = useState(false)
  const [feedback, setFeedback] = useState(submission.feedback ?? '')
  const [score, setScore] = useState(String(submission.score ?? ''))
  const [answerOverrides, setAnswerOverrides] = useState<
    Record<number, { points_earned?: string; teacher_feedback?: string }>
  >({})
  useEffect(() => {
    setFeedback(submission.feedback ?? '')
    setScore(String(submission.score ?? ''))
  }, [submission.id, submission.feedback, submission.score])

  const answerGrades = submission.answer_grades || {}
  let answers: Record<string, string> = {}
  try {
    answers = submission.submission_text ? JSON.parse(submission.submission_text) : {}
  } catch {}

  const getAnswer = (qId: number) => answers[String(qId)] ?? answers[qId] ?? '(vide)'
  const getPoints = (q: any) =>
    answerOverrides[q.id]?.points_earned ?? String(answerGrades[String(q.id)]?.points_earned ?? '')
  const getFeedback = (q: any) =>
    answerOverrides[q.id]?.teacher_feedback ?? (answerGrades[String(q.id)]?.teacher_feedback ?? '')

  const updateOverride = (qId: number, field: 'points_earned' | 'teacher_feedback', value: string) => {
    setAnswerOverrides((prev) => ({
      ...prev,
      [qId]: { ...prev[qId], [field]: value },
    }))
  }

  const handleGrade = () => {
    if (assignmentQuestions.length > 0) {
      const answers = assignmentQuestions.map((q: any) => {
        const ptsStr = getPoints(q)
        const ptsNum = parseFloat(String(ptsStr).replace(',', '.'))
        return {
          question_id: q.id,
          points_earned: isNaN(ptsNum) ? 0 : ptsNum,
          teacher_feedback: getFeedback(q) || '',
        }
      })
      onGrade({ answers, feedback })
    } else {
      const scoreNum = parseFloat(String(score).replace(',', '.'))
      onGrade({ score: isNaN(scoreNum) ? 0 : scoreNum, feedback })
    }
  }

  return (
    <div className="border border-gray-200 dark:border-gray-600 rounded-lg overflow-hidden">
      <button
        type="button"
        onClick={() => setExpanded(!expanded)}
        className="w-full px-4 py-3 flex items-center justify-between bg-gray-50 dark:bg-gray-800 hover:bg-gray-100 dark:hover:bg-gray-700"
      >
        <div className="flex items-center gap-3">
          <span className="font-medium text-gray-900 dark:text-white">
            {submission.student_name || submission.student_id || 'Élève'}
          </span>
          <span
            className={`badge ${submission.status === 'GRADED' ? 'badge-success' : submission.status === 'LATE' ? 'badge-warning' : 'badge-info'}`}
          >
            {submission.status === 'GRADED' ? 'Noté' : submission.status === 'LATE' ? 'En retard' : 'Soumis'}
          </span>
          {submission.score != null && (
            <span className="text-sm text-gray-600 dark:text-gray-400">
              {submission.score}/{totalPoints}
            </span>
          )}
        </div>
        <ChevronDown className={`w-5 h-5 transition-transform ${expanded ? 'rotate-180' : ''}`} />
      </button>
      {expanded && (
        <div className="p-4 border-t border-gray-200 dark:border-gray-600 space-y-4">
          {submission.submission_file && (
            <div>
              <a
                href={submission.submission_file}
                target="_blank"
                rel="noopener noreferrer"
                className="text-primary-600 hover:underline text-sm"
              >
                Télécharger le fichier joint
              </a>
            </div>
          )}
          {assignmentQuestions.length > 0 && (
            <div className="space-y-4">
              <p className="text-xs font-medium text-gray-500 dark:text-gray-400 uppercase">
                Détail des réponses – Modifier la notation par question (comme pour les Quiz)
              </p>
              {assignmentQuestions.map((q: any) => (
                <div
                  key={q.id}
                  className="text-sm border border-gray-200 dark:border-gray-600 rounded-lg p-3 space-y-2"
                >
                  <span className="text-xs text-gray-500 dark:text-gray-400">
                    {q.question_type} • {q.points} pts
                  </span>
                  <p className="font-medium text-gray-700 dark:text-gray-300">{q.question_text}</p>
                  <p className="text-gray-600 dark:text-gray-400">→ {getAnswer(q.id)}</p>
                  <div className="flex flex-col sm:flex-row gap-2 pt-2">
                    <div className="flex items-center gap-2">
                      <label className="text-xs text-gray-500">Points :</label>
                      <input
                        type="text"
                        inputMode="decimal"
                        placeholder={`${q.points}`}
                        value={getPoints(q)}
                        onChange={(e) => updateOverride(q.id, 'points_earned', e.target.value)}
                        className="input w-20 text-sm"
                      />
                    </div>
                    <div className="flex-1 flex items-center gap-2">
                      <label className="text-xs text-gray-500">Commentaire :</label>
                      <input
                        type="text"
                        placeholder="Commentaire pour cette question..."
                        value={getFeedback(q)}
                        onChange={(e) => updateOverride(q.id, 'teacher_feedback', e.target.value)}
                        className="input flex-1 text-sm"
                      />
                    </div>
                  </div>
                </div>
              ))}
            </div>
          )}
          {assignmentQuestions.length === 0 && (
            <div className="flex flex-col sm:flex-row gap-3 flex-wrap">
              <label className="flex items-center gap-2">
                <span className="text-xs text-gray-500">Note :</span>
                <input
                  type="text"
                  inputMode="decimal"
                  placeholder={`/${totalPoints}`}
                  value={score}
                  onChange={(e) => setScore(e.target.value)}
                  className="input w-24"
                />
              </label>
            </div>
          )}
          {!submission.submission_text && !submission.submission_file && assignmentQuestions.length === 0 && (
            <p className="text-sm text-gray-500">Aucune réponse détaillée</p>
          )}
          <div className="pt-2 border-t border-gray-200 dark:border-gray-600 flex flex-col sm:flex-row gap-3 flex-wrap">
            <div className="flex-1 flex items-center gap-2 min-w-[200px]">
              <label className="text-xs text-gray-500">Commentaire général :</label>
              <input
                type="text"
                placeholder="Commentaire général (optionnel)"
                value={feedback}
                onChange={(e) => setFeedback(e.target.value)}
                className="input flex-1 text-sm"
              />
            </div>
            <button
              type="button"
              onClick={handleGrade}
              disabled={isGrading}
              className="btn btn-primary"
            >
              {isGrading ? '...' : submission.status === 'GRADED' ? 'Modifier' : 'Noter'}
            </button>
            {onAllowResubmit && (
              <button
                type="button"
                onClick={onAllowResubmit}
                disabled={isAllowingResubmit}
                className="btn btn-secondary"
                title="L'élève pourra soumettre une seule fois à nouveau"
              >
                {isAllowingResubmit ? '...' : 'Autoriser une nouvelle soumission'}
              </button>
            )}
          </div>
        </div>
      )}
    </div>
  )
}

function QuestionForm({
  types,
  initial,
  onSave,
  onCancel,
  isPending,
}: {
  types: readonly { value: string; label: string }[]
  initial?: any
  onSave: (body: any) => void
  onCancel: () => void
  isPending: boolean
}) {
  const [question_text, setQuestion_text] = useState(initial?.question_text ?? '')
  const [question_type, setQuestion_type] = useState(initial?.question_type ?? 'SINGLE_CHOICE')
  const [points, setPoints] = useState(initial?.points ?? 1)
  const [order, setOrder] = useState(initial?.order ?? 0)
  const [option_a, setOption_a] = useState(initial?.option_a ?? '')
  const [option_b, setOption_b] = useState(initial?.option_b ?? '')
  const [option_c, setOption_c] = useState(initial?.option_c ?? '')
  const [option_d, setOption_d] = useState(initial?.option_d ?? '')
  const [correct_answer, setCorrect_answer] = useState(initial?.correct_answer ?? '')
  const isChoice = question_type === 'SINGLE_CHOICE' || question_type === 'MULTIPLE_CHOICE'
  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault()
    const body: any = { question_text, question_type, points, order }
    if (isChoice) {
      body.option_a = option_a
      body.option_b = option_b
      body.option_c = option_c
      body.option_d = option_d
      body.correct_answer = correct_answer
    } else {
      body.correct_answer = correct_answer
    }
    onSave(body)
  }
  return (
    <form onSubmit={handleSubmit} className="p-4 rounded-lg border border-gray-200 dark:border-gray-700 space-y-3">
      <h4 className="text-sm font-medium text-gray-700 dark:text-gray-300">
        {initial ? 'Modifier la question' : 'Nouvelle question'}
      </h4>
      <div>
        <label className="block text-xs text-gray-500 dark:text-gray-400 mb-1">Type</label>
        <select value={question_type} onChange={(e) => setQuestion_type(e.target.value)} className="input w-full">
          {types.map((t) => (
            <option key={t.value} value={t.value}>{t.label}</option>
          ))}
        </select>
      </div>
      <div>
        <label className="block text-xs text-gray-500 dark:text-gray-400 mb-1">Question</label>
        <textarea value={question_text} onChange={(e) => setQuestion_text(e.target.value)} className="input w-full" rows={2} required />
      </div>
      <div className="grid grid-cols-2 gap-2">
        <div>
          <label className="block text-xs text-gray-500 dark:text-gray-400 mb-1">Points</label>
          <input type="number" min={0} step={0.01} value={points} onChange={(e) => setPoints(Number(e.target.value))} className="input w-full" />
        </div>
        <div>
          <label className="block text-xs text-gray-500 dark:text-gray-400 mb-1">Ordre</label>
          <input type="number" min={0} value={order} onChange={(e) => setOrder(Number(e.target.value))} className="input w-full" />
        </div>
      </div>
      {isChoice && (
        <div className="space-y-2">
          <input placeholder="Option A" value={option_a} onChange={(e) => setOption_a(e.target.value)} className="input w-full text-sm" />
          <input placeholder="Option B" value={option_b} onChange={(e) => setOption_b(e.target.value)} className="input w-full text-sm" />
          <input placeholder="Option C" value={option_c} onChange={(e) => setOption_c(e.target.value)} className="input w-full text-sm" />
          <input placeholder="Option D" value={option_d} onChange={(e) => setOption_d(e.target.value)} className="input w-full text-sm" />
          <input placeholder="Réponse correcte (A, B, C, D ou A,B pour multiple)" value={correct_answer} onChange={(e) => setCorrect_answer(e.target.value)} className="input w-full text-sm" />
        </div>
      )}
      {!isChoice && (
        <div>
          <label className="block text-xs text-gray-500 dark:text-gray-400 mb-1">Réponse correcte attendue (texte ou nombre)</label>
          <input value={correct_answer} onChange={(e) => setCorrect_answer(e.target.value)} className="input w-full" />
        </div>
      )}
      <div className="flex gap-2">
        <button type="submit" className="btn btn-primary" disabled={isPending}>{isPending ? 'Enregistrement...' : 'Enregistrer'}</button>
        <button type="button" onClick={onCancel} className="btn btn-secondary">Annuler</button>
      </div>
    </form>
  )
}
