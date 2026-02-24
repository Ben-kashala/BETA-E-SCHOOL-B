"""
Communication models (SMS, WhatsApp, notifications)
"""
from django.db import models
from apps.accounts.models import User, Student
from apps.schools.models import School


class Notification(models.Model):
    """Model for in-app notifications"""
    NOTIFICATION_TYPES = [
        ('GRADE', 'Note'),
        ('ATTENDANCE', 'Présence'),
        ('ASSIGNMENT', 'Devoir'),
        ('PAYMENT', 'Paiement'),
        ('ANNOUNCEMENT', 'Annonce'),
        ('MEETING', 'Réunion'),
        ('DISCIPLINE', 'Discipline'),
        ('GENERAL', 'Général'),
    ]
    
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='notifications', verbose_name="Utilisateur")
    school = models.ForeignKey(School, on_delete=models.CASCADE, related_name='notifications', verbose_name="École")
    notification_type = models.CharField(max_length=20, choices=NOTIFICATION_TYPES, verbose_name="Type")
    title = models.CharField(max_length=200, verbose_name="Titre")
    message = models.TextField(verbose_name="Message")
    
    # Link to related object
    related_object_type = models.CharField(max_length=50, null=True, blank=True, verbose_name="Type d'objet lié")
    related_object_id = models.IntegerField(null=True, blank=True, verbose_name="ID de l'objet lié")
    
    # Status
    is_read = models.BooleanField(default=False, verbose_name="Lu")
    read_at = models.DateTimeField(null=True, blank=True, verbose_name="Lu le")
    
    created_at = models.DateTimeField(auto_now_add=True)
    
    class Meta:
        verbose_name = "Notification"
        verbose_name_plural = "Notifications"
        ordering = ['-created_at']
    
    def __str__(self):
        return f"{self.title} - {self.user.username}"


class Message(models.Model):
    """Model for messages between users"""
    sender = models.ForeignKey(User, on_delete=models.CASCADE, related_name='sent_messages', verbose_name="Expéditeur")
    recipient = models.ForeignKey(User, on_delete=models.CASCADE, related_name='received_messages', verbose_name="Destinataire")
    school = models.ForeignKey(School, on_delete=models.CASCADE, related_name='messages', verbose_name="École")
    
    subject = models.CharField(max_length=200, verbose_name="Sujet")
    message = models.TextField(verbose_name="Message")
    
    # Status
    is_read = models.BooleanField(default=False, verbose_name="Lu")
    read_at = models.DateTimeField(null=True, blank=True, verbose_name="Lu le")
    
    created_at = models.DateTimeField(auto_now_add=True)
    
    class Meta:
        verbose_name = "Message"
        verbose_name_plural = "Messages"
        ordering = ['-created_at']
    
    def __str__(self):
        return f"{self.subject} - {self.sender.username} -> {self.recipient.username}"


class SMSLog(models.Model):
    """Model for SMS sending logs"""
    STATUS_CHOICES = [
        ('PENDING', 'En attente'),
        ('SENT', 'Envoyé'),
        ('FAILED', 'Échoué'),
        ('DELIVERED', 'Livré'),
    ]
    
    school = models.ForeignKey(School, on_delete=models.CASCADE, related_name='sms_logs', verbose_name="École")
    recipient_phone = models.CharField(max_length=20, verbose_name="Téléphone du destinataire")
    message = models.TextField(verbose_name="Message")
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default='PENDING', verbose_name="Statut")
    
    # Provider info
    provider = models.CharField(max_length=50, default='Twilio', verbose_name="Fournisseur")
    provider_message_id = models.CharField(max_length=100, null=True, blank=True, verbose_name="ID message fournisseur")
    
    # Error handling
    error_message = models.TextField(null=True, blank=True, verbose_name="Message d'erreur")
    
    sent_at = models.DateTimeField(null=True, blank=True, verbose_name="Envoyé le")
    delivered_at = models.DateTimeField(null=True, blank=True, verbose_name="Livré le")
    created_at = models.DateTimeField(auto_now_add=True)
    
    class Meta:
        verbose_name = "Log SMS"
        verbose_name_plural = "Logs SMS"
        ordering = ['-created_at']
    
    def __str__(self):
        return f"SMS to {self.recipient_phone} - {self.status}"


