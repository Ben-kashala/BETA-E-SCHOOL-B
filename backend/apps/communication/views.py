from rest_framework import viewsets, permissions, status
from rest_framework.decorators import action
from rest_framework.response import Response
from django.utils import timezone
from django.db import models
from rest_framework.exceptions import PermissionDenied, ValidationError
from .models import Notification, Message, SMSLog, WhatsAppLog, Announcement, ParentMeeting
from .serializers import (
    NotificationSerializer, MessageSerializer, SMSLogSerializer,
    WhatsAppLogSerializer, AnnouncementSerializer, ParentMeetingSerializer
)
from apps.schools.models import School
from apps.accounts.models import User
# from .tasks import send_sms, send_whatsapp  # Uncomment when Celery is configured


class NotificationViewSet(viewsets.ModelViewSet):
    serializer_class = NotificationSerializer
    permission_classes = [permissions.IsAuthenticated]
    filterset_fields = ['notification_type', 'is_read', 'school']
    search_fields = ['title', 'message']
    
    def get_queryset(self):
        queryset = Notification.objects.filter(user=self.request.user)
        if self.request.user.school:
            queryset = queryset.filter(school=self.request.user.school)
        return queryset
    
    @action(detail=True, methods=['post'])
    def mark_read(self, request, pk=None):
        """Mark notification as read"""
        notification = self.get_object()
        notification.is_read = True
        notification.read_at = timezone.now()
        notification.save()
        return Response(NotificationSerializer(notification).data)
    
    @action(detail=False, methods=['post'])
    def mark_all_read(self, request):
        """Mark all notifications as read"""
        count = Notification.objects.filter(
            user=request.user,
            is_read=False
        ).update(is_read=True, read_at=timezone.now())
        return Response({'marked_read': count})


class MessageViewSet(viewsets.ModelViewSet):
    serializer_class = MessageSerializer
    permission_classes = [permissions.IsAuthenticated]
    filterset_fields = ['sender', 'recipient', 'is_read', 'school']
    search_fields = ['subject', 'message']
    
    def get_queryset(self):
        user = self.request.user
        queryset = Message.objects.filter(
            models.Q(sender=user) | models.Q(recipient=user)
        )
        # Pour les rôles non-admin, on limite aux messages de leur école
        if user.school and not getattr(user, 'is_admin', False):
            queryset = queryset.filter(school=user.school)
        return queryset
    
    def create(self, request, *args, **kwargs):
        """Override create to add debug logging and validation"""
        user = request.user
        print(f"DEBUG MESSAGE CREATE: User: {user.username}, Role: {user.role}, School: {user.school}")
        print(f"DEBUG MESSAGE CREATE: Request data: {request.data}")
        
        # Vérifier si l'utilisateur a une école
        if not user.school:
            print(f"DEBUG MESSAGE CREATE: ERREUR - L'utilisateur {user.username} n'a pas d'école associée")
            return Response({
                'non_field_errors': ['Vous devez être associé à une école pour envoyer un message. Veuillez contacter l\'administrateur système.']
            }, status=status.HTTP_400_BAD_REQUEST)
        
        try:
            serializer = self.get_serializer(data=request.data)
            serializer.is_valid(raise_exception=True)
            self.perform_create(serializer)
            headers = self.get_success_headers(serializer.data)
            print(f"DEBUG MESSAGE CREATE: Succès - Message créé")
            return Response(serializer.data, status=status.HTTP_201_CREATED, headers=headers)
        except Exception as e:
            print(f"DEBUG MESSAGE CREATE: ERREUR lors de la création: {type(e).__name__}: {str(e)}")
            import traceback
            traceback.print_exc()
            # Retourner une erreur formatée au lieu de laisser l'exception se propager
            if hasattr(e, 'detail'):
                return Response(e.detail, status=status.HTTP_400_BAD_REQUEST)
            return Response({
                'non_field_errors': [f'Erreur lors de l\'envoi du message: {str(e)}']
            }, status=status.HTTP_400_BAD_REQUEST)
    
    def perform_create(self, serializer):
        message = serializer.save(
            sender=self.request.user,
            school=self.request.user.school
        )
        from .notifications import notify_message_received
        notify_message_received(message)

    @action(detail=True, methods=['post'])
    def mark_read(self, request, pk=None):
        """Mark message as read"""
        message = self.get_object()
        if message.recipient == request.user:
            message.is_read = True
            message.read_at = timezone.now()
            message.save()
        return Response(MessageSerializer(message).data)

    @action(detail=False, methods=['post'], url_path='inter-school')
    def inter_school(self, request):
        """
        Collaboration inter-école : l'admin de l'école A envoie un message
        aux administrateurs d'une école B (plateforme).
        """
        user = request.user
        if not getattr(user, 'is_admin', False):
            raise PermissionDenied("Réservé aux administrateurs d'école.")

        target_school_id = request.data.get('target_school')
        subject = (request.data.get('subject') or '').strip()
        body = (request.data.get('message') or '').strip()

        if not target_school_id:
            raise ValidationError({'target_school': "L'école cible est obligatoire."})
        if not subject:
            raise ValidationError({'subject': "Le sujet est obligatoire."})
        if not body:
            raise ValidationError({'message': "Le message est obligatoire."})

        target_school = School.objects.filter(pk=target_school_id, is_active=True).first()
        if not target_school:
            raise ValidationError({'target_school': "École cible introuvable."})

        admins_b = User.objects.filter(school=target_school, role='ADMIN', is_active=True)
        if not admins_b.exists():
            raise ValidationError({'target_school': "Aucun administrateur trouvé dans l'école cible."})

        created = []
        for admin in admins_b:
            msg = Message.objects.create(
                sender=user,
                recipient=admin,
                school=user.school or target_school,
                subject=subject,
                message=body,
            )
            created.append(msg)

        from .notifications import notify_message_received
        for msg in created:
            notify_message_received(msg)

        return Response({'created': len(created)}, status=status.HTTP_201_CREATED)


