import { NavLink } from 'react-router-dom'
import { User } from '@/types'
import { 
  LayoutDashboard, 
  Users, 
  BookOpen, 
  GraduationCap,
  CreditCard,
  BarChart3,
  FileText,
  Calendar,
  MessageSquare,
  Library,
  Home,
  UserCheck,
  AlertCircle,
  Wallet,
  X,
  Building2,
} from 'lucide-react'
import { cn } from '@/utils/cn'

interface SidebarProps {
  user: User
  currentPath: string
  isOpen?: boolean
  onClose?: () => void
}

const adminMenu = [
  { path: '/admin', label: 'Tableau de bord', icon: LayoutDashboard },
  { path: '/admin/enrollments', label: 'Inscriptions', icon: Users },
  { path: '/admin/students', label: 'Élèves', icon: Users },
  { path: '/admin/classes', label: 'Classes', icon: GraduationCap },
  { path: '/admin/former-students', label: 'Anciens élèves', icon: GraduationCap },
  { path: '/admin/teachers', label: 'Enseignants', icon: Users },
  { path: '/admin/payments', label: 'Paiements', icon: CreditCard },
  { path: '/admin/expenses', label: 'Dépenses', icon: BarChart3 },
  { path: '/admin/caisse', label: 'Caisse', icon: Wallet },
  { path: '/admin/meetings', label: 'Réunions', icon: Calendar },
  { path: '/admin/library', label: 'Bibliothèque', icon: Library },
  { path: '/admin/elearning', label: 'E-learning', icon: BookOpen },
  { path: '/admin/tutoring', label: 'Encadrement', icon: MessageSquare },
  { path: '/admin/discipline', label: 'Fiches de discipline', icon: AlertCircle },
  { path: '/admin/communication', label: 'Communication', icon: MessageSquare },
]

const teacherMenu = [
  { path: '/teacher', label: 'Tableau de bord', icon: LayoutDashboard },
  { path: '/teacher/students', label: 'Élèves', icon: Users },
  { path: '/teacher/my-class', label: 'Ma classe', icon: UserCheck },
  { path: '/teacher/classes', label: 'Classes', icon: GraduationCap },
  { path: '/teacher/class-subjects', label: 'Matières par classe', icon: BookOpen },
  { path: '/teacher/grades', label: 'Notes', icon: FileText },
  { path: '/teacher/attendance', label: 'Présences', icon: Users },
  { path: '/teacher/assignments', label: 'Devoirs', icon: BookOpen },
  { path: '/teacher/quizzes', label: 'Interrogations & Examens', icon: GraduationCap },
  { path: '/teacher/courses', label: 'Cours', icon: BookOpen },
  { path: '/teacher/elearning', label: 'E-learning', icon: BookOpen },
  { path: '/teacher/library', label: 'Bibliothèque', icon: Library },
  { path: '/teacher/meetings', label: 'Réunions', icon: Calendar },
  { path: '/teacher/discipline', label: 'Fiches de discipline', icon: AlertCircle },
  { path: '/teacher/tutoring', label: 'Encadrement', icon: MessageSquare },
  { path: '/teacher/communication', label: 'Communication', icon: MessageSquare },
]

const parentMenu = [
  { path: '/parent', label: 'Tableau de bord', icon: LayoutDashboard },
  { path: '/parent/enrollments', label: 'Inscriptions', icon: Users },
  { path: '/parent/grades', label: 'Notes', icon: FileText },
  { path: '/parent/meetings', label: 'Réunions', icon: Calendar },
  { path: '/parent/payments', label: 'Paiements', icon: CreditCard },
  { path: '/parent/library', label: 'Bibliothèque', icon: Library },
  { path: '/parent/tutoring', label: 'Encadrement', icon: Home },
  { path: '/parent/discipline', label: 'Fiches de discipline', icon: AlertCircle },
  { path: '/parent/communication', label: 'Communication', icon: MessageSquare },
]

const studentMenu = [
  { path: '/student', label: 'Tableau de bord', icon: LayoutDashboard },
  { path: '/student/courses', label: 'Cours', icon: BookOpen },
  { path: '/student/assignments', label: 'Devoirs', icon: FileText },
  { path: '/student/exams', label: 'Examens', icon: GraduationCap },
  { path: '/student/library', label: 'Bibliothèque', icon: Library },
  { path: '/student/grades', label: 'Notes', icon: FileText },
  { path: '/student/discipline', label: 'Fiches de discipline', icon: AlertCircle },
  { path: '/student/communication', label: 'Communication', icon: MessageSquare },
]

