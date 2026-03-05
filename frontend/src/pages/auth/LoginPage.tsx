import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'
import { useAuthStore } from '@/store/authStore'
import { showErrorToast, showSuccessToast } from '@/utils/toast'
import logoImage from '@/images/logo.png'

const loginSchema = z.object({
  username: z.string().min(1, 'Le nom d\'utilisateur est requis'),
  password: z.string().min(1, 'Le mot de passe est requis'),
})

type LoginForm = z.infer<typeof loginSchema>

export default function LoginPage() {
  const [isLoading, setIsLoading] = useState(false)
  const { login } = useAuthStore()
  const navigate = useNavigate()
  
  const {
    register,
    handleSubmit,
    formState: { errors },
  } = useForm<LoginForm>({
    resolver: zodResolver(loginSchema),
  })

  const onSubmit = async (data: LoginForm) => {
    setIsLoading(true)
    try {
      const user = await login(data.username, data.password)
      
      // Redirect based on role (utiliser le user retourné directement)
      const roleRoutes: Record<string, string> = {
        ADMIN: '/admin',
        TEACHER: '/teacher',
        PARENT: '/parent',
        STUDENT: '/student',
        ACCOUNTANT: '/accountant',
        DISCIPLINE_OFFICER: '/discipline-officer',
      }
      
      const redirectPath = roleRoutes[user?.role || ''] || '/admin'
      showSuccessToast('Connexion réussie')
      // Laisser le store (Zustand) et la persistance se mettre à jour avant la navigation
      window.requestAnimationFrame(() => {
        navigate(redirectPath, { replace: true })
      })
    } catch (error: any) {
      // Gérer les erreurs spécifiques de connexion
      const errorData = error.response?.data
      
      if (error.request && !error.response) {
        // Erreur réseau (pas de réponse du serveur)
        showErrorToast(
          { message: 'Pas de réponse du serveur. Vérifiez votre connexion internet.' },
          'Erreur de connexion'
        )
      } else if (error.response?.status === 401) {
        // Erreur d'authentification
        let errorMessage = 'Nom d\'utilisateur ou mot de passe incorrect.'
        
        // Messages spécifiques selon le champ d'erreur
        if (errorData?.username) {
          errorMessage = Array.isArray(errorData.username) 
            ? errorData.username[0] 
            : errorData.username
        } else if (errorData?.password) {
          errorMessage = Array.isArray(errorData.password) 
            ? errorData.password[0] 
            : errorData.password
        } else if (errorData?.non_field_errors) {
          errorMessage = Array.isArray(errorData.non_field_errors) 
            ? errorData.non_field_errors[0] 
            : errorData.non_field_errors
        } else if (errorData?.detail) {
          errorMessage = errorData.detail
        }
        
        showErrorToast(
          { message: errorMessage },
          'Erreur de connexion'
        )
      } else if (error.response?.status >= 500) {
        // Erreur serveur
        showErrorToast(
          { message: 'Erreur serveur. Veuillez réessayer plus tard.' },
          'Erreur de connexion'
        )
      } else {
        // Autres erreurs
        const message = errorData?.detail || errorData?.message || 'Une erreur est survenue lors de la connexion.'
        showErrorToast(
          { message },
          'Erreur de connexion'
        )
      }
    } finally {
      setIsLoading(false)
    }
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-eschool-body px-4">
      <div className="max-w-md w-full">
        <div className="bg-eschool-header rounded-2xl shadow-xl p-8 border border-eschool-header-text/20">
          <div className="text-center mb-8">
            <div className="flex justify-center mb-4">
              <img src={logoImage} alt="E-School" className="h-20 w-auto" />
            </div>
            <p className="text-eschool-header-text/80">Connectez-vous à votre compte</p>
          </div>

          <form onSubmit={handleSubmit(onSubmit)} className="space-y-6">
            <div>
              <label htmlFor="username" className="block text-sm font-medium text-eschool-header-text mb-2">
                Nom d'utilisateur
              </label>
              <input
                {...register('username')}
                type="text"
                id="username"
                className="input bg-white border-eschool-header-text/30 text-eschool-header-text placeholder:text-eschool-header-text/50 focus:ring-eschool-body"
                placeholder="Entrez votre nom d'utilisateur"
              />
              {errors.username && (
                <p className="mt-1 text-sm text-red-600">{errors.username.message}</p>
              )}
            </div>

            <div>
              <label htmlFor="password" className="block text-sm font-medium text-eschool-header-text mb-2">
                Mot de passe
              </label>
              <input
                {...register('password')}
                type="password"
                id="password"
                className="input bg-white border-eschool-header-text/30 text-eschool-header-text placeholder:text-eschool-header-text/50 focus:ring-eschool-body"
                placeholder="Entrez votre mot de passe"
              />
              {errors.password && (
                <p className="mt-1 text-sm text-red-600">{errors.password.message}</p>
              )}
            </div>

            <button
              type="submit"
              disabled={isLoading}
              className="w-full py-3 rounded-lg font-medium bg-eschool-body text-eschool-body-text hover:opacity-90 disabled:opacity-50 transition-opacity"
            >
              {isLoading ? 'Connexion...' : 'Se connecter'}
            </button>
          </form>

          <div className="mt-6 text-center text-sm text-eschool-header-text/70">
            <p>Plateforme scolaire digitale pour l'Afrique</p>
          </div>
        </div>
      </div>
    </div>
  )
}
