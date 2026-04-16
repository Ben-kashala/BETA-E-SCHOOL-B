"""
Meetings models (parent-teacher meetings with video links)
"""
from django.db import models
from apps.accounts.models import User, Teacher, Parent, Student
from apps.schools.models import School


class Meeting(models.Model):
    """Model for parent-teacher meetings"""
    STATUS_CHOICES = [
        ('SCHEDULED', 'Planifiée'),
        ('CONFIRMED', 'Confirmée'),
        ('IN_PROGRESS', 'En cours'),
        ('COMPLETED', 'Terminée'),
        ('CANCELLED', 'Annulée'),
        ('RESCHEDULED', 'Reprogrammée'),
    ]
    
    MEETING_TYPES = [
        ('INDIVIDUAL', 'Individuelle'),
        ('GROUP', 'Groupe'),
        ('GENERAL', 'Générale'),
        ('TEACHER_MEETING', 'Réunion avec enseignant'),
        ('PARENT_MEETING', 'Réunion avec parent'),
    ]
    
    school = models.ForeignKey(School, on_delete=models.CASCADE, related_name='meetings', verbose_name="École")
    title = models.CharField(max_length=200, verbose_name="Titre")
    description = models.TextField(verbose_name="Description")
    meeting_type = models.CharField(max_length=20, choices=MEETING_TYPES, default='INDIVIDUAL', verbose_name="Type")
    
    # Participants
    organizer = models.ForeignKey(User, on_delete=models.CASCADE, related_name='organized_meetings', verbose_name="Organisateur")
    teacher = models.ForeignKey(Teacher, on_delete=models.CASCADE, related_name='scheduled_meetings', verbose_name="Enseignant")
    parent = models.ForeignKey(Parent, on_delete=models.CASCADE, related_name='scheduled_meetings', 
                              null=True, blank=True, verbose_name="Parent")
    student = models.ForeignKey(Student, on_delete=models.CASCADE, related_name='scheduled_meetings', 
                               null=True, blank=True, verbose_name="Élève")
    
    # Schedule
    meeting_date = models.DateTimeField(verbose_name="Date de la réunion")
    duration_minutes = models.IntegerField(default=30, verbose_name="Durée (minutes)")
    location = models.CharField(max_length=200, null=True, blank=True, verbose_name="Lieu")
    
    # Video conference
    video_link = models.URLField(null=True, blank=True, verbose_name="Lien visioconférence")
    video_platform = models.CharField(max_length=50, null=True, blank=True, 
                                     choices=[('JITSI', 'Jitsi Meet'), ('ZOOM', 'Zoom'), ('TEAMS', 'Microsoft Teams'), 
                                             ('GOOGLE_MEET', 'Google Meet'), ('OTHER', 'Autre')],
                                     verbose_name="Plateforme visio")
    meeting_id = models.CharField(max_length=100, null=True, blank=True, verbose_name="ID de réunion")
    meeting_password = models.CharField(max_length=50, null=True, blank=True, verbose_name="Mot de passe")
    
    # Status
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default='SCHEDULED', verbose_name="Statut")
    
    # Agenda and notes
    agenda = models.TextField(null=True, blank=True, verbose_name="Ordre du jour")
    notes = models.TextField(null=True, blank=True, verbose_name="Notes")
    report = models.TextField(null=True, blank=True, verbose_name="Rapport de réunion")
    report_pdf = models.FileField(upload_to='meetings/reports/', null=True, blank=True, verbose_name="Rapport PDF")
    
    # Attendance
    parent_attended = models.BooleanField(default=False, verbose_name="Parent présent")
    teacher_attended = models.BooleanField(default=False, verbose_name="Enseignant présent")
    student_attended = models.BooleanField(default=False, verbose_name="Élève présent")
    
    # Groups (for group meetings)
    groups = models.ManyToManyField('schools.SchoolClass', related_name='meetings', blank=True, verbose_name="Groupes/Classes")
    
    # Publication
    is_published = models.BooleanField(default=False, verbose_name="Publié", 
                                      help_text="Si publié, les participants peuvent voir la réunion")
    published_at = models.DateTimeField(null=True, blank=True, verbose_name="Publié le")
    
    # Notifications
    reminder_sent = models.BooleanField(default=False, verbose_name="Rappel envoyé")
    reminder_sent_at = models.DateTimeField(null=True, blank=True, verbose_name="Rappel envoyé le")
    
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    
    class Meta:
        verbose_name = "Réunion"
        verbose_name_plural = "Réunions"
        ordering = ['-meeting_date']
    
    def __str__(self):
        return f"{self.title} - {self.meeting_date.strftime('%Y-%m-%d %H:%M')}"


class MeetingParticipant(models.Model):
    """Model for additional meeting participants (for group meetings)"""
    meeting = models.ForeignKey(Meeting, on_delete=models.CASCADE, related_name='participants', verbose_name="Réunion")
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='meeting_participations', verbose_name="Participant")
    role = models.CharField(max_length=50, verbose_name="Rôle")  # e.g., "Parent", "Enseignant", "Directeur"
    is_required = models.BooleanField(default=True, verbose_name="Obligatoire")
    attended = models.BooleanField(default=False, verbose_name="Présent")
    notes = models.TextField(null=True, blank=True, verbose_name="Notes")
    
    class Meta:
        verbose_name = "Participant à la réunion"
        verbose_name_plural = "Participants aux réunions"
        unique_together = ['meeting', 'user']
    
    def __str__(self):
        return f"{self.user.get_full_name()} - {self.meeting.title}"
