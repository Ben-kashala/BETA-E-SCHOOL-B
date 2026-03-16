import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import api from '@/services/api'
import { Card } from '@/components/ui/Card'
import { Download } from 'lucide-react'
import toast from 'react-hot-toast'

async function downloadOfficialBulletin(
  studentId: number,
  academicYear: string,
  studentName: string
) {
  try {
    // 1) Récupérer le bulletin officiel (ReportCard AN publié) pour l'élève et l'année
    const rcRes = await api.get('/academics/report-cards/', {
      params: {
        student: studentId,
        academic_year: academicYear,
        term: 'AN',
        is_published: true,
      },
    })

    const results = Array.isArray(rcRes.data) ? rcRes.data : rcRes.data?.results || []
    if (!results.length) {
      toast.error("Aucun bulletin officiel trouvé pour cette année.")
      return
    }

    const reportCard = results[0]

    // 2) Télécharger le PDF officiel du bulletin
    const pdfRes = await api.get(`/academics/report-cards/${reportCard.id}/download_pdf/`, {
      responseType: 'blob',
    })

    const url = window.URL.createObjectURL(new Blob([pdfRes.data]))
    const a = document.createElement('a')
    a.href = url
    a.setAttribute('download', `bulletin_officiel_${studentName.replace(/\s+/g, '-')}_${academicYear.replace('/', '-')}.pdf`)
    document.body.appendChild(a)
    a.click()
    window.URL.revokeObjectURL(url)
    a.remove()
    toast.success('Bulletin officiel téléchargé.')
  } catch (err: unknown) {
    const msg =
      err && typeof err === 'object' && 'response' in err && (err as { response?: { data?: unknown } }).response?.data
    toast.error(msg ? String(msg) : 'Impossible de télécharger le bulletin officiel.')
  }
}

export default function ParentGrades() {
  const [selectedStudent, setSelectedStudent] = useState<number | null>(null)

  const { data: children } = useQuery({
    queryKey: ['parent-children'],
    queryFn: async () => {
      const response = await api.get('/auth/students/parent_dashboard/')
      return response.data
    },
  })

  const { data: grades, isLoading, error } = useQuery({
    queryKey: ['parent-grades', selectedStudent],
    queryFn: async () => {
      try {
        const params: Record<string, string> = {}
        if (selectedStudent) {
          params['student'] = selectedStudent.toString()
        }
        const response = await api.get('/academics/grades/', { params })
        console.log('Grades response:', response.data)
        return response.data
      } catch (error: any) {
        console.error('Erreur lors du chargement des notes:', error)
        console.error('Response:', error?.response?.data)
        throw error
      }
    },
    retry: 1,
  })

  return (
    <div>
      <h1 className="text-3xl font-bold text-gray-900 dark:text-gray-100 mb-6">Notes de mes enfants</h1>

      {children && children.length > 0 && (
        <Card className="mb-6">
          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
            Filtrer par enfant
          </label>
          <select
            value={selectedStudent || ''}
            onChange={(e) => setSelectedStudent(e.target.value ? parseInt(e.target.value) : null)}
            className="input max-w-xs"
          >
            <option value="">Tous les enfants</option>
            {children.map((child: any) => (
              <option key={child.identity.id} value={child.identity.id}>
                {[child.identity.user?.first_name, child.identity.user?.last_name, child.identity.user?.middle_name].filter(Boolean).join(' ')} - {child.identity.student_id}
              </option>
            ))}
          </select>
        </Card>
      )}

      {/* Téléchargement des bulletins (officiels) */}
      {children && children.length > 0 && (
        <Card className="mb-6 p-6">
          <h2 className="text-lg font-semibold text-gray-900 dark:text-gray-100 mb-4">
            Télécharger les bulletins officiels
          </h2>
          <div className="space-y-4">
            {children.map((child: any) => {
              const name = [child.identity.user?.first_name, child.identity.user?.last_name].filter(Boolean).join(' ') || child.identity.student_id
              const options = child.bulletin_downloads || []
              if (options.length === 0) {
                return (
                  <p key={child.identity.id} className="text-sm text-gray-500 dark:text-gray-400">
                    {name} — Aucun bulletin disponible pour le moment.
                  </p>
                )
              }
              return (
                <div key={child.identity.id} className="flex flex-wrap items-center gap-2">
                  <span className="text-sm font-medium text-gray-700 dark:text-gray-300">{name} :</span>
                  {options.map((opt: { school_class: number; school_class_name: string; academic_year: string }) => (
                    <button
                      key={`${opt.school_class}-${opt.academic_year}`}
                      type="button"
                      onClick={() => downloadOfficialBulletin(child.identity.id, opt.academic_year, name)}
                      className="inline-flex items-center gap-2 px-3 py-1.5 rounded-lg bg-primary-600 hover:bg-primary-700 text-white text-sm font-medium transition-colors"
                    >
                      <Download className="w-4 h-4" />
                      Bulletin officiel {opt.academic_year}
                    </button>
                  ))}
                </div>
              )
            })}
          </div>
        </Card>
      )}

      <Card>
        <div className="overflow-x-auto">
          <table className="w-full">
            <thead className="bg-gray-50 dark:bg-gray-700/50">
              <tr>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase">Élève</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase">Matière</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase">Trimestre</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase">Note</th>
              </tr>
            </thead>
            <tbody className="bg-white dark:bg-gray-800 divide-y divide-gray-200 dark:divide-gray-700">
              {isLoading ? (
                <tr>
                  <td colSpan={4} className="px-6 py-4 text-center text-gray-600 dark:text-gray-400">Chargement...</td>
                </tr>
              ) : error ? (
                <tr>
                  <td colSpan={4} className="px-6 py-4 text-center text-red-600 dark:text-red-400">
                    Erreur lors du chargement des notes. Veuillez réessayer plus tard.
                  </td>
                </tr>
              ) : (() => {
                const items = Array.isArray(grades) ? grades : grades?.results || []
                if (!items.length) {
                  return (
                    <tr>
                      <td colSpan={4} className="px-6 py-4 text-center text-gray-600 dark:text-gray-400">
                        <div className="flex flex-col items-center space-y-2">
                          <p>Aucune note disponible pour le moment.</p>
                          {selectedStudent && (
                            <p className="text-xs text-gray-500 dark:text-gray-500">
                              Aucune note trouvée pour cet enfant.
                            </p>
                          )}
                          {!selectedStudent && children && children.length > 0 && (
                            <p className="text-xs text-gray-500 dark:text-gray-500">
                              Essayez de sélectionner un enfant spécifique dans le filtre ci-dessus.
                            </p>
                          )}
                        </div>
                      </td>
                    </tr>
                  )
                }
                return items.map((grade: any) => (
                  <tr key={grade.id} className="hover:bg-gray-50 dark:hover:bg-gray-700/50">
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900 dark:text-gray-100">
                      {grade.student_name || 'N/A'}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900 dark:text-gray-100">
                      {grade.subject_name || 'N/A'}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900 dark:text-gray-100">
                      {grade.term === 'T1'
                        ? 'Trimestre 1'
                        : grade.term === 'T2'
                        ? 'Trimestre 2'
                        : grade.term === 'T3'
                        ? 'Trimestre 3'
                        : grade.term}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900 dark:text-gray-100">
                      {grade.total_score ? `${grade.total_score}/20` : 'N/A'}
                    </td>
                  </tr>
                ))
              })()}
            </tbody>
          </table>
        </div>
      </Card>
    </div>
  )
}
