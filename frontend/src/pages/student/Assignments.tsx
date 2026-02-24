import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import api from '@/services/api'
import { Card } from '@/components/ui/Card'
import { format } from 'date-fns'
import { fr } from 'date-fns/locale'
import { FileEdit } from 'lucide-react'
import AssignmentWorkModal from './AssignmentWorkModal'

export default function StudentAssignments() {
  const [selectedAssignment, setSelectedAssignment] = useState<any>(null)
  const { data: assignments, isLoading } = useQuery({
    queryKey: ['student-assignments'],
    queryFn: async () => {
      const response = await api.get('/elearning/assignments/')
      return response.data
    },
  })

  const { data: submissions } = useQuery({
    queryKey: ['student-submissions'],
    queryFn: async () => {
      const response = await api.get('/elearning/submissions/')
      return (response.data?.results ?? response.data ?? []) as any[]
    },
  })

  const submissionByAssignment = (submissions ?? []).reduce((acc: Record<number, any>, s: any) => {
    const aid = s.assignment
    if (aid != null) acc[typeof aid === 'object' ? aid.id : aid] = s
    return acc
  }, {})

  const isOverdue = (dueDate: string) => {
    return new Date(dueDate) < new Date()
  }

  const assignmentList = assignments?.results ?? assignments ?? []
  const hasAssignments = Array.isArray(assignmentList) && assignmentList.length > 0

  return (
    <div>
      <h1 className="text-3xl font-bold text-gray-900 dark:text-white mb-6">Mes Devoirs</h1>

      <div className="space-y-4">
        {isLoading ? (
          <div className="text-gray-600 dark:text-gray-400">Chargement...</div>
        ) : hasAssignments ? (
          assignmentList.map((assignment: any) => {
            const sub = submissionByAssignment[assignment.id]
            const myScore = sub?.score != null ? Number(sub.score) : null
            const totalPts = Number(assignment.total_points ?? 20)
            return (
            <Card key={assignment.id}>
              <div className="flex items-start justify-between">
                <div className="flex-1">
                  <h3 className="text-lg font-semibold mb-2">{assignment.title}</h3>
                  <p className="text-sm text-gray-600 mb-4">{assignment.description}</p>
                  <div className="flex items-center flex-wrap gap-2 text-sm">
                    <span className="text-gray-500">
                      Échéance: {format(new Date(assignment.due_date), 'dd MMM yyyy', { locale: fr })}
                    </span>
                    <span className="badge badge-info">{totalPts} points</span>
                    {myScore != null && (
                      <span className="badge badge-success">
                        Votre note : {myScore}/{totalPts}
                      </span>
                    )}
                    {isOverdue(assignment.due_date) && (
                      <span className="badge badge-danger">En retard</span>
                    )}
                  </div>
                </div>
                <div className="flex flex-col sm:flex-row gap-2">
                  <button
                    onClick={() => setSelectedAssignment(assignment)}
                    className="btn btn-primary flex items-center space-x-1"
                  >
                    <FileEdit className="w-4 h-4" />
                    <span>Ouvrir / Travailler</span>
                  </button>
                </div>
              </div>
            </Card>
            )
          })
        ) : (
          <div className="p-8 text-center bg-gray-50 dark:bg-gray-800 rounded-lg border border-gray-200 dark:border-gray-700">
            <p className="text-gray-600 dark:text-gray-400">Aucun devoir disponible.</p>
            <p className="text-sm text-gray-500 dark:text-gray-500 mt-2">Les devoirs seront publiés par vos enseignants.</p>
          </div>
        )}
      </div>

      {selectedAssignment && (
        <AssignmentWorkModal
          assignment={selectedAssignment}
          existingSubmission={submissionByAssignment[selectedAssignment.id]}
          onClose={() => setSelectedAssignment(null)}
        />
      )}
    </div>
  )
}
