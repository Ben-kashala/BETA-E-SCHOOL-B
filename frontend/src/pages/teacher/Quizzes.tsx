import { useState, useEffect } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import api from '@/services/api'
import { Card } from '@/components/ui/Card'
import { Plus, FileText, Calendar, Users, X, Pencil, Trash2, Clock, GraduationCap, ChevronDown } from 'lucide-react'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'
import { showErrorToast, showSuccessToast } from '@/utils/toast'
import { useAcademicYears } from '@/hooks/useAcademicYears'

const toNum = (v: unknown) => (typeof v === 'string' ? parseFloat(v.replace(',', '.')) : Number(v))

const quizSchema = z.object({
  title: z.string().min(1, 'Le titre est requis'),
  description: z.string().optional(),
  subject: z.union([z.number(), z.string()]).transform((v) => (isNaN(toNum(v)) ? 0 : toNum(v))).pipe(z.number().min(1, 'La matière est requise')),
  school_class: z.union([z.number(), z.string()]).transform((v) => (isNaN(toNum(v)) ? 0 : toNum(v))).pipe(z.number().min(1, 'La classe est requise')),
  academic_year: z.string().min(1, "L'année scolaire est requise"),
  start_date: z.string().min(1, 'La date de début est requise'),
  end_date: z.string().min(1, 'La date de fin est requise'),
  total_points: z.union([z.number(), z.string()]).transform((v) => (isNaN(toNum(v)) ? 20 : toNum(v))).pipe(z.number().min(0)),
  time_limit: z.union([z.number(), z.string(), z.null()]).optional().transform((v) => {
    if (v === '' || v === null || v === undefined) return null
    const n = toNum(v)
    return isNaN(n) ? null : n
  }),
  passing_score: z.union([z.number(), z.string(), z.null()]).optional().transform((v) => {
    if (v === '' || v === null || v === undefined) return null
    const n = toNum(v)
    return isNaN(n) ? null : n
  }),
  allow_multiple_attempts: z.boolean().default(false),
  max_attempts: z.union([z.number(), z.string()]).transform((v) => (isNaN(toNum(v)) ? 1 : Math.max(1, toNum(v)))),
  shuffle_questions: z.boolean().default(false),
  show_results_immediately: z.boolean().default(true),
  is_published: z.boolean().default(false),
})

type QuizForm = z.infer<typeof quizSchema>

const QUESTION_TYPES = [
  { value: 'SINGLE_CHOICE', label: 'Choix unique' },
  { value: 'MULTIPLE_CHOICE', label: 'Choix multiple' },
  { value: 'TEXT', label: 'Texte' },
  { value: 'NUMBER', label: 'Nombre' },
  { value: 'TRUE_FALSE', label: 'Vrai/Faux' },
  { value: 'SHORT_ANSWER', label: 'Réponse courte' },
  { value: 'ESSAY', label: 'Dissertation' },
] as const

