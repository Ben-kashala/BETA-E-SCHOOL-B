import { useState, useEffect } from 'react'
import { X, Smartphone, CheckCircle } from 'lucide-react'
import { Card } from '@/components/ui/Card'
import api from '@/services/api'
import toast from 'react-hot-toast'

type PaymentFormMode = 'parent' | 'accountant'

type ChildOption = { identity: { id: number; user?: { first_name?: string; last_name?: string; middle_name?: string | null }; student_id?: string } }
type StudentOption = { id: number; user?: { first_name?: string; last_name?: string; middle_name?: string | null }; student_id?: string; parent?: number }
type ParentOption = { id: number; first_name?: string; last_name?: string; middle_name?: string | null; email?: string }
type FeeTypeOption = { id: number; name: string; amount: string | number; currency: string }

const PAYMENT_METHODS = [
  { value: 'CASH', label: 'Espèces' },
  { value: 'MOBILE_MONEY', label: 'Mobile Money' },
  { value: 'MOBILE_MONEY_MPESA', label: 'M-Pesa' },
  { value: 'MOBILE_MONEY_ORANGE', label: 'Orange Money' },
  { value: 'MOBILE_MONEY_AIRTEL', label: 'Airtel Money' },
  { value: 'BANK_TRANSFER', label: 'Virement bancaire' },
  { value: 'ONLINE', label: 'Paiement en ligne' },
]

const MOBILE_MONEY_METHODS = ['MOBILE_MONEY_ORANGE', 'MOBILE_MONEY_MPESA', 'MOBILE_MONEY_AIRTEL']

/** Paiement existant (pour modification / relance d'un paiement non approuvé). */
export type ExistingPayment = {
  id: number
  payment_id: string
  amount: number
  currency: string
  payment_method: string
  status?: string
  [key: string]: unknown
}

interface PaymentFormProps {
  mode: PaymentFormMode
  children?: ChildOption[]
  parents?: ParentOption[]
  students?: StudentOption[]
  feeTypes?: FeeTypeOption[]
  /** Crée le paiement et retourne l'objet payment (avec id). */
  onCreatePayment: (payload: Record<string, unknown>) => Promise<{ id: number; payment_id: string }>
  /** Appelé quand le flux est terminé (création simple ou après confirmation mobile/carte). */
  onSuccess: () => void
  onCancel: () => void
  isPending?: boolean
  title?: string
  /** Si fourni, affiche directement l'étape mobile pour relancer ce paiement (pas de formulaire de création). */
  existingPayment?: ExistingPayment | null
}

