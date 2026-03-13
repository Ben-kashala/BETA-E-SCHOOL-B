from rest_framework import serializers
from .models import AcademicYear, Grade, GradeBulletin, Attendance, DisciplineRecord, DisciplineRequest, ReportCard, EvaluationGrade
from apps.accounts.serializers import StudentSerializer
from apps.schools.models import ClassSubject


class AcademicYearSerializer(serializers.ModelSerializer):
    school_name = serializers.CharField(source='school.name', read_only=True)
    
    class Meta:
        model = AcademicYear
        fields = '__all__'
        read_only_fields = ['school']  # school est assigné automatiquement dans perform_create
        extra_kwargs = {
            'school': {'required': False, 'allow_null': True, 'read_only': True}  # Le champ school est assigné automatiquement dans perform_create
        }


class GradeSerializer(serializers.ModelSerializer):
    student_name = serializers.SerializerMethodField()
    student_id = serializers.SerializerMethodField()
    subject_name = serializers.SerializerMethodField()
    teacher_name = serializers.SerializerMethodField()
    
    class Meta:
        model = Grade
        fields = '__all__'
        read_only_fields = ['created_at', 'updated_at', 'total_score']
        extra_kwargs = {
            'teacher': {'required': False, 'allow_null': True},  # Non requis car assigné dans perform_create
            'exam_score': {'required': False, 'allow_null': True},  # Optionnel
        }
    
    def validate_continuous_assessment(self, value):
        """Valider que la note est entre 0 et 20"""
        if value < 0 or value > 20:
            raise serializers.ValidationError("La note doit être entre 0 et 20")
        return value
    
    def validate_exam_score(self, value):
        """Valider que la note d'examen est entre 0 et 20 si fournie"""
        if value is not None and (value < 0 or value > 20):
            raise serializers.ValidationError("La note d'examen doit être entre 0 et 20")
        return value
    
    def get_student_name(self, obj):
        try:
            if obj.student and obj.student.user:
                return obj.student.user.get_full_name()
            return ''
        except Exception:
            return ''
    
    def get_student_id(self, obj):
        try:
            return obj.student.student_id if obj.student else ''
        except Exception:
            return ''
    
    def get_subject_name(self, obj):
        try:
            return obj.subject.name if obj.subject else ''
        except Exception:
            return ''
    
    def get_teacher_name(self, obj):
        try:
            if obj.teacher and obj.teacher.user:
                return obj.teacher.user.get_full_name()
            return ''
        except Exception:
            return ''


class GradeBulletinSerializer(serializers.ModelSerializer):
    """Notes conforme bulletin RDC: semestres, 4 périodes, examens S1/S2, T.G., repêchage."""
    student_name = serializers.SerializerMethodField()
    subject_name = serializers.SerializerMethodField()
    subject_period_max = serializers.SerializerMethodField()
    teacher_name = serializers.SerializerMethodField()
    
    class Meta:
        model = GradeBulletin
        fields = '__all__'
        read_only_fields = ['created_at', 'updated_at', 'total_s1', 'total_s2', 'total_general']
        extra_kwargs = {
            'teacher': {'required': False, 'allow_null': True},
            'school_class': {'required': False, 'allow_null': True},
        }
    
    def get_student_name(self, obj):
        try:
            return obj.student.user.get_full_name() if obj.student and obj.student.user else ''
        except Exception:
            return ''
    
    def get_subject_name(self, obj):
        try:
            return obj.subject.name if obj.subject else ''
        except Exception:
            return ''
    
    def get_subject_period_max(self, obj):
        """Note de base (max/période) : ClassSubject de la classe de la note (obj.school_class) si dispo, sinon Subject.period_max."""
        try:
            sc = getattr(obj, 'school_class', None) or (getattr(obj.student, 'school_class', None) if obj.student else None)
            if sc and hasattr(sc, 'class_subjects'):
                for cs in sc.class_subjects.all():
                    if cs.subject_id == getattr(obj.subject, 'id', None):
                        return int(cs.period_max or 20)
            return int(getattr(obj.subject, 'period_max', 20) or 20)
        except Exception:
            return 20
    
    def get_teacher_name(self, obj):
        try:
            return obj.teacher.user.get_full_name() if obj.teacher and obj.teacher.user else ''
        except Exception:
            return ''
    
    def validate(self, attrs):
        subj = attrs.get('subject') or (self.instance.subject if self.instance else None)
        if not subj:
            return attrs
        # Utiliser ClassSubject.period_max si school_class fourni (ou issu de l'élève), sinon Subject.period_max
        sc = attrs.get('school_class') or (self.instance.school_class if self.instance else None)
        if not sc and attrs.get('student'):
            sc = getattr(attrs['student'], 'school_class', None)
        pm = 20
        try:
            if sc and subj:
                cs = ClassSubject.objects.filter(school_class=sc, subject=subj).first()
                pm = int((cs.period_max if cs else getattr(subj, 'period_max', 20)) or 20)
            else:
                pm = int(getattr(subj, 'period_max', 20) or 20)
        except Exception:
            pm = 20
        em = pm * 2
        period_fields = ['s1_p1', 's1_p2', 's2_p3', 's2_p4']
        exam_fields = ['s1_exam', 's2_exam']
        for f in period_fields:
            v = attrs.get(f)
            if v is not None and (v < 0 or v > pm):
                raise serializers.ValidationError({f: f'Doit être entre 0 et {pm} (max période).'})
        for f in exam_fields:
            v = attrs.get(f)
            if v is not None and (v < 0 or v > em):
                raise serializers.ValidationError({f: f'Doit être entre 0 et {em} (max examen).'})
        return attrs


