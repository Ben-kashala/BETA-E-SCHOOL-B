import json
from rest_framework import serializers
from .models import Course, Assignment, AssignmentQuestion, AssignmentSubmission, Quiz, QuizQuestion, QuizAttempt, QuizAnswer


class CourseSerializer(serializers.ModelSerializer):
    subject_name = serializers.CharField(source='subject.name', read_only=True, allow_null=True)
    class_name = serializers.CharField(source='school_class.name', read_only=True)
    teacher_name = serializers.CharField(source='teacher.user.get_full_name', read_only=True)
    
    class Meta:
        model = Course
        fields = '__all__'
        read_only_fields = ['created_at', 'updated_at']
        extra_kwargs = {
            'teacher': {'required': False, 'allow_null': True, 'write_only': False},
            'subject': {'required': False, 'allow_null': True},
            'content': {'required': False, 'allow_blank': True},
        }


class AssignmentQuestionSerializer(serializers.ModelSerializer):
    class Meta:
        model = AssignmentQuestion
        fields = '__all__'
        read_only_fields = []


class AssignmentSerializer(serializers.ModelSerializer):
    subject_name = serializers.CharField(source='subject.name', read_only=True)
    class_name = serializers.CharField(source='school_class.name', read_only=True)
    teacher_name = serializers.SerializerMethodField(read_only=True)
    submission_count = serializers.IntegerField(source='submissions.count', read_only=True)
    questions = AssignmentQuestionSerializer(many=True, read_only=True)

    def get_teacher_name(self, obj):
        if obj.teacher and getattr(obj.teacher, 'user', None):
            return obj.teacher.user.get_full_name() or obj.teacher.user.username or ''
        return ''
    
    class Meta:
        model = Assignment
        fields = '__all__'
        read_only_fields = ['created_at', 'updated_at', 'assigned_date']
        extra_kwargs = {
            'teacher': {'required': False, 'allow_null': True, 'write_only': False}
        }


class AssignmentSubmissionSerializer(serializers.ModelSerializer):
    assignment_title = serializers.CharField(source='assignment.title', read_only=True)
    assignment_subject_name = serializers.CharField(source='assignment.subject.name', read_only=True, allow_null=True)
    student_name = serializers.CharField(source='student.user.get_full_name', read_only=True)
    student_id = serializers.CharField(source='student.student_id', read_only=True)
    graded_by_name = serializers.CharField(source='graded_by.user.get_full_name', read_only=True)
    
    class Meta:
        model = AssignmentSubmission
        fields = '__all__'
        read_only_fields = ['submitted_at', 'graded_at']
    
    def to_representation(self, instance):
        data = super().to_representation(instance)
        ag = data.get('answer_grades') or {}
        if not ag and instance.submission_text:
            from .views import _evaluate_answer
            try:
                answers_dict = json.loads(instance.submission_text)
            except (json.JSONDecodeError, TypeError):
                answers_dict = {}
            for q in instance.assignment.questions.all().order_by('order'):
                ans = answers_dict.get(str(q.id)) or answers_dict.get(q.id) or ''
                _, pts = _evaluate_answer(q.question_type, ans, q.correct_answer, q.points)
                ag[str(q.id)] = {'points_earned': float(pts), 'teacher_feedback': ''}
            data['answer_grades'] = ag
        return data


class QuizQuestionSerializer(serializers.ModelSerializer):
    class Meta:
        model = QuizQuestion
        fields = '__all__'


class QuizSerializer(serializers.ModelSerializer):
    subject_name = serializers.CharField(source='subject.name', read_only=True)
    class_name = serializers.CharField(source='school_class.name', read_only=True)
    teacher_name = serializers.SerializerMethodField(read_only=True)
    questions = QuizQuestionSerializer(many=True, read_only=True)
    question_count = serializers.IntegerField(source='questions.count', read_only=True)

    def get_teacher_name(self, obj):
        if obj.teacher and getattr(obj.teacher, 'user', None):
            return obj.teacher.user.get_full_name() or obj.teacher.user.username or ''
        return ''
    
    class Meta:
        model = Quiz
        fields = '__all__'
        read_only_fields = ['created_at', 'updated_at']
        extra_kwargs = {
            'teacher': {'required': False},
        }


class QuizAnswerSerializer(serializers.ModelSerializer):
    question_text = serializers.CharField(source='question.question_text', read_only=True)
    
    class Meta:
        model = QuizAnswer
        fields = '__all__'


class QuizAttemptSerializer(serializers.ModelSerializer):
    quiz_title = serializers.CharField(source='quiz.title', read_only=True)
    quiz_subject_name = serializers.CharField(source='quiz.subject.name', read_only=True, allow_null=True)
    student_name = serializers.CharField(source='student.user.get_full_name', read_only=True)
    student_id = serializers.CharField(source='student.student_id', read_only=True)
    answers = QuizAnswerSerializer(many=True, read_only=True)
    
    class Meta:
        model = QuizAttempt
        fields = '__all__'
        read_only_fields = ['started_at', 'submitted_at']
