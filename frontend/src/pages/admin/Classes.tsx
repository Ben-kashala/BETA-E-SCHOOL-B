import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import api from '@/services/api'
import { Card } from '@/components/ui/Card'
import { Plus, X, User, Mail, Phone, Users, Edit, Search, Calendar, BookOpen, Heart, AlertCircle, Filter } from 'lucide-react'
import { useState, useEffect } from 'react'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'
import { showErrorToast, showSuccessToast } from '@/utils/toast'
import { useAcademicYears } from '@/hooks/useAcademicYears'
const classSchema = z.object({
  name: z.string().min(1, 'Le nom est requis'),
  next_class_name: z.string().max(100).optional().nullable(),
  is_terminal: z.boolean().optional(),
  level: z.string().min(1, 'Le niveau est requis'),
  grade: z.string().min(1, 'La classe est requise'),
  section: z.number().optional().nullable(),
  titulaire: z.number().optional().nullable(),
  capacity: z.number().min(1, 'La capacité doit être supérieure à 0'),
  academic_year: z.string().min(1, 'L\'année scolaire est requise'),
})

type ClassForm = z.infer<typeof classSchema>

export default function AdminClasses() {
  const [showForm, setShowForm] = useState(false)
  const [editingClassId, setEditingClassId] = useState<number | null>(null)
  const [selectedClassId, setSelectedClassId] = useState<number | null>(null)
  const [selectedClassName, setSelectedClassName] = useState<string>('')
  const [searchQuery, setSearchQuery] = useState<string>('')
  const [selectedStudent, setSelectedStudent] = useState<any | null>(null)
  const [classSearchQuery, setClassSearchQuery] = useState<string>('')
  const [academicYearFilter, setAcademicYearFilter] = useState<string>('')
  const queryClient = useQueryClient()
  const { years: academicYearsFromApi, current: currentAcademicYear } = useAcademicYears()
  const { register, handleSubmit, formState: { errors }, reset, setValue } = useForm<ClassForm>({
    resolver: zodResolver(classSchema),
    defaultValues: {
      capacity: 40,
      titulaire: null,
      academic_year: currentAcademicYear || `${new Date().getFullYear()}-${new Date().getFullYear() + 1}`,
    },
  })

  const { data: classes, isLoading, error } = useQuery({
    queryKey: ['school-classes'],
    queryFn: async () => {
      const response = await api.get('/schools/classes/')
      return response.data
    },
    retry: 1,
  })

  const { data: sections, isLoading: sectionsLoading } = useQuery({
    queryKey: ['sections'],
    queryFn: async () => {
      const response = await api.get('/schools/sections/')
      return response.data
    },
    retry: 1,
  })

  const { data: teachers } = useQuery({
    queryKey: ['teachers'],
    queryFn: async () => {
      const response = await api.get('/accounts/teachers/')
      return response.data
    },
    retry: 1,
  })

  // Inscriptions (parcours) dans la classe : actifs, promus, diplômés — garde l'historique
  const { data: classEnrollments, isLoading: isLoadingStudents } = useQuery({
    queryKey: ['class-enrollments', selectedClassId],
    queryFn: async () => {
      if (!selectedClassId) return { results: [] }
      const response = await api.get(`/schools/classes/${selectedClassId}/enrollments/`)
      return response.data
    },
    enabled: !!selectedClassId,
  })

  const handleClassClick = (classItem: any) => {
    setSelectedClassId(classItem.id)
    setSelectedClassName(classItem.name)
  }

  const handleCloseModal = () => {
    setSelectedClassId(null)
    setSelectedClassName('')
    setSearchQuery('')
  }

  const handleStudentClick = (e: React.MouseEvent, enrollment: any) => {
    e.stopPropagation()
    const s = enrollment?.student ?? enrollment
    setSelectedStudent(s ? { ...s, enrollment_date: s.enrollment_date || enrollment?.enrolled_at } : enrollment)
  }

  const handleCloseStudentModal = () => {
    setSelectedStudent(null)
  }

  // Filtrer les inscriptions selon la recherche (sur l'élève)
  const enrollmentsList = classEnrollments?.results ?? []
  const filteredEnrollments = enrollmentsList.filter((enr: any) => {
    if (!searchQuery) return true
    const s = enr.student || {}
    const query = searchQuery.toLowerCase()
    const name = (s.user_name || [s.user?.first_name, s.user?.last_name, s.user?.middle_name].filter(Boolean).join(' ') || '').toLowerCase()
    const studentId = s.student_id?.toLowerCase() || ''
    const email = s.user?.email?.toLowerCase() || ''
    const phone = s.user?.phone?.toLowerCase() || ''
    return name.includes(query) || studentId.includes(query) || email.includes(query) || phone.includes(query)
  })

  // Extraire les années scolaires uniques pour le filtre
  const academicYears: string[] =
    (academicYearsFromApi && academicYearsFromApi.length > 0
      ? academicYearsFromApi
      : classes?.results
        ? (Array.from(
            new Set(
              classes.results
                .map((cls: any) => cls.academic_year)
                .filter((year: unknown): year is string => Boolean(year)),
            ),
          ) as string[]
          ).sort()
        : [])

  // Filtrer les classes selon la recherche et l'année scolaire
  const filteredClasses = classes?.results?.filter((cls: any) => {
    // Filtre par année scolaire
    if (academicYearFilter && cls.academic_year !== academicYearFilter) {
      return false
    }
    
    // Filtre par recherche
    if (!classSearchQuery) return true
    const query = classSearchQuery.toLowerCase()
    const name = cls.name?.toLowerCase() || ''
    const level = cls.level?.toLowerCase() || ''
    const grade = cls.grade?.toLowerCase() || ''
    const sectionName = cls.section_name?.toLowerCase() || ''
    
    return name.includes(query) || 
           level.includes(query) || 
           grade.includes(query) ||
           sectionName.includes(query)
  }) || []

  const handleEditClick = (e: React.MouseEvent, classItem: any) => {
    e.stopPropagation() // Empêcher l'ouverture de la modale des élèves
    setEditingClassId(classItem.id)
    setShowForm(true)
    
    // Pré-remplir le formulaire avec les données de la classe
    setValue('name', classItem.name)
    setValue('next_class_name', classItem.next_class_name ?? '')
    setValue('is_terminal', classItem.is_terminal ?? false)
    setValue('level', classItem.level)
    setValue('grade', classItem.grade)
    // Gérer la section qui peut être un objet ou un ID
    setValue('section', classItem.section?.id || classItem.section || null)
    setValue('titulaire', classItem.titulaire ?? null)
    setValue('capacity', classItem.capacity)
    setValue('academic_year', classItem.academic_year)
  }

  const handleCancelEdit = () => {
    setShowForm(false)
    setEditingClassId(null)
    reset({
      capacity: 40,
      titulaire: null,
      next_class_name: '',
      is_terminal: false,
      academic_year: `${new Date().getFullYear()}-${new Date().getFullYear() + 1}`,
    })
  }

  // Réinitialiser le formulaire quand on annule l'édition ou après création
  useEffect(() => {
    if (!showForm && editingClassId) {
      setEditingClassId(null)
    }
  }, [showForm, editingClassId])

  const createMutation = useMutation({
    mutationFn: (data: ClassForm) => api.post('/schools/classes/', data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['school-classes'] })
      showSuccessToast('Classe créée avec succès')
      setShowForm(false)
      setEditingClassId(null)
      reset({
        capacity: 40,
        titulaire: null,
        next_class_name: '',
        academic_year: `${new Date().getFullYear()}-${new Date().getFullYear() + 1}`,
      })
    },
    onError: (error: any) => {
      showErrorToast(error, 'Erreur lors de la création de la classe')
    },
  })

  const updateMutation = useMutation({
    mutationFn: (data: ClassForm) => {
      if (!editingClassId) throw new Error('ID de classe manquant')
      return api.patch(`/schools/classes/${editingClassId}/`, data)
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['school-classes'] })
      showSuccessToast('Classe modifiée avec succès')
      setShowForm(false)
      setEditingClassId(null)
      reset({
        capacity: 40,
        titulaire: null,
        next_class_name: '',
        is_terminal: false,
        academic_year: `${new Date().getFullYear()}-${new Date().getFullYear() + 1}`,
      })
    },
    onError: (error: any) => {
      showErrorToast(error, 'Erreur lors de la modification de la classe')
    },
  })

  const onSubmit = (data: ClassForm) => {
    if (editingClassId) {
      updateMutation.mutate(data)
    } else {
      createMutation.mutate(data)
    }
  }

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <h1 className="text-3xl font-bold text-gray-900 dark:text-white">Gestion des Classes</h1>
        <button
          onClick={() => {
            setEditingClassId(null)
            setShowForm(!showForm)
            if (!showForm) {
              reset({
                capacity: 40,
                titulaire: null,
                next_class_name: '',
                is_terminal: false,
                academic_year: `${new Date().getFullYear()}-${new Date().getFullYear() + 1}`,
              })
            }
          }}
          className="btn btn-primary flex items-center space-x-2"
        >
          <Plus className="w-4 h-4" />
          <span>Nouvelle classe</span>
        </button>
      </div>

      {showForm && (
        <Card className="mb-6">
          <h2 className="text-xl font-semibold mb-4 text-gray-900 dark:text-white">
            {editingClassId ? 'Modifier la classe' : 'Nouvelle classe'}
          </h2>
          <form onSubmit={handleSubmit(onSubmit)} className="space-y-4">
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div>
                <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
                  Nom de la classe <span className="text-red-500">*</span>
                </label>
                <input
                  {...register('name')}
                  className="input"
                  placeholder="Ex: 6ème A"
                />
                {errors.name && (
                  <p className="mt-1 text-sm text-red-600">{errors.name.message}</p>
                )}
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
                  Classe suivante (promotion)
                </label>
                <input
                  {...register('next_class_name')}
                  className="input"
                  placeholder="Ex: 4ème CG. Vide si année terminale."
                />
              </div>
              <div className="flex items-center gap-2">
                <input
                  type="checkbox"
                  id="is_terminal"
                  {...register('is_terminal')}
                  className="rounded border-gray-300 dark:border-gray-600 text-primary-600 focus:ring-primary-500"
                />
                <label htmlFor="is_terminal" className="text-sm font-medium text-gray-700 dark:text-gray-300">
                  Année terminale (dernière année). Si ≥50% T.G., l&apos;élève sort et rejoint les anciens élèves.
                </label>
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
                  Niveau <span className="text-red-500">*</span>
                </label>
                <select {...register('level')} className="input">
                  <option value="">Sélectionner</option>
                  <option value="Maternelle">Maternelle</option>
                  <option value="Primaire">Primaire</option>
                  <option value="Secondaire">Secondaire</option>
                </select>
                {errors.level && (
                  <p className="mt-1 text-sm text-red-600 dark:text-red-400">{errors.level.message}</p>
                )}
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
                  Classe <span className="text-red-500">*</span>
                </label>
                <input
                  {...register('grade')}
                  className="input"
                  placeholder="Ex: 1ère, 2ème, 6ème"
                />
                {errors.grade && (
                  <p className="mt-1 text-sm text-red-600 dark:text-red-400">{errors.grade.message}</p>
                )}
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
                  Section
                </label>
                <select 
                  {...register('section', { valueAsNumber: true, setValueAs: (v) => v === '' ? null : Number(v) })} 
                  className="input"
                  disabled={sectionsLoading}
                >
                  <option value="">
                    {sectionsLoading 
                      ? 'Chargement des sections...' 
                      : (sections?.results?.length === 0 || (Array.isArray(sections) && sections.length === 0))
                        ? 'Aucune section disponible - Créez d\'abord des sections dans l\'admin Django'
                        : 'Sélectionner une section (optionnel)'}
                  </option>
                  {(sections?.results || (Array.isArray(sections) ? sections : [])).map((section: any) => (
                    <option key={section.id} value={section.id}>
                      {section.name}
                    </option>
                  ))}
                </select>
                {!sectionsLoading && (sections?.results?.length === 0 || (Array.isArray(sections) && sections.length === 0)) && (
                  <p className="mt-1 text-sm text-yellow-600 dark:text-yellow-400">
                    Aucune section disponible. Veuillez créer des sections dans l'admin Django d'abord.
                  </p>
                )}
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
                  Enseignant titulaire
                </label>
                <select
                  {...register('titulaire', { valueAsNumber: true, setValueAs: (v) => v === '' ? null : Number(v) })}
                  className="input"
                >
                  <option value="">Aucun</option>
                  {(teachers?.results || []).map((t: any) => (
                    <option key={t.id} value={t.id}>
                      {[t.user?.first_name, t.user?.last_name, t.user?.middle_name].filter(Boolean).join(' ') || t.user?.username || `Enseignant #${t.id}`}
                    </option>
                  ))}
                </select>
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
                  Capacité <span className="text-red-500">*</span>
                </label>
                <input
                  {...register('capacity', { valueAsNumber: true })}
                  type="number"
                  className="input"
                  min="1"
                />
                {errors.capacity && (
                  <p className="mt-1 text-sm text-red-600 dark:text-red-400">{errors.capacity.message}</p>
                )}
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
                  Année scolaire <span className="text-red-500">*</span>
                </label>
                {academicYearsFromApi && academicYearsFromApi.length > 0 ? (
                  <select {...register('academic_year')} className="input">
                    <option value="">
                      {currentAcademicYear
                        ? `Sélectionner (par défaut ${currentAcademicYear})`
                        : 'Sélectionner une année'}
                    </option>
                    {academicYearsFromApi.map((year) => (
                      <option key={year} value={year}>
                        {year}
                      </option>
                    ))}
                  </select>
                ) : (
                  <input
                    {...register('academic_year')}
                    className="input"
                    placeholder="2024-2025"
                  />
                )}
                {errors.academic_year && (
                  <p className="mt-1 text-sm text-red-600 dark:text-red-400">{errors.academic_year.message}</p>
                )}
              </div>
            </div>
            <div className="flex justify-end gap-4 pt-4">
              <button
                type="button"
                onClick={handleCancelEdit}
                className="btn btn-secondary"
              >
                Annuler
              </button>
              <button
                type="submit"
                disabled={createMutation.isPending || updateMutation.isPending}
                className="btn btn-primary"
              >
                {editingClassId 
                  ? (updateMutation.isPending ? 'Modification...' : 'Modifier la classe')
                  : (createMutation.isPending ? 'Création...' : 'Créer la classe')
                }
              </button>
            </div>
          </form>
        </Card>
      )}

      {/* Barre de recherche et filtre */}
      <div className="mb-6 space-y-4">
        <div className="flex flex-col md:flex-row gap-4">
          {/* Champ de recherche */}
          <div className="flex-1 relative">
            <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 w-5 h-5 text-gray-400" />
            <input
              type="text"
              placeholder="Rechercher une classe par nom, niveau, grade ou section..."
              value={classSearchQuery}
              onChange={(e) => setClassSearchQuery(e.target.value)}
              className="w-full pl-10 pr-4 py-2 border border-gray-300 dark:border-gray-600 rounded-lg bg-white dark:bg-gray-700 text-gray-900 dark:text-white placeholder-gray-400 dark:placeholder-gray-500 focus:outline-none focus:ring-2 focus:ring-primary-500 focus:border-transparent"
            />
          </div>
          
          {/* Filtre par année scolaire */}
          <div className="relative min-w-[200px]">
            <Filter className="absolute left-3 top-1/2 transform -translate-y-1/2 w-5 h-5 text-gray-400 z-10" />
            <select
              value={academicYearFilter}
              onChange={(e) => setAcademicYearFilter(e.target.value)}
              className="w-full pl-10 pr-4 py-2 border border-gray-300 dark:border-gray-600 rounded-lg bg-white dark:bg-gray-700 text-gray-900 dark:text-white focus:outline-none focus:ring-2 focus:ring-primary-500 focus:border-transparent appearance-none cursor-pointer"
            >
              <option value="">Toutes les années</option>
              {academicYears.map((year: string) => (
                <option key={year} value={year}>
                  {year}
                </option>
              ))}
            </select>
          </div>
        </div>
        
        {/* Compteur de résultats */}
        {(classSearchQuery || academicYearFilter) && (
          <div className="text-sm text-gray-600 dark:text-gray-400">
            {filteredClasses.length} classe(s) trouvée(s) sur {classes?.results?.length || 0}
          </div>
        )}
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
        {isLoading ? (
          <div className="col-span-full text-center py-12">Chargement...</div>
        ) : error ? (
          <div className="col-span-full text-center py-12 text-red-600 dark:text-red-400">
            Erreur lors du chargement des classes
          </div>
        ) : !classes?.results || classes?.results?.length === 0 ? (
          <div className="col-span-full text-center py-12 text-gray-500 dark:text-gray-400">
            Aucune classe trouvée. Créez votre première classe.
          </div>
        ) : filteredClasses.length === 0 ? (
          <div className="col-span-full text-center py-12 text-gray-500 dark:text-gray-400">
            Aucune classe ne correspond à votre recherche.
          </div>
        ) : (
          filteredClasses.map((cls: any) => (
            <Card 
              key={cls.id}
              className="cursor-pointer hover:shadow-lg transition-all hover:scale-[1.02] relative"
              onClick={() => handleClassClick(cls)}
            >
              <button
                onClick={(e) => handleEditClick(e, cls)}
                className="absolute top-3 right-3 p-2 bg-primary-100 dark:bg-primary-900 hover:bg-primary-200 dark:hover:bg-primary-800 rounded-lg transition-colors z-10"
                title="Modifier la classe"
              >
                <Edit className="w-4 h-4 text-primary-600 dark:text-primary-400" />
              </button>
              <h3 className="text-xl font-semibold mb-2 text-gray-900 dark:text-white pr-10">{cls.name}</h3>
              <p className="text-sm text-gray-600 dark:text-gray-400 mb-4">{cls.level} - {cls.grade}</p>
              <div className="flex items-center justify-between">
                <span className="text-sm text-gray-500 dark:text-gray-400">Capacité: {cls.capacity}</span>
                <span className="badge badge-info">{cls.academic_year}</span>
              </div>
            </Card>
          ))
        )}
      </div>

      {/* Modale pour afficher les élèves de la classe */}
      {selectedClassId && (
        <div 
          className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50 p-4"
          onClick={handleCloseModal}
        >
          <div 
            className="bg-white dark:bg-gray-800 rounded-lg shadow-xl max-w-7xl w-full max-h-[95vh] overflow-y-auto transition-colors"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="sticky top-0 bg-white dark:bg-gray-800 border-b border-gray-200 dark:border-gray-700 px-6 py-4 z-10">
              <div className="flex items-center justify-between mb-4">
                <div>
                  <h2 className="text-2xl font-semibold text-gray-900 dark:text-white">
                    Élèves de la classe : {selectedClassName}
                  </h2>
                  <p className="text-sm text-gray-500 dark:text-gray-400 mt-1">
                    {filteredEnrollments.length} parcours {searchQuery ? 'trouvé(s)' : ''} sur {enrollmentsList.length} (actifs, promus, diplômés)
                  </p>
                </div>
                <button
                  onClick={handleCloseModal}
                  className="p-2 hover:bg-gray-100 dark:hover:bg-gray-700 rounded-lg transition-colors"
                >
                  <X className="w-5 h-5 text-gray-600 dark:text-gray-400" />
                </button>
              </div>
              
              {/* Barre de recherche */}
              <div className="relative">
                <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 w-5 h-5 text-gray-400" />
                <input
                  type="text"
                  placeholder="Rechercher par ID, Nom, Email ou Numéro de téléphone..."
                  value={searchQuery}
                  onChange={(e) => setSearchQuery(e.target.value)}
                  className="w-full pl-10 pr-4 py-2 border border-gray-300 dark:border-gray-600 rounded-lg bg-white dark:bg-gray-700 text-gray-900 dark:text-white placeholder-gray-400 dark:placeholder-gray-500 focus:outline-none focus:ring-2 focus:ring-primary-500 focus:border-transparent"
                />
              </div>
            </div>

            <div className="p-6">
              {isLoadingStudents ? (
                <div className="text-center py-8">
                  <p className="text-gray-600 dark:text-gray-400">Chargement des élèves...</p>
                </div>
              ) : enrollmentsList.length === 0 ? (
                <div className="text-center py-12">
                  <Users className="w-16 h-16 text-gray-400 dark:text-gray-600 mx-auto mb-4" />
                  <p className="text-gray-600 dark:text-gray-400 text-lg">
                    Aucun parcours dans cette classe (actifs, promus ou diplômés)
                  </p>
                </div>
              ) : filteredEnrollments.length === 0 ? (
                <div className="text-center py-12">
                  <Search className="w-16 h-16 text-gray-400 dark:text-gray-600 mx-auto mb-4" />
                  <p className="text-gray-600 dark:text-gray-400 text-lg">
                    Aucun parcours trouvé pour &quot;{searchQuery}&quot;
                  </p>
                </div>
              ) : (
                <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
                  {filteredEnrollments.map((enr: any) => {
                    const s = enr.student || {}
                    const statusBadgeClass =
                      enr.status === 'active' ? 'badge badge-success' :
                      enr.status === 'promoted' ? 'badge badge-info' :
                      enr.status === 'graduated' ? 'badge bg-purple-100 text-purple-800 dark:bg-purple-900/30 dark:text-purple-300' :
                      enr.status === 'echec' ? 'badge bg-amber-100 text-amber-800 dark:bg-amber-900/30 dark:text-amber-300' :
                      'badge bg-gray-100 text-gray-700 dark:bg-gray-700 dark:text-gray-300'
                    return (
                    <Card 
                      key={enr.id} 
                      className="p-4 hover:shadow-lg transition-all cursor-pointer hover:scale-[1.02]"
                      onClick={(e) => handleStudentClick(e, enr)}
                    >
                      <div className="flex items-start space-x-4">
                        <div className="w-12 h-12 rounded-full bg-primary-100 dark:bg-primary-900 flex items-center justify-center flex-shrink-0">
                          <User className="w-6 h-6 text-primary-600 dark:text-primary-400" />
                        </div>
                        <div className="flex-1 min-w-0">
                          <div className="flex items-center justify-between gap-2 mb-1">
                            <h3 className="text-lg font-semibold text-gray-900 dark:text-white truncate">
                              {s.user_name || [s.user?.first_name, s.user?.last_name, s.user?.middle_name].filter(Boolean).join(' ') || 'Élève sans nom'}
                            </h3>
                            <span className={`text-xs px-2 py-0.5 rounded-full flex-shrink-0 ${statusBadgeClass}`}>
                              {enr.status_display || enr.status}
                            </span>
                          </div>
                          <div className="space-y-1 text-sm text-gray-600 dark:text-gray-400">
                            {s.student_id && (
                              <div className="flex items-center space-x-2">
                                <span className="font-medium">ID:</span>
                                <span>{s.student_id}</span>
                              </div>
                            )}
                            {s.user?.email && (
                              <div className="flex items-center space-x-2">
                                <Mail className="w-4 h-4" />
                                <span className="truncate">{s.user.email}</span>
                              </div>
                            )}
                            {s.user?.phone && (
                              <div className="flex items-center space-x-2">
                                <Phone className="w-4 h-4" />
                                <span>{s.user.phone}</span>
                              </div>
                            )}
                            {(s.enrollment_date || enr.enrolled_at) && (
                              <div className="text-xs text-gray-500 dark:text-gray-500 mt-2">
                                Inscrit le: {new Date(s.enrollment_date || enr.enrolled_at).toLocaleDateString('fr-FR')}
                              </div>
                            )}
                          </div>
                        </div>
                      </div>
                    </Card>
                    )
                  })}
                </div>
              )}
            </div>
          </div>
        </div>
      )}

      {/* Modale pour afficher les détails de l'élève */}
      {selectedStudent && (
        <div 
          className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-[60] p-4"
          onClick={handleCloseStudentModal}
        >
          <div 
            className="bg-white dark:bg-gray-800 rounded-lg shadow-xl max-w-4xl w-full max-h-[90vh] overflow-y-auto transition-colors"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="sticky top-0 bg-white dark:bg-gray-800 border-b border-gray-200 dark:border-gray-700 px-6 py-4 flex items-center justify-between z-10">
              <h2 className="text-2xl font-semibold text-gray-900 dark:text-white">
                Détails de l'élève
              </h2>
              <button
                onClick={handleCloseStudentModal}
                className="p-2 hover:bg-gray-100 dark:hover:bg-gray-700 rounded-lg transition-colors"
              >
                <X className="w-5 h-5 text-gray-600 dark:text-gray-400" />
              </button>
            </div>

            <div className="p-6">
              <div className="flex items-start space-x-6 mb-6">
                <div className="w-24 h-24 rounded-full bg-primary-100 dark:bg-primary-900 flex items-center justify-center flex-shrink-0">
                  <User className="w-12 h-12 text-primary-600 dark:text-primary-400" />
                </div>
                <div className="flex-1">
                  <h3 className="text-2xl font-bold text-gray-900 dark:text-white mb-2">
                    {selectedStudent.user_name || [selectedStudent.user?.first_name, selectedStudent.user?.last_name, selectedStudent.user?.middle_name].filter(Boolean).join(' ') || 'Élève sans nom'}
                  </h3>
                  {selectedStudent.student_id && (
                    <p className="text-lg text-gray-600 dark:text-gray-400">
                      ID: <span className="font-semibold">{selectedStudent.student_id}</span>
                    </p>
                  )}
                </div>
              </div>

              <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                {/* Informations personnelles */}
                <Card className="p-4">
                  <h4 className="text-lg font-semibold text-gray-900 dark:text-white mb-4 flex items-center space-x-2">
                    <User className="w-5 h-5" />
                    <span>Informations personnelles</span>
                  </h4>
                  <div className="space-y-3">
                    {selectedStudent.user?.first_name && (
                      <div>
                        <span className="text-sm font-medium text-gray-500 dark:text-gray-400">Prénom:</span>
                        <p className="text-gray-900 dark:text-white">{selectedStudent.user.first_name}</p>
                      </div>
                    )}
                    {selectedStudent.user?.last_name && (
                      <div>
                        <span className="text-sm font-medium text-gray-500 dark:text-gray-400">Nom:</span>
                        <p className="text-gray-900 dark:text-white">{selectedStudent.user.last_name}</p>
                      </div>
                    )}
                    {selectedStudent.user?.email && (
                      <div className="flex items-center space-x-2">
                        <Mail className="w-4 h-4 text-gray-400" />
                        <div>
                          <span className="text-sm font-medium text-gray-500 dark:text-gray-400">Email:</span>
                          <p className="text-gray-900 dark:text-white">{selectedStudent.user.email}</p>
                        </div>
                      </div>
                    )}
                    {selectedStudent.user?.phone && (
                      <div className="flex items-center space-x-2">
                        <Phone className="w-4 h-4 text-gray-400" />
                        <div>
                          <span className="text-sm font-medium text-gray-500 dark:text-gray-400">Téléphone:</span>
                          <p className="text-gray-900 dark:text-white">{selectedStudent.user.phone}</p>
                        </div>
                      </div>
                    )}
                    {selectedStudent.user?.username && (
                      <div>
                        <span className="text-sm font-medium text-gray-500 dark:text-gray-400">Nom d'utilisateur:</span>
                        <p className="text-gray-900 dark:text-white">{selectedStudent.user.username}</p>
                      </div>
                    )}
                  </div>
                </Card>

                {/* Informations scolaires */}
                <Card className="p-4">
                  <h4 className="text-lg font-semibold text-gray-900 dark:text-white mb-4 flex items-center space-x-2">
                    <BookOpen className="w-5 h-5" />
                    <span>Informations scolaires</span>
                  </h4>
                  <div className="space-y-3">
                    {selectedStudent.school_class && (
                      <div>
                        <span className="text-sm font-medium text-gray-500 dark:text-gray-400">Classe:</span>
                        <p className="text-gray-900 dark:text-white">{selectedStudent.class_name || selectedStudent.school_class?.name || 'Non assignée'}</p>
                      </div>
                    )}
                    {selectedStudent.academic_year && (
                      <div>
                        <span className="text-sm font-medium text-gray-500 dark:text-gray-400">Année scolaire:</span>
                        <p className="text-gray-900 dark:text-white">{selectedStudent.academic_year}</p>
                      </div>
                    )}
                    {selectedStudent.enrollment_date && (
                      <div className="flex items-center space-x-2">
                        <Calendar className="w-4 h-4 text-gray-400" />
                        <div>
                          <span className="text-sm font-medium text-gray-500 dark:text-gray-400">Date d'inscription:</span>
                          <p className="text-gray-900 dark:text-white">
                            {new Date(selectedStudent.enrollment_date).toLocaleDateString('fr-FR', { 
                              year: 'numeric', 
                              month: 'long', 
                              day: 'numeric' 
                            })}
                          </p>
                        </div>
                      </div>
                    )}
                    {selectedStudent.parent_name && (
                      <div>
                        <span className="text-sm font-medium text-gray-500 dark:text-gray-400">Parent:</span>
                        <p className="text-gray-900 dark:text-white">{selectedStudent.parent_name}</p>
                      </div>
                    )}
                  </div>
                </Card>

                {/* Informations médicales */}
                {(selectedStudent.blood_group || selectedStudent.allergies) && (
                  <Card className="p-4 md:col-span-2">
                    <h4 className="text-lg font-semibold text-gray-900 dark:text-white mb-4 flex items-center space-x-2">
                      <Heart className="w-5 h-5" />
                      <span>Informations médicales</span>
                    </h4>
                    <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                      {selectedStudent.blood_group && (
                        <div>
                          <span className="text-sm font-medium text-gray-500 dark:text-gray-400">Groupe sanguin:</span>
                          <p className="text-gray-900 dark:text-white">{selectedStudent.blood_group}</p>
                        </div>
                      )}
                      {selectedStudent.allergies && (
                        <div>
                          <span className="text-sm font-medium text-gray-500 dark:text-gray-400 flex items-center space-x-1">
                            <AlertCircle className="w-4 h-4" />
                            <span>Allergies:</span>
                          </span>
                          <p className="text-gray-900 dark:text-white">{selectedStudent.allergies}</p>
                        </div>
                      )}
                    </div>
                  </Card>
                )}
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
