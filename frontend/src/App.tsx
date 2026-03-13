import { useEffect } from 'react'
import { Routes, Route, Navigate } from 'react-router-dom'
import { useAuthStore } from './store/authStore'
import { ProtectedRoute } from './components/auth/ProtectedRoute'
import { RoleRoute } from './components/auth/RoleRoute'

// Auth pages
import LoginPage from './pages/auth/LoginPage'

// Admin pages
import AdminDashboard from './pages/admin/Dashboard'
import AdminEnrollments from './pages/admin/Enrollments'
import AdminClasses from './pages/admin/Classes'
import AdminTeachers from './pages/admin/Teachers'
import AdminPayments from './pages/admin/Payments'
import AdminMeetings from './pages/admin/Meetings'
import AdminLibrary from './pages/admin/Library'
import AdminElearning from './pages/admin/Elearning'
import AdminTutoring from './pages/admin/Tutoring'
import AdminFormerStudents from './pages/admin/FormerStudents'
import AdminDiscipline from './pages/admin/Discipline'
import AdminCommunication from './pages/admin/Communication'
import StudentsPage from './pages/StudentsPage'

// Teacher pages
import TeacherDashboard from './pages/teacher/Dashboard'
import TeacherClasses from './pages/teacher/Classes'
import TeacherGrades from './pages/teacher/Grades'
import TeacherAttendance from './pages/teacher/Attendance'
import TeacherAssignments from './pages/teacher/Assignments'
import TeacherQuizzes from './pages/teacher/Quizzes'
import TeacherCourses from './pages/teacher/Courses'
import TeacherElearning from './pages/teacher/Elearning'
import TeacherLibrary from './pages/teacher/Library'
import TeacherMeetings from './pages/teacher/Meetings'
import TeacherClassSubjects from './pages/teacher/ClassSubjects'
import TeacherMyClass from './pages/teacher/MyClass'
import TeacherDiscipline from './pages/teacher/Discipline'
import TeacherTutoring from './pages/teacher/Tutoring'
import TeacherCommunication from './pages/teacher/Communication'

// Parent pages
import ParentDashboard from './pages/parent/Dashboard'
import ParentGrades from './pages/parent/Grades'
import ParentMeetings from './pages/parent/Meetings'
import ParentPayments from './pages/parent/Payments'
import ParentLibrary from './pages/parent/Library'
import ParentTutoring from './pages/parent/Tutoring'
import ParentDiscipline from './pages/parent/Discipline'
import ParentCommunication from './pages/parent/Communication'
import ParentEnrollments from './pages/parent/Enrollments'

// Student pages
import StudentDashboard from './pages/student/Dashboard'
import StudentCourses from './pages/student/Courses'
import StudentAssignments from './pages/student/Assignments'
import StudentExams from './pages/student/Exams'
import StudentDiscipline from './pages/student/Discipline'
import StudentLibrary from './pages/student/Library'
import StudentGrades from './pages/student/Grades'
import StudentCommunication from './pages/student/Communication'

// Accountant pages
import AccountantDashboard from './pages/accountant/Dashboard'
import AccountantPayments from './pages/accountant/Payments'
import AccountantExpenses from './pages/accountant/Expenses'
import AccountantCaisse from './pages/accountant/Caisse'

// Promoter pages
import PromoterDashboard from './pages/promoter/Dashboard'
import PromoterSchools from './pages/promoter/Schools'

// Discipline officer pages
import DisciplineOfficerDashboard from './pages/discipline-officer/Dashboard'
import DisciplineOfficerDiscipline from './pages/discipline-officer/Discipline'
import DisciplineOfficerMeetings from './pages/discipline-officer/Meetings'
import DisciplineOfficerCommunication from './pages/discipline-officer/Communication'

// Shared pages
import BookReader from './pages/shared/BookReader'
import PaymentReturnPage from './pages/payments/PaymentReturnPage'

// Layout
import Layout from './components/layout/Layout'

