from rest_framework import serializers
from .models import School, Section, SchoolClass, Subject, ClassSubject, StudentClassEnrollment
from apps.accounts.models import Student


class SchoolSerializer(serializers.ModelSerializer):
    class Meta:
        model = School
        fields = '__all__'
        read_only_fields = ['created_at', 'updated_at']
        extra_kwargs = {
            # Le type d'école est requis à la création dans l'API, mais a une valeur par défaut
            'school_type': {'required': False},
        }
    
    def to_representation(self, instance):
        """Override to return full URL for logo"""
        representation = super().to_representation(instance)
        try:
            if instance.logo and hasattr(instance.logo, 'url'):
                # Vérifier que le fichier existe
                if instance.logo.storage.exists(instance.logo.name):
                    request = self.context.get('request') if self.context else None
                    if request:
                        representation['logo'] = request.build_absolute_uri(instance.logo.url)
                    else:
                        representation['logo'] = instance.logo.url
                else:
                    representation['logo'] = None
            else:
                representation['logo'] = None
        except Exception as e:
            # En cas d'erreur (fichier manquant, etc.), retourner None
            import logging
            logger = logging.getLogger(__name__)
            logger.error(f"Erreur lors de la récupération du logo de l'école {instance.id}: {str(e)}")
            representation['logo'] = None
        return representation


class SectionSerializer(serializers.ModelSerializer):
    school_name = serializers.CharField(source='school.name', read_only=True)
    
    class Meta:
        model = Section
        fields = '__all__'
        read_only_fields = ['created_at']
        extra_kwargs = {
            'school': {'required': False}  # Le champ school est assigné automatiquement dans perform_create
        }


class SchoolClassSerializer(serializers.ModelSerializer):
    school_name = serializers.CharField(source='school.name', read_only=True)
    section_name = serializers.CharField(source='section.name', read_only=True)
    titulaire_name = serializers.SerializerMethodField()
    
    class Meta:
        model = SchoolClass
        fields = '__all__'
        read_only_fields = ['created_at', 'school']  # school est assigné automatiquement dans perform_create
        extra_kwargs = {
            'school': {'required': False, 'allow_null': True, 'read_only': True},  # Le champ school est assigné automatiquement dans perform_create
            'section': {'required': False, 'allow_null': True},  # Section est optionnelle
            'titulaire': {'required': False, 'allow_null': True},
        }
    
    def get_titulaire_name(self, obj):
        if obj.titulaire and obj.titulaire.user:
            return obj.titulaire.user.get_full_name() or obj.titulaire.user.username
        return None

    def validate(self, attrs):
        """
        Valide la cohérence entre le type d'école et la classe (grade) saisie.
        - Maternelle : 1ère à 3ème
        - Primaire : 1ère à 6ème
        - Humanitaire : 7ème, 8ème, 1ère à 4ème
        """
        attrs = super().validate(attrs)
        request = self.context.get('request')
        school = getattr(request.user, 'school', None) if request else None
        # Si on est en mise à jour sans request.school (ex: admin Django), récupérer depuis l'instance
        if not school and self.instance is not None:
            school = getattr(self.instance, 'school', None)
        if not school:
            return attrs

        school_type = getattr(school, 'school_type', None)
        if not school_type:
            return attrs

        grade = (attrs.get('grade') or getattr(self.instance, 'grade', '') or '').strip()
        if not grade:
          return attrs

        normalized = grade.replace('ème', '').replace('ère', '').strip().lower()

        if school_type == 'MATERNELLE':
            allowed = {'1', '2', '3'}
            if normalized not in allowed:
                raise serializers.ValidationError({
                    'grade': "Pour une école maternelle, la classe doit être comprise entre 1ère et 3ème."
                })
        elif school_type == 'PRIMAIRE':
            allowed = {'1', '2', '3', '4', '5', '6'}
            if normalized not in allowed:
                raise serializers.ValidationError({
                    'grade': "Pour une école primaire, la classe doit être comprise entre 1ère et 6ème."
                })
        elif school_type == 'HUMANITAIRE':
            allowed = {'7', '8', '1', '2', '3', '4'}
            if normalized not in allowed:
                raise serializers.ValidationError({
                    'grade': "Pour une école humanitaire, la classe doit être 7ème, 8ème ou entre 1ère et 4ème."
                })

        return attrs


class SubjectSerializer(serializers.ModelSerializer):
    school_name = serializers.CharField(source='school.name', read_only=True)
    
    class Meta:
        model = Subject
        fields = '__all__'
        read_only_fields = ['created_at', 'school']  # school injecté dans perform_create via request.user.school


class ClassSubjectSerializer(serializers.ModelSerializer):
    class_name = serializers.CharField(source='school_class.name', read_only=True)
    subject_name = serializers.CharField(source='subject.name', read_only=True)
    subject_code = serializers.CharField(source='subject.code', read_only=True)
    teacher_name = serializers.SerializerMethodField()

    class Meta:
        model = ClassSubject
        fields = '__all__'
        read_only_fields = ['created_at']
        extra_kwargs = {'teacher': {'required': False, 'allow_null': True}}

    def get_teacher_name(self, obj):
        if obj.teacher and obj.teacher.user:
            return obj.teacher.user.get_full_name() or obj.teacher.user.username
        return None


class EnrollmentStudentSerializer(serializers.ModelSerializer):
    """Minimal élève pour les cartes de la modale Admin (évite import circulaire avec accounts.serializers)."""
    user_name = serializers.SerializerMethodField()
    user = serializers.SerializerMethodField()

    class Meta:
        model = Student
        fields = ['id', 'user_name', 'student_id', 'user']

    def get_user_name(self, obj):
        return getattr(obj, 'user_name', None) or (obj.user.get_full_name() if obj.user else None) or f'Élève #{obj.id}'

    def get_user(self, obj):
        u = obj.user
        if not u:
            return None
        return {
            'first_name': u.first_name,
            'last_name': u.last_name,
            'email': getattr(u, 'email', None),
            'phone': getattr(u, 'phone', None),
            'username': getattr(u, 'username', None),
        }


class StudentClassEnrollmentSerializer(serializers.ModelSerializer):
    """Parcours élève-classe (historique des classes : actif, promu, diplômé, désinscrit)."""
    school_class_name = serializers.CharField(source='school_class.name', read_only=True)
    academic_year = serializers.CharField(source='school_class.academic_year', read_only=True)
    status_label = serializers.SerializerMethodField()
    status_display = serializers.SerializerMethodField()
    student = EnrollmentStudentSerializer(read_only=True)

    class Meta:
        model = StudentClassEnrollment
        fields = ['id', 'school_class', 'school_class_name', 'academic_year', 'status', 'status_label', 'status_display', 'enrolled_at', 'left_at', 'student']
        read_only_fields = ['enrolled_at', 'left_at']

    def get_status_label(self, obj):
        return obj.get_status_display()

    def get_status_display(self, obj):
        return obj.get_status_display()
