import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { useForm } from 'react-hook-form'
import { z } from 'zod'
import { zodResolver } from '@hookform/resolvers/zod'
import api from '@/services/api'
import { Card } from '@/components/ui/Card'
import { useAcademicYears } from '@/hooks/useAcademicYears'
import { useAuthStore } from '@/store/authStore'
import { showError, showSuccess } from '@/utils/notifications'
import { Users, Plus, Calendar as CalendarIcon } from 'lucide-react'
import { format } from 'date-fns'
import { fr } from 'date-fns/locale'

const enrollmentSchema = z.object({
  first_name: z.string().min(1, 'Le prénom est requis'),
  last_name: z.string().min(1, 'Le nom est requis'),
  middle_name: z.string().optional(),
  date_of_birth: z.string().min(1, 'La date de naissance est requise'),
  gender: z.enum(['M', 'F'], { required_error: 'Le genre est requis' }),
  place_of_birth: z.string().min(1, 'Le lieu de naissance est requis'),
  phone: z.string().optional(),
  email: z.string().email('Email invalide').optional().or(z.literal('')),
  // Adresse structurée de l'élève
  address_number: z.string().optional(),
  address_avenue: z.string().optional(),
  address_quarter: z.string().optional(),
  address_commune: z.string().optional(),
  address_city: z.string().min(1, 'La ville est requise'),
  address_province: z.string().min(1, 'La province est requise'),
  address_country: z.string().min(1, 'Le pays est requis'),
  // Champ libre (optionnel) – reconstruit côté frontend
  address: z.string().optional(),
  academic_year: z.string().min(1, "L'année scolaire est requise"),
  requested_class: z.number().optional(),
  previous_school: z.string().optional(),
  parent_name: z.string().min(1, 'Le nom du parent est requis'),
  mother_name: z.string().optional(),
  parent_phone: z.string().min(1, 'Le téléphone du parent est requis'),
  parent_email: z.string().email('Email invalide').optional().or(z.literal('')),
  parent_profession: z.string().optional(),
  // Adresse structurée du parent
  parent_address_number: z.string().optional(),
  parent_address_avenue: z.string().optional(),
  parent_address_quarter: z.string().optional(),
  parent_address_commune: z.string().optional(),
  parent_address_city: z.string().optional(),
  parent_address_province: z.string().optional(),
  parent_address_country: z.string().optional(),
  parent_address: z.string().optional(),
})

type EnrollmentForm = z.infer<typeof enrollmentSchema>

