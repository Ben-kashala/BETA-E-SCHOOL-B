import { useQuery } from '@tanstack/react-query'
import api from '@/services/api'

/**
 * Récupère la liste des années scolaires définies dans l'admin Django.
 * Retourne également l'année actuelle recommandée.
 */
export function useAcademicYears() {
  const { data } = useQuery({
    queryKey: ['academic-years-available'],
    queryFn: async () => {
      const res = await api.get('/academics/academic-years/available/')
      return res.data as { years?: string[]; current?: string | null }
    },
  })

  const years = Array.isArray(data?.years) ? [...data!.years] : []
  const current = data?.current ?? null

  return { years, current }
}

