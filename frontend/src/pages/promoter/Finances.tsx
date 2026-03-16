import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import api from '@/services/api'
import { Card } from '@/components/ui/Card'
import { Building2, CreditCard, ArrowDownCircle, ArrowUpCircle, Check, X, FileText } from 'lucide-react'
import { format } from 'date-fns'
import { fr } from 'date-fns/locale'
import { cn } from '@/utils/cn'
import toast from 'react-hot-toast'

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
  const queryClient = useQueryClient()
  const [selectedSchoolId, setSelectedSchoolId] = useState<number | 'ALL'>('ALL')
  const [activeTab, setActiveTab] = useState<'RECETTES' | 'DEPENSES' | 'CAISSE'>('RECETTES')

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

  // Dépenses détaillées (pour tableau + actions approbation/rejet)
  const { data: expensesData, isLoading: loadingExpenses, error: errorExpenses } = useQuery({
    queryKey: ['promoter-expenses'],
    queryFn: async () => {
      const res = await api.get('/payments/expenses/', {
        params: selectedSchool ? { school: selectedSchool.id } : {},
      })
      return res.data
    },
    enabled: activeTab === 'DEPENSES',
  })

  const expensesList = expensesData?.results ?? expensesData ?? []

  const updateExpenseStatus = useMutation({
    mutationFn: ({ id, status }: { id: number; status: 'APPROVED' | 'REJECTED' }) =>
      api.patch(`/payments/expenses/${id}/`, { status }),
    onSuccess: () => {
      toast.success('Statut de la dépense mis à jour.')
      queryClient.invalidateQueries({ queryKey: ['promoter-expenses'] })
      queryClient.invalidateQueries({ queryKey: ['promoter-schools'] })
    },
    onError: (e: any) => {
      toast.error(e?.response?.data?.detail || 'Erreur lors de la mise à jour du statut.')
    },
  })

  // Mouvements de caisse (lecture seule)
  const { data: caisseMovements, isLoading: loadingCaisse, error: errorCaisse } = useQuery({
    queryKey: ['promoter-caisse-operations'],
    queryFn: async () => {
      const res = await api.get('/payments/caisse/operations/')
      return res.data
    },
    enabled: activeTab === 'CAISSE',
  })

  const { data: caisseBalance = [] } = useQuery({
    queryKey: ['promoter-caisse-balance'],
    queryFn: async () => {
      const res = await api.get('/payments/caisse/balance/')
      return res.data
    },
    enabled: activeTab === 'CAISSE',
  })

  const caisseList = Array.isArray(caisseMovements)
    ? caisseMovements
    : caisseMovements?.results ?? []

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
          <button
            type="button"
            onClick={() => setActiveTab('CAISSE')}
            className={`px-4 py-2 text-sm font-medium ${
              activeTab === 'CAISSE'
                ? 'bg-primary-600 text-white'
                : 'bg-transparent text-gray-700 dark:text-gray-300'
            }`}
          >
            Mouvement caisse
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

          {/* Détail par école (tableau synthétique) */}
          {activeTab !== 'CAISSE' && (
            <Card className="mb-6">
              <div className="overflow-x-auto">
                <table className="w-full">
                  <thead className="bg-gray-50 dark:bg-gray-700/50">
                    <tr>
                      <th className="px-6 py-3 text-left text-xs font-medium text-gray-700 dark:text-gray-300 uppercase">
                        École
                      </th>
                      <th className="px-6 py-3 text-left text-xs font-medium text-gray-700 dark:text-gray-300 uppercase">
                        Ville
                      </th>
                      <th className="px-6 py-3 text-left text-xs font-medium text-gray-700 dark:text-gray-300 uppercase">
                        Année scolaire
                      </th>
                      <th className="px-6 py-3 text-left text-xs font-medium text-gray-700 dark:text-gray-300 uppercase">
                        {activeTab === 'RECETTES' ? 'Entrées cumulées' : 'Dépenses cumulées'}
                      </th>
                    </tr>
                  </thead>
                  <tbody className="bg-white dark:bg-gray-800 divide-y divide-gray-200 dark:divide-gray-700">
                    {schools.map((school) => {
                      if (selectedSchool && school.id !== selectedSchool.id) return null
                      const totals =
                        activeTab === 'RECETTES'
                          ? school.payments_totals || {}
                          : school.expenses_totals || {}
                      const hasData = Object.keys(totals).length > 0
                      return (
                        <tr key={school.id}>
                          <td className="px-6 py-4 text-sm text-gray-900 dark:text-white flex items-center gap-2">
                            <Building2 className="w-4 h-4 text-primary-500" />
                            {school.name}
                          </td>
                          <td className="px-6 py-4 text-sm text-gray-600 dark:text-gray-400">
                            {school.city}
                          </td>
                          <td className="px-6 py-4 text-sm text-gray-600 dark:text-gray-400">
                            {school.academic_year}
                          </td>
                          <td className="px-6 py-4 text-sm text-gray-900 dark:text-white">
                            {hasData ? (
                              Object.entries(totals).map(([currency, amount]) => (
                                <span key={currency} className="block">
                                  {formatAmount(amount as number)} {currency}
                                </span>
                              ))
                            ) : (
                              <span className="text-gray-500 dark:text-gray-400">Aucun mouvement</span>
                            )}
                          </td>
                        </tr>
                      )
                    })}
                  </tbody>
                </table>
              </div>
            </Card>
          )}

          {/* Tableau détaillé des dépenses avec actions */}
          {activeTab === 'DEPENSES' && (
            <Card className="mb-6">
              <h2 className="text-lg font-semibold text-gray-900 dark:text-gray-100 mb-4">
                Dépenses détaillées
              </h2>
              <div className="overflow-x-auto">
                <table className="w-full">
                  <thead className="bg-gray-50 dark:bg-gray-700/50">
                    <tr>
                      <th className="px-6 py-3 text-left text-xs font-medium text-gray-700 dark:text-gray-300 uppercase">
                        Libellé
                      </th>
                      <th className="px-6 py-3 text-left text-xs font-medium text-gray-700 dark:text-gray-300 uppercase">
                        École
                      </th>
                      <th className="px-6 py-3 text-left text-xs font-medium text-gray-700 dark:text-gray-300 uppercase">
                        Montant
                      </th>
                      <th className="px-6 py-3 text-left text-xs font-medium text-gray-700 dark:text-gray-300 uppercase">
                        Statut
                      </th>
                      <th className="px-6 py-3 text-left text-xs font-medium text-gray-700 dark:text-gray-300 uppercase">
                        Date
                      </th>
                      <th className="px-6 py-3 text-left text-xs font-medium text-gray-700 dark:text-gray-300 uppercase">
                        Actions
                      </th>
                    </tr>
                  </thead>
                  <tbody className="bg-white dark:bg-gray-800 divide-y divide-gray-200 dark:divide-gray-700">
                    {loadingExpenses ? (
                      <tr>
                        <td colSpan={6} className="px-6 py-4 text-center text-gray-500">
                          Chargement des dépenses...
                        </td>
                      </tr>
                    ) : errorExpenses ? (
                      <tr>
                        <td colSpan={6} className="px-6 py-4 text-center text-red-600 dark:text-red-400">
                          Impossible de charger les dépenses.
                        </td>
                      </tr>
                    ) : expensesList.length === 0 ? (
                      <tr>
                        <td colSpan={6} className="px-6 py-4 text-center text-gray-500">
                          Aucune dépense trouvée.
                        </td>
                      </tr>
                    ) : (
                      expensesList.map((exp: any) => (
                        <tr key={exp.id}>
                          <td className="px-6 py-4 text-sm text-gray-900 dark:text-gray-100">
                            {exp.title}
                          </td>
                          <td className="px-6 py-4 text-sm text-gray-600 dark:text-gray-400">
                            {exp.school_name || '—'}
                          </td>
                          <td className="px-6 py-4 text-sm font-medium text-gray-900 dark:text-gray-100">
                            {formatAmount(Number(exp.amount))} {exp.currency}
                          </td>
                          <td className="px-6 py-4 text-sm text-gray-600 dark:text-gray-400">
                            {exp.status}
                          </td>
                          <td className="px-6 py-4 text-sm text-gray-600 dark:text-gray-400">
                            {exp.expense_date
                              ? format(new Date(exp.expense_date), 'dd MMM yyyy', { locale: fr })
                              : '-'}
                          </td>
                          <td className="px-6 py-4 text-sm">
                            {exp.status === 'PENDING' ? (
                              <div className="flex items-center gap-2">
                                <button
                                  type="button"
                                  onClick={() =>
                                    updateExpenseStatus.mutate({ id: exp.id, status: 'APPROVED' })
                                  }
                                  className="inline-flex items-center justify-center w-8 h-8 rounded-full bg-green-600 text-white hover:bg-green-700"
                                  title="Approuver"
                                >
                                  <Check className="w-4 h-4" />
                                </button>
                                <button
                                  type="button"
                                  onClick={() =>
                                    updateExpenseStatus.mutate({ id: exp.id, status: 'REJECTED' })
                                  }
                                  className="inline-flex items-center justify-center w-8 h-8 rounded-full bg-red-600 text-white hover:bg-red-700"
                                  title="Rejeter"
                                >
                                  <X className="w-4 h-4" />
                                </button>
                              </div>
                            ) : (
                              <span className="text-xs text-gray-500 dark:text-gray-400">
                                Aucune action
                              </span>
                            )}
                          </td>
                        </tr>
                      ))
                    )}
                  </tbody>
                </table>
              </div>
            </Card>
          )}

          {/* Mouvement caisse (style proche de la page Caisse comptable) */}
          {activeTab === 'CAISSE' && (
            <>
              <Card className="mb-6">
                <h2 className="text-lg font-semibold text-gray-900 dark:text-gray-100 mb-4">
                  Solde par devise
                </h2>
                <div className="flex flex-wrap gap-4">
                  {(Array.isArray(caisseBalance) ? caisseBalance : []).map((b: any) => (
                    <div
                      key={b.currency}
                      className="px-4 py-3 rounded-lg bg-gray-50 dark:bg-gray-700/50 border border-gray-200 dark:border-gray-600"
                    >
                      <span className="text-sm text-gray-600 dark:text-gray-400">{b.currency}</span>
                      <p className="text-xl font-bold text-gray-900 dark:text-gray-100">
                        {formatAmount(Number(b.balance ?? 0))} {b.currency}
                      </p>
                      <p className="text-xs text-gray-500">
                        Entrées: {formatAmount(Number(b.total_in ?? 0))} — Sorties:{' '}
                        {formatAmount(Number(b.total_out ?? 0))}
                      </p>
                    </div>
                  ))}
                </div>
              </Card>

              <Card>
                <div className="flex justify-between items-center mb-4">
                  <h2 className="text-lg font-semibold text-gray-900 dark:text-gray-100">
                    Mouvements de caisse
                  </h2>
                  <p className="text-xs text-gray-500 dark:text-gray-400">
                    Lecture seule depuis les caisses de vos écoles.
                  </p>
                </div>
                <div className="overflow-x-auto">
                  <table className="w-full">
                    <thead className="bg-gray-50 dark:bg-gray-700/50">
                      <tr>
                        <th className="px-6 py-3 text-left text-xs font-medium text-gray-700 dark:text-gray-300 uppercase">
                          Date
                        </th>
                        <th className="px-6 py-3 text-left text-xs font-medium text-gray-700 dark:text-gray-300 uppercase">
                          École
                        </th>
                        <th className="px-6 py-3 text-left text-xs font-medium text-gray-700 dark:text-gray-300 uppercase">
                          Type
                        </th>
                        <th className="px-6 py-3 text-right text-xs font-medium text-gray-700 dark:text-gray-300 uppercase">
                          Montant
                        </th>
                        <th className="px-6 py-3 text-left text-xs font-medium text-gray-700 dark:text-gray-300 uppercase">
                          Devise
                        </th>
                        <th className="px-6 py-3 text-left text-xs font-medium text-gray-700 dark:text-gray-300 uppercase">
                          Document
                        </th>
                        <th className="px-6 py-3 text-left text-xs font-medium text-gray-700 dark:text-gray-300 uppercase">
                          Description
                        </th>
                      </tr>
                    </thead>
                    <tbody className="bg-white dark:bg-gray-800 divide-y divide-gray-200 dark:divide-gray-700">
                      {loadingCaisse ? (
                        <tr>
                          <td colSpan={7} className="px-6 py-4 text-center text-gray-500">
                            Chargement des mouvements...
                          </td>
                        </tr>
                      ) : errorCaisse ? (
                        <tr>
                          <td colSpan={7} className="px-6 py-4 text-center text-red-600 dark:text-red-400">
                            Impossible de charger les mouvements de caisse.
                          </td>
                        </tr>
                      ) : caisseList.length === 0 ? (
                        <tr>
                          <td colSpan={7} className="px-6 py-4 text-center text-gray-500">
                            Aucun mouvement de caisse.
                          </td>
                        </tr>
                      ) : (
                        caisseList.map((m: any) => (
                          <tr key={m.id}>
                            <td className="px-6 py-4 text-sm text-gray-600 dark:text-gray-400 whitespace-nowrap">
                              {m.created_at
                                ? format(new Date(m.created_at), 'dd MMM yyyy HH:mm', { locale: fr })
                                : '-'}
                            </td>
                            <td className="px-6 py-4 text-sm text-gray-600 dark:text-gray-400">
                              {m.school_name || '—'}
                            </td>
                            <td className="px-6 py-4">
                              <span
                                className={cn(
                                  'inline-flex items-center gap-1 text-sm font-medium',
                                  m.movement_type === 'IN' && 'text-green-600 dark:text-green-400',
                                  m.movement_type === 'OUT' && 'text-red-600 dark:text-red-400'
                                )}
                              >
                                {m.movement_type === 'IN' ? (
                                  <ArrowDownCircle className="w-4 h-4" />
                                ) : (
                                  <ArrowUpCircle className="w-4 h-4" />
                                )}
                                {m.movement_type === 'IN' ? 'Entrée' : 'Sortie'}
                              </span>
                            </td>
                            <td className="px-6 py-4 text-sm text-right font-medium">
                              <span
                                className={
                                  m.movement_type === 'IN'
                                    ? 'text-green-600 dark:text-green-400'
                                    : 'text-red-600 dark:text-red-400'
                                }
                              >
                                {m.movement_type === 'OUT' ? '-' : '+'}
                                {formatAmount(Number(m.amount))}
                              </span>
                            </td>
                            <td className="px-6 py-4 text-sm text-gray-600 dark:text-gray-400">
                              {m.currency}
                            </td>
                            <td className="px-6 py-4 text-sm text-gray-600 dark:text-gray-400">
                              {m.document_url ? (
                                <a
                                  href={m.document_url}
                                  target="_blank"
                                  rel="noopener noreferrer"
                                  className="inline-flex items-center gap-1 text-blue-600 dark:text-blue-400 hover:underline"
                                >
                                  <FileText className="w-4 h-4" />
                                  <span>Voir</span>
                                </a>
                              ) : (
                                <span className="text-gray-400">—</span>
                              )}
                            </td>
                            <td className="px-6 py-4 text-sm text-gray-600 dark:text-gray-400">
                              {m.description || '-'}
                            </td>
                          </tr>
                        ))
                      )}
                    </tbody>
                  </table>
                </div>
              </Card>
            </>
          )}
        </>
      )}
    </div>
  )
}