function App() {
  const { checkAuth, isAuthenticated } = useAuthStore()

  useEffect(() => {
    // Vérifier l'authentification seulement une fois au chargement
    // Utiliser un flag pour éviter les appels multiples
    let mounted = true
    const token = localStorage.getItem('access_token')
    if (token && mounted) {
      checkAuth()
    }
    return () => {
      mounted = false
    }
  }, []) // Dépendances vides pour n'exécuter qu'une fois

  return (
    <Routes>
      <Route path="/login" element={<LoginPage />} />
      
      {/* Shared Routes - Accessible to all authenticated users, without Layout */}
      <Route 
        path="/book/:bookId/read" 
        element={<ProtectedRoute><BookReader /></ProtectedRoute>} 
      />
      
      <Route element={<ProtectedRoute><Layout /></ProtectedRoute>}>
        <Route path="payments/return" element={<PaymentReturnPage />} />
        {/* Admin Routes */}
        <Route path="/admin" element={<RoleRoute allowedRoles={['ADMIN']} />}>
          <Route index element={<AdminDashboard />} />
          <Route path="enrollments" element={<AdminEnrollments />} />
          <Route path="students" element={<StudentsPage />} />
          <Route path="classes" element={<AdminClasses />} />
          <Route path="teachers" element={<AdminTeachers />} />
          <Route path="payments" element={<AdminPayments />} />
          <Route path="expenses" element={<AccountantExpenses />} />
          <Route path="caisse" element={<AccountantCaisse />} />
          <Route path="meetings" element={<AdminMeetings />} />
          <Route path="library" element={<AdminLibrary />} />
          <Route path="elearning" element={<AdminElearning />} />
          <Route path="tutoring" element={<AdminTutoring />} />
          <Route path="discipline" element={<AdminDiscipline />} />
          <Route path="former-students" element={<AdminFormerStudents />} />
          <Route path="communication" element={<AdminCommunication />} />
        </Route>

        {/* Teacher Routes */}
        <Route path="/teacher" element={<RoleRoute allowedRoles={['TEACHER']} />}>
          <Route index element={<TeacherDashboard />} />
          <Route path="students" element={<StudentsPage />} />
          <Route path="classes" element={<TeacherClasses />} />
          <Route path="class-subjects" element={<TeacherClassSubjects />} />
          <Route path="my-class" element={<TeacherMyClass />} />
          <Route path="grades" element={<TeacherGrades />} />
          <Route path="attendance" element={<TeacherAttendance />} />
          <Route path="assignments" element={<TeacherAssignments />} />
          <Route path="quizzes" element={<TeacherQuizzes />} />
          <Route path="courses" element={<TeacherCourses />} />
          <Route path="elearning" element={<TeacherElearning />} />
          <Route path="library" element={<TeacherLibrary />} />
          <Route path="meetings" element={<TeacherMeetings />} />
          <Route path="discipline" element={<TeacherDiscipline />} />
          <Route path="tutoring" element={<TeacherTutoring />} />
          <Route path="communication" element={<TeacherCommunication />} />
        </Route>

        {/* Parent Routes */}
        <Route path="/parent" element={<RoleRoute allowedRoles={['PARENT']} />}>
          <Route index element={<ParentDashboard />} />
          <Route path="enrollments" element={<ParentEnrollments />} />
          <Route path="grades" element={<ParentGrades />} />
          <Route path="meetings" element={<ParentMeetings />} />
          <Route path="payments" element={<ParentPayments />} />
          <Route path="library" element={<ParentLibrary />} />
          <Route path="tutoring" element={<ParentTutoring />} />
          <Route path="discipline" element={<ParentDiscipline />} />
          <Route path="communication" element={<ParentCommunication />} />
        </Route>

        {/* Student Routes */}
        <Route path="/student" element={<RoleRoute allowedRoles={['STUDENT']} />}>
          <Route index element={<StudentDashboard />} />
          <Route path="courses" element={<StudentCourses />} />
          <Route path="assignments" element={<StudentAssignments />} />
          <Route path="exams" element={<StudentExams />} />
          <Route path="library" element={<StudentLibrary />} />
          <Route path="grades" element={<StudentGrades />} />
          <Route path="discipline" element={<StudentDiscipline />} />
          <Route path="communication" element={<StudentCommunication />} />
        </Route>

        {/* Accountant Routes */}
        <Route path="/accountant" element={<RoleRoute allowedRoles={['ACCOUNTANT']} />}>
          <Route index element={<AccountantDashboard />} />
          <Route path="enrollments" element={<AdminEnrollments />} />
          <Route path="payments" element={<AccountantPayments />} />
          <Route path="expenses" element={<AccountantExpenses />} />
          <Route path="caisse" element={<AccountantCaisse />} />
        </Route>

        {/* Discipline Officer Routes */}
        <Route path="/discipline-officer" element={<RoleRoute allowedRoles={['DISCIPLINE_OFFICER']} />}>
          <Route index element={<DisciplineOfficerDashboard />} />
          <Route path="discipline" element={<DisciplineOfficerDiscipline />} />
          <Route path="meetings" element={<DisciplineOfficerMeetings />} />
          <Route path="communication" element={<DisciplineOfficerCommunication />} />
        </Route>

        {/* Promoter Routes */}
        <Route path="/promoter" element={<RoleRoute allowedRoles={['PROMOTER']} />}>
          <Route index element={<PromoterDashboard />} />
          <Route path="schools" element={<PromoterSchools />} />
        </Route>

        {/* Redirect based on role */}
        <Route path="/" element={
          isAuthenticated ? (
            <Navigate to={
              (() => {
                const user = useAuthStore.getState().user
                const roleRoutes: Record<string, string> = {
                  ADMIN: '/admin',
                  TEACHER: '/teacher',
                  PARENT: '/parent',
                  STUDENT: '/student',
                  ACCOUNTANT: '/accountant',
                  DISCIPLINE_OFFICER: '/discipline-officer',
                  PROMOTER: '/promoter',
                }
                return roleRoutes[user?.role || ''] || '/admin'
              })()
            } replace />
          ) : (
            <Navigate to="/login" replace />
          )
        } />
      </Route>
    </Routes>
  )
}

export default App
