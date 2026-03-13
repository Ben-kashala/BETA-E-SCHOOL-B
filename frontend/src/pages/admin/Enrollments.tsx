import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { useState, useRef, useEffect } from 'react'
import api from '@/services/api'
import { useAuthStore } from '@/store/authStore'
import { showErrorToast, showSuccessToast } from '@/utils/toast'
import { Check, X, Eye, Plus, Camera, Upload, X as XIcon, Edit2, Save, Search, Calendar } from 'lucide-react'
import { Card } from '@/components/ui/Card'
import { useAcademicYears } from '@/hooks/useAcademicYears'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'

const enrollmentSchema = z.object({
  first_name: z.string().min(1, 'Le prénom est requis'),
  last_name: z.string().min(1, 'Le nom est requis'),
  middle_name: z.string().optional(),
  date_of_birth: z.string().min(1, 'La date de naissance est requise'),
  gender: z.enum(['M', 'F'], { required_error: 'Le genre est requis' }),
  place_of_birth: z.string().min(1, 'Le lieu de naissance est requis'),
  phone: z.string().optional(),
  email: z.string().email('Email invalide').optional().or(z.literal('')),
  address: z.string().min(1, 'L\'adresse est requise'),
  academic_year: z.string().min(1, 'L\'année scolaire est requise'),
  requested_class: z.number().optional(),
  previous_school: z.string().optional(),
  parent_name: z.string().min(1, 'Le nom du parent est requis'),
  mother_name: z.string().optional(),
  parent_phone: z.string().min(1, 'Le téléphone du parent est requis'),
  parent_email: z.string().email('Email invalide').optional().or(z.literal('')),
  parent_profession: z.string().optional(),
  parent_address: z.string().optional(),
  photo: z.instanceof(File).optional(),
})

type EnrollmentForm = z.infer<typeof enrollmentSchema>

/** Nom complet élève / demande : first_name + last_name + middle_name */
function enrollmentFullName(app: { first_name?: string; last_name?: string; middle_name?: string | null }) {
  return [app.first_name, app.last_name, app.middle_name].filter(Boolean).join(' ')
}

