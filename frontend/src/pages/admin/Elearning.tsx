import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import api from '@/services/api'
import { Card } from '@/components/ui/Card'
import { Plus, Pencil, ExternalLink, X } from 'lucide-react'
import { useState, useRef } from 'react'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'
import { showErrorToast, showSuccessToast } from '@/utils/toast'

const API_BASE = import.meta.env.VITE_API_URL || 'http://localhost:8000/api'

const courseSchema = z.object({
  title: z.string().min(1, 'Le titre est requis'),
  description: z.string().min(1, 'La description est requise'),
  school_class: z.number().min(1, 'La classe est requise'),
  teacher: z.number().min(1, "L'enseignant est requis"),
  academic_year: z.string().min(1, "L'année scolaire est requise"),
  content: z.string().optional(),
  content_url: z.string().url('URL invalide').optional().or(z.literal('')),
  video_url: z.string().url('URL invalide').optional().or(z.literal('')),
  is_published: z.boolean().default(false),
})

type CourseForm = z.infer<typeof courseSchema>

type Course = {
  id: number
  title: string
  description: string
  subject_name?: string | null
  school_class_name?: string
  teacher_name?: string
  is_published: boolean
  content?: string
  content_url?: string | null
  video_url?: string | null
  attachments?: string | null
}

