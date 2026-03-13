import { useQuery } from '@tanstack/react-query'
import { School, Users, CreditCard, ArrowDownCircle } from 'lucide-react'
import api from '@/services/api'
import { Card } from '@/components/ui/Card'

type PromoterDashboardStats = {
  schools_total: number
  schools_by_type: {
    MATERNELLE: number
    PRIMAIRE: number
    HUMANITAIRE: number
  }
  students_total: number
  payments_by_currency: Record<string, number>
  expenses_by_currency: Record<string, number>
}

const formatAmount = (amount: number) =>
  Number(amount || 0).toLocaleString('fr-FR', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  })

export default function PromoterDashboard() {
  const { data, isLoading } = useQuery<PromoterDashboardStats>({
    queryKey: ['promoter-dashboard'],
    queryFn: async () => {
      const res = await api.get('/schools/schools/promoter-dashboard/')
      return res.data
    },
  })

  const totalSchools = data?.schools_total ?? 0
  const totalStudents = data?.students_total ?? 0

  return (
    <div>
      <h1 className="text-2xl sm:text-3xl font-bold text-gray-900 dark:text-white mb-4 sm:mb-6">
        Tableau de bord Promoteur
      </h1>

      {/* Statistiques globales */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6 mb-8">
        <Card className="p-6 dark:bg-gray-800">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-gray-600 dark:text-gray-400 mb-1">Nombre d&apos;écoles</p>
              <p className="text-3xl font-bold text-gray-900 dark:text-white">
                {isLoading ? '...' : totalSchools}
              </p>
            </div>
            <div className="bg-blue-500 p-3 rounded-lg">
              <School className="w-6 h-6 text-white" />
            </div>
          </div>
        </Card>

        <Card className="p-6 dark:bg-gray-800">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-gray-600 dark:text-gray-400 mb-1">Nombre d&apos;élèves</p>
              <p className="text-3xl font-bold text-gray-900 dark:text-white">
                {isLoading ? '...' : totalStudents}
              </p>
            </div>
            <div className="bg-emerald-500 p-3 rounded-lg">
              <Users className="w-6 h-6 text-white" />
            </div>
          </div>
        </Card>

        <Card className="p-6 dark:bg-gray-800">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-gray-600 dark:text-gray-400 mb-1">Entrées (paiements)</p>
              <p className="text-base text-gray-900 dark:text-white">
                {isLoading
                  ? '...'
                  : Object.entries(data?.payments_by_currency || {}).map(([currency, amount]) => (
                      <span key={currency} className="block">
                        {formatAmount(amount as number)} {currency}
                      </span>
                    )) || '0,00'}
              </p>
            </div>
            <div className="bg-green-500 p-3 rounded-lg">
              <CreditCard className="w-6 h-6 text-white" />
            </div>
          </div>
        </Card>

        <Card className="p-6 dark:bg-gray-800">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-gray-600 dark:text-gray-400 mb-1">Dépenses payées</p>
              <p className="text-base text-gray-900 dark:text-white">
                {isLoading
                  ? '...'
                  : Object.entries(data?.expenses_by_currency || {}).map(([currency, amount]) => (
                      <span key={currency} className="block">
                        {formatAmount(amount as number)} {currency}
                      </span>
                    )) || '0,00'}
              </p>
            </div>
            <div className="bg-red-500 p-3 rounded-lg">
              <ArrowDownCircle className="w-6 h-6 text-white" />
            </div>
          </div>
        </Card>
      </div>

      {/* Répartition des écoles */}
      <Card className="p-6 dark:bg-gray-800">
        <h2 className="text-lg font-semibold text-gray-900 dark:text-white mb-4">
          Répartition des écoles par type
        </h2>
        <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
          <div className="space-y-1">
            <p className="text-sm text-gray-600 dark:text-gray-400">Maternelle</p>
            <p className="text-2xl font-bold text-gray-900 dark:text-white">
              {isLoading ? '...' : data?.schools_by_type.MATERNELLE ?? 0}
            </p>
          </div>
          <div className="space-y-1">
            <p className="text-sm text-gray-600 dark:text-gray-400">Primaire</p>
            <p className="text-2xl font-bold text-gray-900 dark:text-white">
              {isLoading ? '...' : data?.schools_by_type.PRIMAIRE ?? 0}
            </p>
          </div>
          <div className="space-y-1">
            <p className="text-sm text-gray-600 dark:text-gray-400">Humanitaire</p>
            <p className="text-2xl font-bold text-gray-900 dark:text-white">
              {isLoading ? '...' : data?.schools_by_type.HUMANITAIRE ?? 0}
            </p>
          </div>
        </div>
      </Card>
    </div>
  )
}