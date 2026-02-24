from rest_framework import viewsets, permissions, status
from rest_framework.decorators import action
from rest_framework.response import Response
from django.utils import timezone
from django.db.models import Q
from .models import Meeting, MeetingParticipant
from .serializers import MeetingSerializer, MeetingCreateSerializer, MeetingParticipantSerializer
from .utils import generate_meeting_report_pdf


class MeetingViewSet(viewsets.ModelViewSet):
    serializer_class = MeetingSerializer
    permission_classes = [permissions.IsAuthenticated]
    filterset_fields = ['school', 'teacher', 'parent', 'student', 'status', 'meeting_type', 'meeting_date']
    search_fields = ['title', 'description']
    
    def get_serializer_class(self):
        if self.action == 'create':
            return MeetingCreateSerializer
        return MeetingSerializer
    
    def get_queryset(self):
        queryset = Meeting.objects.all()
        if self.request.user.school:
            queryset = queryset.filter(school=self.request.user.school)
        
        # Filter based on user role (admin and discipline officer see all school meetings)
        if self.request.user.is_parent:
            queryset = queryset.filter(
                Q(parent__user=self.request.user) | 
                Q(participants__user=self.request.user)
            ).distinct()
        elif self.request.user.is_teacher and not self.request.user.is_discipline_officer:
            queryset = queryset.filter(
                Q(teacher__user=self.request.user) |
                Q(organizer=self.request.user) |
                Q(participants__user=self.request.user)
            ).distinct()
        elif self.request.user.is_student:
            queryset = queryset.filter(
                Q(student__user=self.request.user) |
                Q(participants__user=self.request.user)
            ).distinct()
        
        return queryset
    
    def perform_create(self, serializer):
        meeting = serializer.save(
            organizer=self.request.user,
            school=self.request.user.school
        )
        from apps.communication.notifications import notify_meeting_created
        notify_meeting_created(meeting)

    @action(detail=True, methods=['post'])
    def confirm(self, request, pk=None):
        """Confirm attendance to a meeting"""
        meeting = self.get_object()
        
        # Update attendance based on user role
        if request.user.is_parent and meeting.parent and meeting.parent.user == request.user:
            meeting.parent_attended = True
        elif request.user.is_teacher and meeting.teacher.user == request.user:
            meeting.teacher_attended = True
        elif request.user.is_student and meeting.student and meeting.student.user == request.user:
            meeting.student_attended = True
        
        # Update participant attendance
        participant = MeetingParticipant.objects.filter(
            meeting=meeting,
            user=request.user
        ).first()
        if participant:
            participant.attended = True
            participant.save()
        
        if meeting.status == 'SCHEDULED':
            meeting.status = 'CONFIRMED'
        
        meeting.save()
        return Response(MeetingSerializer(meeting).data)
    
    @action(detail=True, methods=['post'])
    def start(self, request, pk=None):
        """Start a meeting"""
        meeting = self.get_object()
        if meeting.status not in ['SCHEDULED', 'CONFIRMED']:
            return Response({'error': 'Meeting cannot be started'}, status=status.HTTP_400_BAD_REQUEST)
        
        meeting.status = 'IN_PROGRESS'
        meeting.save()
        return Response(MeetingSerializer(meeting).data)
    
    @action(detail=True, methods=['post'])
    def complete(self, request, pk=None):
        """Complete a meeting and generate report"""
        meeting = self.get_object()
        if meeting.status != 'IN_PROGRESS':
            return Response({'error': 'Meeting is not in progress'}, status=status.HTTP_400_BAD_REQUEST)
        
        meeting.status = 'COMPLETED'
        meeting.report = request.data.get('report', '')
        meeting.save()
        
        # Generate PDF report
        try:
            pdf_file = generate_meeting_report_pdf(meeting)
            meeting.report_pdf = pdf_file
            meeting.save()
        except Exception as e:
            # Log error but don't fail the request
            pass
        
        return Response(MeetingSerializer(meeting).data)
    
    @action(detail=True, methods=['post'])
    def add_participant(self, request, pk=None):
        """Add a participant to the meeting"""
        meeting = self.get_object()
        user_id = request.data.get('user_id')
        role = request.data.get('role', 'Participant')
        
        from apps.accounts.models import User
        user = User.objects.get(id=user_id)
        
        participant, created = MeetingParticipant.objects.get_or_create(
            meeting=meeting,
            user=user,
            defaults={'role': role}
        )
        
        return Response(MeetingParticipantSerializer(participant).data, 
                       status=status.HTTP_201_CREATED if created else status.HTTP_200_OK)
    
    @action(detail=False, methods=['get'])
    def upcoming(self, request):
        """Get upcoming meetings"""
        queryset = self.get_queryset().filter(
            meeting_date__gte=timezone.now(),
            status__in=['SCHEDULED', 'CONFIRMED']
        ).order_by('meeting_date')
        
        page = self.paginate_queryset(queryset)
        if page is not None:
            serializer = self.get_serializer(page, many=True)
            return self.get_paginated_response(serializer.data)
        
        serializer = self.get_serializer(queryset, many=True)
        return Response(serializer.data)


class MeetingParticipantViewSet(viewsets.ModelViewSet):
    serializer_class = MeetingParticipantSerializer
    permission_classes = [permissions.IsAuthenticated]
    filterset_fields = ['meeting', 'user', 'attended', 'is_required']
    
    def get_queryset(self):
        queryset = MeetingParticipant.objects.all()
        if self.request.user.school:
            queryset = queryset.filter(meeting__school=self.request.user.school)
        return queryset