export default function AdminElearning() {
  const [showForm, setShowForm] = useState(false)
  const [editingCourse, setEditingCourse] = useState<Course | null>(null)
  const [importFile, setImportFile] = useState<File | null>(null)
  const fileInputRef = useRef<HTMLInputElement>(null)
  const queryClient = useQueryClient()

  const { register, handleSubmit, formState: { errors }, reset, setValue, watch } = useForm<CourseForm>({
    resolver: zodResolver(courseSchema),
    defaultValues: {
      academic_year: `${new Date().getFullYear()}-${new Date().getFullYear() + 1}`,
      is_published: false,
      content: '',
      content_url: '',
      video_url: '',
    },
  })

  const contentUrl = watch('content_url')

  const { data: courses, isLoading, error } = useQuery({
    queryKey: ['elearning-courses'],
    queryFn: async () => {
      const response = await api.get('/elearning/courses/')
      return response.data
    },
    retry: 1,
  })

  const { data: classes } = useQuery({
    queryKey: ['school-classes'],
    queryFn: async () => {
      const response = await api.get('/schools/classes/')
      return response.data
    },
  })

  const { data: teachers } = useQuery({
    queryKey: ['teachers'],
    queryFn: async () => {
      const response = await api.get('/auth/teachers/')
      return response.data
    },
  })

  const createMutation = useMutation({
    mutationFn: async (data: CourseForm & { file?: File }) => {
      if (data.file) {
        const formData = new FormData()
        formData.append('title', data.title)
        formData.append('description', data.description)
        formData.append('school_class', String(data.school_class))
        formData.append('teacher', String(data.teacher))
        formData.append('academic_year', data.academic_year)
        formData.append('is_published', String(data.is_published))
        if (data.content) formData.append('content', data.content)
        if (data.content_url) formData.append('content_url', data.content_url)
        if (data.video_url) formData.append('video_url', data.video_url)
        formData.append('attachments', data.file)
        return api.post('/elearning/courses/', formData, {
          headers: { 'Content-Type': 'multipart/form-data' },
        })
      }
      return api.post('/elearning/courses/', {
        title: data.title,
        description: data.description,
        school_class: data.school_class,
        teacher: data.teacher,
        academic_year: data.academic_year,
        content: data.content || '',
        content_url: data.content_url || null,
        video_url: data.video_url || null,
        is_published: data.is_published,
      })
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['elearning-courses'] })
      showSuccessToast('Cours créé avec succès')
      setShowForm(false)
      setImportFile(null)
      reset()
    },
    onError: (error: any) => {
      showErrorToast(error, 'Erreur lors de la création du cours')
    },
  })

  const updateMutation = useMutation({
    mutationFn: async ({ id, data, file }: { id: number; data: CourseForm; file?: File }) => {
      if (file) {
        const formData = new FormData()
        formData.append('title', data.title)
        formData.append('description', data.description)
        formData.append('school_class', String(data.school_class))
        formData.append('teacher', String(data.teacher))
        formData.append('academic_year', data.academic_year)
        formData.append('is_published', String(data.is_published))
        if (data.content !== undefined) formData.append('content', data.content || '')
        if (data.content_url) formData.append('content_url', data.content_url)
        if (data.video_url) formData.append('video_url', data.video_url)
        formData.append('attachments', file)
        return api.patch(`/elearning/courses/${id}/`, formData, {
          headers: { 'Content-Type': 'multipart/form-data' },
        })
      }
      return api.patch(`/elearning/courses/${id}/`, {
        title: data.title,
        description: data.description,
        school_class: data.school_class,
        teacher: data.teacher,
        academic_year: data.academic_year,
        content: data.content ?? '',
        content_url: data.content_url || null,
        video_url: data.video_url || null,
        is_published: data.is_published,
      })
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['elearning-courses'] })
      showSuccessToast('Cours modifié')
      setEditingCourse(null)
      setImportFile(null)
      reset()
    },
    onError: (error: any) => {
      showErrorToast(error, 'Erreur lors de la modification')
    },
  })

  const onSubmit = (data: CourseForm) => {
    if (editingCourse) {
      updateMutation.mutate({ id: editingCourse.id, data, file: importFile || undefined })
    } else {
      createMutation.mutate({ ...data, file: importFile || undefined })
    }
  }

  const openEdit = (course: Course) => {
    setEditingCourse(course)
    setValue('title', course.title)
    setValue('description', course.description)
    setValue('school_class', (course as any).school_class)
    setValue('teacher', (course as any).teacher)
    setValue('academic_year', (course as any).academic_year || '')
    setValue('content', course.content || '')
    setValue('content_url', course.content_url || '')
    setValue('video_url', course.video_url || '')
    setValue('is_published', course.is_published)
    setImportFile(null)
  }

  const closeForm = () => {
    setShowForm(false)
    setEditingCourse(null)
    setImportFile(null)
    reset()
  }

  const openContent = (course: Course) => {
    if (course.content_url) {
      window.open(course.content_url, '_blank')
      return
    }
    if (course.attachments) {
      const url = course.attachments.startsWith('http') ? course.attachments : `${API_BASE.replace('/api', '')}${course.attachments}`
      window.open(url, '_blank')
      return
    }
    if (course.video_url) {
      window.open(course.video_url, '_blank')
      return
    }
    showErrorToast(null, 'Aucun contenu ou lien à ouvrir')
  }

  const formVisible = showForm || editingCourse
  const isEditing = !!editingCourse

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <h1 className="text-3xl font-bold text-gray-900">Gestion E-learning</h1>
        <button
          onClick={() => {
            setEditingCourse(null)
            reset()
            setImportFile(null)
            setShowForm(!showForm)
          }}
          className="btn btn-primary flex items-center gap-2"
        >
          <Plus className="w-5 h-5" />
          Nouveau cours
        </button>
      </div>

      {formVisible && (
        <Card className="mb-6">
          <div className="flex items-center justify-between mb-4">
            <h2 className="text-xl font-semibold mb-0">
              {isEditing ? 'Modifier le cours' : 'Nouveau cours'}
            </h2>
            <button type="button" onClick={closeForm} className="p-1 text-gray-500 hover:text-gray-700">
              <X className="w-5 h-5" />
            </button>
          </div>
          <form onSubmit={handleSubmit(onSubmit)} className="space-y-4">
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  Titre <span className="text-red-500">*</span>
                </label>
                <input
                  {...register('title')}
                  className="input"
                  placeholder="Titre du cours"
                />
                {errors.title && (
                  <p className="mt-1 text-sm text-red-600">{errors.title.message}</p>
                )}
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
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
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  Enseignant <span className="text-red-500">*</span>
                </label>
                <select {...register('teacher', { valueAsNumber: true })} className="input">
                  <option value="">Sélectionner un enseignant</option>
                  {teachers?.results?.map((teacher: any) => (
                    <option key={teacher.id} value={teacher.id}>
                      {teacher.user?.first_name} {teacher.user?.last_name}
                    </option>
                  ))}
                </select>
                {errors.teacher && (
                  <p className="mt-1 text-sm text-red-600">{errors.teacher.message}</p>
                )}
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  Année scolaire <span className="text-red-500">*</span>
                </label>
                <input
                  {...register('academic_year')}
                  className="input"
                  placeholder="2024-2025"
                />
                {errors.academic_year && (
                  <p className="mt-1 text-sm text-red-600">{errors.academic_year.message}</p>
                )}
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">URL vidéo</label>
                <input
                  {...register('video_url')}
                  type="url"
                  className="input"
                  placeholder="https://..."
                />
              </div>
              <div className="flex items-center gap-2">
                <input
                  {...register('is_published')}
                  type="checkbox"
                  className="w-4 h-4"
                />
                <label className="text-sm font-medium text-gray-700">Publié</label>
              </div>
            </div>

            <div>
              <label className="block text-sm font-medium text-gray-700 mb-2">
                Importer le contenu
              </label>
              <div className="flex flex-wrap gap-4 items-end">
                <div className="flex-1 min-w-[200px]">
                  <span className="block text-xs text-gray-500 mb-1">Fichier local (PDF, etc.)</span>
                  <input
                    ref={fileInputRef}
                    type="file"
                    accept=".pdf,.doc,.docx,.txt,.odt"
                    className="input py-1"
                    onChange={(e) => setImportFile(e.target.files?.[0] || null)}
                  />
                  {importFile && (
                    <p className="mt-1 text-sm text-gray-600">
                      {importFile.name}
                    </p>
                  )}
                </div>
                <div className="flex-1 min-w-[200px]">
                  <span className="block text-xs text-gray-500 mb-1">Ou lien vers le contenu</span>
                  <input
                    {...register('content_url')}
                    type="url"
                    className="input"
                    placeholder="https://..."
                  />
                </div>
              </div>
              {(importFile || contentUrl) && (
                <p className="mt-1 text-sm text-gray-500">
                  Le contenu pourra être ouvert via « Lire » sur la liste des cours.
                </p>
              )}
            </div>

            <div>
              <label className="block text-sm font-medium text-gray-700 mb-2">Description <span className="text-red-500">*</span></label>
              <textarea
                {...register('description')}
                className="input"
                rows={3}
                placeholder="Description du cours"
              />
              {errors.description && (
                <p className="mt-1 text-sm text-red-600">{errors.description.message}</p>
              )}
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-2">
                Contenu (optionnel)
              </label>
              <textarea
                {...register('content')}
                className="input"
                rows={6}
                placeholder="Contenu du cours ou laisser vide si import par fichier/lien"
              />
            </div>
            <div className="flex justify-end gap-4 pt-4">
              <button type="button" onClick={closeForm} className="btn btn-secondary">
                Annuler
              </button>
              <button
                type="submit"
                disabled={createMutation.isPending || updateMutation.isPending}
                className="btn btn-primary"
              >
                {isEditing
                  ? (updateMutation.isPending ? 'Enregistrement...' : 'Enregistrer')
                  : (createMutation.isPending ? 'Création...' : 'Créer le cours')}
              </button>
            </div>
          </form>
        </Card>
      )}

      <div className="grid grid-cols-1 md:grid-cols-2 gap-6 mb-6">
        <Card>
          <h2 className="text-xl font-semibold mb-4">Cours</h2>
          <div className="text-3xl font-bold text-primary-600">
            {courses?.results?.length || 0}
          </div>
        </Card>
        <Card>
          <h2 className="text-xl font-semibold mb-4">Cours publiés</h2>
          <div className="text-3xl font-bold text-green-600">
            {courses?.results?.filter((c: any) => c.is_published)?.length || 0}
          </div>
        </Card>
      </div>

      <Card>
        <div className="overflow-x-auto">
          <table className="w-full">
            <thead className="bg-gray-50 dark:bg-gray-700/50">
              <tr>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-700 dark:text-gray-300 uppercase">Titre</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-700 dark:text-gray-300 uppercase">Classe</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-700 dark:text-gray-300 uppercase">Enseignant</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-700 dark:text-gray-300 uppercase">Statut</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-700 dark:text-gray-300 uppercase">Actions</th>
              </tr>
            </thead>
            <tbody className="bg-white divide-y divide-gray-200">
              {isLoading ? (
                <tr>
                  <td colSpan={5} className="px-6 py-4 text-center">Chargement...</td>
                </tr>
              ) : error ? (
                <tr>
                  <td colSpan={5} className="px-6 py-4 text-center text-red-600">
                    Erreur lors du chargement des cours
                  </td>
                </tr>
              ) : !courses?.results || courses?.results?.length === 0 ? (
                <tr>
                  <td colSpan={5} className="px-6 py-4 text-center text-gray-500">
                    Aucun cours trouvé
                  </td>
                </tr>
              ) : (
                courses?.results?.map((course: any) => (
                  <tr
                    key={course.id}
                    className="hover:bg-gray-50 cursor-pointer"
                    onClick={() => openEdit(course)}
                  >
                    <td className="px-6 py-4">
                      <div className="text-sm font-medium text-gray-900">{course.title}</div>
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                      {course.school_class_name || 'N/A'}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                      {course.teacher_name || 'N/A'}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap">
                      {course.is_published ? (
                        <span className="badge badge-success">Publié</span>
                      ) : (
                        <span className="badge badge-warning">Brouillon</span>
                      )}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap" onClick={(e) => e.stopPropagation()}>
                      <div className="flex items-center gap-2">
                        <button
                          type="button"
                          onClick={() => openEdit(course)}
                          className="p-1.5 text-gray-600 hover:text-primary-600 rounded"
                          title="Modifier"
                        >
                          <Pencil className="w-4 h-4" />
                        </button>
                        <button
                          type="button"
                          onClick={() => openContent(course)}
                          className="p-1.5 text-gray-600 hover:text-primary-600 rounded"
                          title="Lire le contenu"
                        >
                          <ExternalLink className="w-4 h-4" />
                        </button>
                      </div>
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
