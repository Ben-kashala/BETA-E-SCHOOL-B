import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import api from '@/services/api'
import { X, Upload, Loader2 } from 'lucide-react'
import { showErrorToast, showSuccessToast } from '@/utils/toast'

interface AssignmentWorkModalProps {
  assignment: { id: number; title: string; due_date: string; total_points: number }
  existingSubmission?: { allow_resubmit?: boolean } | null
  onClose: () => void
}

export default function AssignmentWorkModal({ assignment, existingSubmission, onClose }: AssignmentWorkModalProps) {
  const queryClient = useQueryClient()
  const [answers, setAnswers] = useState<Record<number, string>>({})
  const canSubmit = !existingSubmission || existingSubmission.allow_resubmit === true

  const { data: questions, isLoading } = useQuery({
    queryKey: ['assignment-questions', assignment.id],
    queryFn: async () => {
      const res = await api.get(`/elearning/assignments/${assignment.id}/questions/`)
      return Array.isArray(res.data) ? res.data : []
    },
  })

  const submitMutation = useMutation({
    mutationFn: async () => {
      const submissionText = JSON.stringify(answers)
      return api.post(`/elearning/assignments/${assignment.id}/submit/`, {
        submission_text: submissionText,
      })
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['student-assignments'] })
      queryClient.invalidateQueries({ queryKey: ['student-submissions'] })
      queryClient.invalidateQueries({ queryKey: ['student-elearning-grades'] })
      showSuccessToast('Devoir soumis avec succès')
      onClose()
    },
    onError: (err: any) => {
      showErrorToast(err, 'Erreur lors de la soumission')
    },
  })

  const handleSubmit = () => {
    if (!questions?.length) return
    submitMutation.mutate()
  }

  const renderQuestionInput = (q: any) => {
    const value = answers[q.id] ?? ''
    const setValue = (v: string) => setAnswers((prev) => ({ ...prev, [q.id]: v }))

    switch (q.question_type) {
      case 'SINGLE_CHOICE':
        const opts = [
          { key: 'A', val: q.option_a },
          { key: 'B', val: q.option_b },
          { key: 'C', val: q.option_c },
          { key: 'D', val: q.option_d },
        ].filter((o) => o.val)
        return (
          <div className="space-y-2">
            {opts.map((o) => (
              <label key={o.key} className="flex items-center gap-2 cursor-pointer">
                <input
                  type="radio"
                  name={`q-${q.id}`}
                  value={o.key}
                  checked={value === o.key}
                  onChange={(e) => setValue(e.target.value)}
                  className="w-4 h-4"
                />
                <span>{o.val}</span>
              </label>
            ))}
          </div>
        )
      case 'MULTIPLE_CHOICE':
        const multOpts = [
          { key: 'A', val: q.option_a },
          { key: 'B', val: q.option_b },
          { key: 'C', val: q.option_c },
          { key: 'D', val: q.option_d },
        ].filter((o) => o.val)
        const selected = value ? value.split(',').filter(Boolean) : []
        const toggle = (k: string) => {
          const next = selected.includes(k) ? selected.filter((x) => x !== k) : [...selected, k].sort()
          setValue(next.join(','))
        }
        return (
          <div className="space-y-2">
            {multOpts.map((o) => (
              <label key={o.key} className="flex items-center gap-2 cursor-pointer">
                <input
                  type="checkbox"
                  checked={selected.includes(o.key)}
                  onChange={() => toggle(o.key)}
                  className="w-4 h-4"
                />
                <span>{o.val}</span>
              </label>
            ))}
          </div>
        )
      case 'NUMBER':
        return (
          <input
            type="number"
            value={value}
            onChange={(e) => setValue(e.target.value)}
            className="input w-full max-w-xs"
            placeholder="Votre réponse..."
          />
        )
      case 'TEXT':
      default:
        return (
          <textarea
            value={value}
            onChange={(e) => setValue(e.target.value)}
            className="input w-full min-h-[100px]"
            placeholder="Votre réponse..."
            rows={4}
          />
        )
    }
  }

  return (
    <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
      <div className="bg-white dark:bg-gray-800 rounded-xl shadow-xl max-w-2xl w-full max-h-[90vh] overflow-hidden flex flex-col">
        <div className="flex items-center justify-between p-4 border-b border-gray-200 dark:border-gray-700">
          <h2 className="text-xl font-semibold text-gray-900 dark:text-white">{assignment.title}</h2>
          <button onClick={onClose} className="p-2 hover:bg-gray-100 dark:hover:bg-gray-700 rounded-lg">
            <X className="w-5 h-5" />
          </button>
        </div>
        <div className="flex-1 overflow-y-auto p-4 space-y-6">
          {isLoading ? (
            <div className="flex items-center justify-center py-12">
              <Loader2 className="w-8 h-8 animate-spin text-primary-500" />
            </div>
          ) : questions?.length ? (
            questions.map((q: any, idx: number) => (
              <div key={q.id} className="border border-gray-200 dark:border-gray-600 rounded-lg p-4">
                <div className="flex items-start gap-2 mb-3">
                  <span className="font-medium text-primary-600 dark:text-primary-400">Q{idx + 1}.</span>
                  <p className="text-gray-900 dark:text-white flex-1">{q.question_text}</p>
                  <span className="text-sm text-gray-500 dark:text-gray-400">{q.points} pt(s)</span>
                </div>
                {renderQuestionInput(q)}
              </div>
            ))
          ) : (
            <p className="text-gray-500 dark:text-gray-400 text-center py-8">
              Aucune question dans ce devoir. Vous pouvez soumettre un fichier ou un commentaire.
            </p>
          )}
          {!canSubmit && (
            <div className="rounded-lg bg-amber-50 dark:bg-amber-900/20 border border-amber-200 dark:border-amber-800 p-4 text-amber-800 dark:text-amber-200 text-sm">
              Ce devoir a déjà été soumis. Une seule soumission est autorisée. Pour soumettre à nouveau, votre enseignant doit vous y autoriser.
            </div>
          )}
        </div>
        <div className="p-4 border-t border-gray-200 dark:border-gray-700 flex justify-end gap-3">
          <button onClick={onClose} className="btn btn-secondary">
            Annuler
          </button>
          <button
            onClick={handleSubmit}
            disabled={submitMutation.isPending || !canSubmit}
            className="btn btn-primary flex items-center gap-2"
          >
            {submitMutation.isPending ? (
              <Loader2 className="w-4 h-4 animate-spin" />
            ) : (
              <Upload className="w-4 h-4" />
            )}
            Soumettre
          </button>
        </div>
      </div>
    </div>
  )
}