class WhatsAppLog(models.Model):
    """Model for WhatsApp message logs"""
    STATUS_CHOICES = [
        ('PENDING', 'En attente'),
        ('SENT', 'Envoyé'),
        ('FAILED', 'Échoué'),
        ('DELIVERED', 'Livré'),
        ('READ', 'Lu'),
    ]
    
    school = models.ForeignKey(School, on_delete=models.CASCADE, related_name='whatsapp_logs', verbose_name="École")
    recipient_phone = models.CharField(max_length=20, verbose_name="Téléphone du destinataire")
    message = models.TextField(verbose_name="Message")
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default='PENDING', verbose_name="Statut")
    
    # Provider info
    provider = models.CharField(max_length=50, default='Twilio', verbose_name="Fournisseur")
    provider_message_id = models.CharField(max_length=100, null=True, blank=True, verbose_name="ID message fournisseur")
    
    # Error handling
    error_message = models.TextField(null=True, blank=True, verbose_name="Message d'erreur")
    
    sent_at = models.DateTimeField(null=True, blank=True, verbose_name="Envoyé le")
    delivered_at = models.DateTimeField(null=True, blank=True, verbose_name="Livré le")
    read_at = models.DateTimeField(null=True, blank=True, verbose_name="Lu le")
    created_at = models.DateTimeField(auto_now_add=True)
    
    class Meta:
        verbose_name = "Log WhatsApp"
        verbose_name_plural = "Logs WhatsApp"
        ordering = ['-created_at']
    
    def __str__(self):
        return f"WhatsApp to {self.recipient_phone} - {self.status}"


class Announcement(models.Model):
    """Model for school announcements"""
    school = models.ForeignKey(School, on_delete=models.CASCADE, related_name='announcements', verbose_name="École")
    title = models.CharField(max_length=200, verbose_name="Titre")
    message = models.TextField(verbose_name="Message")
    
    # Target audience
    target_audience = models.CharField(max_length=20, choices=[
        ('ALL', 'Tous'),
        ('STUDENTS', 'Élèves'),
        ('PARENTS', 'Parents'),
        ('TEACHERS', 'Enseignants'),
        ('ADMINS', 'Administrateurs'),
    ], default='ALL', verbose_name="Public cible")
    
    # Delivery
    send_sms = models.BooleanField(default=False, verbose_name="Envoyer par SMS")
    send_whatsapp = models.BooleanField(default=False, verbose_name="Envoyer par WhatsApp")
    send_notification = models.BooleanField(default=True, verbose_name="Envoyer notification")
    
    # Status
    is_published = models.BooleanField(default=False, verbose_name="Publié")
    published_at = models.DateTimeField(null=True, blank=True, verbose_name="Publié le")
    
    created_by = models.ForeignKey(User, on_delete=models.SET_NULL, null=True, 
                                   related_name='created_announcements', verbose_name="Créé par")
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    
    class Meta:
        verbose_name = "Annonce"
        verbose_name_plural = "Annonces"
        ordering = ['-created_at']
    
    def __str__(self):
        return f"{self.title} - {self.school.name}"


class ParentMeeting(models.Model):
    """Model for parent-teacher meetings"""
    school = models.ForeignKey(School, on_delete=models.CASCADE, related_name='parent_meetings', verbose_name="École")
    title = models.CharField(max_length=200, verbose_name="Titre")
    description = models.TextField(verbose_name="Description")
    
    # Participants
    teacher = models.ForeignKey('accounts.Teacher', on_delete=models.CASCADE, 
                               related_name='communication_parent_meetings', verbose_name="Enseignant")
    parent = models.ForeignKey('accounts.Parent', on_delete=models.CASCADE, 
                             related_name='communication_parent_meetings', verbose_name="Parent")
    student = models.ForeignKey('accounts.Student', on_delete=models.CASCADE, 
                               related_name='communication_parent_meetings', verbose_name="Élève")
    
    # Schedule
    meeting_date = models.DateTimeField(verbose_name="Date de la réunion")
    duration_minutes = models.IntegerField(default=30, verbose_name="Durée (minutes)")
    
    # Status
    status = models.CharField(max_length=20, choices=[
        ('SCHEDULED', 'Planifiée'),
        ('CONFIRMED', 'Confirmée'),
        ('COMPLETED', 'Terminée'),
        ('CANCELLED', 'Annulée'),
    ], default='SCHEDULED', verbose_name="Statut")
    
    # Notes
    agenda = models.TextField(null=True, blank=True, verbose_name="Ordre du jour")
    notes = models.TextField(null=True, blank=True, verbose_name="Notes")
    
    # Notifications
    reminder_sent = models.BooleanField(default=False, verbose_name="Rappel envoyé")
    
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    
    class Meta:
        verbose_name = "Réunion parent-enseignant"
        verbose_name_plural = "Réunions parent-enseignant"
        ordering = ['-meeting_date']
    
    def __str__(self):
        return f"{self.title} - {self.student.user.get_full_name()}"
