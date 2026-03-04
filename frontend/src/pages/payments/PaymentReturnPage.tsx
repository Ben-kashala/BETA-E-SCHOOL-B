import { useEffect, useState } from 'react'
import { useSearchParams, useNavigate } from 'react-router-dom'
import { useQueryClient } from '@tanstack/react-query'
import { useAuthStore } from '@/store/authStore'
import api from '@/services/api'
import toast from 'react-hot-toast'
import { CheckCircle, XCircle } from 'lucide-react'

/**
 * Page de retour après paiement carte Flutterwave.
 * Flutterwave redirige ici avec ?transaction_id=...&tx_ref=...
 * On envoie payment_id (notre query) + transaction_id au backend pour confirmer.
 */
export default function PaymentReturnPage() {
  const [searchParams] = useSearchParams()
  const navigate = useNavigate()
  const queryClient = useQueryClient()
  const { user } = useAuthStore()
  const [status, setStatus] = useState<'loading' | 'success' | 'error'>('loading')
  const [message, setMessage] = useState('')

  useEffect(() => {
    const paymentId = searchParams.get('payment_id')
    const transactionId = searchParams.get('transaction_id')

    if (!paymentId) {
      setStatus('error')
      setMessage('Paramètre payment_id manquant.')
      return
    }
    const tid = transactionId || searchParams.get('flw_ref')
    if (!tid) {
      setStatus('error')
      setMessage('Référence de transaction manquante. Le paiement a peut-être été annulé.')
      return
    }

    api
      .post('/payments/payments/confirm-card/', {
        payment_id: parseInt(paymentId, 10),
        transaction_id: String(tid),
      })
      .then(() => {
        setStatus('success')
        toast.success('Paiement enregistré avec succès.')
        queryClient.invalidateQueries({ queryKey: ['parent-payments'] })
        queryClient.invalidateQueries({ queryKey: ['payments'] })
        const paymentsPath = user?.role === 'ACCOUNTANT' ? '/accountant/payments' : '/parent/payments'
        setTimeout(() => navigate(paymentsPath, { replace: true }), 2000)
      })
      .catch((err: { response?: { data?: { error?: string } } }) => {
        setStatus('error')
        const msg = err?.response?.data?.error || 'Impossible de confirmer le paiement.'
        setMessage(msg)
        toast.error(msg)
      })
  }, [searchParams, navigate, user?.role, queryClient])

  if (status === 'loading') {
    return (
      <div className="min-h-[40vh] flex items-center justify-center">
        <p className="text-gray-600 dark:text-gray-400">Vérification du paiement...</p>
      </div>
    )
  }

  if (status === 'error') {
    return (
      <div className="min-h-[40vh] flex flex-col items-center justify-center gap-4">
        <XCircle className="w-16 h-16 text-red-500" />
        <p className="text-red-600 dark:text-red-400 text-center max-w-md">{message}</p>
        <button
          type="button"
          onClick={() => navigate(user?.role === 'ACCOUNTANT' ? '/accountant/payments' : '/parent/payments', { replace: true })}
          className="btn btn-primary"
        >
          Retour aux paiements
        </button>
      </div>
    )
  }

  return (
    <div className="min-h-[40vh] flex flex-col items-center justify-center gap-4">
      <CheckCircle className="w-16 h-16 text-green-500" />
      <p className="text-gray-800 dark:text-gray-200 font-medium">Paiement enregistré avec succès.</p>
      <p className="text-sm text-gray-500 dark:text-gray-400">Redirection vers la liste des paiements...</p>
    </div>
  )
}
