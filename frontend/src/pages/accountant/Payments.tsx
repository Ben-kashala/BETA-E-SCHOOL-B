import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import api from '@/services/api'
import { Card } from '@/components/ui/Card'
import { format } from 'date-fns'
import { fr } from 'date-fns/locale'
import { Check, X, FileText, Plus } from 'lucide-react'
import { showErrorToast, showSuccessToast } from '@/utils/toast'
import { cn } from '@/utils/cn'
import PaymentForm from '@/components/payment/PaymentForm'

const PAYMENT_METHOD_LABELS: Record<string, string> = {
  CASH: 'Espèces',
  MOBILE_MONEY: 'Mobile Money',
  MOBILE_MONEY_MPESA: 'M-Pesa',
  MOBILE_MONEY_ORANGE: 'Orange Money',
  MOBILE_MONEY_AIRTEL: 'Airtel Money',
  BANK_TRANSFER: 'Virement bancaire',
  CARD: 'Carte bancaire',
  ONLINE: 'Paiement en ligne',
}

export default function AccountantPayments() {
  const queryClient = useQueryClient()
  const [showPaymentForm, setShowPaymentForm] = useState(false)

  const { data: payments, isLoading, error } = useQuery({
    queryKey: ['payments'],
    queryFn: async () => {
      const response = await api.get('/payments/payments/')
      return response.data
    },
    retry: 1,
  })

  const { data: parents } = useQuery({
    queryKey: ['users-parents'],
    queryFn: async () => {
      const res = await api.get('/auth/users/', { params: { role: 'PARENT' } })
      const data = res.data?.results ?? res.data
      return Array.isArray(data) ? data : []
    },
    enabled: showPaymentForm,
  })

  const { data: feeTypes } = useQuery({
    queryKey: ['fee-types'],
    queryFn: async () => {
      const res = await api.get('/payments/fee-types/')
      const data = res.data?.results ?? res.data
      return Array.isArray(data) ? data : []
    },
    enabled: showPaymentForm,
  })

  const { data: studentsData } = useQuery({
    queryKey: ['auth-students'],
    queryFn: async () => {
      const res = await api.get('/auth/students/')
      const data = res.data?.results ?? res.data
      return Array.isArray(data) ? data : []
    },
    enabled: showPaymentForm,
  })
  const students = studentsData ?? []

  const { data: summaryByFeeType = [] } = useQuery({
    queryKey: ['payments-summary-by-fee-type'],
    queryFn: async () => {
      const res = await api.get('/payments/payments/summary-by-fee-type/')
      return res.data ?? []
    },
  })

  const validateMutation = useMutation({
    mutationFn: (id: number) => api.post(`/payments/payments/${id}/validate/`),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['payments'] })
      queryClient.invalidateQueries({ queryKey: ['payments-summary-by-fee-type'] })
      showSuccessToast('Paiement validé avec succès')
    },
    onError: (error: any) => {
      showErrorToast(error, 'Erreur lors de la validation du paiement')
    },
  })

  const rejectMutation = useMutation({
    mutationFn: (id: number) => api.post(`/payments/payments/${id}/reject/`),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['payments'] })
      queryClient.invalidateQueries({ queryKey: ['payments-summary-by-fee-type'] })
      showSuccessToast('Paiement rejeté')
    },
    onError: (error: any) => {
      showErrorToast(error, 'Erreur lors du rejet du paiement')
    },
  })

  const createPaymentMutation = useMutation({
    mutationFn: async (payload: Record<string, unknown>) => {
      const response = await api.post('/payments/payments/', payload)
      return response.data
    },
    onError: (error: any) => {
      showErrorToast(error, 'Erreur lors de l\'enregistrement du paiement')
    },
  })

  const getStatusBadge = (status: string) => {
    const badges: Record<string, string> = {
      COMPLETED: 'bg-green-100 dark:bg-green-900/30 text-green-800 dark:text-green-300',
      PENDING: 'bg-yellow-100 dark:bg-yellow-900/30 text-yellow-800 dark:text-yellow-300',
      FAILED: 'bg-red-100 dark:bg-red-900/30 text-red-800 dark:text-red-300',
      PROCESSING: 'bg-blue-100 dark:bg-blue-900/30 text-blue-800 dark:text-blue-300',
    }
    return badges[status] || 'bg-blue-100 dark:bg-blue-900/30 text-blue-800 dark:text-blue-300'
  }

  const paymentList = payments?.results ?? payments ?? []

  return (
    <div>
      <div className="flex justify-between items-center mb-6">
        <h1 className="text-3xl font-bold text-gray-900 dark:text-gray-100">Gestion des Paiements</h1>
        <button
          type="button"
          onClick={() => setShowPaymentForm(true)}
          className="btn btn-primary flex items-center gap-2"
        >
          <Plus className="w-4 h-4" />
          Effectuer un paiement
        </button>
      </div>

      <Card className="mb-8">
        <div className="overflow-x-auto">
          <table className="w-full">
            <thead className="bg-gray-50 dark:bg-gray-700/50">
              <tr>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-700 dark:text-gray-300 uppercase">ID</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-700 dark:text-gray-300 uppercase">Utilisateur</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-700 dark:text-gray-300 uppercase">Montant</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-700 dark:text-gray-300 uppercase">Méthode</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-700 dark:text-gray-300 uppercase">Statut</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-700 dark:text-gray-300 uppercase">Date</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-700 dark:text-gray-300 uppercase">Actions</th>
              </tr>
            </thead>
            <tbody className="bg-white dark:bg-gray-800 divide-y divide-gray-200 dark:divide-gray-700">
              {isLoading ? (
                <tr>
                  <td colSpan={7} className="px-6 py-4 text-center text-gray-600 dark:text-gray-400">Chargement...</td>
                </tr>
              ) : error ? (
                <tr>
                  <td colSpan={7} className="px-6 py-4 text-center text-red-600 dark:text-red-400">
                    Erreur lors du chargement des paiements
                  </td>
                </tr>
              ) : paymentList.length === 0 ? (
                <tr>
                  <td colSpan={7} className="px-6 py-4 text-center text-gray-600 dark:text-gray-400">
                    Aucun paiement trouvé
                  </td>
                </tr>
              ) : (
                paymentList.map((payment: any) => (
                  <tr key={payment.id} className="hover:bg-gray-50 dark:hover:bg-gray-700/50">
                    <td className="px-6 py-4 whitespace-nowrap text-sm font-mono text-gray-900 dark:text-gray-100">
                      {payment.payment_id}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900 dark:text-gray-100">
                      {payment.user_name}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900 dark:text-gray-100">
                      {payment.amount} {payment.currency}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900 dark:text-gray-100">
                      {PAYMENT_METHOD_LABELS[payment.payment_method] ?? payment.payment_method}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap">
                      <span className={cn('badge', getStatusBadge(payment.status))}>
                        {payment.status}
                      </span>
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-600 dark:text-gray-400">
                      {payment.payment_date
                        ? format(new Date(payment.payment_date), 'dd MMM yyyy', { locale: fr })
                        : '-'}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm font-medium space-x-2">
                      {payment.status === 'PENDING' && (
                        <>
                          <button
                            onClick={() => validateMutation.mutate(payment.id)}
                            className="text-green-600 dark:text-green-400 hover:text-green-900 dark:hover:text-green-300"
                            title="Valider"
                          >
                            <Check className="w-5 h-5" />
                          </button>
                          <button
                            onClick={() => rejectMutation.mutate(payment.id)}
                            className="text-red-600 dark:text-red-400 hover:text-red-900 dark:hover:text-red-300"
                            title="Rejeter"
                          >
                            <X className="w-5 h-5" />
                          </button>
                        </>
                      )}
                      {payment.status === 'COMPLETED' && (
                        <button
                          onClick={async () => {
                            try {
                              const response = await api.get(`/payments/payments/${payment.id}/download_receipt/`, {
                                responseType: 'blob',
                              })
                              const url = window.URL.createObjectURL(new Blob([response.data]))
                              const link = document.createElement('a')
                              link.href = url
                              link.setAttribute('download', `receipt_${payment.payment_id}.pdf`)
                              document.body.appendChild(link)
                              link.click()
                              link.remove()
                              window.URL.revokeObjectURL(url)
                              showSuccessToast('Reçu téléchargé avec succès')
                            } catch (err: any) {
                              showErrorToast(err, 'Erreur lors du téléchargement du reçu')
                            }
                          }}
                          className="text-primary-600 dark:text-primary-400 hover:text-primary-800 dark:hover:text-primary-300 flex items-center space-x-1"
                          title="Télécharger le reçu"
                        >
                          <FileText className="w-4 h-4" />
                          <span>Reçu</span>
                        </button>
                      )}
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </Card>

      <Card>
        <h2 className="text-xl font-semibold text-gray-900 dark:text-gray-100 mb-4">
          Classement des montants par type de frais
        </h2>
        <p className="text-sm text-gray-500 dark:text-gray-400 mb-4">
          Frais d&apos;inscription, Première tranche, Deuxième tranche, etc. — selon les types de frais définis pour l&apos;école.
        </p>
        <div className="overflow-x-auto">
          <table className="w-full">
            <thead className="bg-gray-50 dark:bg-gray-700/50">
              <tr>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-700 dark:text-gray-300 uppercase">Rang</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-700 dark:text-gray-300 uppercase">Type de frais</th>
                <th className="px-6 py-3 text-right text-xs font-medium text-gray-700 dark:text-gray-300 uppercase">Montant total</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-700 dark:text-gray-300 uppercase">Devise</th>
                <th className="px-6 py-3 text-right text-xs font-medium text-gray-700 dark:text-gray-300 uppercase">Nombre de paiements</th>
              </tr>
            </thead>
            <tbody className="bg-white dark:bg-gray-800 divide-y divide-gray-200 dark:divide-gray-700">
              {summaryByFeeType.length === 0 ? (
                <tr>
                  <td colSpan={5} className="px-6 py-4 text-center text-gray-500 dark:text-gray-400">
                    Aucune donnée (les montants par type de frais proviennent des paiements ventilés par type).
                  </td>
                </tr>
              ) : (
                summaryByFeeType.map((row: any, idx: number) => (
                  <tr key={row.fee_type_id != null ? row.fee_type_id : `non-ventile-${row.currency}-${idx}`} className="hover:bg-gray-50 dark:hover:bg-gray-700/50">
                    <td className="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900 dark:text-gray-100">
                      {row.rank}
                    </td>
                    <td className="px-6 py-4 text-sm text-gray-900 dark:text-gray-100">{row.fee_type_name}</td>
                    <td className="px-6 py-4 text-sm text-right font-medium text-gray-900 dark:text-gray-100">
                      {Number(row.total_amount).toLocaleString('fr-FR')}
                    </td>
                    <td className="px-6 py-4 text-sm text-gray-600 dark:text-gray-400">{row.currency}</td>
                    <td className="px-6 py-4 text-sm text-right text-gray-600 dark:text-gray-400">{row.payment_count}</td>
                  </tr>
                ))
              )}
            </tbody>
            {summaryByFeeType.length > 0 && (() => {
              const totalsByCurrency = (summaryByFeeType as any[]).reduce<Record<string, { total_amount: number; payment_count: number }>>((acc, row) => {
                const c = row.currency || 'CDF'
                if (!acc[c]) acc[c] = { total_amount: 0, payment_count: 0 }
                acc[c].total_amount += Number(row.total_amount) || 0
                acc[c].payment_count += Number(row.payment_count) || 0
                return acc
              }, {})
              const totalPaymentCount = Object.values(totalsByCurrency).reduce((s, x) => s + x.payment_count, 0)
              const totalAmountsText = Object.entries(totalsByCurrency)
                .map(([currency, { total_amount }]) => `${total_amount.toLocaleString('fr-FR')} ${currency}`)
                .join(' / ')
              return (
                <tfoot className="bg-gray-100 dark:bg-gray-700/70 border-t-2 border-gray-200 dark:border-gray-600">
                  <tr className="font-semibold text-gray-900 dark:text-gray-100">
                    <td className="px-6 py-3 text-sm" />
                    <td className="px-6 py-3 text-sm">Total</td>
                    <td className="px-6 py-3 text-sm text-right">{totalAmountsText}</td>
                    <td className="px-6 py-3 text-sm text-gray-600 dark:text-gray-400">—</td>
                    <td className="px-6 py-3 text-sm text-right">{totalPaymentCount}</td>
                  </tr>
                </tfoot>
              )
            })()}
          </table>
        </div>
      </Card>

      {showPaymentForm && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
          <div className="bg-white dark:bg-gray-800 rounded-lg shadow-xl max-w-lg w-full max-h-[90vh] overflow-y-auto">
            <PaymentForm
              mode="accountant"
              parents={parents ?? []}
              students={students}
              feeTypes={feeTypes ?? []}
              onCreatePayment={async (payload) => {
                const data = await createPaymentMutation.mutateAsync(payload)
                return { id: data.id, payment_id: data.payment_id }
              }}
              onSuccess={() => {
                queryClient.invalidateQueries({ queryKey: ['payments'] })
                queryClient.invalidateQueries({ queryKey: ['payments-summary-by-fee-type'] })
                showSuccessToast('Paiement enregistré')
                setShowPaymentForm(false)
              }}
              onCancel={() => setShowPaymentForm(false)}
              isPending={createPaymentMutation.isPending}
              title="Effectuer un paiement"
            />
          </div>
        </div>
      )}
    </div>
  )
}
