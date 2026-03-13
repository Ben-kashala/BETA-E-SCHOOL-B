import { useQuery, useQueryClient } from '@tanstack/react-query'
import { useState, useMemo, useEffect } from 'react'
import api from '@/services/api'
import { Card } from '@/components/ui/Card'
import {
  Search,
  Users,
  X,
  User,
  BookOpen,
  CreditCard,
  ChevronRight,
  Filter,
  FileDown,
} from 'lucide-react'
import { useAcademicYears } from '@/hooks/useAcademicYears'
import { useAuthStore } from '@/store/authStore'
import toast from 'react-hot-toast'

type StatusFilter = 'all' | 'actifs' | 'anciens' | 'sortants'

export default function StudentsPage() {
  const [search, setSearch] = useState('')
  const [academicYear, setAcademicYear] = useState('')
  const [classId, setClassId] = useState('')
  const [statusFilter, setStatusFilter] = useState<StatusFilter>('all')
  const [selectedId, setSelectedId] = useState<number | null>(null)
  const [detailTab, setDetailTab] = useState<'identity' | 'parcours' | 'payments'>('identity')
  const [showTransferModal, setShowTransferModal] = useState(false)
  const { user } = useAuthStore()
  const queryClient = useQueryClient()
  const { years: academicYearNames, current: currentAcademicYear } = useAcademicYears()

  // Params pour l'API
  const params = useMemo(() => {
    const p: Record<string, string | number> = { page_size: 500 }
    if (search.trim()) p['search'] = search.trim()
    if (academicYear) p['academic_year'] = academicYear
    if (classId) p['school_class'] = classId
    if (statusFilter === 'anciens') {
      p['is_former_student'] = 'true'
    } else if (statusFilter === 'actifs') {
      p['is_former_student'] = 'false'
    } else if (statusFilter === 'sortants') {
      p['is_former_student'] = 'false'
      p['school_class__is_terminal'] = 'true'
    }
    return p
  }, [search, academicYear, classId, statusFilter])

  const { data: studentsData, isLoading, error } = useQuery({
    queryKey: ['students', params],
    queryFn: async () => {
      const res = await api.get('/accounts/students/', { params })
      return res.data
    },
  })

  const { data: classesData } = useQuery({
    queryKey: ['school-classes'],
    queryFn: async () => {
      const res = await api.get('/schools/classes/')
      return res.data
    },
  })

  // Fallback pour les anciennes API: on garde l'appel /academics/academic-years/ si le hook ne retourne rien.
  const { data: academicYearsData } = useQuery({
    queryKey: ['academic-years'],
    queryFn: async () => {
      const res = await api.get('/academics/academic-years/', { params: { page_size: 100 } })
      return res.data
    },
    enabled: !academicYearNames.length,
  })

  const { data: detailData, isLoading: detailLoading } = useQuery({
    queryKey: ['student-full-detail', selectedId],
    queryFn: async () => {
      const res = await api.get(`/accounts/students/${selectedId}/full_detail/`)
      return res.data
    },
    enabled: !!selectedId,
  })

  const list = useMemo(() => (studentsData?.results ?? []) as any[], [studentsData])
  const classes = useMemo(() => (classesData?.results ?? classesData ?? []) as any[], [classesData])
  const academicYears = useMemo(
    () => (academicYearsData?.results ?? academicYearsData ?? []) as any[],
    [academicYearsData],
  )

  // Années distinctes depuis les classes si academic-years est vide
  const yearOptions = useMemo(() => {
    if (academicYearNames.length > 0) {
      return academicYearNames.map((name) => ({ id: name, name }))
    }
    if (academicYears.length > 0) return academicYears
    const years = new Set<string>()
    classes.forEach((c: any) => {
      if (c.academic_year) years.add(c.academic_year)
    })
    return Array.from(years)
      .sort()
      .reverse()
      .map((name) => ({ id: name, name }))
  }, [academicYearNames, academicYears, classes])

  const getStatusLabel = (s: any) => {
    if (s.is_former_student) return { label: 'Ancien', className: 'bg-amber-100 text-amber-800 dark:bg-amber-900/40 dark:text-amber-300' }
    if (s.school_class?.is_terminal) return { label: 'Sortant', className: 'bg-blue-100 text-blue-800 dark:bg-blue-900/40 dark:text-blue-300' }
    return { label: 'Actif', className: 'bg-green-100 text-green-800 dark:bg-green-900/40 dark:text-green-300' }
  }

  const resetFilters = () => {
    setSearch('')
    setAcademicYear('')
    setClassId('')
    setStatusFilter('all')
  }

  const hasActiveFilters = search || academicYear || classId || statusFilter !== 'all'

  return (
    <div>
      <h1 className="text-3xl font-bold text-gray-900 dark:text-white mb-2 flex items-center gap-2">
        <Users className="w-8 h-8" />
        Élèves
      </h1>
      <p className="text-gray-600 dark:text-gray-400 mb-6">
        Tous les élèves de l&apos;école (actifs, anciens, sortants). Cliquez sur une ligne pour afficher le détail.
      </p>

      {/* Filtres */}
      <Card className="mb-6">
        <div className="flex flex-wrap items-end gap-4">
          <div className="flex-1 min-w-[200px]">
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">Recherche</label>
            <div className="relative">
              <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-5 h-5 text-gray-400" />
              <input
                type="text"
                placeholder="Nom, matricule..."
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                className="input w-full pl-10"
              />
            </div>
          </div>
          <div className="w-40">
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">Année scolaire</label>
            <select
              value={academicYear}
              onChange={(e) => setAcademicYear(e.target.value)}
              className="input w-full"
            >
              <option value="">
                {currentAcademicYear
                  ? `Toutes (par défaut ${currentAcademicYear})`
                  : 'Toutes'}
              </option>
              {yearOptions.map((y: any) => (
                <option key={y.id || y.name} value={y.name || y.id}>
                  {y.name || y.id}
                </option>
              ))}
            </select>
          </div>
          <div className="w-48">
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">Classe</label>
            <select
              value={classId}
              onChange={(e) => setClassId(e.target.value)}
              className="input w-full"
            >
              <option value="">Toutes</option>
              {classes.map((c: any) => (
                <option key={c.id} value={c.id}>{c.name} {c.academic_year ? `(${c.academic_year})` : ''}</option>
              ))}
            </select>
          </div>
          <div className="w-36">
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">Statut</label>
            <select
              value={statusFilter}
              onChange={(e) => setStatusFilter(e.target.value as StatusFilter)}
              className="input w-full"
            >
              <option value="all">Tous</option>
              <option value="actifs">Actifs</option>
              <option value="anciens">Anciens</option>
              <option value="sortants">Sortants</option>
            </select>
          </div>
          {hasActiveFilters && (
            <button
              onClick={resetFilters}
              className="btn btn-secondary flex items-center gap-1"
            >
              <Filter className="w-4 h-4" />
              Réinitialiser
            </button>
          )}
        </div>
      </Card>

      {/* Tableau */}
      <Card>
        {isLoading ? (
          <div className="py-12 text-center text-gray-500 dark:text-gray-400">Chargement...</div>
        ) : error ? (
          <div className="py-12 text-center text-red-600 dark:text-red-400">
            Erreur lors du chargement des élèves.
          </div>
        ) : list.length === 0 ? (
          <div className="py-12 text-center">
            <Users className="w-16 h-16 text-gray-400 dark:text-gray-600 mx-auto mb-4" />
            <p className="text-gray-600 dark:text-gray-400">Aucun élève trouvé.</p>
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full">
              <thead className="bg-gray-50 dark:bg-gray-800">
                <tr>
                  <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase">Matricule</th>
                  <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase">Nom</th>
                  <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase">Classe</th>
                  <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase">Année scolaire</th>
                  <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase">Statut</th>
                  <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase">Contact</th>
                  <th className="px-4 py-3 w-10" />
                </tr>
              </thead>
              <tbody className="bg-white dark:bg-gray-900 divide-y divide-gray-200 dark:divide-gray-700">
                {list.map((s: any) => {
                  const st = getStatusLabel(s)
                  return (
                    <tr
                      key={s.id}
                      onClick={() => { setSelectedId(s.id); setDetailTab('identity'); }}
                      className="hover:bg-gray-50 dark:hover:bg-gray-800/50 cursor-pointer group"
                    >
                      <td className="px-4 py-3 text-sm font-medium text-gray-900 dark:text-white">{s.student_id ?? '-'}</td>
                      <td className="px-4 py-3 text-sm text-gray-700 dark:text-gray-300">
                        {(s.user_name ?? [s.user?.first_name, s.user?.last_name, s.user?.middle_name].filter(Boolean).join(' ')) || '-'}
                      </td>
                      <td className="px-4 py-3 text-sm text-gray-600 dark:text-gray-400">{s.class_name || s.school_class?.name || '-'}</td>
                      <td className="px-4 py-3 text-sm text-gray-600 dark:text-gray-400">{s.academic_year ?? '-'}</td>
                      <td className="px-4 py-3">
                        <span className={`inline-flex px-2 py-0.5 rounded text-xs font-medium ${st.className}`}>
                          {st.label}
                        </span>
                      </td>
                      <td className="px-4 py-3 text-sm text-gray-600 dark:text-gray-400">{s.user?.email ?? s.user?.phone ?? '-'}</td>
                      <td className="px-4 py-3">
                        <ChevronRight className="w-5 h-5 text-gray-400 group-hover:text-primary-600" />
                      </td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </div>
        )}
      </Card>

      {/* Modal détail élève */}
      {selectedId && (
        <div
          className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4"
          onClick={() => setSelectedId(null)}
        >
          <div
            className="bg-white dark:bg-gray-900 rounded-xl shadow-xl max-w-3xl w-full max-h-[90vh] overflow-hidden flex flex-col"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex items-center justify-between p-4 border-b border-gray-200 dark:border-gray-700">
              <h2 className="text-xl font-bold text-gray-900 dark:text-white">
                Fiche élève {detailData?.identity?.user_name || detailData?.identity?.student_id || `#${selectedId}`}
              </h2>
              <div className="flex items-center gap-2">
                {user?.role === 'ADMIN' && (
                  <button
                    onClick={() => setShowTransferModal(true)}
                    className="btn btn-secondary px-3 py-1 text-xs sm:text-sm"
                  >
                    Transférer vers une autre école
                  </button>
                )}
                <button
                  onClick={() => setSelectedId(null)}
                  className="p-2 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-800 text-gray-500"
                >
                  <X className="w-5 h-5" />
                </button>
              </div>
            </div>

            {/* Onglets */}
            <div className="flex border-b border-gray-200 dark:border-gray-700">
              {(['identity', 'parcours', 'payments'] as const).map((tab) => (
                <button
                  key={tab}
                  onClick={() => setDetailTab(tab)}
                  className={`px-4 py-3 text-sm font-medium flex items-center gap-2 ${
                    detailTab === tab
                      ? 'text-primary-600 border-b-2 border-primary-600'
                      : 'text-gray-500 hover:text-gray-700 dark:hover:text-gray-400'
                  }`}
                >
                  {tab === 'identity' && <User className="w-4 h-4" />}
                  {tab === 'parcours' && <BookOpen className="w-4 h-4" />}
                  {tab === 'payments' && <CreditCard className="w-4 h-4" />}
                  {tab === 'identity' && 'Identité'}
                  {tab === 'parcours' && 'Parcours'}
                  {tab === 'payments' && 'Paiements'}
                </button>
              ))}
            </div>

            <div className="flex-1 overflow-y-auto p-4">
              {detailLoading ? (
                <div className="py-8 text-center text-gray-500">Chargement...</div>
              ) : !detailData ? (
                <div className="py-8 text-center text-red-500">Erreur lors du chargement.</div>
              ) : detailTab === 'identity' ? (
                <IdentityTab data={detailData.identity} />
              ) : detailTab === 'parcours' ? (
                <ParcoursTab
                  studentId={selectedId}
                  classEnrollments={detailData.class_enrollments || []}
                  gradeBulletins={detailData.grade_bulletins || []}
                  reportCards={detailData.report_cards || []}
                />
              ) : (
                <PaymentsTab payments={detailData.payments || []} />
              )}
            </div>
          </div>
        </div>
      )}
      {showTransferModal && selectedId && user?.role === 'ADMIN' && (
        <TransferStudentModal
          studentId={selectedId}
          onClose={() => setShowTransferModal(false)}
          onTransferred={() => {
            queryClient.invalidateQueries({ queryKey: ['students'] })
            setShowTransferModal(false)
            setSelectedId(null)
          }}
        />
      )}
    </div>
  )
}

function IdentityTab({ data }: { data: any }) {
  const u = data?.user || {}
  return (
    <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
      <div>
        <p className="text-xs text-gray-500 dark:text-gray-400">Matricule</p>
        <p className="font-medium text-gray-900 dark:text-white">{data?.student_id ?? '-'}</p>
      </div>
      <div>
        <p className="text-xs text-gray-500 dark:text-gray-400">Nom complet</p>
        <p className="font-medium text-gray-900 dark:text-white">{data?.user_name || [u?.first_name, u?.last_name, u?.middle_name].filter(Boolean).join(' ') || '-'}</p>
      </div>
      <div>
        <p className="text-xs text-gray-500 dark:text-gray-400">Date de naissance</p>
        <p className="font-medium text-gray-900 dark:text-white">{u?.date_of_birth ? new Date(u.date_of_birth).toLocaleDateString('fr-FR') : '-'}</p>
      </div>
      <div>
        <p className="text-xs text-gray-500 dark:text-gray-400">Email</p>
        <p className="font-medium text-gray-900 dark:text-white">{u?.email ?? '-'}</p>
      </div>
      <div>
        <p className="text-xs text-gray-500 dark:text-gray-400">Téléphone</p>
        <p className="font-medium text-gray-900 dark:text-white">{u?.phone ?? '-'}</p>
      </div>
      <div>
        <p className="text-xs text-gray-500 dark:text-gray-400">Adresse</p>
        <p className="font-medium text-gray-900 dark:text-white">{u?.address ?? '-'}</p>
      </div>
      <div>
        <p className="text-xs text-gray-500 dark:text-gray-400">Classe actuelle</p>
        <p className="font-medium text-gray-900 dark:text-white">{data?.class_name ?? data?.school_class?.name ?? '-'}</p>
      </div>
      <div>
        <p className="text-xs text-gray-500 dark:text-gray-400">Année scolaire</p>
        <p className="font-medium text-gray-900 dark:text-white">{data?.academic_year ?? '-'}</p>
      </div>
      <div>
        <p className="text-xs text-gray-500 dark:text-gray-400">Parent / Tuteur</p>
        <p className="font-medium text-gray-900 dark:text-white">{data?.parent_name ?? '-'}</p>
      </div>
      <div>
        <p className="text-xs text-gray-500 dark:text-gray-400">Date d&apos;inscription</p>
        <p className="font-medium text-gray-900 dark:text-white">{data?.enrollment_date ? new Date(data.enrollment_date).toLocaleDateString('fr-FR') : '-'}</p>
      </div>
      <div>
        <p className="text-xs text-gray-500 dark:text-gray-400">Ancien élève</p>
        <p className="font-medium text-gray-900 dark:text-white">{data?.is_former_student ? 'Oui' : 'Non'}</p>
      </div>
      {data?.is_former_student && (
        <div>
          <p className="text-xs text-gray-500 dark:text-gray-400">Année de sortie</p>
          <p className="font-medium text-gray-900 dark:text-white">{data?.graduation_year ?? '-'}</p>
        </div>
      )}
      <div className="md:col-span-2">
        <p className="text-xs text-gray-500 dark:text-gray-400">Groupe sanguin / Allergies</p>
        <p className="font-medium text-gray-900 dark:text-white">
          {[data?.blood_group, data?.allergies].filter(Boolean).join(' — ') || '-'}
        </p>
      </div>
    </div>
  )
}

function ParcoursTab({
  studentId,
  classEnrollments,
  gradeBulletins,
  reportCards,
}: {
  studentId: number | null
  classEnrollments: any[]
  gradeBulletins: any[]
  reportCards: any[]
}) {
  const downloadPdf = async (url: string, filename: string) => {
    try {
      const res = await api.get(url, { responseType: 'blob' })
      const blob = res.data instanceof Blob ? res.data : new Blob([res.data], { type: 'application/pdf' })
      const u = URL.createObjectURL(blob)
      const a = document.createElement('a')
      a.href = u
      a.download = filename
      a.click()
      URL.revokeObjectURL(u)
    } catch {
      // Erreur gérée par l'intercepteur api (toast)
    }
  }

  return (
    <div className="space-y-6">
      <section>
        <h3 className="text-sm font-semibold text-gray-700 dark:text-gray-300 mb-2">Historique des classes</h3>
        {classEnrollments.length === 0 ? (
          <p className="text-gray-500 dark:text-gray-400">Aucune inscription en classe.</p>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="bg-gray-50 dark:bg-gray-800">
                <tr>
                  <th className="px-3 py-2 text-left">Classe</th>
                  <th className="px-3 py-2 text-left">Année</th>
                  <th className="px-3 py-2 text-left">Statut</th>
                  <th className="px-3 py-2 text-center">Rang</th>
                  <th className="px-3 py-2 text-center">Pourcentage</th>
                  <th className="px-3 py-2 text-left">Inscrit le</th>
                  <th className="px-3 py-2 text-center">Bulletin PDF</th>
                </tr>
              </thead>
              <tbody>
                {classEnrollments.map((e: any) => (
                  <tr key={e.id} className="border-b border-gray-100 dark:border-gray-800">
                    <td className="px-3 py-2">{e.school_class_name ?? '-'}</td>
                    <td className="px-3 py-2">{e.academic_year ?? '-'}</td>
                    <td className="px-3 py-2">{e.status_label ?? e.status ?? '-'}</td>
                    <td className="px-3 py-2 text-center">{e.rank != null ? e.rank : '-'}</td>
                    <td className="px-3 py-2 text-center">{e.percentage != null ? `${Number(e.percentage).toFixed(1)} %` : '-'}</td>
                    <td className="px-3 py-2">{e.enrolled_at ? new Date(e.enrolled_at).toLocaleDateString('fr-FR') : '-'}</td>
                    <td className="px-3 py-2 text-center">
                      {studentId && e.school_class && e.academic_year ? (
                        (() => {
                          const reportCardForYear = reportCards.find(
                            (r: any) => r.academic_year === e.academic_year && r.term === 'AN'
                          )
                          const url = reportCardForYear
                            ? `academics/report-cards/${reportCardForYear.id}/download_pdf/`
                            : `accounts/students/${studentId}/bulletin_pdf/?school_class=${e.school_class}&academic_year=${encodeURIComponent(e.academic_year)}`
                          const filename = `bulletin_${String(e.school_class_name || e.school_class).replace(/[/\\?%*:|"<>]/g, '-')}_${String(e.academic_year).replace(/[/\\?%*:|"<>]/g, '-')}.pdf`
                          return (
                            <button
                              type="button"
                              onClick={() => downloadPdf(url, filename)}
                              className="inline-flex items-center gap-1 text-primary-600 hover:text-primary-700 dark:text-primary-400 dark:hover:text-primary-300 font-medium"
                              title={reportCardForYear ? 'Télécharger le bulletin officiel (décision)' : 'Télécharger le bulletin PDF (notes)'}
                            >
                              <FileDown className="w-4 h-4" />
                              PDF
                            </button>
                          )
                        })()
                      ) : (
                        '-'
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      <section>
        <h3 className="text-sm font-semibold text-gray-700 dark:text-gray-300 mb-2">Notes (bulletin RDC)</h3>
        {gradeBulletins.length === 0 ? (
          <p className="text-gray-500 dark:text-gray-400">Aucune note enregistrée.</p>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="bg-gray-50 dark:bg-gray-800">
                <tr>
                  <th className="px-3 py-2 text-left">Matière</th>
                  <th className="px-3 py-2 text-left">Année</th>
                  <th className="px-3 py-2 text-right">S1</th>
                  <th className="px-3 py-2 text-right">S2</th>
                  <th className="px-3 py-2 text-right">T.G.</th>
                </tr>
              </thead>
              <tbody>
                {gradeBulletins.map((b: any) => (
                  <tr key={b.id} className="border-b border-gray-100 dark:border-gray-800">
                    <td className="px-3 py-2">{b.subject_name ?? '-'}</td>
                    <td className="px-3 py-2">{b.academic_year ?? '-'}</td>
                    <td className="px-3 py-2 text-right">{b.total_s1 != null ? Number(b.total_s1).toFixed(1) : '-'}</td>
                    <td className="px-3 py-2 text-right">{b.total_s2 != null ? Number(b.total_s2).toFixed(1) : '-'}</td>
                    <td className="px-3 py-2 text-right font-medium">{b.total_general != null ? Number(b.total_general).toFixed(1) : '-'}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      <section>
        <h3 className="text-sm font-semibold text-gray-700 dark:text-gray-300 mb-2">Bulletins (décision)</h3>
        {reportCards.length === 0 ? (
          <p className="text-gray-500 dark:text-gray-400">Aucun bulletin.</p>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="bg-gray-50 dark:bg-gray-800">
                <tr>
                  <th className="px-3 py-2 text-left">Année</th>
                  <th className="px-3 py-2 text-left">Période</th>
                  <th className="px-3 py-2 text-right">Moyenne</th>
                  <th className="px-3 py-2 text-right">Place</th>
                  <th className="px-3 py-2 text-left">Décision</th>
                  <th className="px-3 py-2 text-left">Publié</th>
                  <th className="px-3 py-2 text-center">Bulletin PDF</th>
                </tr>
              </thead>
              <tbody>
                {reportCards.map((r: any) => (
                  <tr key={r.id} className="border-b border-gray-100 dark:border-gray-800">
                    <td className="px-3 py-2">{r.academic_year ?? '-'}</td>
                    <td className="px-3 py-2">{r.term ?? '-'}</td>
                    <td className="px-3 py-2 text-right">{r.average_score != null ? Number(r.average_score).toFixed(2) : '-'}</td>
                    <td className="px-3 py-2 text-right">{r.rank != null ? `${r.rank}/${r.total_students ?? '?'}` : '-'}</td>
                    <td className="px-3 py-2">{r.decision ?? '-'}</td>
                    <td className="px-3 py-2">{r.is_published ? 'Oui' : 'Non'}</td>
                    <td className="px-3 py-2 text-center">
                      <button
                        type="button"
                        onClick={() => downloadPdf(
                          `academics/report-cards/${r.id}/download_pdf/`,
                          `bulletin_${String(r.academic_year || '').replace(/[/\\?%*:|"<>]/g, '-')}_${String(r.term || 'AN').replace(/[/\\?%*:|"<>]/g, '-')}.pdf`
                        )}
                        className="inline-flex items-center gap-1 text-primary-600 hover:text-primary-700 dark:text-primary-400 dark:hover:text-primary-300 font-medium"
                        title="Télécharger ou imprimer le bulletin PDF"
                      >
                        <FileDown className="w-4 h-4" />
                        PDF
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>
    </div>
  )
}

function PaymentsTab({ payments }: { payments: any[] }) {
  const statusLabel: Record<string, string> = {
    PENDING: 'En attente',
    PROCESSING: 'En traitement',
    COMPLETED: 'Complété',
    FAILED: 'Échoué',
    CANCELLED: 'Annulé',
    REFUNDED: 'Remboursé',
  }
  return (
    <div>
      {payments.length === 0 ? (
        <p className="text-gray-500 dark:text-gray-400">Aucun paiement enregistré.</p>
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead className="bg-gray-50 dark:bg-gray-800">
              <tr>
                <th className="px-3 py-2 text-left">ID</th>
                <th className="px-3 py-2 text-right">Montant</th>
                <th className="px-3 py-2 text-left">Méthode</th>
                <th className="px-3 py-2 text-left">Statut</th>
                <th className="px-3 py-2 text-left">Date</th>
              </tr>
            </thead>
            <tbody>
              {payments.map((p: any) => (
                <tr key={p.id} className="border-b border-gray-100 dark:border-gray-800">
                  <td className="px-3 py-2 font-mono text-xs">{p.payment_id ?? p.id}</td>
                  <td className="px-3 py-2 text-right">{p.amount != null ? `${Number(p.amount).toLocaleString('fr-FR')} ${p.currency || 'CDF'}` : '-'}</td>
                  <td className="px-3 py-2">{p.payment_method ?? '-'}</td>
                  <td className="px-3 py-2">
                    <span className={p.status === 'COMPLETED' ? 'text-green-600' : p.status === 'FAILED' || p.status === 'CANCELLED' ? 'text-red-600' : 'text-amber-600'}>
                      {statusLabel[p.status] ?? p.status}
                    </span>
                  </td>
                  <td className="px-3 py-2">{p.payment_date ? new Date(p.payment_date).toLocaleDateString('fr-FR') : (p.created_at ? new Date(p.created_at).toLocaleDateString('fr-FR') : '-')}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  )
}

function TransferStudentModal({
  studentId,
  onClose,
  onTransferred,
}: {
  studentId: number
  onClose: () => void
  onTransferred: () => void
}) {
  const [schools, setSchools] = useState<any[]>([])
  const [classes, setClasses] = useState<any[]>([])
  const [loadingSchools, setLoadingSchools] = useState(false)
  const [loadingClasses, setLoadingClasses] = useState(false)
  const [submitting, setSubmitting] = useState(false)
  const [selectedSchoolId, setSelectedSchoolId] = useState<string>('')
  const [selectedClassId, setSelectedClassId] = useState<string>('')

  useEffect(() => {
    const loadSchools = async () => {
      try {
        setLoadingSchools(true)
        const res = await api.get('/schools/all-for-transfer/')
        const data = res.data?.results ?? res.data ?? []
        setSchools(data)
      } catch (e) {
        toast.error('Erreur lors du chargement des écoles.')
      } finally {
        setLoadingSchools(false)
      }
    }
    loadSchools()
  }, [])

  const handleChangeSchool = async (value: string) => {
    setSelectedSchoolId(value)
    setSelectedClassId('')
    if (!value) {
      setClasses([])
      return
    }
    try {
      setLoadingClasses(true)
      const res = await api.get('/schools/classes/', { params: { school: value } })
      const data = res.data?.results ?? res.data ?? []
      setClasses(data)
    } catch (e) {
      toast.error('Erreur lors du chargement des classes de l’école cible.')
    } finally {
      setLoadingClasses(false)
    }
  }

  const handleSubmit = async (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault()
    if (!selectedSchoolId) {
      toast.error("Veuillez choisir l'école cible.")
      return
    }
    try {
      setSubmitting(true)
      await api.post(`/accounts/students/${studentId}/transfer/`, {
        target_school: selectedSchoolId,
        target_class: selectedClassId || null,
      })
      toast.success('Transfert effectué avec succès.')
      onTransferred()
    } catch (err: any) {
      const msg =
        err?.response?.data?.detail ||
        err?.response?.data?.non_field_errors?.join(', ') ||
        'Erreur lors du transfert.'
      toast.error(msg)
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
      <div className="bg-white dark:bg-gray-900 rounded-xl shadow-xl max-w-lg w-full max-h-[90vh] overflow-hidden flex flex-col">
        <div className="flex items-center justify-between p-4 border-b border-gray-200 dark:border-gray-700">
          <h2 className="text-lg font-bold text-gray-900 dark:text-white">Transférer l&apos;élève</h2>
          <button
            onClick={onClose}
            className="p-2 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-800 text-gray-500"
          >
            <X className="w-5 h-5" />
          </button>
        </div>
        <form onSubmit={handleSubmit} className="p-4 space-y-4">
          <p className="text-sm text-gray-600 dark:text-gray-400">
            Sélectionnez l&apos;école de destination et éventuellement une classe dans cette école.
          </p>
          <div>
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
              École cible <span className="text-red-500">*</span>
            </label>
            {loadingSchools ? (
              <div className="input">Chargement des écoles...</div>
            ) : (
              <select
                className="input"
                value={selectedSchoolId}
                onChange={(e) => handleChangeSchool(e.target.value)}
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
              Classe cible (optionnel)
            </label>
            {loadingClasses ? (
              <div className="input">Chargement des classes...</div>
            ) : (
              <select
                className="input"
                value={selectedClassId}
                onChange={(e) => setSelectedClassId(e.target.value)}
                disabled={!selectedSchoolId || classes.length === 0}
              >
                <option value="">Sans classe (à affecter plus tard)</option>
                {classes.map((c: any) => (
                  <option key={c.id} value={c.id}>
                    {c.name} {c.academic_year ? `(${c.academic_year})` : ''}
                  </option>
                ))}
              </select>
            )}
          </div>
          <div className="flex justify-end gap-3 pt-2">
            <button type="button" onClick={onClose} className="btn btn-secondary">
              Annuler
            </button>
            <button
              type="submit"
              disabled={submitting}
              className="btn btn-primary"
            >
              {submitting ? 'Transfert...' : 'Confirmer le transfert'}
            </button>
          </div>
        </form>
      </div>
    </div>
  )
}
