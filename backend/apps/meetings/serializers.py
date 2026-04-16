from uuid import uuid4
import re
from rest_framework import serializers
from .models import Meeting, MeetingParticipant
from apps.accounts.serializers import UserSerializer


class MeetingParticipantSerializer(serializers.ModelSerializer):
    user_name = serializers.CharField(source='user.get_full_name', read_only=True)
    user_email = serializers.CharField(source='user.email', read_only=True)
    
    class Meta:
        model = MeetingParticipant
        fields = '__all__'


class MeetingSerializer(serializers.ModelSerializer):
    school_name = serializers.CharField(source='school.name', read_only=True)
    organizer_name = serializers.CharField(source='organizer.get_full_name', read_only=True)
    teacher_name = serializers.CharField(source='teacher.user.get_full_name', read_only=True)
    parent_name = serializers.CharField(source='parent.user.get_full_name', read_only=True)
    student_name = serializers.CharField(source='student.user.get_full_name', read_only=True)
    participants = MeetingParticipantSerializer(many=True, read_only=True)
    groups = serializers.SerializerMethodField()
    
    class Meta:
        model = Meeting
        fields = '__all__'
        read_only_fields = ['created_at', 'updated_at', 'reminder_sent_at', 'published_at']
    
    def get_groups(self, obj):
        """Return list of group names"""
        return [{'id': group.id, 'name': group.name} for group in obj.groups.all()]