class SMSLogViewSet(viewsets.ReadOnlyModelViewSet):
    serializer_class = SMSLogSerializer
    permission_classes = [permissions.IsAuthenticated]
    filterset_fields = ['status', 'school', 'provider']
    search_fields = ['recipient_phone', 'message']
    
    def get_queryset(self):
        queryset = SMSLog.objects.all()
        if self.request.user.school:
            queryset = queryset.filter(school=self.request.user.school)
        if not self.request.user.is_admin:
            # Non-admins can only see logs for their own messages
            queryset = queryset.filter(recipient_phone=self.request.user.phone)
        return queryset
    
    @action(detail=False, methods=['post'])
    def send(self, request):
        """Send an SMS"""
        recipient_phone = request.data.get('recipient_phone')
        message = request.data.get('message')
        
        # Create log entry
        sms_log = SMSLog.objects.create(
            school=request.user.school,
            recipient_phone=recipient_phone,
            message=message,
            status='PENDING'
        )
        
        # Send SMS asynchronously
        # send_sms.delay(sms_log.id)  # Uncomment when Celery is configured
        sms_log.status = 'SENT'
        sms_log.sent_at = timezone.now()
        sms_log.save()
        
        return Response(SMSLogSerializer(sms_log).data, status=status.HTTP_201_CREATED)


class WhatsAppLogViewSet(viewsets.ReadOnlyModelViewSet):
    serializer_class = WhatsAppLogSerializer
    permission_classes = [permissions.IsAuthenticated]
    filterset_fields = ['status', 'school', 'provider']
    search_fields = ['recipient_phone', 'message']
    
    def get_queryset(self):
        queryset = WhatsAppLog.objects.all()
        if self.request.user.school:
            queryset = queryset.filter(school=self.request.user.school)
        if not self.request.user.is_admin:
            queryset = queryset.filter(recipient_phone=self.request.user.phone)
        return queryset
    
    @action(detail=False, methods=['post'])
    def send(self, request):
        """Send a WhatsApp message"""
        recipient_phone = request.data.get('recipient_phone')
        message = request.data.get('message')
        
        # Create log entry
        whatsapp_log = WhatsAppLog.objects.create(
            school=request.user.school,
            recipient_phone=recipient_phone,
            message=message,
            status='PENDING'
        )
        
        # Send WhatsApp asynchronously
        # send_whatsapp.delay(whatsapp_log.id)  # Uncomment when Celery is configured
        whatsapp_log.status = 'SENT'
        whatsapp_log.sent_at = timezone.now()
        whatsapp_log.save()
        
        return Response(WhatsAppLogSerializer(whatsapp_log).data, status=status.HTTP_201_CREATED)


class AnnouncementViewSet(viewsets.ModelViewSet):
    serializer_class = AnnouncementSerializer
    permission_classes = [permissions.IsAuthenticated]
    filterset_fields = ['school', 'target_audience', 'is_published']
    search_fields = ['title', 'message']
    
    def get_queryset(self):
        # Admin et chargé de discipline voient toutes les annonces (y compris brouillons)
        if self.request.user.is_admin or self.request.user.is_discipline_officer:
            queryset = Announcement.objects.all()
        else:
            queryset = Announcement.objects.filter(is_published=True)
        if self.request.user.school:
            queryset = queryset.filter(school=self.request.user.school)
        return queryset
    
    def perform_create(self, serializer):
        serializer.save(
            created_by=self.request.user,
            school=self.request.user.school
        )
    
    @action(detail=True, methods=['post'])
    def publish(self, request, pk=None):
        """Publish an announcement and send notifications"""
        announcement = self.get_object()
        announcement.is_published = True
        announcement.published_at = timezone.now()
        announcement.save()
        from .notifications import notify_announcement_published
        notify_announcement_published(announcement)
        return Response(AnnouncementSerializer(announcement).data)


class ParentMeetingViewSet(viewsets.ModelViewSet):
    serializer_class = ParentMeetingSerializer
    permission_classes = [permissions.IsAuthenticated]
    filterset_fields = ['school', 'teacher', 'parent', 'student', 'status']
    search_fields = ['title', 'description']
    
    def get_queryset(self):
        queryset = ParentMeeting.objects.all()
        if self.request.user.school:
            queryset = queryset.filter(school=self.request.user.school)
        # Parents can only see their own meetings
        if self.request.user.is_parent:
            queryset = queryset.filter(parent__user=self.request.user)
        # Teachers can only see their own meetings
        elif self.request.user.is_teacher:
            queryset = queryset.filter(teacher__user=self.request.user)
        return queryset
