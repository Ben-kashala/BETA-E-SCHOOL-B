import { useState, useMemo, useEffect } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import api from '@/services/api'
import { Card } from '@/components/ui/Card'
import { BookOpen, Plus, Trash2, Loader2, X } from 'lucide-react'
import { showErrorToast, showSuccessToast } from '@/utils/toast'
import { sortClassesByLevel } from '@/utils/classLevel'

// Note de base : 10 à 100 par pas de 10. Examen (max) = 2 × période.
const PERIOD_MAX_OPTIONS = [10, 20, 30, 40, 50, 60, 70, 80, 90, 100]

export default function TeacherClassSubjects() {
  const queryClient = useQueryClient()
  const [selectedClass, setSelectedClass] = useState<number | null>(null)
  const [addSubject, setAddSubject] = useState<number | ''>('')
  const [addPeriodMax, setAddPeriodMax] = useState<number>(20)
  const [addTeacher, setAddTeacher] = useState<number | ''>('')
  const [addDomain, setAddDomain] = useState<string>('')
  const [showCreateSubjectModal, setShowCreateSubjectModal] = useState(false)
  const [createName, setCreateName] = useState('')
  const [createCode, setCreateCode] = useState('')
  const [createPeriodMax, setCreatePeriodMax] = useState(20)
  const [createDesc, setCreateDesc] = useState('')

  const { data: classesData } = useQuery({
    queryKey: ['teacher-classes-my-titular'],
    queryFn: async () => {
      const res = await api.get('/schools/classes/my_titular/')
      return res.data
    },
  })

  const { data: subjectsData } = useQuery({
    queryKey: ['subjects'],
    queryFn: async () => {
      const res = await api.get('/schools/subjects/')
      return res.data
    },
  })

  const { data: teachersData } = useQuery({
    queryKey: ['teachers'],
    queryFn: async () => {
      const res = await api.get('/accounts/teachers/', { params: { page_size: '200' } })
      return res.data
    },
  })

  const { data: classSubjectsData } = useQuery({
    queryKey: ['class-subjects', selectedClass],
    queryFn: async () => {
      if (!selectedClass) return { results: [] }
      const res = await api.get('/schools/class-subjects/', {
        params: { school_class: selectedClass },
      })
      return res.data
    },
    enabled: !!selectedClass,
  })

  const createMutation = useMutation({
    mutationFn: (payload: { school_class: number; subject: number; period_max: number; teacher?: number | null; domain?: string | null }) =>
      api.post('/schools/class-subjects/', payload),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['class-subjects'] })
      showSuccessToast('Matière ajoutée à la classe')
      setAddSubject('')
      setAddPeriodMax(20)
      setAddTeacher('')
      setAddDomain('')
    },
    onError: (e: any) => showErrorToast(e, 'Erreur lors de l\'ajout'),
  })

  const updateMutation = useMutation({
    mutationFn: ({ id, period_max, teacher, domain }: { id: number; period_max?: number; teacher?: number | null; domain?: string | null }) => {
      const body: Record<string, unknown> = {}
      if (period_max !== undefined) body.period_max = period_max
      if (teacher !== undefined) body.teacher = teacher
      if (domain !== undefined) body.domain = domain
      return api.patch(`/schools/class-subjects/${id}/`, body)
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['class-subjects'] })
      showSuccessToast('Mise à jour enregistrée')
    },
    onError: (e: any) => showErrorToast(e, 'Erreur lors de la mise à jour'),
  })

  const deleteMutation = useMutation({
    mutationFn: (id: number) => api.delete(`/schools/class-subjects/${id}/`),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['class-subjects'] })
      showSuccessToast('Matière retirée de la classe')
    },
    onError: (e: any) => showErrorToast(e, 'Erreur lors de la suppression'),
  })

  const createSubjectMutation = useMutation({
    mutationFn: (body: { name: string; code: string; period_max?: number; description?: string }) =>
      api.post('/schools/subjects/', body),
    onSuccess: (res) => {
      queryClient.invalidateQueries({ queryKey: ['subjects'] })
      const id = res.data?.id
      if (id != null) setAddSubject(id)
      setShowCreateSubjectModal(false)
      setCreateName('')
      setCreateCode('')
      setCreatePeriodMax(20)
      setCreateDesc('')
      showSuccessToast('Matière créée. Vous pouvez l\'ajouter à la classe.')
    },
    onError: (e: any) => showErrorToast(e, 'Erreur lors de la création de la matière'),
  })

  const classes = useMemo(() => classesData?.results ?? [], [classesData])
  // Auto-sélection : 1 classe → celle-ci ; 2+ classes → la plus basse (1ère < 2ème < … < 6ème), avec possibilité de changer
  useEffect(() => {
    if (classes.length === 0 || selectedClass !== null) return
    const sorted = sortClassesByLevel(classes)
    const firstId = (sorted[0] as { id?: number })?.id
    if (firstId != null) setSelectedClass(firstId)
  }, [classes, selectedClass])

  const subjects = useMemo(() => subjectsData?.results ?? [], [subjectsData])
  const teachers = useMemo(() => teachersData?.results ?? [], [teachersData])
  const classSubjects = useMemo(() => classSubjectsData?.results ?? [], [classSubjectsData])
  const assignedIds = useMemo(() => new Set(classSubjects.map((cs: any) => cs.subject)), [classSubjects])
  const availableSubjects = useMemo(
    () => subjects.filter((s: { id?: number }) => s.id != null && !assignedIds.has(s.id)),
    [subjects, assignedIds]
  )

  const handleAdd = () => {
    if (!selectedClass || !addSubject) return
    const domain = addDomain.trim() || null
    createMutation.mutate({
      school_class: selectedClass,
      subject: Number(addSubject),
      period_max: addPeriodMax,
      teacher: addTeacher === '' ? null : Number(addTeacher),
      domain,
    })
  }

  const handlePeriodMaxChange = (cs: any, value: number) => {
    updateMutation.mutate({ id: cs.id, period_max: value })
  }

  const handleTeacherChange = (cs: any, value: string) => {
    updateMutation.mutate({ id: cs.id, teacher: value === '' ? null : Number(value) })
  }

  const handleDomainChange = (cs: any, value: string) => {
    const clean = value.trim() || null
    updateMutation.mutate({ id: cs.id, domain: clean })
  }

  const teacherName = (t: any) =>
    t?.user ? ([t.user.first_name, t.user.last_name, t.user.middle_name].filter(Boolean).join(' ') || t.user.username) : `#${t?.id}`

  const handleDelete = (id: number) => {
    if (window.confirm('Retirer cette matière de la classe ?')) deleteMutation.mutate(id)
  }

  const hasTitularClasses = (classesData?.results ?? []).length > 0

  return (
    <div>
      <h1 className="text-3xl font-bold text-gray-900 dark:text-white mb-6">
        Matières par classe
      </h1>
      <p className="text-gray-600 dark:text-gray-400 mb-6">
        En tant que titulaire, définissez les matières de votre classe, les notes de base (max par <strong>période</strong> et <strong>examen</strong> = 2 × période, bulletin RDC), <strong>classez-les par domaine (Sciences, Langues, Arts…)</strong> et <strong>attribuez chaque matière à un enseignant</strong>. Les domaines et notes de base sont utilisés pour construire le bulletin officiel RDC.
      </p>

      {!hasTitularClasses ? (
        <Card>
          <div className="py-12 text-center text-amber-700 dark:text-amber-300">
            <p className="font-medium">Vous n&apos;êtes titulaire d&apos;aucune classe.</p>
            <p className="text-sm mt-2">Seul l&apos;enseignant titulaire peut gérer les matières et notes de base. L&apos;administrateur peut vous désigner comme titulaire dans la fiche de la classe.</p>
          </div>
        </Card>
      ) : (
        <>
      <Card className="mb-6">
        <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
          Classe (mes classes titulaires)
        </label>
        <select
          value={selectedClass ?? ''}
          onChange={(e) => setSelectedClass(e.target.value ? Number(e.target.value) : null)}
          className="input max-w-md"
        >
          <option value="">Sélectionner une classe</option>
          {classes.map((c: any) => (
            <option key={c.id} value={c.id}>{c.name}</option>
          ))}
        </select>
      </Card>

      {selectedClass && (
        <Card>
          <h2 className="text-lg font-semibold text-gray-900 dark:text-white mb-4 flex items-center gap-2">
            <BookOpen className="w-5 h-5" />
            Matières de la classe
          </h2>

          {/* Ajouter une matière */}
          <div className="flex flex-wrap items-end gap-4 mb-6 p-4 bg-gray-50 dark:bg-gray-800/50 rounded-lg">
            <div>
              <div className="flex items-center gap-2 mb-1">
                <label className="block text-sm font-medium text-gray-700 dark:text-gray-300">Matière</label>
                <button
                  type="button"
                  onClick={() => setShowCreateSubjectModal(true)}
                  className="text-sm text-primary-600 dark:text-primary-400 hover:underline"
                >
                  + Créer une matière
                </button>
              </div>
              <select
                value={addSubject}
                onChange={(e) => setAddSubject(e.target.value ? Number(e.target.value) : '')}
                className="input"
              >
                <option value="">Choisir une matière</option>
                {availableSubjects.map((s: any) => (
                  <option key={s.id} value={s.id}>{s.name} (défaut: {s.period_max ?? 20})</option>
                ))}
              </select>
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">Note de base — Période (interrogation)</label>
              <select
                value={addPeriodMax}
                onChange={(e) => setAddPeriodMax(Number(e.target.value))}
                className="input"
              >
                {PERIOD_MAX_OPTIONS.map((v) => (
                  <option key={v} value={v}>{v}</option>
                ))}
              </select>
              <p className="text-xs text-gray-500 dark:text-gray-400 mt-0.5">Examen (max) = 2 × période = {addPeriodMax * 2}</p>
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                Domaine (bulletin RDC)
              </label>
              <input
                value={addDomain}
                onChange={(e) => setAddDomain(e.target.value)}
                className="input min-w-[200px]"
                placeholder="Ex. DOMAINE DES SCIENCES"
              />
              <p className="text-xs text-gray-500 dark:text-gray-400 mt-0.5">
                Utilisé pour regrouper les matières dans le bulletin officiel.
              </p>
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">Enseignant assigné</label>
              <select
                value={addTeacher}
                onChange={(e) => setAddTeacher(e.target.value === '' ? '' : Number(e.target.value))}
                className="input min-w-[180px]"
              >
                <option value="">— Non assigné —</option>
                {teachers.map((t: any) => (
                  <option key={t.id} value={t.id}>{teacherName(t)}</option>
                ))}
              </select>
              <p className="text-xs text-gray-500 dark:text-gray-400 mt-0.5">Saisira les notes de cette matière</p>
            </div>
            <button
              onClick={handleAdd}
              disabled={!addSubject || createMutation.isPending}
              className="btn btn-primary flex items-center gap-2"
            >
              {createMutation.isPending ? <Loader2 className="w-4 h-4 animate-spin" /> : <Plus className="w-4 h-4" />}
              Ajouter
            </button>
          </div>

          {/* Liste */}
          <div className="overflow-x-auto">
            <table className="w-full">
              <thead className="bg-gray-50 dark:bg-gray-800">
                <tr>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase">Matière</th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase">Domaine (bulletin RDC)</th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase">Note de base (max/période)</th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase">Enseignant assigné</th>
                  <th className="px-6 py-3 text-right text-xs font-medium text-gray-500 dark:text-gray-400 uppercase">Actions</th>
                </tr>
              </thead>
              <tbody className="bg-white dark:bg-gray-900 divide-y divide-gray-200 dark:divide-gray-700">
                {classSubjects.length === 0 ? (
                  <tr>
                    <td colSpan={5} className="px-6 py-8 text-center text-gray-500 dark:text-gray-400">
                      Aucune matière assignée. Ajoutez-en une ci-dessus.
                    </td>
                  </tr>
                ) : (
                  classSubjects.map((cs: any) => (
                    <tr key={cs.id} className="hover:bg-gray-50 dark:hover:bg-gray-800/50">
                      <td className="px-6 py-3 text-sm font-medium text-gray-900 dark:text-white">
                        {cs.subject_name} {cs.subject_code && `(${cs.subject_code})`}
                      </td>
                      <td className="px-6 py-3">
                        <input
                          defaultValue={cs.domain ?? ''}
                          onBlur={(e) => handleDomainChange(cs, e.target.value)}
                          disabled={updateMutation.isPending}
                          className="input w-full py-1.5 text-sm"
                          placeholder="Ex. DOMAINE DES SCIENCES"
                        />
                      </td>
                      <td className="px-6 py-3">
                        <div className="flex flex-col gap-0.5">
                          <select
                            value={cs.period_max}
                            onChange={(e) => handlePeriodMaxChange(cs, Number(e.target.value))}
                            disabled={updateMutation.isPending}
                            className="input w-24 py-1.5"
                          >
                            {PERIOD_MAX_OPTIONS.map((v) => (
                              <option key={v} value={v}>{v}</option>
                            ))}
                          </select>
                          <span className="text-xs text-gray-500 dark:text-gray-400">Ex. max: {Number(cs.period_max) * 2}</span>
                        </div>
                      </td>
                      <td className="px-6 py-3">
                        <select
                          value={cs.teacher ?? ''}
                          onChange={(e) => handleTeacherChange(cs, e.target.value)}
                          disabled={updateMutation.isPending}
                          className="input min-w-[160px] py-1.5"
                        >
                          <option value="">— Non assigné —</option>
                          {teachers.map((t: any) => (
                            <option key={t.id} value={t.id}>{teacherName(t)}</option>
                          ))}
                        </select>
                      </td>
                      <td className="px-6 py-3 text-right">
                        <button
                          onClick={() => handleDelete(cs.id)}
                          disabled={deleteMutation.isPending}
                          className="text-red-600 hover:text-red-800 dark:text-red-400 dark:hover:text-red-300 p-1"
                          title="Retirer de la classe"
                        >
                          <Trash2 className="w-4 h-4" />
                        </button>
                      </td>
                    </tr>
                  ))
                )}
              </tbody>
            </table>
          </div>
        </Card>
      )}

      {!selectedClass && (
        <Card>
          <p className="py-8 text-center text-gray-500 dark:text-gray-400">
            Sélectionnez une classe pour gérer ses matières et notes de base.
          </p>
        </Card>
      )}
        </>
      )}

      {/* Modal Créer une matière */}
      {showCreateSubjectModal && (
        <div
          className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4"
          onClick={() => setShowCreateSubjectModal(false)}
        >
          <Card
            className="w-full max-w-md"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex items-center justify-between mb-4">
              <h3 className="text-lg font-semibold text-gray-900 dark:text-white">Créer une matière</h3>
              <button
                type="button"
                onClick={() => setShowCreateSubjectModal(false)}
                className="p-2 hover:bg-gray-100 dark:hover:bg-gray-700 rounded-lg"
              >
                <X className="w-5 h-5" />
              </button>
            </div>
            <form
              onSubmit={(e) => {
                e.preventDefault()
                const name = createName.trim()
                const code = createCode.trim().toUpperCase()
                if (!name || !code) {
                  showErrorToast(new Error('Nom et code requis'), 'Validation')
                  return
                }
                createSubjectMutation.mutate({
                  name,
                  code,
                  period_max: createPeriodMax,
                  description: createDesc.trim() || undefined,
                })
              }}
              className="space-y-4"
            >
              <div>
                <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">Nom <span className="text-red-500">*</span></label>
                <input
                  value={createName}
                  onChange={(e) => setCreateName(e.target.value)}
                  className="input w-full"
                  placeholder="Ex. Mathématiques"
                />
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">Code <span className="text-red-500">*</span></label>
                <input
                  value={createCode}
                  onChange={(e) => setCreateCode(e.target.value.toUpperCase())}
                  className="input w-full"
                  placeholder="Ex. MATH (unique par école)"
                  maxLength={20}
                />
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">Note de base par défaut (période)</label>
                <select
                  value={createPeriodMax}
                  onChange={(e) => setCreatePeriodMax(Number(e.target.value))}
                  className="input w-full"
                >
                  {PERIOD_MAX_OPTIONS.map((v) => (
                    <option key={v} value={v}>{v}</option>
                  ))}
                </select>
                <p className="text-xs text-gray-500 dark:text-gray-400 mt-0.5">Examen (max) = 2 × période = {createPeriodMax * 2}</p>
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">Description (optionnel)</label>
                <textarea
                  value={createDesc}
                  onChange={(e) => setCreateDesc(e.target.value)}
                  className="input w-full min-h-[80px]"
                  placeholder="Description de la matière"
                />
              </div>
              <div className="flex justify-end gap-2 pt-2">
                <button
                  type="button"
                  onClick={() => setShowCreateSubjectModal(false)}
                  className="btn btn-secondary"
                >
                  Annuler
                </button>
                <button
                  type="submit"
                  disabled={createSubjectMutation.isPending || !createName.trim() || !createCode.trim()}
                  className="btn btn-primary flex items-center gap-2"
                >
                  {createSubjectMutation.isPending && <Loader2 className="w-4 h-4 animate-spin" />}
                  Créer
                </button>
              </div>
            </form>
          </Card>
        </div>
      )}
    </div>
  )
}
