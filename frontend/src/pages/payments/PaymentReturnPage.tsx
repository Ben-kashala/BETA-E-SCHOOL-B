import { useSearchParams, useNavigate } from 'react-router-dom'
import { useAuthStore } from '@/store/authStore'
import { CheckCircle } from 'lucide-react'

/**
 * Page de retour après tentative de paiement (ex. lien de redirection).
 * Les paiements Mobile Money (Airtel, Orange, M-Pesa) sont confirmés par callback côté backend.
 */
export default function PaymentReturnPage() {
  const [searchParams] = useSearchParams()
  const navigate = useNavigate()
  const { user } = useAuthStore()
  const paymentId = searchParams.get('payment_id')

  const paymentsPath = user?.role === 'ACCOUNTANT' ? '/accountant/payments' : '/parent/payments'

  return (
    <div className="min-h-[40vh] flex flex-col items-center justify-center gap-4 p-4">
      <CheckCircle className="w-16 h-16 text-green-500" />
      <p className="text-gray-800 dark:text-gray-200 font-medium text-center">
        {paymentId
          ? 'Si vous venez de confirmer un paiement Mobile Money, il sera enregistré sous peu.'
          : 'Retour paiements'}
      </p>
      <p className="text-sm text-gray-500 dark:text-gray-400 text-center">
        Les paiements Airtel Money, Orange Money et M-Pesa sont confirmés automatiquement par l’opérateur.
      </p>
      <button
        type="button"
        onClick={() => navigate(paymentsPath, { replace: true })}
        className="btn btn-primary"
      >
        Retour aux paiements
      </button>
    </div>
  )
}