const accountantMenu = [
  { path: '/accountant', label: 'Tableau de bord', icon: LayoutDashboard },
  { path: '/accountant/enrollments', label: 'Inscriptions', icon: Users },
  { path: '/accountant/payments', label: 'Paiements', icon: CreditCard },
  { path: '/accountant/expenses', label: 'Dépenses', icon: BarChart3 },
  { path: '/accountant/caisse', label: 'Caisse', icon: Wallet },
]

const disciplineOfficerMenu = [
  { path: '/discipline-officer', label: 'Tableau de bord', icon: LayoutDashboard },
  { path: '/discipline-officer/discipline', label: 'Fiches de discipline', icon: AlertCircle },
  { path: '/discipline-officer/meetings', label: 'Réunions', icon: Calendar },
  { path: '/discipline-officer/communication', label: 'Communication', icon: MessageSquare },
]

const promoterMenu = [
  { path: '/promoter', label: 'Tableau de bord', icon: LayoutDashboard },
  { path: '/promoter/schools', label: 'Mes écoles', icon: Building2 },
  { path: '/promoter/finances', label: 'Finances', icon: CreditCard },
  { path: '/promoter/communication', label: 'Communication', icon: MessageSquare },
  { path: '/promoter/meetings', label: 'Réunions', icon: Calendar },
]

export default function Sidebar({ user, currentPath, isOpen = false, onClose }: SidebarProps) {
  const getMenu = () => {
    switch (user.role) {
      case 'ADMIN':
        return adminMenu
      case 'TEACHER':
        return teacherMenu
      case 'PARENT':
        return parentMenu
      case 'STUDENT':
        return studentMenu
      case 'ACCOUNTANT':
        return accountantMenu
      case 'DISCIPLINE_OFFICER':
        return disciplineOfficerMenu
      case 'PROMOTER':
        return promoterMenu
      default:
        return []
    }
  }

  const menu = getMenu()

  return (
    <>
      {/* Sidebar pour desktop : fond #21335c, texte blanc */}
      <aside className="hidden lg:flex lg:w-64 bg-eschool-body border-r border-eschool-body-text/20 min-h-[calc(100vh-73px)] transition-colors flex-shrink-0">
        <nav className="p-4 space-y-2 w-full">
          {menu.map((item) => {
            const Icon = item.icon
            const isActive = currentPath === item.path || currentPath.startsWith(item.path + '/')
            return (
              <NavLink
                key={item.path}
                to={item.path}
                className={cn(
                  'flex items-center space-x-3 px-4 py-3 rounded-lg transition-colors text-eschool-body-text',
                  isActive
                    ? 'bg-eschool-body-text/15 text-eschool-body-text font-medium'
                    : 'text-eschool-body-text/90 hover:bg-eschool-body-text/10'
                )}
              >
                <Icon className="w-5 h-5 flex-shrink-0" />
                <span className="truncate">{item.label}</span>
              </NavLink>
            )
          })}
        </nav>
      </aside>

      {/* Sidebar pour mobile - overlay : même couleurs */}
      <aside
        className={cn(
          'fixed top-[65px] sm:top-[73px] left-0 h-[calc(100vh-65px)] sm:h-[calc(100vh-73px)] w-64 bg-eschool-body border-r border-eschool-body-text/20 z-50 transition-transform duration-300 ease-in-out lg:hidden overflow-y-auto',
          isOpen ? 'translate-x-0' : '-translate-x-full'
        )}
      >
        <div className="p-4 border-b border-eschool-body-text/20 flex items-center justify-between">
          <h2 className="text-lg font-semibold text-eschool-body-text">Menu</h2>
          {onClose && (
            <button
              onClick={onClose}
              className="p-2 text-eschool-body-text hover:bg-eschool-body-text/10 rounded-lg transition-colors"
              aria-label="Fermer le menu"
            >
              <X className="w-5 h-5" />
            </button>
          )}
        </div>
        <nav className="p-4 space-y-2">
          {menu.map((item) => {
            const Icon = item.icon
            const isActive = currentPath === item.path || currentPath.startsWith(item.path + '/')
            return (
              <NavLink
                key={item.path}
                to={item.path}
                onClick={onClose}
                className={cn(
                  'flex items-center space-x-3 px-4 py-3 rounded-lg transition-colors text-eschool-body-text',
                  isActive
                    ? 'bg-eschool-body-text/15 text-eschool-body-text font-medium'
                    : 'text-eschool-body-text/90 hover:bg-eschool-body-text/10'
                )}
              >
                <Icon className="w-5 h-5 flex-shrink-0" />
                <span className="truncate">{item.label}</span>
              </NavLink>
            )
          })}
        </nav>
      </aside>
    </>
  )
}