export default function PaymentForm({
  mode,
  children = [],
  parents = [],
  students = [],
  feeTypes = [],
  onCreatePayment,
  onSuccess,
  onCancel,
  isPending = false,
  title = 'Nouveau paiement',
  existingPayment = null,
}: PaymentFormProps) {
  const [selectedParentId, setSelectedParentId] = useState('')
  const [step, setStep] = useState<'form' | 'mobile_wait'>('form')
  const [createdPayment, setCreatedPayment] = useState<{ id: number; payment_id: string } | null>(null)
  const [mobileMessage, setMobileMessage] = useState('')
  const [submitting, setSubmitting] = useState(false)
  const [selectedMethod, setSelectedMethod] = useState('')
  const [existingPaymentLoaded, setExistingPaymentLoaded] = useState(false)

  const studentOptions =
    mode === 'parent'
      ? children
      : students.filter((s) => !selectedParentId || s.parent === Number(selectedParentId))

  const isMobileMoney = (method: string) => MOBILE_MONEY_METHODS.includes(method)

  // Flux "modifier" : ouvrir directement l'étape mobile pour un paiement existant
  useEffect(() => {
    if (!existingPayment || existingPaymentLoaded) return
    setExistingPaymentLoaded(true)
    const method = existingPayment.payment_method || ''
    if (isMobileMoney(method)) {
      setCreatedPayment({ id: existingPayment.id, payment_id: existingPayment.payment_id })
      setMobileMessage('Confirmez le paiement sur votre téléphone ou relancez la demande.')
      setStep('mobile_wait')
    }
  }, [existingPayment, existingPaymentLoaded])

  const handleSubmit = async (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault()
    const formData = new FormData(e.currentTarget)
    const paymentMethod = formData.get('payment_method') as string
    const payload: Record<string, unknown> = {
      student: parseInt(formData.get('student') as string),
      amount: parseFloat(formData.get('amount') as string),
      currency: (formData.get('currency') as string) || 'CDF',
      payment_method: paymentMethod,
      description: (formData.get('description') as string) || '',
      reference_number: (formData.get('reference_number') as string) || '',
    }
    if (mode === 'accountant' && formData.get('user')) {
      payload.user = parseInt(formData.get('user') as string)
    }
    const feeType = formData.get('fee_type')
    if (feeType) payload.fee_type = parseInt(feeType as string)
    const academicYear = formData.get('academic_year')
    if (academicYear) payload.academic_year = academicYear as string
    if (mode === 'accountant' && formData.get('status')) {
      payload.status = formData.get('status') as string
    }
    if (isMobileMoney(paymentMethod)) {
      const phone = (formData.get('payer_phone') as string)?.trim()
      if (!phone) {
        toast.error('Veuillez indiquer le numéro de téléphone pour le Mobile Money.')
        return
      }
      payload.payer_phone = phone
    }
    if (isMobileMoney(paymentMethod)) {
      payload.status = 'PENDING'
    }

    setSubmitting(true)
    try {
      const payment = await onCreatePayment(payload)
      setCreatedPayment(payment)

      if (isMobileMoney(paymentMethod)) {
        const { data } = await api.post('/payments/payments/initiate-mobile/', {
          payment_id: payment.id,
          phone_number: payload.payer_phone,
          payment_method: paymentMethod,
        })
        setMobileMessage(data.message || 'Confirmez le paiement sur votre téléphone.')
        setStep('mobile_wait')
        setSubmitting(false)
        return
      }

      onSuccess()
    } catch (err: unknown) {
      const msg = (err as { response?: { data?: { error?: string } } })?.response?.data?.error
      toast.error(msg || 'Erreur lors de la création du paiement')
    }
    setSubmitting(false)
  }

  const handleConfirmMobile = async () => {
    if (!createdPayment) return
    setSubmitting(true)
    try {
      await api.post(`/payments/payments/${createdPayment.id}/confirm-mobile/`)
      toast.success('Paiement enregistré avec succès.')
      onSuccess()
    } catch (err: unknown) {
      const msg = (err as { response?: { data?: { error?: string } } })?.response?.data?.error
      toast.error(msg || 'Erreur lors de la confirmation')
    }
    setSubmitting(false)
  }

  const feeTypesList = Array.isArray(feeTypes) ? feeTypes : ((feeTypes as { results?: FeeTypeOption[] })?.results ?? [])

  if (step === 'mobile_wait') {
    return (
      <Card className="mb-6">
        <div className="flex items-center justify-between mb-4">
          <h2 className="text-xl font-semibold text-gray-900 dark:text-gray-100">Confirmation Mobile Money</h2>
          <button type="button" onClick={onCancel} className="p-2 hover:bg-gray-100 dark:hover:bg-gray-700 rounded-lg">
            <X className="w-5 h-5 text-gray-600 dark:text-gray-400" />
          </button>
        </div>
        <div className="flex flex-col items-center text-center space-y-4 py-4">
          <Smartphone className="w-12 h-12 text-primary-500" />
          <p className="text-gray-700 dark:text-gray-300">{mobileMessage}</p>
          <p className="text-sm text-gray-500 dark:text-gray-400">
            Référence : {createdPayment?.payment_id}
          </p>
          <button
            type="button"
            onClick={handleConfirmMobile}
            disabled={submitting}
            className="btn btn-primary flex items-center gap-2"
          >
            <CheckCircle className="w-4 h-4" />
            {submitting ? 'Enregistrement...' : "J'ai confirmé le paiement sur mon téléphone"}
          </button>
        </div>
      </Card>
    )
  }

  return (
    <Card className="mb-6">
      <div className="flex items-center justify-between mb-4">
        <h2 className="text-xl font-semibold text-gray-900 dark:text-gray-100">{title}</h2>
        <button
          type="button"
          onClick={onCancel}
          className="p-2 hover:bg-gray-100 dark:hover:bg-gray-700 rounded-lg"
        >
          <X className="w-5 h-5 text-gray-600 dark:text-gray-400" />
        </button>
      </div>
      <form onSubmit={handleSubmit} className="space-y-4">
        {mode === 'accountant' && (
          <div>
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
              Parent (payeur) *
            </label>
            <select
              name="user"
              required
              className="input w-full"
              value={selectedParentId}
              onChange={(e) => setSelectedParentId(e.target.value)}
            >
              <option value="">Sélectionner un parent</option>
              {parents.map((p) => (
                <option key={p.id} value={p.id}>
                  {[p?.first_name, p?.last_name, p?.middle_name].filter(Boolean).join(' ')} {p.email ? `(${p.email})` : ''}
                </option>
              ))}
            </select>
          </div>
        )}

        <div>
          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
            Enfant *
          </label>
          <select name="student" required className="input w-full">
            <option value="">
              {mode === 'accountant' ? 'Sélectionner un enfant (du parent choisi)' : 'Sélectionner un enfant'}
            </option>
            {mode === 'parent' &&
              children.map((child: ChildOption) => (
                <option key={child.identity.id} value={child.identity.id}>
                  {[child.identity.user?.first_name, child.identity.user?.last_name, child.identity.user?.middle_name].filter(Boolean).join(' ')} - {child.identity.student_id}
                </option>
              ))}
            {mode === 'accountant' &&
              (studentOptions as StudentOption[]).map((s) => (
                <option key={s.id} value={s.id}>
                  {[s.user?.first_name, s.user?.last_name, s.user?.middle_name].filter(Boolean).join(' ')} - {s.student_id}
                </option>
              ))}
          </select>
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
            Type de frais
          </label>
          <select
            name="fee_type"
            className="input w-full"
            onChange={(e) => {
              const selectedFee = feeTypesList.find((f: FeeTypeOption) => f.id === parseInt(e.target.value))
              if (selectedFee) {
                const amountInput = document.querySelector('input[name="amount"]') as HTMLInputElement
                if (amountInput) amountInput.value = String(selectedFee.amount)
              }
            }}
          >
            <option value="">Sélectionner un type de frais (optionnel)</option>
            {feeTypesList.map((fee: FeeTypeOption) => (
              <option key={fee.id} value={fee.id}>
                {fee.name} - {fee.amount} {fee.currency}
              </option>
            ))}
          </select>
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
            Montant *
          </label>
          <input
            type="number"
            name="amount"
            step="0.01"
            required
            className="input w-full"
            placeholder="0.00"
          />
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
            Devise *
          </label>
          <select name="currency" required className="input w-full">
            <option value="CDF">CDF</option>
            <option value="USD">USD</option>
            <option value="EUR">EUR</option>
          </select>
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
            Méthode de paiement *
          </label>
          <select
            name="payment_method"
            required
            className="input w-full"
            value={selectedMethod}
            onChange={(e) => setSelectedMethod(e.target.value)}
          >
            <option value="">Sélectionner une méthode</option>
            {PAYMENT_METHODS.map((m) => (
              <option key={m.value} value={m.value}>
                {m.label}
              </option>
            ))}
          </select>
        </div>

        {isMobileMoney(selectedMethod) && (
          <div>
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
              Téléphone du payeur *
            </label>
            <input
              type="tel"
              name="payer_phone"
              className="input w-full"
              placeholder="+243 XXX XXX XXX"
              required={isMobileMoney(selectedMethod)}
            />
          </div>
        )}

        <div>
          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
            Numéro de référence
          </label>
          <input
            type="text"
            name="reference_number"
            className="input w-full"
            placeholder="Numéro de transaction (optionnel)"
          />
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
            Description
          </label>
          <textarea
            name="description"
            rows={3}
            className="input w-full"
            placeholder="Description du paiement (optionnel)"
          />
        </div>

        {mode === 'accountant' && (
          <>
            <div>
              <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
                Statut
              </label>
              <select name="status" className="input w-full">
                <option value="COMPLETED">Complété (avec reçu)</option>
                <option value="PENDING">En attente</option>
              </select>
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
                Année scolaire
              </label>
              <input
                type="text"
                name="academic_year"
                className="input w-full"
                placeholder="ex. 2025-2026"
                defaultValue={`${new Date().getFullYear()}-${new Date().getFullYear() + 1}`}
              />
            </div>
          </>
        )}

        <div className="flex space-x-3">
          <button type="submit" disabled={isPending || submitting} className="btn btn-primary">
            {submitting ? 'Création...' : 'Créer le paiement'}
          </button>
          <button type="button" onClick={onCancel} className="btn btn-secondary">
            Annuler
          </button>
        </div>
      </form>
    </Card>
  )
}
