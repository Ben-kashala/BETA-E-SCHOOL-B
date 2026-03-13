import { Outlet, Navigate } from 'react-router-dom'
import { useAuthStore } from '@/store/authStore'
import { UserRole } from '@/types'

interface RoleRouteProps {
  allowedRoles: UserRole[]
}

export function RoleRoute({ allowedRoles }: RoleRouteProps) {
  const { user } = useAuthStore()

  if (!user) {
    return <Navigate to="/login" replace />
  }

  if (!allowedRoles.includes(user.role)) {
    // Redirect to appropriate dashboard based on role
    const roleRoutes: Record<UserRole, string> = {
      ADMIN: '/admin',
      TEACHER: '/teacher',
      PARENT: '/parent',
      STUDENT: '/student',
      ACCOUNTANT: '/accountant',
      DISCIPLINE_OFFICER: '/discipline-officer',
      PROMOTER: '/promoter',
    }
    return <Navigate to={roleRoutes[user.role] || '/login'} replace />
  }

  return <Outlet />
}
