import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import api from '@/services/api'
import { Card } from '@/components/ui/Card'
import { Building2, CreditCard, ArrowDownCircle } from 'lucide-react'

type PromoterSchool = {
  id: number
  name: string
  code: string
  city: string
  academic_year: string
  payments_totals: Record<string, number>
  expenses_totals: Record<string, number>
}

const formatAmount = (amount: number) =>
  Number(amount || 0).toLocaleString('fr-FR', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  })

export default function PromoterFinances() {
  const [selectedSchoolId, setSelectedSchoolId] = useState<number | 'ALL'>('ALL')
  const [activeTab, setActiveTab] = useState<'RECETTES' | 'DEPENSES'>('RECETTES')

  const { data, isLoading, error } = useQuery<{ results: PromoterSchool[] }>({
    queryKey: ['promoter-schools'],
    queryFn: async () => {
      const res = await api.get('/schools/my-schools/')
      return res.data
    },
  })

  const schools = data?.results || []
  const selectedSchool =
    selectedSchoolId === 'ALL' ? undefined : schools.find((s) => s.id === selectedSchoolId)

  const aggregateTotals = (key: 'payments_totals' | 'expenses_totals') => {
    const totals: Record<string, number> = {}
    const sourceSchools = selectedSchool ? [selectedSchool] : schools
    for (const s of sourceSchools) {
      const src = s[key] || {}
      for (const [currency, amount] of Object.entries(src)) {
        totals[currency] = (totals[currency] || 0) + (amount || 0)
      }
    }
    return totals
  }

  const currentTotals =
    activeTab === 'RECETTES'
      ? aggregateTotals('payments_totals')
      : aggregateTotals('expenses_totals')

  return (
    <div>
      <h1 className="text-2xl sm:text-3xl font-bold text-gray-900 dark:text-white mb-2 flex items-center gap-2">
        <CreditCard className="w-7 h-7" />
        Finances
      </h1>
      <p className="text-gray-600 dark:text-gray-400 mb-6">
        Vue consolidée des <span className="font-medium">recettes</span> (paiements) et{' '}
        <span className="font-medium">dépenses</span> sur l&apos;ensemble de vos écoles, avec filtre par
        établissement.
      </p>

      {/* Filtres et onglets */}
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4 mb-6">
        <div>
          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
            École
          </label>
          <select
            value={selectedSchoolId}
            onChange={(e) =>
              setSelectedSchoolId(e.target.value === 'ALL' ? 'ALL' : Number(e.target.value))
            }
            className="input max-w-xs"
          >
            <option value="ALL">Toutes les écoles</option>
            {schools.map((school) => (
              <option key={school.id} value={school.id}>
                {school.name} ({school.city})
              </option>
            ))}
          </select>
        </div>

        <div className="inline-flex rounded-lg border border-gray-200 dark:border-gray-700 overflow-hidden">
          <button
            type="button"
            onClick={() => setActiveTab('RECETTES')}
            className={`px-4 py-2 text-sm font-medium flex items-center gap-2 ${
              activeTab === 'RECETTES'
                ? 'bg-primary-600 text-white'
                : 'bg-transparent text-gray-700 dark:text-gray-300'
            }`}
          >
            <ArrowDownCircle className="w-4 h-4" />
            Recettes
          </button>
          <button
            type="button"
            onClick={() => setActiveTab('DEPENSES')}
            className={`px-4 py-2 text-sm font-medium ${
              activeTab === 'DEPENSES'
                ? 'bg-primary-600 text-white'
                : 'bg-transparent text-gray-700 dark:text-gray-300'
            }`}
          >
            Dépenses
          </button>
        </div>
      </div>

      {isLoading ? (
        <div className="py-12 text-center text-gray-500 dark:text-gray-400">Chargement...</div>
      ) : error ? (
        <div className="py-12 text-center text-red-600 dark:text-red-400">
          Erreur lors du chargement des données financières.
        </div>
      ) : schools.length === 0 ? (
        <div className="py-12 text-center text-gray-500 dark:text-gray-400">
          Aucune école associée à votre profil promoteur.
        </div>
      ) : (
        <>
          {/* Résumé global */}
          <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mb-6">
            <Card className="p-5 dark:bg-gray-900">
              <p className="text-xs text-gray-500 dark:text-gray-400 mb-1">Portefeuille</p>
              <p className="text-lg font-semibold text-gray-900 dark:text-white mb-1">
                {selectedSchool ? selectedSchool.name : 'Toutes les écoles'}
              </p>
              <p className="text-xs text-gray-500 dark:text-gray-400">
                {selectedSchool ? selectedSchool.academic_year : 'Année(s) scolaire(s) en cours'}
              </p>
            </Card>
            <Card className="p-5 dark:bg-gray-900">
              <p className="text-xs text-gray-500 dark:text-gray-400 mb-1">
                {activeTab === 'RECETTES' ? 'Total des entrées' : 'Total des dépenses'}
              </p>
              <div className="space-y-1">
                {Object.keys(currentTotals).length === 0 ? (
                  <p className="text-base text-gray-900 dark:text-white">0,00</p>
                ) : (
                  Object.entries(currentTotals).map(([currency, amount]) => (
                    <p key={currency} className="text-base text-gray-900 dark:text-white">
                      {formatAmount(amount)} {currency}
                    </p>
                  ))
                )}
              </div>
            </Card>
            <Card className="p-5 dark:bg-gray-900">
              <p className="text-xs text-gray-500 dark:text-gray-400 mb-1">Répartition par école</p>
              <p className="text-3xl font-bold text-gray-900 dark:text-white">
                {selectedSchool ? 1 : schools.length}
              </p>
              <p className="text-xs text-gray-500 dark:text-gray-400 mt-1">
                {selectedSchool ? 'École sélectionnée' : 'Écoles suivies'}
              </p>
            </Card>
          </div>

          {/* Détail par école */}
          {!selectedSchool && (
            <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-5">
              {schools.map((school) => {
                const totals =
                  activeTab === 'RECETTES'
                    ? school.payments_totals || {}
                    : school.expenses_totals || {}
                const hasData = Object.keys(totals).length > 0
                return (
                  <Card key={school.id} className="p-5 dark:bg-gray-900">
                    <div className="flex items-start justify-between mb-3">
                      <div>
                        <h2 className="text-lg font-semibold text-gray-900 dark:text-white">
                          {school.name}
                        </h2>
                        <p className="text-xs text-gray-500 dark:text-gray-400">
                          {school.code} • {school.city}
                        </p>
                      </div>
                      <Building2 className="w-5 h-5 text-primary-500" />
                    </div>
                    <p className="text-xs text-gray-500 dark:text-gray-400 mb-2">
                      Année scolaire : {school.academic_year}
                    </p>
                    <p className="text-xs text-gray-500 dark:text-gray-400 mb-1">
                      {activeTab === 'RECETTES' ? 'Entrées cumulées' : 'Dépenses cumulées'}
                    </p>
                    {hasData ? (
                      <div className="space-y-1">
                        {Object.entries(totals).map(([currency, amount]) => (
                          <p key={currency} className="text-sm text-gray-900 dark:text-white">
                            {formatAmount(amount as number)} {currency}
                          </p>
                        ))}
                      </div>
                    ) : (
                      <p className="text-sm text-gray-500 dark:text-gray-400">Aucun mouvement.</p>
                    )}
                  </Card>
                )
              })}
            </div>
          )}
        </>
      )}
    </div>
  )
}

