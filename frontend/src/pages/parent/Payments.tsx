import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import api from '@/services/api'
import { Card } from '@/components/ui/Card'
import { format } from 'date-fns'
import { fr } from 'date-fns/locale'
import { cn } from '@/utils/cn'
import { Plus, FileText, Pencil } from 'lucide-react'
import toast from 'react-hot-toast'
import PaymentForm from '@/components/payment/PaymentForm'

const PAYMENT_METHODS_EDITABLE = ['CARD', 'MOBILE_MONEY_ORANGE', 'MOBILE_MONEY_MPESA', 'MOBILE_MONEY_AIRTEL', 'MOBILE_MONEY']

export default function ParentPayments() {
  const [showPaymentForm, setShowPaymentForm] = useState(false)
  const [editingPayment, setEditingPayment] = useState<any | null>(null)
  const queryClient = useQueryClient()

  const { data: payments, isLoading, error } = useQuery({
    queryKey: ['parent-payments'],
    queryFn: async () => {
      const response = await api.get('/payments/payments/')
      return response.data
    },
  })

  const { data: children = [] } = useQuery({
    queryKey: ['parent-children'],
    queryFn: async () => {
      const response = await api.get('/auth/students/parent_dashboard/')
      return response.data
    },
  })

  const { data: feeTypes } = useQuery({
    queryKey: ['fee-types'],
    queryFn: async () => {
      const response = await api.get('/payments/fee-types/')
      return response.data
    },
  })

  const createPaymentMutation = useMutation({
    mutationFn: async (data: Record<string, unknown>) => {
      const response = await api.post('/payments/payments/', data)
      return response.data
    },
  })

  const getStatusBadge = (status: string) => {
    const badges: Record<string, string> = {
      COMPLETED: 'bg-green-100 dark:bg-green-900/30 text-green-800 dark:text-green-300',
      PENDING: 'bg-yellow-100 dark:bg-yellow-900/30 text-yellow-800 dark:text-yellow-300',
      FAILED: 'bg-red-100 dark:bg-red-900/30 text-red-800 dark:text-red-300',
    }
    return badges[status] || 'bg-blue-100 dark:bg-blue-900/30 text-blue-800 dark:text-blue-300'
  }

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <h1 className="text-3xl font-bold text-gray-900 dark:text-gray-100">Mes Paiements</h1>
        <button
          onClick={() => setShowPaymentForm(true)}
          className="btn btn-primary flex items-center space-x-2"
        >
          <Plus className="w-4 h-4" />
          <span>Nouveau paiement</span>
        </button>
      </div>

      {(showPaymentForm || editingPayment) && (
        <PaymentForm
          mode="parent"
          children={children}
          feeTypes={feeTypes?.results ?? feeTypes ?? []}
          existingPayment={editingPayment}
          onCreatePayment={async (payload) => {
            const data = await createPaymentMutation.mutateAsync(payload)
            return { id: data.id, payment_id: data.payment_id }
          }}
          onSuccess={() => {
            queryClient.invalidateQueries({ queryKey: ['parent-payments'] })
            setShowPaymentForm(false)
            setEditingPayment(null)
            toast.success(editingPayment ? 'Paiement mis à jour' : 'Paiement enregistré avec succès')
          }}
          onCancel={() => {
            setShowPaymentForm(false)
            setEditingPayment(null)
          }}
          isPending={createPaymentMutation.isPending}
          title={editingPayment ? 'Modifier / Relancer le paiement' : 'Nouveau paiement'}
        />
      )}

      <Card>
        <div className="overflow-x-auto">
          <table className="w-full">
            <thead className="bg-gray-50 dark:bg-gray-700/50">
              <tr>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase">ID</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase">Montant</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase">Méthode</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase">Statut</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase">Date</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase">Actions</th>
              </tr>
            </thead>
            <tbody className="bg-white dark:bg-gray-800 divide-y divide-gray-200 dark:divide-gray-700">
              {isLoading ? (
                <tr>
                  <td colSpan={6} className="px-6 py-4 text-center text-gray-600 dark:text-gray-400">Chargement...</td>
                </tr>
              ) : error ? (
                <tr>
                  <td colSpan={6} className="px-6 py-4 text-center text-red-600 dark:text-red-400">
                    Erreur lors du chargement des paiements. Veuillez réessayer plus tard.
                  </td>
                </tr>
              ) : !payments?.results || payments.results.length === 0 ? (
                <tr>
                  <td colSpan={6} className="px-6 py-4 text-center text-gray-600 dark:text-gray-400">
                    Aucun paiement enregistré pour le moment.
                  </td>
                </tr>
              ) : (
                payments.results.map((payment: any) => (
                  <tr key={payment.id} className="hover:bg-gray-50 dark:hover:bg-gray-700/50">
                    <td className="px-6 py-4 whitespace-nowrap text-sm font-mono text-gray-900 dark:text-gray-100">
                      {payment.payment_id}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900 dark:text-gray-100">
                      {payment.amount} {payment.currency}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900 dark:text-gray-100">
                      {payment.payment_method}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap">
                      <span className={cn('badge', getStatusBadge(payment.status))}>
                        {payment.status}
                      </span>
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500 dark:text-gray-400">
                      {payment.payment_date
                        ? format(new Date(payment.payment_date), 'dd MMM yyyy', { locale: fr })
                        : '-'}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm">
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
                              toast.success('Reçu téléchargé avec succès')
                            } catch (error: any) {
                              toast.error(error?.response?.data?.error || 'Erreur lors du téléchargement du reçu')
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
    </div>
  )
}
