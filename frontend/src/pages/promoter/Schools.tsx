import { useQuery } from '@tanstack/react-query'
import { useNavigate } from 'react-router-dom'
import api from '@/services/api'
import { Card } from '@/components/ui/Card'
import { Building2, Users, CreditCard, ArrowDownCircle, ChevronRight } from 'lucide-react'

type PromoterSchool = {
  id: number
  name: string
  code: string
  city: string
  school_type: 'MATERNELLE' | 'PRIMAIRE' | 'HUMANITAIRE'
  academic_year: string
  students_count: number
  payments_totals: Record<string, number>
  expenses_totals: Record<string, number>
}

const formatAmount = (amount: number) =>
  Number(amount || 0).toLocaleString('fr-FR', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  })

const typeLabel: Record<PromoterSchool['school_type'], string> = {
  MATERNELLE: 'Maternelle',
  PRIMAIRE: 'Primaire',
  HUMANITAIRE: 'Humanitaire',
}

export default function PromoterSchools() {
  const navigate = useNavigate()

  const { data, isLoading, error } = useQuery<{ results: PromoterSchool[] }>({
    queryKey: ['promoter-schools'],
    queryFn: async () => {
      const res = await api.get('/schools/my-schools/')
      return res.data
    },
  })

  const schools = data?.results || []

  return (
    <div>
      <h1 className="text-2xl sm:text-3xl font-bold text-gray-900 dark:text-white mb-2 flex items-center gap-2">
        <Building2 className="w-7 h-7" />
        Mes écoles
      </h1>
      <p className="text-gray-600 dark:text-gray-400 mb-6">
        Vue d&apos;ensemble de toutes vos écoles avec effectifs, entrées et dépenses.
      </p>

      {isLoading ? (
        <div className="py-12 text-center text-gray-500 dark:text-gray-400">Chargement...</div>
      ) : error ? (
        <div className="py-12 text-center text-red-600 dark:text-red-400">
          Erreur lors du chargement des écoles.
        </div>
      ) : schools.length === 0 ? (
        <div className="py-12 text-center text-gray-500 dark:text-gray-400">
          Aucune école associée à votre profil.
        </div>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-6">
          {schools.map((school) => (
            <Card
              key={school.id}
              className="p-5 dark:bg-gray-900 hover:border-primary-500/60 cursor-pointer transition-colors"
              onClick={() => {
                // Ouvre les détails financiers de l'école dans l'onglet Finances promoteur
                navigate(`/promoter/finances?school=${school.id}`)
              }}
            >
              <div className="flex items-start justify-between mb-3">
                <div>
                  <h2 className="text-lg font-semibold text-gray-900 dark:text-white">
                    {school.name}
                  </h2>
                  <p className="text-sm text-gray-500 dark:text-gray-400">
                    {school.code} • {school.city}
                  </p>
                </div>
                <span className="inline-flex px-2 py-1 rounded-full text-xs font-medium bg-primary-50 text-primary-700 dark:bg-primary-900/30 dark:text-primary-200">
                  {typeLabel[school.school_type]}
                </span>
              </div>

              <p className="text-xs text-gray-500 dark:text-gray-400 mb-4">
                Année scolaire : {school.academic_year}
              </p>

              <div className="grid grid-cols-3 gap-3 mb-4">
                <div className="space-y-1">
                  <div className="flex items-center gap-1 text-xs text-gray-500 dark:text-gray-400">
                    <Users className="w-3 h-3" />
                    Élèves
                  </div>
                  <p className="text-xl font-semibold text-gray-900 dark:text-white">
                    {school.students_count}
                  </p>
                </div>
                <div className="space-y-1">
                  <div className="flex items-center gap-1 text-xs text-gray-500 dark:text-gray-400">
                    <CreditCard className="w-3 h-3" />
                    Entrées
                  </div>
                  <p className="text-xs text-gray-900 dark:text-gray-100">
                    {Object.keys(school.payments_totals || {}).length === 0
                      ? '0,00'
                      : Object.entries(school.payments_totals).map(([currency, amount]) => (
                          <span key={currency} className="block">
                            {formatAmount(amount as number)} {currency}
                          </span>
                        ))}
                  </p>
                </div>
                <div className="space-y-1">
                  <div className="flex items-center gap-1 text-xs text-gray-500 dark:text-gray-400">
                    <ArrowDownCircle className="w-3 h-3" />
                    Dépenses
                  </div>
                  <p className="text-xs text-gray-900 dark:text-gray-100">
                    {Object.keys(school.expenses_totals || {}).length === 0
                      ? '0,00'
                      : Object.entries(school.expenses_totals).map(([currency, amount]) => (
                          <span key={currency} className="block">
                            {formatAmount(amount as number)} {currency}
                          </span>
                        ))}
                  </p>
                </div>
              </div>

              <div className="flex items-center justify-between text-xs text-primary-600 dark:text-primary-300">
                <span>Voir les détails de l&apos;école (dashboard, élèves, dépenses...)</span>
                <ChevronRight className="w-4 h-4" />
              </div>
            </Card>
          ))}
        </div>
      )}
    </div>
  )
}