export default function AdminEnrollments() {
  const { user } = useAuthStore()
  const canApproveReject = user?.role !== 'ACCOUNTANT'
  const [selectedId, setSelectedId] = useState<number | null>(null)
  const [showForm, setShowForm] = useState(false)
  const [showDetailsModal, setShowDetailsModal] = useState(false)
  const [isEditing, setIsEditing] = useState(false)
  const [selectedApplication, setSelectedApplication] = useState<any>(null)
  const [photoPreview, setPhotoPreview] = useState<string | null>(null)
  const [editPhotoPreview, setEditPhotoPreview] = useState<string | null>(null)
  const [showCamera, setShowCamera] = useState(false)
  const [showEditCamera, setShowEditCamera] = useState(false)
  const [searchQuery, setSearchQuery] = useState<string>('')
  const [enrollmentDateFilter, setEnrollmentDateFilter] = useState<string>('')
  const videoRef = useRef<HTMLVideoElement>(null)
  const editVideoRef = useRef<HTMLVideoElement>(null)
  const streamRef = useRef<MediaStream | null>(null)
  const editStreamRef = useRef<MediaStream | null>(null)
  const fileInputRef = useRef<HTMLInputElement>(null)
  const cameraInputRef = useRef<HTMLInputElement>(null)
  const editFileInputRef = useRef<HTMLInputElement>(null)
  const editCameraInputRef = useRef<HTMLInputElement>(null)
  const queryClient = useQueryClient()
  const { years: academicYears, current: currentAcademicYear } = useAcademicYears()
  
  const { register, handleSubmit, formState: { errors }, reset, setValue } = useForm<EnrollmentForm>({
    resolver: zodResolver(enrollmentSchema),
  })

  // Form for editing
  const { register: registerEdit, handleSubmit: handleSubmitEdit, formState: { errors: errorsEdit }, reset: resetEdit, setValue: setValueEdit } = useForm<EnrollmentForm>({
    resolver: zodResolver(enrollmentSchema),
  })
  const [lastParentData, setLastParentData] = useState<Pick<EnrollmentForm, 'parent_name' | 'mother_name' | 'parent_phone' | 'parent_email' | 'parent_profession' | 'parent_address'> | null>(null)
  

  // Cleanup camera on unmount
  useEffect(() => {
    return () => {
      if (streamRef.current) {
        streamRef.current.getTracks().forEach(track => track.stop())
      }
      if (editStreamRef.current) {
        editStreamRef.current.getTracks().forEach(track => track.stop())
      }
    }
  }, [])

  const { data: applications, isLoading } = useQuery({
    queryKey: ['enrollment-applications'],
    queryFn: async () => {
      const response = await api.get('/enrollment/applications/')
      return response.data
    },
  })

  // Fetch application details when selectedId changes
  const { data: applicationDetails } = useQuery({
    queryKey: ['enrollment-application', selectedId],
    queryFn: async () => {
      if (!selectedId) return null
      const response = await api.get(`/enrollment/applications/${selectedId}/`)
      return response.data
    },
    enabled: !!selectedId && showDetailsModal,
  })

  const { data: classes, isLoading: classesLoading, error: classesError } = useQuery({
    queryKey: ['school-classes'],
    queryFn: async () => {
      try {
        const response = await api.get('/schools/classes/')
        // La réponse peut être paginée (results) ou une liste directe
        return response.data
      } catch (error: any) {
        console.error('Erreur lors du chargement des classes:', error)
        throw error
      }
    },
  })

  const createMutation = useMutation({
    mutationFn: async (data: EnrollmentForm) => {
      const formData = new FormData()
      
      // Add all form fields to FormData
      Object.keys(data).forEach((key) => {
        if (key === 'photo' && data.photo) {
          formData.append('photo', data.photo)
        } else if (key !== 'photo' && data[key as keyof EnrollmentForm] !== undefined && data[key as keyof EnrollmentForm] !== null) {
          formData.append(key, String(data[key as keyof EnrollmentForm]))
        }
      })
      
      return api.post('/enrollment/applications/', formData, {
        headers: {
          'Content-Type': 'multipart/form-data',
        },
      })
    },
    onSuccess: (_data, variables) => {
      queryClient.invalidateQueries({ queryKey: ['enrollment-applications'] })
      showSuccessToast('Demande d\'inscription créée avec succès')
      // Proposer d'inscrire un autre élève pour le même parent
      if (variables) {
        const parentBlock: Pick<EnrollmentForm, 'parent_name' | 'mother_name' | 'parent_phone' | 'parent_email' | 'parent_profession' | 'parent_address'> = {
          parent_name: variables.parent_name,
          mother_name: variables.mother_name,
          parent_phone: variables.parent_phone,
          parent_email: variables.parent_email,
          parent_profession: variables.parent_profession,
          parent_address: variables.parent_address,
        }
        setLastParentData(parentBlock)
      }
      const wantsAnother = window.confirm('Voulez-vous inscrire un autre élève pour le même parent ?')
      if (wantsAnother && lastParentData) {
        // Réinitialiser uniquement les informations de l\'élève, conserver les infos du parent
        reset({
          first_name: '',
          last_name: '',
          middle_name: '',
          date_of_birth: '',
          gender: 'M',
          place_of_birth: '',
          phone: '',
          email: '',
          address: '',
          academic_year: '',
          requested_class: undefined,
          previous_school: '',
          photo: undefined,
          parent_name: lastParentData.parent_name,
          mother_name: lastParentData.mother_name,
          parent_phone: lastParentData.parent_phone,
          parent_email: lastParentData.parent_email,
          parent_profession: lastParentData.parent_profession,
          parent_address: lastParentData.parent_address,
        })
        setPhotoPreview(null)
        setShowCamera(false)
        stopCamera()
      } else {
        setShowForm(false)
        setPhotoPreview(null)
        setShowCamera(false)
        stopCamera()
        reset()
      }
    },
    onError: (error: any) => {
      showErrorToast(error, 'Erreur lors de la création de la demande d\'inscription')
    },
  })

  const onSubmit = (data: EnrollmentForm) => {
    const currentYear = new Date().getFullYear()
    const fullAddress = [
      data.address, // champ texte existant (au cas où)
    ]
      .filter(Boolean)
      .join(' ')

    createMutation.mutate({
      ...data,
      address: fullAddress,
      academic_year:
        data.academic_year ||
        currentAcademicYear ||
        `${currentYear}-${currentYear + 1}`,
    })
  }

  // Handle photo file selection
  const handlePhotoChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    if (file) {
      setValue('photo', file)
      const reader = new FileReader()
      reader.onloadend = () => {
        setPhotoPreview(reader.result as string)
      }
      reader.readAsDataURL(file)
    }
  }

  // Handle camera capture
  const startCamera = async () => {
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ video: true })
      streamRef.current = stream
      if (videoRef.current) {
        videoRef.current.srcObject = stream
        setShowCamera(true)
      }
    } catch (error) {
      showErrorToast({ message: 'Impossible d\'accéder à la caméra' }, 'Erreur d\'accès à la caméra')
    }
  }

  const stopCamera = () => {
    if (streamRef.current) {
      streamRef.current.getTracks().forEach(track => track.stop())
      streamRef.current = null
    }
    setShowCamera(false)
  }

  const capturePhoto = () => {
    if (videoRef.current) {
      const canvas = document.createElement('canvas')
      canvas.width = videoRef.current.videoWidth
      canvas.height = videoRef.current.videoHeight
      const ctx = canvas.getContext('2d')
      if (ctx) {
        ctx.drawImage(videoRef.current, 0, 0)
        canvas.toBlob((blob) => {
          if (blob) {
            const file = new File([blob], 'photo.jpg', { type: 'image/jpeg' })
            setValue('photo', file)
            setPhotoPreview(URL.createObjectURL(blob))
            stopCamera()
          }
        }, 'image/jpeg', 0.9)
      }
    }
  }

  // Handle edit camera capture
  const startEditCamera = async () => {
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ video: true })
      editStreamRef.current = stream
      if (editVideoRef.current) {
        editVideoRef.current.srcObject = stream
        setShowEditCamera(true)
      }
    } catch (error) {
      showErrorToast({ message: 'Impossible d\'accéder à la caméra' }, 'Erreur d\'accès à la caméra')
    }
  }

  const stopEditCamera = () => {
    if (editStreamRef.current) {
      editStreamRef.current.getTracks().forEach(track => track.stop())
      editStreamRef.current = null
    }
    setShowEditCamera(false)
  }

  const captureEditPhoto = () => {
    if (editVideoRef.current) {
      const canvas = document.createElement('canvas')
      canvas.width = editVideoRef.current.videoWidth
      canvas.height = editVideoRef.current.videoHeight
      const ctx = canvas.getContext('2d')
      if (ctx) {
        ctx.drawImage(editVideoRef.current, 0, 0)
        canvas.toBlob((blob) => {
          if (blob) {
            const file = new File([blob], 'photo.jpg', { type: 'image/jpeg' })
            setValueEdit('photo', file)
            setEditPhotoPreview(URL.createObjectURL(blob))
            stopEditCamera()
          }
        }, 'image/jpeg', 0.9)
      }
    }
  }

  const handleEditPhotoChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    if (file) {
      setValueEdit('photo', file)
      const reader = new FileReader()
      reader.onloadend = () => {
        setEditPhotoPreview(reader.result as string)
      }
      reader.readAsDataURL(file)
    }
  }

  // Handle view details
  const handleViewDetails = (app: any) => {
    setSelectedApplication(app)
    setSelectedId(app.id)
    setShowDetailsModal(true)
    setIsEditing(false)
  }

  // Handle edit mode
  const handleEdit = (app: any) => {
    setIsEditing(true)
    // Pre-fill form with existing data
    const dateOfBirth = app.date_of_birth ? new Date(app.date_of_birth).toISOString().split('T')[0] : ''
    resetEdit({
      first_name: app.first_name || '',
      last_name: app.last_name || '',
      middle_name: app.middle_name || '',
      date_of_birth: dateOfBirth,
      gender: app.gender || 'M',
      place_of_birth: app.place_of_birth || '',
      phone: app.phone || '',
      email: app.email || '',
      address: app.address || '',
      academic_year: app.academic_year || '',
      requested_class: app.requested_class || undefined,
      previous_school: app.previous_school || '',
      parent_name: app.parent_name || '',
      mother_name: app.mother_name || '',
      parent_phone: app.parent_phone || '',
      parent_email: app.parent_email || '',
      parent_profession: app.parent_profession || '',
      parent_address: app.parent_address || '',
    })
    if (app.photo) {
      setEditPhotoPreview(app.photo)
    }
  }

  const handleCancelEdit = () => {
    setIsEditing(false)
    setEditPhotoPreview(null)
    setShowEditCamera(false)
    stopEditCamera()
    resetEdit()
  }

  const approveMutation = useMutation({
    mutationFn: ({ id, confirmDuplicate }: { id: number; confirmDuplicate?: boolean }) =>
      api.post(`/enrollment/applications/${id}/approve/`, confirmDuplicate ? { confirm_duplicate: true } : {}),
    onSuccess: (res: any) => {
      queryClient.invalidateQueries({ queryKey: ['enrollment-applications'] })
      const data = res?.data || {}
      let message = 'Inscription approuvée avec succès'
      if (data.parent_username && data.parent_created) {
        message += `. Compte parent créé : ${data.parent_username} (mot de passe : Prénom+Nom@)`
      } else if (data.parent_username) {
        message += `. Parent associé : ${data.parent_username}`
      }
      showSuccessToast(message)
      setSelectedId(null)
    },
    onError: (error: any, variables) => {
      const response = error?.response
      const data = response?.data
      if (data?.code === 'duplicate_student' && variables?.id) {
        const confirm = window.confirm(
          `${data.detail || 'Un élève avec le même nom existe déjà dans cette classe.'}\n` +
          'Cliquez sur "OK" pour confirmer malgré tout, ou sur "Annuler" pour modifier les informations.'
        )
        if (confirm) {
          approveMutation.mutate({ id: variables.id, confirmDuplicate: true })
          return
        }
      }
      showErrorToast(error, 'Erreur lors de l\'approbation de l\'inscription')
    },
  })

  const rejectMutation = useMutation({
    mutationFn: ({ id, notes }: { id: number; notes: string }) =>
      api.post(`/enrollment/applications/${id}/reject/`, { notes }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['enrollment-applications'] })
      queryClient.invalidateQueries({ queryKey: ['enrollment-application', selectedId] })
      showSuccessToast('Inscription rejetée')
      setSelectedId(null)
    },
    onError: (error: any) => {
      showErrorToast(error, 'Erreur lors du rejet de l\'inscription')
    },
  })

  const updateMutation = useMutation({
    mutationFn: async ({ id, data }: { id: number; data: EnrollmentForm }) => {
      const formData = new FormData()
      
      // Add all form fields to FormData
      Object.keys(data).forEach((key) => {
        if (key === 'photo' && data.photo) {
          formData.append('photo', data.photo)
        } else if (key !== 'photo' && data[key as keyof EnrollmentForm] !== undefined && data[key as keyof EnrollmentForm] !== null) {
          formData.append(key, String(data[key as keyof EnrollmentForm]))
        }
      })
      
      return api.patch(`/enrollment/applications/${id}/`, formData, {
        headers: {
          'Content-Type': 'multipart/form-data',
        },
      })
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['enrollment-applications'] })
      queryClient.invalidateQueries({ queryKey: ['enrollment-application', selectedId] })
      showSuccessToast('Inscription mise à jour avec succès')
      setIsEditing(false)
      setEditPhotoPreview(null)
      setShowEditCamera(false)
      stopEditCamera()
    },
    onError: (error: any) => {
      showErrorToast(error, 'Erreur lors de la mise à jour de l\'inscription')
    },
  })

  const onEditSubmit = (data: EnrollmentForm) => {
    if (!selectedId) return
    updateMutation.mutate({ id: selectedId, data })
  }

  // Filtrer les inscriptions selon la recherche et la date
  const filteredApplications = applications?.results?.filter((app: any) => {
    // Filtre par date d'inscription
    if (enrollmentDateFilter) {
      const appDate = new Date(app.created_at).toISOString().split('T')[0]
      if (appDate !== enrollmentDateFilter) {
        return false
      }
    }
    
    // Filtre par recherche (ID, Nom, Classe)
    if (!searchQuery) return true
    const query = searchQuery.toLowerCase()
    const studentId = app.generated_student_id?.toLowerCase() || ''
    const firstName = app.first_name?.toLowerCase() || ''
    const lastName = app.last_name?.toLowerCase() || ''
    const fullName = `${firstName} ${lastName}`.toLowerCase()
    const className = app.requested_class_name?.toLowerCase() || ''
    
    return studentId.includes(query) || 
           firstName.includes(query) || 
           lastName.includes(query) ||
           fullName.includes(query) ||
           className.includes(query)
  }) || []

  const getStatusBadge = (status: string) => {
    const badges: Record<string, string> = {
      PENDING: 'badge-warning',
      APPROVED: 'badge-success',
      REJECTED: 'badge-danger',
      COMPLETED: 'badge-info',
    }
    return badges[status] || 'badge-info'
  }

  const getStatusLabel = (status: string) => {
    const labels: Record<string, string> = {
      PENDING: 'En attente',
      APPROVED: 'Approuvée',
      REJECTED: 'Rejetée',
      COMPLETED: 'Complétée',
    }
    return labels[status] || status
  }

  if (isLoading) {
    return <div className="text-center py-12">Chargement...</div>
  }

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <h1 className="text-3xl font-bold text-gray-900">Gestion des Inscriptions</h1>
        <button
          onClick={() => setShowForm(!showForm)}
          className="btn btn-primary flex items-center gap-2"
        >
          <Plus className="w-5 h-5" />
          Nouvelle inscription
        </button>
      </div>

      {showForm && (
        <Card className="mb-6">
          <h2 className="text-xl font-semibold mb-4">Nouvelle inscription</h2>
          <form onSubmit={handleSubmit(onSubmit)} className="space-y-4">
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  Prénom <span className="text-red-500">*</span>
                </label>
                <input
                  {...register('first_name')}
                  className="input"
                  placeholder="Prénom"
                />
                {errors.first_name && (
                  <p className="mt-1 text-sm text-red-600">{errors.first_name.message}</p>
                )}
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  Nom <span className="text-red-500">*</span>
                </label>
                <input
                  {...register('last_name')}
                  className="input"
                  placeholder="Nom"
                />
                {errors.last_name && (
                  <p className="mt-1 text-sm text-red-600">{errors.last_name.message}</p>
                )}
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  Postnom
                </label>
                <input
                  {...register('middle_name')}
                  className="input"
                  placeholder="Postnom"
                />
                {errors.middle_name && (
                  <p className="mt-1 text-sm text-red-600">{errors.middle_name.message}</p>
                )}
              </div>
              
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  Date de naissance <span className="text-red-500">*</span>
                </label>
                <input
                  {...register('date_of_birth')}
                  type="date"
                  className="input focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                  max={new Date().toISOString().split('T')[0]}
                  title="Sélectionnez la date de naissance"
                />
                {errors.date_of_birth && (
                  <p className="mt-1 text-sm text-red-600">{errors.date_of_birth.message}</p>
                )}
                <p className="mt-1 text-xs text-gray-500">Format: JJ/MM/AAAA</p>
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  Genre <span className="text-red-500">*</span>
                </label>
                <select {...register('gender')} className="input">
                  <option value="">Sélectionner</option>
                  <option value="M">Masculin</option>
                  <option value="F">Féminin</option>
                </select>
                {errors.gender && (
                  <p className="mt-1 text-sm text-red-600">{errors.gender.message}</p>
                )}
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  Lieu de naissance <span className="text-red-500">*</span>
                </label>
                <input
                  {...register('place_of_birth')}
                  className="input"
                  placeholder="Lieu de naissance"
                />
                {errors.place_of_birth && (
                  <p className="mt-1 text-sm text-red-600">{errors.place_of_birth.message}</p>
                )}
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  Téléphone
                </label>
                <input
                  {...register('phone')}
                  className="input"
                  placeholder="Téléphone"
                />
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  Email
                </label>
                <input
                  {...register('email')}
                  type="email"
                  className="input"
                  placeholder="Email"
                />
                {errors.email && (
                  <p className="mt-1 text-sm text-red-600">{errors.email.message}</p>
                )}
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  Année scolaire <span className="text-red-500">*</span>
                </label>
                {academicYears.length > 0 ? (
                  <select {...register('academic_year')} className="input">
                    <option value="">
                      {currentAcademicYear
                        ? `Sélectionner (par défaut ${currentAcademicYear})`
                        : 'Sélectionner une année'}
                    </option>
                    {academicYears.map((year) => (
                      <option key={year} value={year}>
                        {year}
                      </option>
                    ))}
                  </select>
                ) : (
                  <input
                    {...register('academic_year')}
                    className="input"
                    placeholder="2024-2025"
                  />
                )}
                {errors.academic_year && (
                  <p className="mt-1 text-sm text-red-600">{errors.academic_year.message}</p>
                )}
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  Classe demandée
                </label>
                <select 
                  {...register('requested_class', { valueAsNumber: true })} 
                  className="input"
                  disabled={classesLoading}
                >
                  <option value="">
                    {classesLoading 
                      ? 'Chargement des classes...' 
                      : classesError 
                        ? 'Erreur de chargement' 
                        : (classes?.results?.length === 0 || (Array.isArray(classes) && classes.length === 0))
                          ? 'Aucune classe disponible - Créez d\'abord des classes'
                          : 'Sélectionner une classe'}
                  </option>
                  {(classes?.results || (Array.isArray(classes) ? classes : [])).map((cls: any) => (
                    <option key={cls.id} value={cls.id}>
                      {cls.name} {cls.level ? `(${cls.level})` : ''}
                    </option>
                  ))}
                </select>
                {classesError && (
                  <p className="mt-1 text-sm text-yellow-600">
                    Impossible de charger les classes. Vérifiez votre connexion.
                  </p>
                )}
                {!classesLoading && !classesError && (classes?.results?.length === 0 || (Array.isArray(classes) && classes.length === 0)) && (
                  <p className="mt-1 text-sm text-yellow-600">
                    Aucune classe disponible. Veuillez créer des classes dans la section "Classes" d'abord.
                  </p>
                )}
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  École précédente
                </label>
                <input
                  {...register('previous_school')}
                  className="input"
                  placeholder="École précédente"
                />
              </div>
              <div className="md:col-span-2">
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  Photo de l'élève (optionnel)
                </label>
                <div className="flex items-center gap-4">
                  <div className="flex-1">
                    {photoPreview ? (
                      <div className="relative">
                        <img
                          src={photoPreview}
                          alt="Aperçu"
                          className="w-32 h-32 object-cover rounded-lg border border-gray-300"
                        />
                        <button
                          type="button"
                          onClick={() => {
                            setPhotoPreview(null)
                            setValue('photo', undefined)
                            if (fileInputRef.current) fileInputRef.current.value = ''
                            if (cameraInputRef.current) cameraInputRef.current.value = ''
                          }}
                          className="absolute -top-2 -right-2 bg-red-500 text-white rounded-full p-1 hover:bg-red-600"
                        >
                          <XIcon className="w-4 h-4" />
                        </button>
                      </div>
                    ) : (
                      <div className="flex gap-2">
                        <button
                          type="button"
                          onClick={() => fileInputRef.current?.click()}
                          className="btn btn-secondary flex items-center gap-2"
                        >
                          <Upload className="w-4 h-4" />
                          Importer
                        </button>
                        <button
                          type="button"
                          onClick={startCamera}
                          className="btn btn-secondary flex items-center gap-2"
                        >
                          <Camera className="w-4 h-4" />
                          Prendre une photo
                        </button>
                      </div>
                    )}
                    <input
                      ref={fileInputRef}
                      type="file"
                      accept="image/*"
                      onChange={handlePhotoChange}
                      className="hidden"
                    />
                    <input
                      ref={cameraInputRef}
                      type="file"
                      accept="image/*"
                      capture="user"
                      onChange={handlePhotoChange}
                      className="hidden"
                    />
                  </div>
                </div>
                {showCamera && (
                  <div className="mt-4 p-4 bg-gray-50 rounded-lg">
                    <div className="relative">
                      <video
                        ref={videoRef}
                        autoPlay
                        playsInline
                        className="w-full max-w-md rounded-lg"
                      />
                      <div className="mt-2 flex gap-2">
                        <button
                          type="button"
                          onClick={capturePhoto}
                          className="btn btn-primary flex items-center gap-2"
                        >
                          <Camera className="w-4 h-4" />
                          Capturer
                        </button>
                        <button
                          type="button"
                          onClick={stopCamera}
                          className="btn btn-secondary"
                        >
                          Annuler
                        </button>
                      </div>
                    </div>
                  </div>
                )}
              </div>
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-2">
                Adresse <span className="text-red-500">*</span>
              </label>
              <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                <div>
                  <label className="block text-xs font-medium text-gray-600 mb-1">Numéro N°</label>
                  <input
                    className="input"
                    placeholder="Ex: 12"
                    onChange={(e) => setValue('address', `${e.target.value} ${''}`)}
                  />
                </div>
                <div>
                  <label className="block text-xs font-medium text-gray-600 mb-1">Avenue</label>
                  <input
                    className="input"
                    placeholder="Ex: Boulevard du 30 Juin"
                    onChange={(e) => setValue('address', `${''} ${e.target.value}`)}
                  />
                </div>
                <div>
                  <label className="block text-xs font-medium text-gray-600 mb-1">Quartier</label>
                  <input
                    className="input"
                    placeholder="Ex: Quartier"
                    onChange={(e) => setValue('address', `${''} ${e.target.value}`)}
                  />
                </div>
                <div>
                  <label className="block text-xs font-medium text-gray-600 mb-1">Commune</label>
                  <input
                    className="input"
                    placeholder="Ex: Gombe"
                    onChange={(e) => setValue('address', `${''} ${e.target.value}`)}
                  />
                </div>
                <div>
                  <label className="block text-xs font-medium text-gray-600 mb-1">Ville / Province</label>
                  <input
                    className="input"
                    placeholder="Ex: Kinshasa"
                    onChange={(e) => setValue('address', `${''} ${e.target.value}`)}
                  />
                </div>
                <div>
                  <label className="block text-xs font-medium text-gray-600 mb-1">Pays</label>
                  <input
                    className="input"
                    placeholder="Ex: RDC"
                    onChange={(e) => setValue('address', `${''} ${e.target.value}`)}
                  />
                </div>
              </div>
              <textarea {...register('address')} className="hidden" />
              {errors.address && (
                <p className="mt-1 text-sm text-red-600">{errors.address.message}</p>
              )}
            </div>
            <div className="border-t pt-4">
              <h3 className="text-lg font-semibold mb-4">Informations du parent/tuteur</h3>
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">
                    Nom du parent <span className="text-red-500">*</span>
                  </label>
                  <input
                    {...register('parent_name')}
                    className="input"
                    placeholder="Nom complet"
                  />
                  {errors.parent_name && (
                    <p className="mt-1 text-sm text-red-600">{errors.parent_name.message}</p>
                  )}
                </div>
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">
                  Nom de la mère (optionnel)
                  </label>
                  <input
                    {...register('mother_name')}
                    className="input"
                    placeholder="Nom complet"
                  />
                  {errors.mother_name && (
                    <p className="mt-1 text-sm text-red-600">{errors.mother_name.message}</p>
                  )}
                </div>
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">
                    Téléphone du parent <span className="text-red-500">*</span>
                  </label>
                  <input
                    {...register('parent_phone')}
                    className="input"
                    placeholder="Téléphone"
                  />
                  {errors.parent_phone && (
                    <p className="mt-1 text-sm text-red-600">{errors.parent_phone.message}</p>
                  )}
                </div>
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">
                    Email du parent
                  </label>
                  <input
                    {...register('parent_email')}
                    type="email"
                    className="input"
                    placeholder="Email"
                  />
                  {errors.parent_email && (
                    <p className="mt-1 text-sm text-red-600">{errors.parent_email.message}</p>
                  )}
                </div>
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">
                    Profession du parent
                  </label>
                  <input
                    {...register('parent_profession')}
                    className="input"
                    placeholder="Profession"
                  />
                </div>
                <div className="md:col-span-2">
                  <label className="block text-sm font-medium text-gray-700 mb-2">
                    Adresse du parent
                  </label>
                  <textarea
                    {...register('parent_address')}
                    className="input"
                    rows={2}
                    placeholder="Adresse du parent"
                  />
                </div>
              </div>
            </div>
            <div className="flex justify-end gap-4 pt-4">
              <button
                type="button"
                onClick={() => {
                  setShowForm(false)
                  setPhotoPreview(null)
                  setShowCamera(false)
                  stopCamera()
                  reset()
                }}
                className="btn btn-secondary"
              >
                Annuler
              </button>
              <button
                type="submit"
                disabled={createMutation.isPending}
                className="btn btn-primary"
              >
                {createMutation.isPending ? 'Création...' : 'Créer l\'inscription'}
              </button>
            </div>
          </form>
        </Card>
      )}

      {/* Barre de recherche et filtre */}
      <Card className="mb-6">
        <div className="space-y-4">
          <div className="flex flex-col md:flex-row gap-4">
            {/* Champ de recherche */}
            <div className="flex-1 relative">
              <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 w-5 h-5 text-gray-400" />
              <input
                type="text"
                placeholder="Rechercher par ID élève, Nom ou Classe..."
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                className="w-full pl-10 pr-4 py-2 border border-gray-300 dark:border-gray-600 rounded-lg bg-white dark:bg-gray-700 text-gray-900 dark:text-white placeholder-gray-400 dark:placeholder-gray-500 focus:outline-none focus:ring-2 focus:ring-primary-500 focus:border-transparent"
              />
            </div>
            
            {/* Filtre par date d'inscription */}
            <div className="relative min-w-[200px]">
              <Calendar className="absolute left-3 top-1/2 transform -translate-y-1/2 w-5 h-5 text-gray-400 z-10" />
              <input
                type="date"
                value={enrollmentDateFilter}
                onChange={(e) => setEnrollmentDateFilter(e.target.value)}
                className="w-full pl-10 pr-4 py-2 border border-gray-300 dark:border-gray-600 rounded-lg bg-white dark:bg-gray-700 text-gray-900 dark:text-white focus:outline-none focus:ring-2 focus:ring-primary-500 focus:border-transparent"
              />
            </div>
            
            {/* Bouton pour réinitialiser les filtres */}
            {(searchQuery || enrollmentDateFilter) && (
              <button
                onClick={() => {
                  setSearchQuery('')
                  setEnrollmentDateFilter('')
                }}
                className="px-4 py-2 text-sm text-gray-700 dark:text-gray-300 bg-gray-100 dark:bg-gray-700 rounded-lg hover:bg-gray-200 dark:hover:bg-gray-600 transition-colors"
              >
                Réinitialiser
              </button>
            )}
          </div>
          
          {/* Compteur de résultats */}
          {(searchQuery || enrollmentDateFilter) && (
            <div className="text-sm text-gray-600 dark:text-gray-400">
              {filteredApplications.length} inscription(s) trouvée(s) sur {applications?.results?.length || 0}
            </div>
          )}
        </div>
      </Card>

      <Card>
        <div className="overflow-x-auto">
          <table className="w-full">
            <thead className="bg-gray-50 dark:bg-gray-700/50">
              <tr>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-700 dark:text-gray-300 uppercase">ID de l'élève</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-700 dark:text-gray-300 uppercase">Élève</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-700 dark:text-gray-300 uppercase">Classe</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-700 dark:text-gray-300 uppercase">Parent</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-700 dark:text-gray-300 uppercase">Statut</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-700 dark:text-gray-300 uppercase">Date</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-700 dark:text-gray-300 uppercase">Actions</th>
              </tr>
            </thead>
            <tbody className="bg-white dark:bg-gray-900 divide-y divide-gray-200 dark:divide-gray-700">
              {isLoading ? (
                <tr>
                  <td colSpan={7} className="px-6 py-4 text-center text-gray-500 dark:text-gray-400">
                    Chargement...
                  </td>
                </tr>
              ) : !applications?.results || applications.results.length === 0 ? (
                <tr>
                  <td colSpan={7} className="px-6 py-4 text-center text-gray-500 dark:text-gray-400">
                    Aucune demande d'inscription trouvée
                  </td>
                </tr>
              ) : filteredApplications.length === 0 ? (
                <tr>
                  <td colSpan={7} className="px-6 py-4 text-center text-gray-500 dark:text-gray-400">
                    Aucune inscription ne correspond à votre recherche.
                  </td>
                </tr>
              ) : (
                filteredApplications.map((app: any) => (
                <tr key={app.id} className="hover:bg-gray-50 dark:hover:bg-gray-800">
                  <td 
                    className="px-6 py-4 whitespace-nowrap cursor-pointer hover:bg-blue-50 dark:hover:bg-blue-900/20 transition-colors"
                    onClick={() => handleViewDetails(app)}
                    title="Cliquer pour voir les détails"
                  >
                    <div className="text-sm font-medium text-gray-900 dark:text-white">
                      {app.generated_student_id || (
                        <span className="text-gray-400 dark:text-gray-500 italic">En attente</span>
                      )}
                    </div>
                  </td>
                  <td 
                    className="px-6 py-4 whitespace-nowrap cursor-pointer hover:bg-blue-50 dark:hover:bg-blue-900/20 transition-colors"
                    onClick={() => handleViewDetails(app)}
                    title="Cliquer pour voir les détails"
                  >
                    <div>
                      <div className="text-sm font-medium text-gray-900 dark:text-white">
                        {enrollmentFullName(app)}
                      </div>
                      <div className="text-sm text-gray-500 dark:text-gray-400">{app.email || app.phone}</div>
                    </div>
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900 dark:text-white">
                    {app.requested_class_name || 'N/A'}
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900 dark:text-white">
                    {app.parent_name}
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap">
                    <span className={`badge ${getStatusBadge(app.status)}`}>
                      {getStatusLabel(app.status)}
                    </span>
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500 dark:text-gray-400">
                    {new Date(app.created_at).toLocaleDateString('fr-FR')}
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm font-medium space-x-2">
                    {app.status === 'PENDING' && canApproveReject && (
                      <>
                        <button
                          onClick={() => approveMutation.mutate(app.id)}
                          className="text-green-600 hover:text-green-900"
                          title="Approuver"
                        >
                          <Check className="w-5 h-5" />
                        </button>
                        <button
                          onClick={() => rejectMutation.mutate({ id: app.id, notes: '' })}
                          className="text-red-600 hover:text-red-900"
                          title="Rejeter"
                        >
                          <X className="w-5 h-5" />
                        </button>
                      </>
                    )}
                    <button
                      onClick={() => handleViewDetails(app)}
                      className="text-blue-600 hover:text-blue-900 flex items-center gap-1"
                      title="Voir détails"
                    >
                      <Eye className="w-5 h-5" />
                      <span className="text-sm">Détails</span>
                    </button>
                  </td>
                </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </Card>

      {/* Modal de détails */}
      {showDetailsModal && (applicationDetails || selectedApplication) && (
        <div 
          className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50 p-4"
          onClick={(e) => {
            if (e.target === e.currentTarget) {
              setShowDetailsModal(false)
              setSelectedId(null)
              setSelectedApplication(null)
            }
          }}
        >
          <div className="max-w-3xl w-full max-h-[90vh] overflow-y-auto" onClick={(e: React.MouseEvent) => e.stopPropagation()}>
            <Card className="p-6">
            <div className="flex items-center justify-between mb-4">
              <h2 className="text-2xl font-bold text-gray-900">
                {isEditing ? 'Modifier l\'inscription' : 'Détails de l\'inscription'}
              </h2>
              <div className="flex items-center gap-2">
                {!isEditing && (applicationDetails || selectedApplication) && (
                  <button
                    onClick={() => handleEdit(applicationDetails || selectedApplication)}
                    className="text-blue-600 hover:text-blue-900 flex items-center gap-1"
                    title="Modifier"
                  >
                    <Edit2 className="w-5 h-5" />
                    <span>Modifier</span>
                  </button>
                )}
                <button
                  onClick={() => {
                    setShowDetailsModal(false)
                    setSelectedId(null)
                    setSelectedApplication(null)
                    setIsEditing(false)
                    handleCancelEdit()
                  }}
                  className="text-gray-500 hover:text-gray-700"
                >
                  <XIcon className="w-6 h-6" />
                </button>
              </div>
            </div>
            
            {isEditing ? (
              // Formulaire d'édition
              <form onSubmit={handleSubmitEdit(onEditSubmit)} className="space-y-4">
                <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                  <div>
                    <label className="block text-sm font-medium text-gray-700 mb-2">
                      Prénom <span className="text-red-500">*</span>
                    </label>
                    <input
                      {...registerEdit('first_name')}
                      className="input"
                      placeholder="Prénom"
                    />
                    {errorsEdit.first_name && (
                      <p className="mt-1 text-sm text-red-600">{errorsEdit.first_name.message}</p>
                    )}
                  </div>
                  <div>
                    <label className="block text-sm font-medium text-gray-700 mb-2">
                      Nom <span className="text-red-500">*</span>
                    </label>
                    <input
                      {...registerEdit('last_name')}
                      className="input"
                      placeholder="Nom"
                    />
                    {errorsEdit.last_name && (
                      <p className="mt-1 text-sm text-red-600">{errorsEdit.last_name.message}</p>
                    )}
                  </div>
                  <div>
                    <label className="block text-sm font-medium text-gray-700 mb-2">
                      Postnom
                    </label>
                    <input
                      {...registerEdit('middle_name')}
                      className="input"
                      placeholder="Postnom"
                    />
                    {errorsEdit.middle_name && (
                      <p className="mt-1 text-sm text-red-600">{errorsEdit.middle_name.message}</p>
                    )}
                  </div>
                  <div>
                    <label className="block text-sm font-medium text-gray-700 mb-2">
                      Date de naissance <span className="text-red-500">*</span>
                    </label>
                    <input
                      {...registerEdit('date_of_birth')}
                      type="date"
                      className="input focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                      max={new Date().toISOString().split('T')[0]}
                      title="Sélectionnez la date de naissance"
                    />
                    {errorsEdit.date_of_birth && (
                      <p className="mt-1 text-sm text-red-600">{errorsEdit.date_of_birth.message}</p>
                    )}
                    <p className="mt-1 text-xs text-gray-500">Format: JJ/MM/AAAA</p>
                  </div>
                  <div>
                    <label className="block text-sm font-medium text-gray-700 mb-2">
                      Genre <span className="text-red-500">*</span>
                    </label>
                    <select {...registerEdit('gender')} className="input">
                      <option value="">Sélectionner</option>
                      <option value="M">Masculin</option>
                      <option value="F">Féminin</option>
                    </select>
                    {errorsEdit.gender && (
                      <p className="mt-1 text-sm text-red-600">{errorsEdit.gender.message}</p>
                    )}
                  </div>
                  <div>
                    <label className="block text-sm font-medium text-gray-700 mb-2">
                      Lieu de naissance <span className="text-red-500">*</span>
                    </label>
                    <input
                      {...registerEdit('place_of_birth')}
                      className="input"
                      placeholder="Lieu de naissance"
                    />
                    {errorsEdit.place_of_birth && (
                      <p className="mt-1 text-sm text-red-600">{errorsEdit.place_of_birth.message}</p>
                    )}
                  </div>
                  <div>
                    <label className="block text-sm font-medium text-gray-700 mb-2">
                      Téléphone
                    </label>
                    <input
                      {...registerEdit('phone')}
                      className="input"
                      placeholder="Téléphone"
                    />
                  </div>
                  <div>
                    <label className="block text-sm font-medium text-gray-700 mb-2">
                      Email
                    </label>
                    <input
                      {...registerEdit('email')}
                      type="email"
                      className="input"
                      placeholder="Email"
                    />
                    {errorsEdit.email && (
                      <p className="mt-1 text-sm text-red-600">{errorsEdit.email.message}</p>
                    )}
                  </div>
                  <div>
                    <label className="block text-sm font-medium text-gray-700 mb-2">
                      Année scolaire <span className="text-red-500">*</span>
                    </label>
                    <input
                      {...registerEdit('academic_year')}
                      className="input"
                      placeholder="2024-2025"
                    />
                    {errorsEdit.academic_year && (
                      <p className="mt-1 text-sm text-red-600">{errorsEdit.academic_year.message}</p>
                    )}
                  </div>
                  <div>
                    <label className="block text-sm font-medium text-gray-700 mb-2">
                      Classe demandée
                    </label>
                    <select 
                      {...registerEdit('requested_class', { valueAsNumber: true })} 
                      className="input"
                      disabled={classesLoading}
                    >
                      <option value="">
                        {classesLoading 
                          ? 'Chargement des classes...' 
                          : classesError 
                            ? 'Erreur de chargement' 
                            : (classes?.results?.length === 0 || (Array.isArray(classes) && classes.length === 0))
                              ? 'Aucune classe disponible'
                              : 'Sélectionner une classe'}
                      </option>
                      {(classes?.results || (Array.isArray(classes) ? classes : [])).map((cls: any) => (
                        <option key={cls.id} value={cls.id}>
                          {cls.name} {cls.level ? `(${cls.level})` : ''}
                        </option>
                      ))}
                    </select>
                  </div>
                  <div>
                    <label className="block text-sm font-medium text-gray-700 mb-2">
                      École précédente
                    </label>
                    <input
                      {...registerEdit('previous_school')}
                      className="input"
                      placeholder="École précédente"
                    />
                  </div>
                  <div className="md:col-span-2">
                    <label className="block text-sm font-medium text-gray-700 mb-2">
                      Photo de l'élève (optionnel)
                    </label>
                    <div className="flex items-center gap-4">
                      <div className="flex-1">
                        {editPhotoPreview ? (
                          <div className="relative">
                            <img
                              src={editPhotoPreview}
                              alt="Aperçu"
                              className="w-32 h-32 object-cover rounded-lg border border-gray-300"
                            />
                            <button
                              type="button"
                              onClick={() => {
                                setEditPhotoPreview(null)
                                setValueEdit('photo', undefined)
                                if (editFileInputRef.current) editFileInputRef.current.value = ''
                                if (editCameraInputRef.current) editCameraInputRef.current.value = ''
                              }}
                              className="absolute -top-2 -right-2 bg-red-500 text-white rounded-full p-1 hover:bg-red-600"
                            >
                              <XIcon className="w-4 h-4" />
                            </button>
                          </div>
                        ) : (
                          <div className="flex gap-2">
                            <button
                              type="button"
                              onClick={() => editFileInputRef.current?.click()}
                              className="btn btn-secondary flex items-center gap-2"
                            >
                              <Upload className="w-4 h-4" />
                              Importer
                            </button>
                            <button
                              type="button"
                              onClick={startEditCamera}
                              className="btn btn-secondary flex items-center gap-2"
                            >
                              <Camera className="w-4 h-4" />
                              Prendre une photo
                            </button>
                          </div>
                        )}
                        <input
                          ref={editFileInputRef}
                          type="file"
                          accept="image/*"
                          onChange={handleEditPhotoChange}
                          className="hidden"
                        />
                        <input
                          ref={editCameraInputRef}
                          type="file"
                          accept="image/*"
                          capture="user"
                          onChange={handleEditPhotoChange}
                          className="hidden"
                        />
                      </div>
                    </div>
                    {showEditCamera && (
                      <div className="mt-4 p-4 bg-gray-50 rounded-lg">
                        <div className="relative">
                          <video
                            ref={editVideoRef}
                            autoPlay
                            playsInline
                            className="w-full max-w-md rounded-lg"
                          />
                          <div className="mt-2 flex gap-2">
                            <button
                              type="button"
                              onClick={captureEditPhoto}
                              className="btn btn-primary flex items-center gap-2"
                            >
                              <Camera className="w-4 h-4" />
                              Capturer
                            </button>
                            <button
                              type="button"
                              onClick={stopEditCamera}
                              className="btn btn-secondary"
                            >
                              Annuler
                            </button>
                          </div>
                        </div>
                      </div>
                    )}
                  </div>
                </div>
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">
                    Adresse <span className="text-red-500">*</span>
                  </label>
                  <textarea
                    {...registerEdit('address')}
                    className="input"
                    rows={3}
                    placeholder="Adresse complète"
                  />
                  {errorsEdit.address && (
                    <p className="mt-1 text-sm text-red-600">{errorsEdit.address.message}</p>
                  )}
                </div>
                <div className="border-t pt-4">
                  <h3 className="text-lg font-semibold mb-4">Informations du parent/tuteur</h3>
                  <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                    <div>
                      <label className="block text-sm font-medium text-gray-700 mb-2">
                        Nom du parent <span className="text-red-500">*</span>
                      </label>
                      <input
                        {...registerEdit('parent_name')}
                        className="input"
                        placeholder="Nom complet"
                      />
                      {errorsEdit.parent_name && (
                        <p className="mt-1 text-sm text-red-600">{errorsEdit.parent_name.message}</p>
                      )}
                    </div>
                    <div>
                      <label className="block text-sm font-medium text-gray-700 mb-2">
                        Nom de la mère
                      </label>
                      <input
                        {...registerEdit('mother_name')}
                        className="input"
                        placeholder="Nom complet"
                      />
                      {errorsEdit.mother_name && (
                        <p className="mt-1 text-sm text-red-600">{errorsEdit.mother_name.message}</p>
                      )}
                    </div>
                    <div>
                      <label className="block text-sm font-medium text-gray-700 mb-2">
                        Téléphone du parent <span className="text-red-500">*</span>
                      </label>
                      <input
                        {...registerEdit('parent_phone')}
                        className="input"
                        placeholder="Téléphone"
                      />
                      {errorsEdit.parent_phone && (
                        <p className="mt-1 text-sm text-red-600">{errorsEdit.parent_phone.message}</p>
                      )}
                    </div>
                    <div>
                      <label className="block text-sm font-medium text-gray-700 mb-2">
                        Email du parent
                      </label>
                      <input
                        {...registerEdit('parent_email')}
                        type="email"
                        className="input"
                        placeholder="Email"
                      />
                      {errorsEdit.parent_email && (
                        <p className="mt-1 text-sm text-red-600">{errorsEdit.parent_email.message}</p>
                      )}
                    </div>
                    <div>
                      <label className="block text-sm font-medium text-gray-700 mb-2">
                        Profession du parent
                      </label>
                      <input
                        {...registerEdit('parent_profession')}
                        className="input"
                        placeholder="Profession"
                      />
                    </div>
                    <div className="md:col-span-2">
                      <label className="block text-sm font-medium text-gray-700 mb-2">
                        Adresse du parent
                      </label>
                      <textarea
                        {...registerEdit('parent_address')}
                        className="input"
                        rows={2}
                        placeholder="Adresse du parent"
                      />
                    </div>
                  </div>
                </div>
                <div className="flex justify-end gap-4 pt-4 border-t">
                  <button
                    type="button"
                    onClick={handleCancelEdit}
                    className="btn btn-secondary"
                  >
                    Annuler
                  </button>
                  <button
                    type="submit"
                    disabled={updateMutation.isPending}
                    className="btn btn-primary flex items-center gap-2"
                  >
                    <Save className="w-4 h-4" />
                    {updateMutation.isPending ? 'Enregistrement...' : 'Enregistrer'}
                  </button>
                </div>
              </form>
            ) : (
              // Vue en lecture seule
              (applicationDetails || selectedApplication) && (() => {
                const app = applicationDetails || selectedApplication
                return (
                  <div className="space-y-6">
                        {/* Informations de l'élève */}
                    <div>
                      <h3 className="text-lg font-semibold mb-3 text-gray-900">Informations de l'élève</h3>
                      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                    {app.photo && (
                      <div className="md:col-span-2">
                        <p className="text-sm text-gray-500 mb-2">Photo</p>
                        <img
                          src={app.photo}
                          alt={enrollmentFullName(app)}
                          className="w-32 h-32 object-cover rounded-lg border border-gray-300"
                        />
                      </div>
                    )}
                    <div>
                      <p className="text-sm text-gray-500">Nom complet</p>
                      <p className="text-sm font-medium text-gray-900">
                        {enrollmentFullName(app)}
                      </p>
                    </div>
                    {app.middle_name && (
                      <div>
                        <p className="text-sm text-gray-500">Postnom</p>
                        <p className="text-sm font-medium text-gray-900">
                          {app.middle_name}
                        </p>
                      </div>
                    )}
                    <div>
                      <p className="text-sm text-gray-500">Date de naissance</p>
                      <p className="text-sm font-medium text-gray-900">
                        {app.date_of_birth 
                          ? new Date(app.date_of_birth).toLocaleDateString('fr-FR')
                          : 'N/A'}
                      </p>
                    </div>
                    <div>
                      <p className="text-sm text-gray-500">Genre</p>
                      <p className="text-sm font-medium text-gray-900">
                        {app.gender === 'M' ? 'Masculin' : 'Féminin'}
                      </p>
                    </div>
                    <div>
                      <p className="text-sm text-gray-500">Lieu de naissance</p>
                      <p className="text-sm font-medium text-gray-900">
                        {app.place_of_birth || 'N/A'}
                      </p>
                    </div>
                    <div>
                      <p className="text-sm text-gray-500">Téléphone</p>
                      <p className="text-sm font-medium text-gray-900">
                        {app.phone || 'N/A'}
                      </p>
                    </div>
                    <div>
                      <p className="text-sm text-gray-500">Email</p>
                      <p className="text-sm font-medium text-gray-900">
                        {app.email || 'N/A'}
                      </p>
                    </div>
                    <div className="md:col-span-2">
                      <p className="text-sm text-gray-500">Adresse</p>
                      <p className="text-sm font-medium text-gray-900">
                        {app.address || 'N/A'}
                      </p>
                      </div>
                    </div>
                  </div>

                  {/* Informations scolaires */}
                  <div className="border-t pt-4">
                    <h3 className="text-lg font-semibold mb-3 text-gray-900">Informations scolaires</h3>
                    <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                    <div>
                      <p className="text-sm text-gray-500">Année scolaire</p>
                      <p className="text-sm font-medium text-gray-900">
                        {app.academic_year || 'N/A'}
                      </p>
                    </div>
                    <div>
                      <p className="text-sm text-gray-500">Classe demandée</p>
                      <p className="text-sm font-medium text-gray-900">
                        {app.requested_class_name || 'N/A'}
                      </p>
                    </div>
                    <div className="md:col-span-2">
                      <p className="text-sm text-gray-500">École précédente</p>
                      <p className="text-sm font-medium text-gray-900">
                        {app.previous_school || 'N/A'}
                      </p>
                    </div>
                  </div>
                </div>

                {/* Informations du parent */}
                <div className="border-t pt-4">
                  <h3 className="text-lg font-semibold mb-3 text-gray-900">Informations du parent/tuteur</h3>
                  <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                    <div>
                      <p className="text-sm text-gray-500">Nom du parent</p>
                      <p className="text-sm font-medium text-gray-900">
                        {app.parent_name || 'N/A'}
                      </p>
                    </div>
                    <div>
                      <p className="text-sm text-gray-500">Nom de la mère</p>
                      <p className="text-sm font-medium text-gray-900">
                        {app.mother_name || 'N/A'}
                      </p>
                    </div>
                    <div>
                      <p className="text-sm text-gray-500">Téléphone</p>
                      <p className="text-sm font-medium text-gray-900">
                        {app.parent_phone || 'N/A'}
                      </p>
                    </div>
                    <div>
                      <p className="text-sm text-gray-500">Email</p>
                      <p className="text-sm font-medium text-gray-900">
                        {app.parent_email || 'N/A'}
                      </p>
                    </div>
                    <div>
                      <p className="text-sm text-gray-500">Profession</p>
                      <p className="text-sm font-medium text-gray-900">
                        {app.parent_profession || 'N/A'}
                      </p>
                    </div>
                    <div className="md:col-span-2">
                      <p className="text-sm text-gray-500">Adresse</p>
                      <p className="text-sm font-medium text-gray-900">
                        {app.parent_address || 'N/A'}
                      </p>
                    </div>
                  </div>
                </div>

                {/* Statut et dates */}
                <div className="border-t pt-4">
                  <h3 className="text-lg font-semibold mb-3 text-gray-900">Statut</h3>
                  <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                    <div>
                      <p className="text-sm text-gray-500">Statut</p>
                      <span className={`badge ${getStatusBadge(app.status)}`}>
                        {getStatusLabel(app.status)}
                      </span>
                    </div>
                    <div>
                      <p className="text-sm text-gray-500">Date de soumission</p>
                      <p className="text-sm font-medium text-gray-900">
                        {new Date(app.created_at).toLocaleDateString('fr-FR', {
                          year: 'numeric',
                          month: 'long',
                          day: 'numeric',
                          hour: '2-digit',
                          minute: '2-digit'
                        })}
                      </p>
                    </div>
                    {app.reviewed_by_name && (
                      <div>
                        <p className="text-sm text-gray-500">Examiné par</p>
                        <p className="text-sm font-medium text-gray-900">
                          {app.reviewed_by_name}
                        </p>
                      </div>
                    )}
                    {app.generated_student_id && (
                      <div>
                        <p className="text-sm text-gray-500">Matricule généré</p>
                        <p className="text-sm font-medium text-gray-900">
                          {app.generated_student_id}
                        </p>
                      </div>
                    )}
                    {app.notes && (
                      <div className="md:col-span-2">
                        <p className="text-sm text-gray-500">Notes</p>
                        <p className="text-sm font-medium text-gray-900">
                          {app.notes}
                        </p>
                      </div>
                    )}
                  </div>
                </div>

                {/* Actions - Comptable ne peut pas approuver ni rejeter */}
                {app.status === 'PENDING' && canApproveReject && (
                  <div className="border-t pt-4 flex gap-2">
                    <button
                      onClick={() => {
                        approveMutation.mutate(app.id)
                        setShowDetailsModal(false)
                      }}
                      className="btn btn-primary flex items-center gap-2"
                    >
                      <Check className="w-4 h-4" />
                      Approuver
                    </button>
                    <button
                      onClick={() => {
                        const notes = prompt('Raison du rejet (optionnel):') || ''
                        rejectMutation.mutate({ id: app.id, notes })
                        setShowDetailsModal(false)
                      }}
                      className="btn btn-danger flex items-center gap-2"
                    >
                      <X className="w-4 h-4" />
                      Rejeter
                    </button>
                  </div>
                )}
                  </div>
                )
              })()
            )}
            </Card>
          </div>
        </div>
      )}
    </div>
  )
}