class MeetingCreateSerializer(serializers.ModelSerializer):
    """Serializer for creating meetings with participants"""
    participant_ids = serializers.ListField(
        child=serializers.IntegerField(),
        write_only=True,
        required=False,
        help_text="List of user IDs to add as participants"
    )
    student_ids = serializers.ListField(
        child=serializers.IntegerField(),
        write_only=True,
        required=False,
        help_text="List of student IDs to add as participants"
    )
    parent_ids = serializers.ListField(
        child=serializers.IntegerField(),
        write_only=True,
        required=False,
        help_text="List of parent IDs to add as participants"
    )
    group_ids = serializers.ListField(
        child=serializers.IntegerField(),
        write_only=True,
        required=False,
        help_text="List of class/group IDs to add to the meeting"
    )
    auto_generate_video_link = serializers.BooleanField(
        write_only=True,
        required=False,
        default=False,
        help_text="Automatically generate video link for Google Meet or Zoom"
    )
    
    class Meta:
        model = Meeting
        fields = '__all__'
        read_only_fields = ['created_at', 'updated_at', 'reminder_sent_at', 'organizer', 'school', 'published_at']
        extra_kwargs = {
            'school': {'required': False, 'allow_null': True, 'read_only': True},
            'video_link': {'required': False, 'allow_blank': True},
            'video_platform': {'required': False, 'allow_blank': True},
        }

    def validate(self, attrs):
        auto_generate_video_link = attrs.get('auto_generate_video_link', False)
        video_platform = attrs.get('video_platform')
        if auto_generate_video_link and not video_platform:
            raise serializers.ValidationError({
                'video_platform': "Sélectionnez une plateforme avant de générer automatiquement le lien."
            })
        return attrs

    def _extract_meeting_id_from_link(self, video_link):
        if not video_link:
            return None

        patterns = [
            r'meet\.google\.com/([a-z0-9-]+)',
            r'zoom\.us/(?:j|wc/join)/([0-9]+)',
            r'meet\.jit\.si/([A-Za-z0-9_-]+)',
        ]
        for pattern in patterns:
            match = re.search(pattern, video_link)
            if match:
                return match.group(1)
        return None

    def _generate_jitsi_link(self, meeting_date):
        timestamp = meeting_date.strftime('%Y%m%d%H%M') if meeting_date else 'meeting'
        room_name = f"eschool-{timestamp}-{uuid4().hex[:10]}"
        return {
            'link': f'https://meet.jit.si/{room_name}',
            'meeting_id': room_name,
            'password': None,
            'platform': 'JITSI',
        }

    def _apply_video_link_rules(self, validated_data):
        auto_generate_video_link = validated_data.pop('auto_generate_video_link', False)

        if auto_generate_video_link and validated_data.get('video_platform'):
            video_data = self.generate_video_link(
                validated_data.get('video_platform'),
                validated_data.get('meeting_date'),
            )
            if video_data:
                validated_data['video_link'] = video_data.get('link')
                validated_data['meeting_id'] = video_data.get('meeting_id')
                validated_data['video_platform'] = video_data.get(
                    'platform',
                    validated_data.get('video_platform'),
                )
                validated_data['meeting_password'] = video_data.get('password')
        elif validated_data.get('video_link') and not validated_data.get('meeting_id'):
            validated_data['meeting_id'] = self._extract_meeting_id_from_link(
                validated_data.get('video_link')
            )

        return validated_data

    def _sync_related_items(
        self,
        meeting,
        *,
        participant_ids,
        student_ids,
        parent_ids,
        group_ids,
        meeting_type,
    ):
        if group_ids is not None:
            meeting.groups.set(group_ids)
        # Add groups
        if group_ids:
            from apps.accounts.models import Student
            from apps.schools.models import SchoolClass
            for group_id in group_ids:
                try:
                    school_class = SchoolClass.objects.get(id=group_id)
                    students = Student.objects.filter(school_class=school_class, user__school=meeting.school)
                    for student in students:
                        MeetingParticipant.objects.get_or_create(
                            meeting=meeting,
                            user=student.user,
                            defaults={'role': 'Élève'}
                        )
                        if student.parent and meeting_type != 'PARENT_MEETING':
                            MeetingParticipant.objects.get_or_create(
                                meeting=meeting,
                                user=student.parent,
                                defaults={'role': 'Parent'}
                            )
                except SchoolClass.DoesNotExist:
                    pass

        from apps.accounts.models import User, Student, Parent

        for user_id in participant_ids:
            try:
                user = User.objects.get(id=user_id)
                MeetingParticipant.objects.get_or_create(
                    meeting=meeting,
                    user=user,
                    defaults={'role': user.get_role_display() if hasattr(user, 'get_role_display') else 'Participant'}
                )
            except User.DoesNotExist:
                pass

        for student_id in student_ids:
            try:
                student = Student.objects.get(id=student_id)
                MeetingParticipant.objects.get_or_create(
                    meeting=meeting,
                    user=student.user,
                    defaults={'role': 'Élève'}
                )
                if student.parent and meeting_type != 'PARENT_MEETING':
                    MeetingParticipant.objects.get_or_create(
                        meeting=meeting,
                        user=student.parent,
                        defaults={'role': 'Parent'}
                    )
            except Student.DoesNotExist:
                pass

        for parent_id in parent_ids:
            try:
                parent = Parent.objects.get(id=parent_id)
                MeetingParticipant.objects.get_or_create(
                    meeting=meeting,
                    user=parent.user,
                    defaults={'role': 'Parent'}
                )
            except Parent.DoesNotExist:
                pass
    
    def create(self, validated_data):
        participant_ids = validated_data.pop('participant_ids', [])
        student_ids = validated_data.pop('student_ids', [])
        parent_ids = validated_data.pop('parent_ids', [])
        group_ids = validated_data.pop('group_ids', [])
        validated_data = self._apply_video_link_rules(validated_data)
        
        # Handle publication
        if validated_data.get('is_published'):
            from django.utils import timezone
            validated_data['published_at'] = timezone.now()
        
        meeting = Meeting.objects.create(**validated_data)
        self._sync_related_items(
            meeting,
            participant_ids=participant_ids,
            student_ids=student_ids,
            parent_ids=parent_ids,
            group_ids=group_ids,
            meeting_type=validated_data.get('meeting_type'),
        )
        
        return meeting

    def update(self, instance, validated_data):
        participant_ids = validated_data.pop('participant_ids', [])
        student_ids = validated_data.pop('student_ids', [])
        parent_ids = validated_data.pop('parent_ids', [])
        group_ids = validated_data.pop('group_ids', None)
        validated_data = self._apply_video_link_rules(validated_data)

        if validated_data.get('is_published') and not instance.published_at:
            from django.utils import timezone
            validated_data['published_at'] = timezone.now()

        for attr, value in validated_data.items():
            setattr(instance, attr, value)
        instance.save()

        self._sync_related_items(
            instance,
            participant_ids=participant_ids,
            student_ids=student_ids,
            parent_ids=parent_ids,
            group_ids=group_ids,
            meeting_type=validated_data.get('meeting_type', instance.meeting_type),
        )
        return instance
    
    def generate_video_link(self, platform, meeting_date):
        """Generate video link based on platform
        
        Returns a dict with 'link', 'meeting_id', and optionally 'password'
        """
        if not platform or not meeting_date:
            return None
        
        # Sans intégration API Google/Zoom/Teams, on génère un salon Jitsi
        # réellement joignable pour éviter de produire de faux liens.
        if platform in {'GOOGLE_MEET', 'ZOOM', 'TEAMS', 'JITSI'}:
            return self._generate_jitsi_link(meeting_date)
        
        return None
