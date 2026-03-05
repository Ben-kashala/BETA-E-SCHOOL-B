import { Card } from '@/components/ui/Card'

const FLUTTERWAVE_HOSTED_URL = 'https://checkout.flutterwave.com/v3/hosted/pay'

export interface FlutterwaveCheckoutOptions {
  public_key: string
  PBFPubKey?: string
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

/**
 * Soumet le paiement via formulaire POST vers Flutterwave Hosted Pay.
 * Ouvre la page de paiement dans un nouvel onglet du navigateur.
 */
export default function CardPaymentForm({ config, onError }: CardPaymentFormProps) {
  const handlePay = () => {
    const pubKey = (config.public_key || (config as { PBFPubKey?: string }).PBFPubKey || '').trim()
    if (!pubKey) {
      onError('Clé publique Flutterwave manquante. Configurez FLUTTERWAVE_PUBLIC_KEY sur Railway ou dans l\'admin (Configuration paiement de l\'école).')
      return
    }
    const c = config.customer
    if (!c?.email || !c?.name) {
      onError('Données client manquantes pour Flutterwave.')
      return
    }
    try {
      const form = document.createElement('form')
      form.method = 'POST'
      form.action = FLUTTERWAVE_HOSTED_URL
      form.target = '_blank'
      form.rel = 'noopener noreferrer'
      const fields: [string, string][] = [
        ['public_key', pubKey],
        ['tx_ref', config.tx_ref],
        ['amount', String(config.amount)],
        ['currency', config.currency],
        ['redirect_url', config.redirect_url],
        ['payment_options', config.payment_options || 'card'],
        ['customer[name]', c.name],
        ['customer[email]', c.email],
      ]
      if (c.phone_number) fields.push(['customer[phone_number]', c.phone_number])
      fields.forEach(([name, value]) => {
        const input = document.createElement('input')
        input.type = 'hidden'
        input.name = name
        input.value = value
        form.appendChild(input)
      })
      document.body.appendChild(form)
      form.submit()
      document.body.removeChild(form)
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
        Montant : <strong>{config.amount} {config.currency}</strong>. Un nouvel onglet s&apos;ouvrira sur la page sécurisée Flutterwave pour finaliser le paiement.
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
