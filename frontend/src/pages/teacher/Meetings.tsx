import { useQuery } from '@tanstack/react-query'
import api from '@/services/api'
import { Card } from '@/components/ui/Card'
import { Calendar, Video, ExternalLink } from 'lucide-react'
import { format } from 'date-fns'
import { fr } from 'date-fns/locale'

const STATUS_LABELS: Record<string, string> = {
  SCHEDULED: 'Planifiée',
  CONFIRMED: 'Confirmée',
  COMPLETED: 'Terminée',
  CANCELLED: 'Annulée',
  IN_PROGRESS: 'En cours',
}

export default function TeacherMeetings() {
  const { data: meetings, isLoading } = useQuery({
    queryKey: ['meetings'],
    queryFn: async () => {
      const response = await api.get('/meetings/')
      return response.data
    },
  })

  const handleMeetingClick = (meeting: any) => {
    if (meeting.video_link) {
      window.open(meeting.video_link, '_blank', 'noopener,noreferrer')
    }
  }

  return (
    <div>
      <h1 className="text-3xl font-bold text-gray-900 dark:text-white mb-6">Réunions</h1>

      <div className="space-y-4">
        {isLoading ? (
          <div className="text-gray-600 dark:text-gray-400">Chargement...</div>
        ) : !meetings?.results?.length ? (
          <p className="text-gray-600 dark:text-gray-400">Aucune réunion planifiée.</p>
        ) : (
          meetings.results.map((meeting: any) => (
            <Card
              key={meeting.id}
              className={`cursor-pointer transition-colors hover:bg-gray-50 dark:hover:bg-gray-700/50 border-gray-200 dark:border-gray-600 ${
                meeting.video_link ? 'hover:border-primary-500 dark:hover:border-primary-500' : 'cursor-default'
              }`}
              onClick={() => meeting.video_link && handleMeetingClick(meeting)}
            >
              <div className="flex items-start justify-between gap-4">
                <div className="flex-1 min-w-0">
                  <h3 className="text-lg font-semibold text-gray-900 dark:text-white mb-2">{meeting.title}</h3>
                  {meeting.description && (
                    <p className="text-sm text-gray-600 dark:text-gray-300 mb-4">{meeting.description}</p>
                  )}
                  <div className="flex flex-wrap items-center gap-x-4 gap-y-1 text-sm text-gray-500 dark:text-gray-400">
                    <div className="flex items-center space-x-1">
                      <Calendar className="w-4 h-4 flex-shrink-0" />
                      <span>
                        {format(new Date(meeting.meeting_date), 'dd MMM yyyy à HH:mm', { locale: fr })}
                      </span>
                    </div>
                    {meeting.video_link && (
                      <a
                        href={meeting.video_link}
                        target="_blank"
                        rel="noopener noreferrer"
                        onClick={(e) => e.stopPropagation()}
                        className="flex items-center space-x-1 text-primary-600 dark:text-primary-400 font-medium hover:underline inline-flex items-center gap-1"
                      >
                        <Video className="w-4 h-4 flex-shrink-0" />
                        Lien visio
                        <ExternalLink className="w-3.5 h-3.5" />
                      </a>
                    )}
                  </div>
                </div>
                <span
                  className={`badge flex-shrink-0 ${
                    meeting.status === 'CONFIRMED' || meeting.status === 'COMPLETED'
                      ? 'badge-success'
                      : meeting.status === 'CANCELLED'
                        ? 'badge-danger'
                        : 'badge-warning'
                  }`}
                >
                  {STATUS_LABELS[meeting.status] ?? meeting.status}
                </span>
              </div>
            </Card>
          ))
        )}
      </div>
    </div>
  )
}
