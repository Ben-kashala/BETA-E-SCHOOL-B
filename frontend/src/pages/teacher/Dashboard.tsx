import { useQuery } from '@tanstack/react-query'
import { Card } from '@/components/ui/Card'
import {
  BookOpen,
  Users,
  FileText,
  Calendar,
  GraduationCap,
  Gavel,
  ClipboardList,
  Video,
} from 'lucide-react'
import api from '@/services/api'
import { Link } from 'react-router-dom'

function getCount(data: unknown): number {
  if (data == null) return 0
  if (typeof data === 'object' && 'count' in data && typeof (data as { count: number }).count === 'number') {
    return (data as { count: number }).count
  }
  if (Array.isArray(data)) return data.length
  if (typeof data === 'object' && 'results' in data && Array.isArray((data as { results: unknown[] }).results)) {
    return (data as { results: unknown[] }).results.length
  }
  return 0
}

export default function TeacherDashboard() {
  const { data: stats, isLoading, error } = useQuery({
    queryKey: ['teacher-dashboard-stats'],
    queryFn: async () => {
      const today = new Date().toISOString().slice(0, 10)

      const [
        classesRes,
        studentsRes,
        assignmentsRes,
        meetingsRes,
        meetingsUpcomingRes,
        coursesRes,
        quizzesRes,
        disciplineRes,
        attendanceRes,
      ] = await Promise.allSettled([
        api.get('/schools/classes/'),
        api.get('/accounts/students/', { params: { page_size: 1 } }),
        api.get('/elearning/assignments/', { params: { page_size: 1 } }),
        api.get('/meetings/', { params: { page_size: 1 } }),
        api.get('/meetings/', { params: { page_size: 1, meeting_date__gte: today, status: 'SCHEDULED' } }),
        api.get('/elearning/courses/', { params: { page_size: 1 } }),
        api.get('/elearning/quizzes/', { params: { page_size: 1 } }),
        api.get('/academics/discipline/', { params: { page_size: 1, status: 'OPEN' } }),
        api.get('/academics/attendance/', { params: { page_size: 1, date: today } }),
      ])

      return {
        classes: getCount(classesRes.status === 'fulfilled' ? classesRes.value.data : null),
        students: getCount(studentsRes.status === 'fulfilled' ? studentsRes.value.data : null),
        assignments: getCount(assignmentsRes.status === 'fulfilled' ? assignmentsRes.value.data : null),
        meetings: getCount(meetingsRes.status === 'fulfilled' ? meetingsRes.value.data : null),
        meetingsUpcoming: getCount(meetingsUpcomingRes.status === 'fulfilled' ? meetingsUpcomingRes.value.data : null),
        courses: getCount(coursesRes.status === 'fulfilled' ? coursesRes.value.data : null),
        quizzes: getCount(quizzesRes.status === 'fulfilled' ? quizzesRes.value.data : null),
        disciplineOpen: getCount(disciplineRes.status === 'fulfilled' ? disciplineRes.value.data : null),
        attendanceToday: getCount(attendanceRes.status === 'fulfilled' ? attendanceRes.value.data : null),
      }
    },
  })

  const mainCards = [
    {
      title: 'Classes',
      value: stats?.classes,
      icon: BookOpen,
      color: 'bg-blue-500',
      link: '/teacher/classes',
    },
    {
      title: 'Élèves',
      value: stats?.students,
      icon: Users,
      color: 'bg-green-500',
      link: '/teacher/students',
    },
    {
      title: 'Devoirs',
      value: stats?.assignments,
      icon: FileText,
      color: 'bg-yellow-500',
      link: '/teacher/assignments',
    },
    {
      title: 'Réunions',
      value: stats?.meetingsUpcoming ?? stats?.meetings,
      subtitle: stats?.meetings != null && stats.meetings > 0 ? `${stats.meetings} au total` : undefined,
      icon: Calendar,
      color: 'bg-purple-500',
      link: '/teacher/meetings',
    },
  ]

  const secondaryCards = [
    {
      title: 'Cours',
      value: stats?.courses,
      icon: Video,
      color: 'bg-indigo-500',
      link: '/teacher/courses',
    },
    {
      title: 'Interrogations & Examens',
      value: stats?.quizzes,
      icon: GraduationCap,
      color: 'bg-amber-500',
      link: '/teacher/quizzes',
    },
    {
      title: 'Fiches de discipline (ouvertes)',
      value: stats?.disciplineOpen,
      icon: Gavel,
      color: 'bg-rose-500',
      link: '/teacher/discipline',
    },
    {
      title: 'Présences aujourd\'hui',
      value: stats?.attendanceToday,
      icon: ClipboardList,
      color: 'bg-teal-500',
      link: '/teacher/attendance',
    },
  ]

  return (
    <div>
      <h1 className="text-3xl font-bold text-gray-900 dark:text-white mb-2">Tableau de bord Enseignant</h1>
      <p className="text-gray-600 dark:text-gray-400 mb-6">
        Données en temps réel de vos classes, élèves et activités.
      </p>

      {error && (
        <div className="mb-4 p-4 rounded-lg bg-red-50 dark:bg-red-900/20 text-red-700 dark:text-red-300 text-sm">
          Impossible de charger certaines données. Vérifiez votre connexion.
        </div>
      )}

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6 mb-8">
        {mainCards.map((stat) => {
          const Icon = stat.icon
          return (
            <Link key={stat.title} to={stat.link}>
              <Card className="p-6 hover:shadow-md transition-shadow cursor-pointer h-full">
                <div className="flex items-center justify-between">
                  <div>
                    <p className="text-sm text-gray-600 dark:text-gray-400 mb-1">{stat.title}</p>
                    <p className="text-3xl font-bold text-gray-900 dark:text-white">
                      {isLoading ? '...' : stat.value ?? '—'}
                    </p>
                    {stat.subtitle && (
                      <p className="text-xs text-gray-500 dark:text-gray-500 mt-1">{stat.subtitle}</p>
                    )}
                  </div>
                  <div className={`${stat.color} p-3 rounded-lg`}>
                    <Icon className="w-6 h-6 text-white" />
                  </div>
                </div>
              </Card>
            </Link>
          )
        })}
      </div>

      <h2 className="text-xl font-semibold text-gray-900 dark:text-white mb-4">Autres indicateurs</h2>
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
        {secondaryCards.map((stat) => {
          const Icon = stat.icon
          return (
            <Link key={stat.title} to={stat.link}>
              <Card className="p-5 hover:shadow-md transition-shadow cursor-pointer h-full">
                <div className="flex items-center justify-between">
                  <div className="min-w-0">
                    <p className="text-sm text-gray-600 dark:text-gray-400 mb-1 truncate" title={stat.title}>
                      {stat.title}
                    </p>
                    <p className="text-2xl font-bold text-gray-900 dark:text-white">
                      {isLoading ? '...' : stat.value ?? '—'}
                    </p>
                  </div>
                  <div className={`${stat.color} p-2.5 rounded-lg flex-shrink-0`}>
                    <Icon className="w-5 h-5 text-white" />
                  </div>
                </div>
              </Card>
            </Link>
          )
        })}
      </div>
    </div>
  )
}