class AttendanceSerializer(serializers.ModelSerializer):
    student_name = serializers.SerializerMethodField()
    student_id = serializers.SerializerMethodField()
    class_name = serializers.SerializerMethodField()
    subject_name = serializers.SerializerMethodField()
    teacher_name = serializers.SerializerMethodField()
    
    class Meta:
        model = Attendance
        fields = '__all__'
        read_only_fields = ['created_at']
        extra_kwargs = {'subject': {'required': False, 'allow_null': True}}
    
    def get_student_name(self, obj):
        try:
            if obj.student and obj.student.user:
                return obj.student.user.get_full_name()
            return ''
        except Exception:
            return ''
    
    def get_student_id(self, obj):
        try:
            return obj.student.student_id if obj.student else ''
        except Exception:
            return ''
    
    def get_class_name(self, obj):
        try:
            return obj.school_class.name if obj.school_class else ''
        except Exception:
            return ''
    
    def get_subject_name(self, obj):
        try:
            return obj.subject.name if obj.subject else ''
        except Exception:
            return ''
    
    def get_teacher_name(self, obj):
        try:
            if obj.teacher and obj.teacher.user:
                return obj.teacher.user.get_full_name()
            return ''
        except Exception:
            return ''


class DisciplineRecordSerializer(serializers.ModelSerializer):
    student_name = serializers.SerializerMethodField()
    student_id = serializers.SerializerMethodField()
    class_name = serializers.SerializerMethodField()
    recorded_by_name = serializers.SerializerMethodField()
    resolved_by_name = serializers.SerializerMethodField()
    closed_by_name = serializers.SerializerMethodField()
    
    class Meta:
        model = DisciplineRecord
        fields = '__all__'
        read_only_fields = ['created_at', 'updated_at', 'resolved_at', 'closed_at']
    
    def get_student_name(self, obj):
        try:
            if obj.student and obj.student.user:
                return obj.student.user.get_full_name()
            return ''
        except Exception:
            return ''
    
    def get_student_id(self, obj):
        try:
            return obj.student.student_id if obj.student else ''
        except Exception:
            return ''
    
    def get_class_name(self, obj):
        try:
            return obj.school_class.name if obj.school_class else ''
        except Exception:
            return ''
    
    def get_recorded_by_name(self, obj):
        try:
            return obj.recorded_by.get_full_name() if obj.recorded_by else ''
        except Exception:
            return ''
    
    def get_resolved_by_name(self, obj):
        try:
            return obj.resolved_by.get_full_name() if obj.resolved_by else ''
        except Exception:
            return ''
    
    def get_closed_by_name(self, obj):
        try:
            return obj.closed_by.get_full_name() if obj.closed_by else ''
        except Exception:
            return ''


class DisciplineRequestSerializer(serializers.ModelSerializer):
    parent_name = serializers.SerializerMethodField()
    discipline_record_detail = serializers.SerializerMethodField()
    responded_by_name = serializers.SerializerMethodField()
    
    class Meta:
        model = DisciplineRequest
        fields = '__all__'
        read_only_fields = ['parent', 'created_at', 'updated_at', 'responded_at', 'responded_by', 'status']
    
    def get_parent_name(self, obj):
        try:
            return obj.parent.user.get_full_name() if obj.parent and obj.parent.user else ''
        except Exception:
            return ''


class EvaluationGradeSerializer(serializers.ModelSerializer):
  student_name = serializers.SerializerMethodField()
  subject_name = serializers.SerializerMethodField()
  class_name = serializers.SerializerMethodField()

  class Meta:
      model = EvaluationGrade
      fields = '__all__'
      read_only_fields = ['created_at', 'updated_at']

  def get_student_name(self, obj):
      try:
          return obj.student.user.get_full_name() if obj.student and obj.student.user else ''
      except Exception:
          return ''

  def get_subject_name(self, obj):
      try:
          return obj.subject.name if obj.subject else ''
      except Exception:
          return ''

  def get_class_name(self, obj):
      try:
          return obj.school_class.name if obj.school_class else ''
      except Exception:
          return ''
    
    def get_discipline_record_detail(self, obj):
        try:
            record = obj.discipline_record
            return {
                'id': record.id,
                'student_name': record.student.user.get_full_name() if record.student and record.student.user else '',
                'student_id': record.student.student_id if record.student else '',
                'class_name': record.school_class.name if record.school_class else '',
                'date': record.date,
                'type': record.type,
                'type_display': record.get_type_display(),
                'severity': record.severity,
                'severity_display': record.get_severity_display(),
                'description': record.description,
                'action_taken': record.action_taken,
                'status': record.status,
                'status_display': record.get_status_display(),
                'recorded_by_name': record.recorded_by.get_full_name() if record.recorded_by else '',
            }
        except Exception:
            return {}
    
    def get_responded_by_name(self, obj):
        try:
            return obj.responded_by.get_full_name() if obj.responded_by else ''
        except Exception:
            return ''


class ReportCardSerializer(serializers.ModelSerializer):
    student_detail = StudentSerializer(source='student', read_only=True)
    
    class Meta:
        model = ReportCard
        fields = '__all__'
        read_only_fields = ['created_at', 'updated_at', 'published_at']