export default function TeacherQuizzes() {
  const [showForm, setShowForm] = useState(false)
  const [selectedQuizId, setSelectedQuizId] = useState<number | null>(null)
  const [editingQuestionId, setEditingQuestionId] = useState<number | null>(null)
  const [showAddQuestion, setShowAddQuestion] = useState(false)
  const queryClient = useQueryClient()
  const { years: academicYears, current: currentAcademicYear } = useAcademicYears()

  const { register, handleSubmit, formState: { errors }, reset } = useForm<QuizForm>({
    resolver: zodResolver(quizSchema),
    defaultValues: {
      is_published: false,
      total_points: 20,
      allow_multiple_attempts: false,
      max_attempts: 1,
      shuffle_questions: false,
      show_results_immediately: true,
    },
  })

  const { data: quizzes, isLoading, error } = useQuery({
    queryKey: ['quizzes'],
    queryFn: async () => {
      const response = await api.get('/elearning/quizzes/')
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
    mutationFn: async (data: QuizForm) => {
      const payload = {
        ...data,
        start_date: data.start_date ? new Date(data.start_date).toISOString() : null,
        end_date: data.end_date ? new Date(data.end_date).toISOString() : null,
        time_limit: Number.isFinite(Number(data.time_limit)) ? Number(data.time_limit) : null,
        passing_score: Number.isFinite(Number(data.passing_score)) ? Number(data.passing_score) : null,
      }
      return api.post('/elearning/quizzes/', payload)
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['quizzes'] })
      showSuccessToast('Quiz / Examen créé avec succès')
      setShowForm(false)
      reset()
    },
    onError: (e: any) => showErrorToast(e, 'Erreur lors de la création'),
  })

  const { data: selectedQuiz, isLoading: loadingQuiz } = useQuery({
    queryKey: ['quiz', selectedQuizId],
    queryFn: async () => {
      const res = await api.get(`/elearning/quizzes/${selectedQuizId}/`)
      return res.data
    },
    enabled: !!selectedQuizId,
  })

  const { data: quizQuestions = [], refetch: refetchQuestions } = useQuery({
    queryKey: ['quiz-questions', selectedQuizId],
    queryFn: async () => {
      const res = await api.get(`/elearning/quizzes/${selectedQuizId}/questions/`)
      return res.data as any[]
    },
    enabled: !!selectedQuizId,
  })

  const { data: quizAttempts = [], refetch: refetchQuizAttempts } = useQuery({
    queryKey: ['quiz-attempts', selectedQuizId],
    queryFn: async () => {
      const res = await api.get('/elearning/quiz-attempts/', { params: { quiz: selectedQuizId } })
      return (res.data?.results ?? res.data ?? []) as any[]
    },
    enabled: !!selectedQuizId,
  })

  const toIsoDate = (val: string | undefined) => {
    if (!val || typeof val !== 'string') return undefined
    const normalized = val.trim().replace(' ', 'T')
    const d = new Date(normalized)
    return isNaN(d.getTime()) ? undefined : d.toISOString()
  }

  const updateMutation = useMutation({
    mutationFn: async ({ id, data }: { id: number; data: Partial<QuizForm> }) => {
      const sanitize = (v: any) => (v === '' || v === null || v === undefined || Number.isNaN(v) ? undefined : v)
      const d = selectedQuiz as any
      const payload: Record<string, any> = {
        title: data.title ?? d?.title,
        description: data.description ?? d?.description ?? '',
        subject: typeof data.subject === 'object' && data.subject && 'id' in data.subject ? (data.subject as any).id : (data.subject ?? d?.subject?.id ?? d?.subject),
        school_class: typeof data.school_class === 'object' && data.school_class && 'id' in data.school_class ? (data.school_class as any).id : (data.school_class ?? d?.school_class?.id ?? d?.school_class),
        academic_year: data.academic_year || d?.academic_year,
        start_date: toIsoDate(data.start_date) ?? (d?.start_date ? new Date(d.start_date).toISOString() : undefined),
        end_date: toIsoDate(data.end_date) ?? (d?.end_date ? new Date(d.end_date).toISOString() : undefined),
        total_points: sanitize(data.total_points) ?? d?.total_points,
        time_limit: sanitize(data.time_limit) ?? d?.time_limit,
        passing_score: sanitize(data.passing_score) ?? d?.passing_score,
        allow_multiple_attempts: data.allow_multiple_attempts,
        max_attempts: data.max_attempts ?? d?.max_attempts ?? 1,
        shuffle_questions: data.shuffle_questions,
        show_results_immediately: data.show_results_immediately,
        is_published: data.is_published,
      }
      Object.keys(payload).forEach((k) => payload[k] === undefined && delete payload[k])
      return api.patch(`/elearning/quizzes/${id}/`, payload)
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['quizzes'] })
      queryClient.invalidateQueries({ queryKey: ['quiz', selectedQuizId] })
      showSuccessToast('Quiz / Examen mis à jour')
    },
    onError: (e: any) => showErrorToast(e, 'Erreur lors de la mise à jour'),
  })

  const addQuestionMutation = useMutation({
    mutationFn: async (body: any) =>
      api.post(`/elearning/quizzes/${selectedQuizId}/questions/`, body),
    onSuccess: () => {
      refetchQuestions()
      setShowAddQuestion(false)
      showSuccessToast('Question ajoutée')
    },
    onError: (e: any) => showErrorToast(e, 'Erreur'),
  })

  const updateQuestionMutation = useMutation({
    mutationFn: async ({ id, body }: { id: number; body: any }) =>
      api.patch(`/elearning/quiz-questions/${id}/`, body),
    onSuccess: () => {
      refetchQuestions()
      setEditingQuestionId(null)
      showSuccessToast('Question mise à jour')
    },
    onError: (e: any) => showErrorToast(e, 'Erreur'),
  })

  const deleteQuestionMutation = useMutation({
    mutationFn: (id: number) => api.delete(`/elearning/quiz-questions/${id}/`),
    onSuccess: () => {
      refetchQuestions()
      showSuccessToast('Question supprimée')
    },
    onError: (e: any) => showErrorToast(e, 'Erreur'),
  })

  const onUpdateQuiz = (data: QuizForm) => {
    if (!selectedQuizId) return
    updateMutation.mutate({
      id: selectedQuizId,
      data: {
        ...data,
        academic_year: data.academic_year || (selectedQuiz as any)?.academic_year,
      },
    })
  }

  useEffect(() => {
    if (selectedQuiz) {
      const d = selectedQuiz as any
      const start = d.start_date ? new Date(d.start_date) : null
      const end = d.end_date ? new Date(d.end_date) : null
      const pad = (n: number) => String(n).padStart(2, '0')
      const toLocal = (dt: Date | null) =>
        dt
          ? `${dt.getFullYear()}-${pad(dt.getMonth() + 1)}-${pad(dt.getDate())}T${pad(dt.getHours())}:${pad(dt.getMinutes())}`
          : ''
      const subjId = typeof d.subject === 'object' && d.subject?.id != null ? d.subject.id : (d.subject ?? 0)
      const classId = typeof d.school_class === 'object' && d.school_class?.id != null ? d.school_class.id : (d.school_class ?? 0)
      reset({
        title: d.title ?? '',
        description: d.description ?? '',
        subject: subjId,
        school_class: classId,
        academic_year: d.academic_year ?? '',
        start_date: toLocal(start),
        end_date: toLocal(end),
        total_points: d.total_points ?? 20,
        time_limit: d.time_limit ?? null,
        passing_score: d.passing_score ?? null,
        allow_multiple_attempts: d.allow_multiple_attempts ?? false,
        max_attempts: d.max_attempts ?? 1,
        shuffle_questions: d.shuffle_questions ?? false,
        show_results_immediately: d.show_results_immediately ?? true,
        is_published: d.is_published ?? false,
      })
    }
  }, [selectedQuiz, reset])

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <h1 className="text-3xl font-bold text-gray-900 dark:text-white">
          Interrogations & Examens
        </h1>
        <button
          onClick={() => setShowForm(!showForm)}
          className="btn btn-primary flex items-center space-x-2"
        >
          <Plus className="w-4 h-4" />
          <span>Nouveau quiz / examen</span>
        </button>
      </div>

      {showForm && (
        <Card className="mb-6 p-6">
          <div className="flex items-center justify-between mb-4">
            <h2 className="text-xl font-semibold">Nouveau quiz ou examen</h2>
            <button
              onClick={() => {
                setShowForm(false)
                reset()
              }}
              className="text-gray-500 hover:text-gray-700 dark:hover:text-gray-300"
            >
              <X className="w-5 h-5" />
            </button>
          </div>
          <form onSubmit={handleSubmit((data) => createMutation.mutate(data))} className="space-y-4">
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div>
                <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">Titre *</label>
                <input {...register('title')} className="input w-full" placeholder="Ex: Interro Chapitre 3" />
                {errors.title && <p className="text-sm text-red-600">{errors.title.message}</p>}
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">Matière *</label>
                <select {...register('subject', { valueAsNumber: true })} className="input w-full">
                  {(subjects?.results ?? subjects ?? []).map((s: any) => (
                    <option key={s.id} value={s.id}>{s.name}</option>
                  ))}
                </select>
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">Classe *</label>
                <select {...register('school_class', { valueAsNumber: true })} className="input w-full">
                  {(classes?.results ?? classes ?? []).map((c: any) => (
                    <option key={c.id} value={c.id}>{c.name}</option>
                  ))}
                </select>
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">Année scolaire *</label>
                {academicYears.length > 0 ? (
                  <select {...register('academic_year')} className="input w-full">
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
                  <input {...register('academic_year')} className="input w-full" placeholder="2024-2025" />
                )}
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">Date de début *</label>
                <input {...register('start_date')} type="datetime-local" className="input w-full" />
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">Date de fin *</label>
                <input {...register('end_date')} type="datetime-local" className="input w-full" />
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">Points totaux</label>
                <input {...register('total_points', { valueAsNumber: true })} type="number" min={0} step={0.01} className="input w-full" />
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">Durée (minutes, optionnel)</label>
                <input {...register('time_limit', { valueAsNumber: true })} type="number" min={0} className="input w-full" placeholder="Ex: 30" />
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">Note de passage (optionnel)</label>
                <input {...register('passing_score', { valueAsNumber: true })} type="number" min={0} step={0.01} className="input w-full" placeholder="Ex: 10" />
              </div>
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">Description</label>
              <textarea {...register('description')} className="input w-full" rows={2} />
            </div>
            <div className="flex flex-wrap gap-4">
              <label className="flex items-center gap-2 cursor-pointer">
                <input {...register('is_published')} type="checkbox" className="checkbox" />
                <span className="text-sm">Publier</span>
              </label>
              <label className="flex items-center gap-2 cursor-pointer">
                <input {...register('allow_multiple_attempts')} type="checkbox" className="checkbox" />
                <span className="text-sm">Autoriser plusieurs tentatives</span>
              </label>
              <label className="flex items-center gap-2 cursor-pointer">
                <input {...register('shuffle_questions')} type="checkbox" className="checkbox" />
                <span className="text-sm">Mélanger les questions</span>
              </label>
              <label className="flex items-center gap-2 cursor-pointer">
                <input {...register('show_results_immediately')} type="checkbox" className="checkbox" />
                <span className="text-sm">Afficher les résultats immédiatement</span>
              </label>
            </div>
            <div className="flex gap-2">
              <button type="submit" className="btn btn-primary" disabled={createMutation.isPending}>
                {createMutation.isPending ? 'Création...' : 'Créer'}
              </button>
              <button type="button" onClick={() => { setShowForm(false); reset() }} className="btn btn-secondary">
                Annuler
              </button>
            </div>
          </form>
        </Card>
      )}

      {isLoading ? (
        <Card>
          <div className="text-center py-12">
            <div className="inline-block animate-spin rounded-full h-8 w-8 border-b-2 border-primary-600" />
            <p className="mt-4 text-gray-600 dark:text-gray-400">Chargement...</p>
          </div>
        </Card>
      ) : error ? (
        <Card>
          <div className="text-center py-12 text-red-600">Erreur lors du chargement</div>
        </Card>
      ) : !quizzes?.results || quizzes?.results?.length === 0 ? (
        <Card>
          <div className="text-center py-12 text-gray-500">
            <FileText className="mx-auto h-12 w-12 text-gray-400 mb-4" />
            <p>Aucun quiz ou examen</p>
          </div>
        </Card>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
          {quizzes?.results?.map((quiz: any) => (
            <Card
              key={quiz.id}
              className="hover:shadow-lg transition-shadow cursor-pointer"
              onClick={() => setSelectedQuizId(quiz.id)}
            >
              <div className="flex items-start justify-between mb-3">
                <h3 className="text-lg font-semibold text-gray-900 dark:text-white flex-1">{quiz.title}</h3>
                <span className="flex items-center gap-1 text-gray-500" title="Ouvrir / Modifier">
                  <Pencil className="w-4 h-4" />
                </span>
                {!quiz.is_published && (
                  <span className="badge badge-warning ml-2">Brouillon</span>
                )}
              </div>
              <p className="text-sm text-gray-600 dark:text-gray-400 mb-4 line-clamp-2">
                {quiz.description || '—'}
              </p>
              <div className="space-y-2 mb-4">
                <div className="flex items-center gap-2 text-sm text-gray-600 dark:text-gray-400">
                  <Calendar className="w-4 h-4" />
                  <span>
                    {new Date(quiz.start_date).toLocaleDateString('fr-FR')} – {new Date(quiz.end_date).toLocaleDateString('fr-FR')}
                  </span>
                </div>
                {quiz.class_name && (
                  <div className="flex items-center gap-2 text-sm text-gray-600 dark:text-gray-400">
                    <Users className="w-4 h-4" />
                    <span>{quiz.class_name}</span>
                  </div>
                )}
                {quiz.time_limit && (
                  <div className="flex items-center gap-2 text-sm text-gray-600 dark:text-gray-400">
                    <Clock className="w-4 h-4" />
                    <span>{quiz.time_limit} min</span>
                  </div>
                )}
              </div>
              <div className="flex items-center justify-between pt-4 border-t border-gray-200 dark:border-gray-700">
                <span className="badge badge-info text-sm">{quiz.total_points || 0} pts</span>
                {quiz.subject_name && (
                  <span className="badge badge-info text-sm">{quiz.subject_name}</span>
                )}
              </div>
            </Card>
          ))}
        </div>
      )}

      {/* Modal Ouvrir / Modifier le quiz */}
      {selectedQuizId && (
        <div
          className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4"
          onClick={() => {
            setSelectedQuizId(null)
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
                {selectedQuiz ? (selectedQuiz as any).title : 'Chargement...'}
              </h2>
              <button
                type="button"
                onClick={() => {
                  setSelectedQuizId(null)
                  setShowAddQuestion(false)
                  setEditingQuestionId(null)
                }}
                className="p-2 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-800 text-gray-500"
              >
                <X className="w-5 h-5" />
              </button>
            </div>
            <div className="p-4 space-y-6">
              {loadingQuiz ? (
                <div className="py-8 text-center text-gray-500">Chargement...</div>
              ) : selectedQuiz ? (
                <>
                  <section>
                    <h3 className="text-sm font-semibold text-gray-700 dark:text-gray-300 mb-3">Modifier le quiz / examen</h3>
                    <form
                      onSubmit={handleSubmit(
                        onUpdateQuiz,
                        (err) => {
                          const msg = Object.values(err)
                            .map((e: any) => e?.message)
                            .filter(Boolean)[0]
                          showErrorToast({ message: msg || 'Vérifiez les champs du formulaire' }, 'Erreur de validation')
                        }
                      )}
                      className="space-y-4"
                    >
                      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                        <div>
                          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">Titre</label>
                          <input {...register('title')} className="input w-full" />
                        </div>
                        <div>
                          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">Matière</label>
                          <select {...register('subject', { valueAsNumber: true })} className="input w-full">
                            {(subjects?.results ?? subjects ?? []).map((s: any) => (
                              <option key={s.id} value={s.id}>{s.name}</option>
                            ))}
                          </select>
                        </div>
                        <div>
                          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">Classe</label>
                          <select {...register('school_class', { valueAsNumber: true })} className="input w-full">
                            {(classes?.results ?? classes ?? []).map((c: any) => (
                              <option key={c.id} value={c.id}>{c.name}</option>
                            ))}
                          </select>
                        </div>
                        <div>
                          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">Année scolaire</label>
                          {academicYears.length > 0 ? (
                            <select {...register('academic_year')} className="input w-full">
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
                            <input {...register('academic_year')} className="input w-full" placeholder="2024-2025" />
                          )}
                        </div>
                        <div className="md:col-span-2">
                          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">Début / Fin</label>
                          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                            <div>
                              <label className="block text-xs text-gray-500 dark:text-gray-400 mb-0.5">Début</label>
                              <input {...register('start_date')} type="datetime-local" className="input w-full min-w-0" />
                            </div>
                            <div>
                              <label className="block text-xs text-gray-500 dark:text-gray-400 mb-0.5">Fin</label>
                              <input {...register('end_date')} type="datetime-local" className="input w-full min-w-0" />
                            </div>
                          </div>
                        </div>
                        <div>
                          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">Points totaux</label>
                          <input {...register('total_points', { valueAsNumber: true })} type="number" min={0} step={0.01} className="input w-full" />
                        </div>
                        <div>
                          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">Durée (min)</label>
                          <input {...register('time_limit', { valueAsNumber: true })} type="number" min={0} className="input w-full" />
                        </div>
                      </div>
                      <div>
                        <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">Description</label>
                        <textarea {...register('description')} className="input w-full" rows={2} />
                      </div>
                      <div className="flex items-center gap-2">
                        <label className="flex items-center gap-2 cursor-pointer">
                          <input {...register('is_published')} type="checkbox" className="checkbox" />
                          <span className="text-sm">Publier</span>
                        </label>
                        <button type="submit" className="btn btn-primary" disabled={updateMutation.isPending}>
                          {updateMutation.isPending ? 'Enregistrement...' : 'Enregistrer'}
                        </button>
                      </div>
                    </form>
                  </section>

                  <section>
                    <div className="flex items-center justify-between mb-3">
                      <h3 className="text-sm font-semibold text-gray-700 dark:text-gray-300">Questions du quiz / examen</h3>
                      <button
                        type="button"
                        onClick={() => setShowAddQuestion(true)}
                        className="btn btn-secondary text-sm flex items-center gap-1"
                      >
                        <Plus className="w-4 h-4" /> Ajouter une question
                      </button>
                    </div>
                    {quizQuestions.length === 0 && !showAddQuestion && (
                      <p className="text-sm text-gray-500 dark:text-gray-400">Aucune question. Cliquez sur « Ajouter une question ».</p>
                    )}
                    <ul className="space-y-2">
                      {quizQuestions.map((q: any) => (
                        <li key={q.id} className="flex items-start justify-between gap-2 p-3 rounded-lg bg-gray-50 dark:bg-gray-800">
                          <div className="flex-1 min-w-0">
                            <span className="text-xs text-gray-500 dark:text-gray-400 font-medium">
                              {QUESTION_TYPES.find((t) => t.value === q.question_type)?.label ?? q.question_type} • {q.points} pts
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
                      <QuizQuestionForm
                        types={QUESTION_TYPES}
                        onSave={(body) => addQuestionMutation.mutate(body)}
                        onCancel={() => setShowAddQuestion(false)}
                        isPending={addQuestionMutation.isPending}
                      />
                    )}
                    {editingQuestionId && (() => {
                      const q = quizQuestions.find((x: any) => x.id === editingQuestionId)
                      if (!q) return null
                      return (
                        <QuizQuestionForm
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
                      Tentatives des élèves ({quizAttempts.length})
                    </h3>
                    {quizAttempts.length === 0 ? (
                      <p className="text-sm text-gray-500 dark:text-gray-400">Aucune tentative pour le moment.</p>
                    ) : (
                      <div className="space-y-3">
                        {quizAttempts.map((att: any) => (
                          <QuizAttemptCard
                            key={att.id}
                            attempt={att}
                            totalPoints={Number(selectedQuiz?.total_points ?? 20)}
                            onGraded={refetchQuizAttempts}
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

function QuizAttemptCard({ attempt, totalPoints, onGraded }: { attempt: any; totalPoints: number; onGraded?: () => void }) {
  const [expanded, setExpanded] = useState(false)
  const [answerOverrides, setAnswerOverrides] = useState<Record<number, { points?: string; feedback?: string }>>({})
  const answers = attempt.answers ?? []

  const gradeMutation = useMutation({
    mutationFn: async () => {
      const payload = {
        answers: answers.map((a: any) => {
          const ptsStr = getPoints(a)
          const ptsNum = parseFloat(String(ptsStr).replace(',', '.'))
          return {
            id: a.id,
            points_earned: isNaN(ptsNum) ? a.points_earned : ptsNum,
            teacher_feedback: getFeedback(a) || '',
          }
        }),
      }
      return api.post(`/elearning/quiz-attempts/${attempt.id}/teacher_grade/`, payload)
    },
    onSuccess: () => {
      showSuccessToast('Notation enregistrée')
      onGraded?.()
    },
    onError: (e: any) => showErrorToast(e, 'Erreur lors de la notation'),
  })

  const updateOverride = (answerId: number, field: 'points' | 'feedback', value: string) => {
    setAnswerOverrides((prev) => ({
      ...prev,
      [answerId]: { ...prev[answerId], [field]: value },
    }))
  }

  const getPoints = (a: any) =>
    answerOverrides[a.id]?.points ?? String(a.points_earned ?? '')
  const getFeedback = (a: any) =>
    answerOverrides[a.id]?.feedback ?? (a.teacher_feedback ?? '')

  return (
    <div className="border border-gray-200 dark:border-gray-600 rounded-lg overflow-hidden">
      <button
        type="button"
        onClick={() => setExpanded(!expanded)}
        className="w-full px-4 py-3 flex items-center justify-between bg-gray-50 dark:bg-gray-800 hover:bg-gray-100 dark:hover:bg-gray-700"
      >
        <div className="flex items-center gap-3">
          <span className="font-medium text-gray-900 dark:text-white">{attempt.student_name || attempt.student_id || 'Élève'}</span>
          <span className={`badge ${attempt.is_passed ? 'badge-success' : 'badge-warning'}`}>
            {attempt.is_passed ? 'Réussi' : 'Non réussi'}
          </span>
          {attempt.score != null && (
            <span className="text-sm text-gray-600 dark:text-gray-400">
              {attempt.score}/{totalPoints}
            </span>
          )}
          {attempt.submitted_at && (
            <span className="text-xs text-gray-500 dark:text-gray-400">
              {new Date(attempt.submitted_at).toLocaleString('fr-FR')}
            </span>
          )}
        </div>
        <ChevronDown className={`w-5 h-5 transition-transform ${expanded ? 'rotate-180' : ''}`} />
      </button>
      {expanded && answers.length > 0 && (
        <div className="p-4 border-t border-gray-200 dark:border-gray-600 space-y-4">
          <p className="text-xs font-medium text-gray-500 dark:text-gray-400 uppercase">Détail des réponses – Modifier la notation</p>
          {answers.map((a: any, i: number) => (
            <div key={a.id ?? i} className="text-sm border border-gray-200 dark:border-gray-600 rounded-lg p-3 space-y-2">
              <p className="font-medium text-gray-700 dark:text-gray-300">{a.question_text}</p>
              <p className="text-gray-600 dark:text-gray-400">
                → {a.answer_text ?? '(vide)'}
                {a.is_correct != null && (
                  <span className={`ml-2 ${a.is_correct ? 'text-green-600' : 'text-red-600'}`}>
                    (Auto: {a.is_correct ? 'Correct' : 'Incorrect'} · {a.points_earned ?? 0} pts)
                  </span>
                )}
              </p>
              <div className="flex flex-col sm:flex-row gap-2 pt-2">
                <div className="flex items-center gap-2">
                  <label className="text-xs text-gray-500">Points:</label>
                  <input
                    type="text"
                    inputMode="decimal"
                    placeholder={`${a.points_earned ?? 0}`}
                    value={getPoints(a)}
                    onChange={(e) => updateOverride(a.id, 'points', e.target.value)}
                    className="input w-20 text-sm"
                  />
                </div>
                <div className="flex-1 flex items-center gap-2">
                  <label className="text-xs text-gray-500">Commentaire:</label>
                  <input
                    type="text"
                    placeholder="Commentaire de l'enseignant..."
                    value={getFeedback(a)}
                    onChange={(e) => updateOverride(a.id, 'feedback', e.target.value)}
                    className="input flex-1 text-sm"
                  />
                </div>
              </div>
            </div>
          ))}
          <button
            type="button"
            onClick={() => gradeMutation.mutate()}
            disabled={gradeMutation.isPending}
            className="btn btn-primary"
          >
            {gradeMutation.isPending ? 'Enregistrement...' : 'Enregistrer la notation'}
          </button>
        </div>
      )}
    </div>
  )
}

function QuizQuestionForm({
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
  const isChoice = question_type === 'SINGLE_CHOICE' || question_type === 'MULTIPLE_CHOICE' || question_type === 'TRUE_FALSE'

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
        <button type="submit" className="btn btn-primary" disabled={isPending}>
          {isPending ? 'Enregistrement...' : 'Enregistrer'}
        </button>
        <button type="button" onClick={onCancel} className="btn btn-secondary">Annuler</button>
      </div>
    </form>
  )
}
