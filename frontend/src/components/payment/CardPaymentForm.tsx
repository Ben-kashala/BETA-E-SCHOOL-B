import { useEffect, useRef } from 'react'
import { Card } from '@/components/ui/Card'

declare global {
  interface Window {
    FlutterwaveCheckout?: (options: FlutterwaveCheckoutOptions) => void
  }
}

export interface FlutterwaveCheckoutOptions {
  public_key: string
  tx_ref: string
  amount: number
  currency: string
  redirect_url: string
  payment_options?: string
  customer: {
    email: string
    name: string
    phone_number?: string
  }
  customizations?: {
    title?: string
    description?: string
    logo?: string
  }
}

type CardPaymentFormProps = {
  /** Config retournée par l'API initiate-card (Flutterwave, multi-tenant). */
  config: FlutterwaveCheckoutOptions & { payment_id?: number }
  onError: (message: string) => void
}

const SCRIPT_URL = 'https://checkout.flutterwave.com/v3.js'

export default function CardPaymentForm({ config, onError }: CardPaymentFormProps) {
  const loaded = useRef(false)

  useEffect(() => {
    if (loaded.current || typeof window === 'undefined') return
    const existing = document.querySelector(`script[src="${SCRIPT_URL}"]`)
    if (existing) {
      loaded.current = true
      return
    }
    const script = document.createElement('script')
    script.src = SCRIPT_URL
    script.async = true
    script.onload = () => {
      loaded.current = true
    }
    script.onerror = () => onError('Impossible de charger Flutterwave.')
    document.body.appendChild(script)
  }, [onError])

  const handlePay = () => {
    if (!window.FlutterwaveCheckout) {
      onError('Flutterwave n\'est pas encore chargé. Réessayez dans un instant.')
      return
    }
    if (!config.public_key) {
      onError('Paiement carte non configuré (Flutterwave).')
      return
    }
    try {
      window.FlutterwaveCheckout!({
        public_key: config.public_key,
        tx_ref: config.tx_ref,
        amount: config.amount,
        currency: config.currency,
        redirect_url: config.redirect_url,
        payment_options: 'card',
        customer: config.customer,
        customizations: {
          title: 'E-School',
          description: `Paiement ${config.tx_ref}`,
        },
      })
    } catch (err) {
      onError(err instanceof Error ? err.message : 'Erreur Flutterwave')
    }
  }

  return (
    <Card className="p-4">
      <h3 className="text-lg font-semibold mb-3 text-gray-900 dark:text-gray-100">
        Paiement par carte (VISA / Mastercard) — Flutterwave
      </h3>
      <p className="text-sm text-gray-600 dark:text-gray-400 mb-4">
        Montant : <strong>{config.amount} {config.currency}</strong>. Vous serez redirigé vers la page sécurisée Flutterwave.
      </p>
      <button
        type="button"
        onClick={handlePay}
        className="btn btn-primary w-full"
      >
        Payer avec Flutterwave
      </button>
    </Card>
  )
}
