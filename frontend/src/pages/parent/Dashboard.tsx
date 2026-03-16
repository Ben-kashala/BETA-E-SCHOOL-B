import { useQuery } from '@tanstack/react-query'
import api from '@/services/api'
import { Card } from '@/components/ui/Card'
import { FileText, Calendar, CreditCard, BookOpen, User, BookMarked, GraduationCap, CheckCircle, XCircle } from 'lucide-react'
import { Link } from 'react-router-dom'

interface ChildData {
  identity: {
    id: number
    student_id: string
    user: { first_name: string; last_name: string }
    class_name: string
    titulaire_name: string | null
    school_class_academic_year: string | null
    academic_year?: string
  }
  average_score: number | null
  attendance_by_week: Array<{
    week_start: string
    week_end: string
    label: string
    present: number
    absent: number
    late: number
    excused: number
    total: number
  }>
}



export default function ParentDashboard() {
  const { data: dashboardData, isLoading } = useQuery({
    queryKey: ['parent-dashboard'],
    queryFn: async () => {
      const response = await api.get<ChildData[]>('/auth/students/parent_dashboard/')
      return response.data
    },
  })

  if (isLoading) {
    return (
      <div className="flex items-center justify-center min-h-[200px]">
        <p className="text-gray-500 dark:text-gray-400">Chargement…</p>
      </div>
    )
  }

  const children = Array.isArray(dashboardData) ? dashboardData : []

  return (
    <div>
      <h1 className="text-3xl font-bold text-gray-900 dark:text-gray-100 mb-6">Tableau de bord Parent</h1>

      {children.length > 0 ? (
        <div className="space-y-6">
          {children.map(({ identity, average_score, attendance_by_week }: ChildData) => (
            <Card key={identity.id} className="p-6">
              <h2 className="text-xl font-semibold mb-4 flex items-center gap-2 text-gray-900 dark:text-gray-100">
                <User className="w-5 h-5" />
                {identity.user?.first_name} {identity.user?.last_name}
              </h2>
              <p className="text-sm text-gray-600 dark:text-gray-400 mb-4">{identity.student_id}</p>

              {/* Infos classe, année, titulaire, moyenne */}
              <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
                <div className="flex items-center gap-2 p-3 bg-gray-50 dark:bg-gray-700/60 rounded-lg">
                  <BookMarked className="w-5 h-5 text-blue-600 dark:text-blue-400" />
                  <div>
                    <p className="text-xs text-gray-600 dark:text-gray-400">Classe</p>
                    <p className="font-medium text-gray-900 dark:text-gray-100">{identity.class_name || '—'}</p>
                  </div>
                </div>
                <div className="flex items-center gap-2 p-3 bg-gray-50 dark:bg-gray-700/60 rounded-lg">
                  <Calendar className="w-5 h-5 text-amber-600 dark:text-amber-400" />
                  <div>
                    <p className="text-xs text-gray-600 dark:text-gray-400">Année académique</p>
                    <p className="font-medium text-gray-900 dark:text-gray-100">{identity.school_class_academic_year || identity.academic_year || '—'}</p>
                  </div>
                </div>
                <div className="flex items-center gap-2 p-3 bg-gray-50 dark:bg-gray-700/60 rounded-lg">
                  <GraduationCap className="w-5 h-5 text-green-600 dark:text-green-400" />
                  <div>
                    <p className="text-xs text-gray-600 dark:text-gray-400">Enseignant titulaire</p>
                    <p className="font-medium text-gray-900 dark:text-gray-100">{identity.titulaire_name || '—'}</p>
                  </div>
                </div>
                <div className="flex items-center gap-2 p-3 bg-gray-50 dark:bg-gray-700/60 rounded-lg">
                  <FileText className="w-5 h-5 text-purple-600 dark:text-purple-400" />
                  <div>
                    <p className="text-xs text-gray-600 dark:text-gray-400">Moyenne générale</p>
                    <p className="font-medium text-gray-900 dark:text-gray-100">{average_score != null ? average_score.toFixed(2) : '—'}</p>
                  </div>
                </div>
              </div>

              {/* Présences et absences par semaine */}
              <div>
                <h3 className="text-sm font-semibold text-gray-900 dark:text-gray-100 mb-3">Présences et absences par semaine</h3>
                <div className="flex flex-wrap gap-3">
                  {attendance_by_week.map((week) => (
                    <div
                      key={week.week_start}
                      className="flex items-center gap-2 px-4 py-2 rounded-lg border border-gray-200 dark:border-gray-600 bg-white dark:bg-gray-700/60"
                    >
                      <span className="text-sm font-medium text-gray-900 dark:text-gray-100 whitespace-nowrap">{week.label}</span>
                      <span className="flex items-center gap-1 text-green-600 dark:text-green-400 text-sm font-medium">
                        <CheckCircle className="w-4 h-4" />
                        {week.present}
                      </span>
                      <span className="flex items-center gap-1 text-red-600 dark:text-red-400 text-sm font-medium">
                        <XCircle className="w-4 h-4" />
                        {week.absent}
                      </span>
                      {week.late > 0 && (
                        <span className="text-amber-600 dark:text-amber-400 text-sm font-medium">Retard: {week.late}</span>
                      )}
                    </div>
                  ))}
                </div>
              </div>
            </Card>
          ))}
        </div>
      ) : (
        <p className="text-gray-500 dark:text-gray-400">Aucun enfant enregistré.</p>
      )}

      {/* Cartes d'accès rapide */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6 mt-8">
        <Link to="/parent/grades">
          <Card className="p-6 text-center hover:shadow-md transition-shadow">
            <FileText className="w-8 h-8 text-primary-600 dark:text-primary-400 mx-auto mb-2" />
            <p className="text-sm text-gray-600 dark:text-gray-300">Notes</p>
          </Card>
        </Link>
        <Link to="/parent/meetings">
          <Card className="p-6 text-center hover:shadow-md transition-shadow">
            <Calendar className="w-8 h-8 text-primary-600 dark:text-primary-400 mx-auto mb-2" />
            <p className="text-sm text-gray-600 dark:text-gray-300">Réunions</p>
          </Card>
        </Link>
        <Link to="/parent/payments">
          <Card className="p-6 text-center hover:shadow-md transition-shadow">
            <CreditCard className="w-8 h-8 text-primary-600 dark:text-primary-400 mx-auto mb-2" />
            <p className="text-sm text-gray-600 dark:text-gray-300">Paiements</p>
          </Card>
        </Link>
        <Link to="/parent/library">
          <Card className="p-6 text-center hover:shadow-md transition-shadow">
            <BookOpen className="w-8 h-8 text-primary-600 dark:text-primary-400 mx-auto mb-2" />
            <p className="text-sm text-gray-600 dark:text-gray-300">Bibliothèque</p>
          </Card>
        </Link>
      </div>
    </div>
  )
}