export default function ParentEnrollments() {
  const queryClient = useQueryClient()
  const { user } = useAuthStore()
  const { years: academicYears, current: currentAcademicYear } = useAcademicYears()

  const {
    register,
    handleSubmit,
    formState: { errors },
    reset,
  } = useForm<EnrollmentForm>({
    resolver: zodResolver(enrollmentSchema),
    defaultValues: {
      parent_name: `${user?.first_name ?? ''} ${user?.last_name ?? ''}`.trim() || '',
      parent_phone: user?.phone ?? '',
      parent_email: user?.email ?? '',
      parent_address_city: user?.school?.city ?? '',
      parent_address_country: user?.school?.country ?? 'RDC',
    },
  })

  const { data: classesData } = useQuery({
    queryKey: ['school-classes'],
    queryFn: async () => {
      const res = await api.get('/schools/classes/')
      return res.data
    },
  })

  const classes = Array.isArray(classesData) ? classesData : (classesData?.results ?? [])

  const { data: applicationsData, isLoading } = useQuery({
    queryKey: ['parent-enrollment-applications'],
    queryFn: async () => {
      const res = await api.get('/enrollment/applications/')
      return res.data
    },
  })

  const applications = Array.isArray(applicationsData)
    ? applicationsData
    : (applicationsData?.results ?? [])

  const createMutation = useMutation({
    mutationFn: async (data: EnrollmentForm) => {
      const formData = new FormData()
      Object.entries(data).forEach(([key, value]) => {
        if (value !== undefined && value !== null && value !== '') {
          formData.append(key, String(value))
        }
      })
      return api.post('/enrollment/applications/', formData, {
        headers: { 'Content-Type': 'multipart/form-data' },
      })
    },
    onSuccess: () => {
      showSuccess("Demande d'inscription envoyée à l'école.")
      queryClient.invalidateQueries({ queryKey: ['parent-enrollment-applications'] })
      reset()
    },
    onError: (error: any) => {
      const data = error?.response?.data
      const msg =
        data?.detail ||
        data?.non_field_errors?.join(', ') ||
        'Erreur lors de la création de la demande.'
      showError(msg)
    },
  })

  const onSubmit = (form: EnrollmentForm) => {
    // Reconstruire les champs adresse libres à partir des morceaux structurés
    const addressParts = [
      form.address_number ? `N° ${form.address_number}` : '',
      form.address_avenue ? `Av. ${form.address_avenue}` : '',
      form.address_quarter ? `Q. ${form.address_quarter}` : '',
      form.address_commune ? `C. ${form.address_commune}` : '',
      form.address_city,
      form.address_province,
      form.address_country,
    ].filter(Boolean)

    const parentAddressParts = [
      form.parent_address_number ? `N° ${form.parent_address_number}` : '',
      form.parent_address_avenue ? `Av. ${form.parent_address_avenue}` : '',
      form.parent_address_quarter ? `Q. ${form.parent_address_quarter}` : '',
      form.parent_address_commune ? `C. ${form.parent_address_commune}` : '',
      form.parent_address_city,
      form.parent_address_province,
      form.parent_address_country,
    ].filter(Boolean)

    const payload: EnrollmentForm = {
      ...form,
      address: addressParts.join(', '),
      parent_address: parentAddressParts.join(', '),
    }

    createMutation.mutate({
      ...payload,
      requested_class: payload.requested_class ? Number(payload.requested_class) : undefined,
    })
  }

  return (
    <div>
      <h1 className="text-2xl sm:text-3xl font-bold text-gray-900 dark:text-white mb-2 flex items-center gap-2">
        <Users className="w-7 h-7" />
        Inscriptions de mes enfants
      </h1>
      <p className="text-gray-600 dark:text-gray-400 mb-6">
        Vous pouvez enregistrer une demande d&apos;inscription pour vos enfants. L&apos;école
        analysera et approuvera la demande avant de créer le dossier élève.
      </p>

      {/* Formulaire d'inscription */}
      <Card className="mb-8 p-4 sm:p-6">
        <h2 className="text-lg font-semibold text-gray-900 dark:text-white mb-4 flex items-center gap-2">
          <Plus className="w-5 h-5" />
          Nouvelle demande d&apos;inscription
        </h2>
        <form onSubmit={handleSubmit(onSubmit)} className="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div>
            <label className="label">Prénom de l&apos;élève *</label>
            <input className="input" {...register('first_name')} />
            {errors.first_name && <p className="text-sm text-red-500">{errors.first_name.message}</p>}
          </div>
          <div>
            <label className="label">Nom de famille *</label>
            <input className="input" {...register('last_name')} />
            {errors.last_name && <p className="text-sm text-red-500">{errors.last_name.message}</p>}
          </div>
          <div>
            <label className="label">Post-nom</label>
            <input className="input" {...register('middle_name')} />
          </div>
          <div>
            <label className="label">Date de naissance *</label>
            <input type="date" className="input" {...register('date_of_birth')} />
            {errors.date_of_birth && (
              <p className="text-sm text-red-500">{errors.date_of_birth.message}</p>
            )}
          </div>
          <div>
            <label className="label">Genre *</label>
            <select className="input" {...register('gender')}>
              <option value="">Sélectionner</option>
              <option value="M">Garçon</option>
              <option value="F">Fille</option>
            </select>
            {errors.gender && <p className="text-sm text-red-500">{errors.gender.message}</p>}
          </div>
          <div>
            <label className="label">Lieu de naissance *</label>
            <input className="input" {...register('place_of_birth')} />
            {errors.place_of_birth && (
              <p className="text-sm text-red-500">{errors.place_of_birth.message}</p>
            )}
          </div>
          <div>
            <label className="label">Téléphone de l&apos;élève</label>
            <input className="input" {...register('phone')} />
          </div>
          <div>
            <label className="label">Email de l&apos;élève</label>
            <input className="input" {...register('email')} />
            {errors.email && <p className="text-sm text-red-500">{errors.email.message}</p>}
          </div>
          <div className="md:col-span-2">
            <label className="label">Adresse de l&apos;élève</label>
            <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
              <div>
                <label className="label text-xs">Numéro</label>
                <input className="input" {...register('address_number')} />
              </div>
              <div>
                <label className="label text-xs">Avenue</label>
                <input className="input" {...register('address_avenue')} />
              </div>
              <div>
                <label className="label text-xs">Quartier</label>
                <input className="input" {...register('address_quarter')} />
              </div>
              <div>
                <label className="label text-xs">Commune</label>
                <input className="input" {...register('address_commune')} />
              </div>
              <div>
                <label className="label text-xs">Ville *</label>
                <input className="input" {...register('address_city')} />
                {errors.address_city && (
                  <p className="text-sm text-red-500">{errors.address_city.message}</p>
                )}
              </div>
              <div>
                <label className="label text-xs">Province *</label>
                <input className="input" {...register('address_province')} />
                {errors.address_province && (
                  <p className="text-sm text-red-500">{errors.address_province.message}</p>
                )}
              </div>
              <div>
                <label className="label text-xs">Pays *</label>
                <input className="input" {...register('address_country')} />
                {errors.address_country && (
                  <p className="text-sm text-red-500">{errors.address_country.message}</p>
                )}
              </div>
            </div>
          </div>
          <div>
            <label className="label">Année scolaire *</label>
            <select className="input" {...register('academic_year')}>
              <option value="">
                {currentAcademicYear ? `Sélectionner (par ex. ${currentAcademicYear})` : 'Sélectionner'}
              </option>
              {academicYears.map((y) => (
                <option key={y} value={y}>
                  {y}
                </option>
              ))}
            </select>
            {errors.academic_year && (
              <p className="text-sm text-red-500">{errors.academic_year.message}</p>
            )}
          </div>
          <div>
            <label className="label">Classe demandée</label>
            <select className="input" {...register('requested_class', { valueAsNumber: true })}>
              <option value="">Sélectionner</option>
              {classes.map((c: any) => (
                <option key={c.id} value={c.id}>
                  {c.name} {c.academic_year ? `(${c.academic_year})` : ''}
                </option>
              ))}
            </select>
          </div>
          <div className="md:col-span-2">
            <label className="label">École précédente</label>
            <input className="input" {...register('previous_school')} />
          </div>

          {/* Infos parent */}
          <div className="md:col-span-2 mt-4 border-t border-gray-200 dark:border-gray-700 pt-4">
            <h3 className="text-sm font-semibold text-gray-900 dark:text-gray-100 mb-2">
              Informations du parent / tuteur
            </h3>
          </div>
          <div>
            <label className="label">Nom complet du parent *</label>
            <input className="input" {...register('parent_name')} />
            {errors.parent_name && (
              <p className="text-sm text-red-500">{errors.parent_name.message}</p>
            )}
          </div>
          <div>
            <label className="label">Nom de la mère</label>
            <input className="input" {...register('mother_name')} />
          </div>
          <div>
            <label className="label">Téléphone du parent *</label>
            <input className="input" {...register('parent_phone')} />
            {errors.parent_phone && (
              <p className="text-sm text-red-500">{errors.parent_phone.message}</p>
            )}
          </div>
          <div>
            <label className="label">Email du parent</label>
            <input className="input" {...register('parent_email')} />
            {errors.parent_email && (
              <p className="text-sm text-red-500">{errors.parent_email.message}</p>
            )}
          </div>
          <div>
            <label className="label">Profession du parent</label>
            <input className="input" {...register('parent_profession')} />
          </div>
          <div className="md:col-span-2">
            <label className="label">Adresse du parent</label>
            <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
              <div>
                <label className="label text-xs">Numéro</label>
                <input className="input" {...register('parent_address_number')} />
              </div>
              <div>
                <label className="label text-xs">Avenue</label>
                <input className="input" {...register('parent_address_avenue')} />
              </div>
              <div>
                <label className="label text-xs">Quartier</label>
                <input className="input" {...register('parent_address_quarter')} />
              </div>
              <div>
                <label className="label text-xs">Commune</label>
                <input className="input" {...register('parent_address_commune')} />
              </div>
              <div>
                <label className="label text-xs">Ville</label>
                <input className="input" {...register('parent_address_city')} />
              </div>
              <div>
                <label className="label text-xs">Province</label>
                <input className="input" {...register('parent_address_province')} />
              </div>
              <div>
                <label className="label text-xs">Pays</label>
                <input className="input" {...register('parent_address_country')} />
              </div>
            </div>
          </div>

          <div className="md:col-span-2 flex justify-end mt-2">
            <button
              type="submit"
              disabled={createMutation.isPending}
              className="btn btn-primary flex items-center gap-2"
            >
              <Plus className="w-4 h-4" />
              {createMutation.isPending ? 'Envoi...' : 'Envoyer la demande'}
            </button>
          </div>
        </form>
      </Card>

      {/* Liste des demandes du parent */}
      <Card className="p-4 sm:p-6">
        <h2 className="text-lg font-semibold text-gray-900 dark:text-white mb-4 flex items-center gap-2">
          <CalendarIcon className="w-5 h-5" />
          Mes demandes d&apos;inscription
        </h2>
        {isLoading ? (
          <div className="py-8 text-center text-gray-500 dark:text-gray-400">Chargement...</div>
        ) : applications.length === 0 ? (
          <div className="py-8 text-center text-gray-500 dark:text-gray-400">
            Aucune demande d&apos;inscription pour le moment.
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="bg-gray-50 dark:bg-gray-800">
                <tr>
                  <th className="px-3 py-2 text-left">Élève</th>
                  <th className="px-3 py-2 text-left">Classe demandée</th>
                  <th className="px-3 py-2 text-left">Année scolaire</th>
                  <th className="px-3 py-2 text-left">Statut</th>
                  <th className="px-3 py-2 text-left">Soumise le</th>
                </tr>
              </thead>
              <tbody>
                {applications.map((a: any) => (
                  <tr key={a.id} className="border-b border-gray-100 dark:border-gray-700">
                    <td className="px-3 py-2">
                      {[a.first_name, a.last_name, a.middle_name].filter(Boolean).join(' ')}
                    </td>
                    <td className="px-3 py-2">
                      {a.requested_class_name || a.requested_class?.name || '-'}
                    </td>
                    <td className="px-3 py-2">{a.academic_year || '-'}</td>
                    <td className="px-3 py-2">
                      <span
                        className={
                          a.status === 'APPROVED'
                            ? 'text-green-600'
                            : a.status === 'REJECTED'
                            ? 'text-red-600'
                            : 'text-amber-600'
                        }
                      >
                        {a.status === 'PENDING'
                          ? 'En attente'
                          : a.status === 'APPROVED'
                          ? 'Approuvée'
                          : a.status === 'REJECTED'
                          ? 'Rejetée'
                          : a.status}
                      </span>
                    </td>
                    <td className="px-3 py-2">
                      {a.created_at
                        ? format(new Date(a.created_at), 'dd MMM yyyy', { locale: fr })
                        : '-'}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Card>
    </div>
  )
}

