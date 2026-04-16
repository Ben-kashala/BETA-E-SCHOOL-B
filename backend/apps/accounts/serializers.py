from rest_framework import serializers
from django.contrib.auth.password_validation import validate_password
from rest_framework_simplejwt.serializers import TokenObtainPairSerializer
from .models import User, Teacher, Parent, Student
from .constants import SUPERADMIN_USERNAME


class UserSerializer(serializers.ModelSerializer):
    password = serializers.CharField(write_only=True, required=False)
    
    class Meta:
        model = User
        fields = ['id', 'username', 'email', 'first_name', 'last_name', 'middle_name', 'phone', 
                 'role', 'school', 'profile_picture', 'address', 'date_of_birth', 
                 'is_verified', 'is_active', 'created_at', 'password']
        read_only_fields = ['id', 'created_at', 'updated_at', 'is_verified']
        extra_kwargs = {
            'password': {'write_only': True, 'required': False},
            'school': {'required': False, 'allow_null': True}  # school peut être assigné automatiquement
        }
    
    def to_representation(self, instance):
        """Override pour remplacer 'school' (ID) par 'school' (objet complet) dans la représentation"""
        representation = super().to_representation(instance)
        # Remplacer l'ID de l'école par l'objet complet avec tous les détails
        try:
            if instance.school:
                from apps.schools.serializers import SchoolSerializer
                # S'assurer que le contexte est disponible, sinon utiliser un contexte vide
                context = self.context if self.context else {}
                school_serializer = SchoolSerializer(instance.school, context=context)
                representation['school'] = school_serializer.data
            else:
                representation['school'] = None
        except Exception as e:
            # En cas d'erreur, retourner None pour éviter de casser la réponse
            # Log l'erreur pour le débogage
            import logging
            logger = logging.getLogger(__name__)
            logger.error(f"Erreur lors de la sérialisation de l'école pour l'utilisateur {instance.id}: {str(e)}")
            representation['school'] = None
        return representation
    
    def validate_username(self, value):
        if value and value == SUPERADMIN_USERNAME:
            raise serializers.ValidationError(
                "Ce nom d'utilisateur est réservé au superadmin du système."
            )
        return value

    def validate(self, attrs):
        attrs = super().validate(attrs)
        _validate_unique_email_phone(self, attrs)
        return attrs

    def create(self, validated_data):
        if validated_data.get('username') == SUPERADMIN_USERNAME:
            raise serializers.ValidationError(
                {'username': "Ce nom d'utilisateur est réservé au superadmin du système."}
            )
        password = validated_data.pop('password', None)
        user = User.objects.create(**validated_data)
        if password:
            user.set_password(password)
            user.save()
        return user

    def update(self, instance, validated_data):
        if getattr(instance, 'is_protected_superadmin', False):
            request = self.context.get('request')
            if request and request.user != instance:
                raise serializers.ValidationError(
                    "Le compte superadmin propriétaire du système ne peut être modifié que par lui-même."
                )
        password = validated_data.pop('password', None)
        for attr, value in validated_data.items():
            setattr(instance, attr, value)
        if password:
            instance.set_password(password)
        instance.save()
        return instance


def _normalize_phone_digits(phone):
    """Retourne les chiffres du numéro de téléphone (pour comparaison)."""
    if not phone:
        return ''
    return ''.join(c for c in str(phone) if c.isdigit())


def _target_school_for_serializer(serializer, attrs):
    """École cible de validation (create/update)."""
    if attrs.get('school') is not None:
        return attrs.get('school')
    if serializer.instance is not None:
        return getattr(serializer.instance, 'school', None)
    request = serializer.context.get('request') if serializer.context else None
    if request is not None:
        return getattr(request.user, 'school', None)
    return None


def _validate_unique_email_phone(serializer, attrs):
    """Validation applicative pour renvoyer un message clair avant la contrainte DB."""
    school = _target_school_for_serializer(serializer, attrs)
    if school is None:
        return

    UserModel = serializer.Meta.model
    qs = UserModel.objects.filter(school=school)
    if serializer.instance is not None:
        qs = qs.exclude(pk=serializer.instance.pk)

    raw_email = attrs.get('email')
    if raw_email is not None:
        email = str(raw_email).strip()
        if email and qs.filter(email__iexact=email).exists():
            raise serializers.ValidationError({
                'email': "Cette adresse email est déjà utilisée dans cette école."
            })

    raw_phone = attrs.get('phone')
    if raw_phone is not None:
        phone = str(raw_phone).strip()
        if phone:
            digits = _normalize_phone_digits(phone)
            for user in qs.exclude(phone__isnull=True).exclude(phone=''):
                pd = _normalize_phone_digits(user.phone)
                same = pd == digits or (
                    len(pd) >= 10 and len(digits) >= 10 and pd[-10:] == digits[-10:]
                )
                if same:
                    raise serializers.ValidationError({
                        'phone': "Ce numéro de téléphone est déjà utilisé dans cette école."
                    })


def get_user_from_login_identifier(identifier):
    """
    Retourne l'utilisateur correspondant à l'identifiant de connexion :
    - si contient @ : recherche par email (insensible à la casse)
    - si exactement 10 chiffres : recherche par téléphone (10 derniers chiffres)
    - sinon : recherche par username
    """
    from django.contrib.auth import get_user_model
    from django.db.models import Q
    User = get_user_model()

    identifier = (identifier or '').strip()
    if not identifier:
        return None

    digits = _normalize_phone_digits(identifier)

    # Email
    if '@' in identifier:
        return User.objects.filter(email__iexact=identifier).first()

    # Téléphone : 10 chiffres exactement
    if len(digits) == 10:
        for user in User.objects.exclude(Q(phone__isnull=True) | Q(phone='')):
            phone_digits = _normalize_phone_digits(user.phone)
            if phone_digits == digits or (len(phone_digits) >= 10 and phone_digits[-10:] == digits):
                return user
        return None


def _matching_users_for_identifier(identifier):
    """
    Retourne tous les utilisateurs correspondant à l'identifiant saisi
    (email, téléphone, username) pour détecter les ambiguïtés.
    """
    from django.contrib.auth import get_user_model
    from django.db.models import Q
    User = get_user_model()

    identifier = (identifier or '').strip()
    if not identifier:
        return User.objects.none()

    digits = _normalize_phone_digits(identifier)

    if '@' in identifier:
        return User.objects.filter(email__iexact=identifier)

    if len(digits) == 10:
        matches = []
        for user in User.objects.exclude(Q(phone__isnull=True) | Q(phone='')):
            phone_digits = _normalize_phone_digits(user.phone)
            if phone_digits == digits or (len(phone_digits) >= 10 and phone_digits[-10:] == digits):
                matches.append(user.id)
        if not matches:
            return User.objects.none()
        return User.objects.filter(id__in=matches)

    return User.objects.filter(username=identifier)


class CustomTokenObtainPairSerializer(TokenObtainPairSerializer):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.fields['username'].error_messages['required'] = 'L\'identifiant (nom d\'utilisateur, email ou téléphone) est requis.'
        self.fields['password'].error_messages['required'] = 'Le mot de passe est requis'
    
    def validate(self, attrs):
        identifier = attrs.get('username')
        password = attrs.get('password')
        
        from django.contrib.auth import get_user_model
        User = get_user_model()
        
        matches = _matching_users_for_identifier(identifier)
        if matches.count() > 1:
            raise serializers.ValidationError({
                'non_field_errors': [
                    "Cet identifiant (email/téléphone) est utilisé par plusieurs comptes. "
                    "Utilisez votre nom d'utilisateur pour vous connecter."
                ]
            })

        user = matches.first() if matches.exists() else None
        if user is None:
            raise serializers.ValidationError({
                'username': ['Identifiant incorrect. Utilisez votre nom d\'utilisateur, email ou numéro de téléphone (10 chiffres).']
            })
        
        if not user.is_active:
            raise serializers.ValidationError({
                'non_field_errors': ['Votre compte est désactivé. Veuillez contacter l\'administrateur.']
            })
        
        if not user.check_password(password):
            raise serializers.ValidationError({
                'password': ['Mot de passe incorrect. Veuillez vérifier votre mot de passe.']
            })

        # Si la plateforme est verrouillée, seul le superadmin peut se connecter
        from .models import PlatformSettings
        try:
            settings_obj = PlatformSettings.get_singleton()
            if settings_obj.is_platform_locked and not getattr(user, 'is_protected_superadmin', False):
                msg = settings_obj.locked_message or (
                    'La plateforme est temporairement indisponible. '
                )
                raise serializers.ValidationError({'non_field_errors': [msg]})
        except serializers.ValidationError:
            raise  # Ne pas avaler l'erreur de verrouillage
        except Exception:
            # Table absente (migrations non appliquées) ou erreur DB : on laisse passer
            pass

        # Pour SimpleJWT, on doit passer le vrai username
        attrs['username'] = user.username
        data = super().validate(attrs)
        return data
    
    @classmethod
    def get_token(cls, user):
        token = super().get_token(user)
        # Add custom claims
        token['role'] = user.role
        token['school_id'] = user.school.id if user.school else None
        return token


class ChangePasswordSerializer(serializers.Serializer):
    """Serializer pour le changement de mot de passe (utilisateur connecté)"""
    current_password = serializers.CharField(write_only=True, required=True)
    new_password = serializers.CharField(write_only=True, required=True, validators=[validate_password])
    new_password2 = serializers.CharField(write_only=True, required=True)

    def validate_current_password(self, value):
        user = self.context['request'].user
        if not user.check_password(value):
            raise serializers.ValidationError('Le mot de passe actuel est incorrect.')
        return value

    def validate(self, attrs):
        if attrs['new_password'] != attrs['new_password2']:
            raise serializers.ValidationError({
                'new_password2': 'Les nouveaux mots de passe ne correspondent pas.'
            })
        return attrs


class RegisterSerializer(serializers.ModelSerializer):
    password = serializers.CharField(write_only=True, required=True, validators=[validate_password])
    password2 = serializers.CharField(write_only=True, required=True)

    class Meta:
        model = User
        fields = ['username', 'email', 'password', 'password2', 'first_name',
                  'last_name', 'phone', 'role']  # school retiré car assigné automatiquement dans la vue

    def validate_username(self, value):
        if value and value == SUPERADMIN_USERNAME:
            raise serializers.ValidationError(
                "Ce nom d'utilisateur est réservé au superadmin du système."
            )
        return value

    def validate(self, attrs):
        if attrs['password'] != attrs['password2']:
            raise serializers.ValidationError({"password": "Les mots de passe ne correspondent pas."})
        _validate_unique_email_phone(self, attrs)
        return attrs
    
    def create(self, validated_data):
        validated_data.pop('password2')
        password = validated_data.pop('password')
        user = User.objects.create(**validated_data)
        user.set_password(password)
        user.save()
        return user


class TeacherSerializer(serializers.ModelSerializer):
    user = UserSerializer(read_only=True)
    user_id = serializers.PrimaryKeyRelatedField(queryset=User.objects.filter(role='TEACHER'), 
                                                 source='user', write_only=True)
    
    class Meta:
        model = Teacher
        fields = '__all__'


class ParentSerializer(serializers.ModelSerializer):
    user = UserSerializer(read_only=True)
    user_id = serializers.PrimaryKeyRelatedField(queryset=User.objects.filter(role='PARENT'), 
                                                 source='user', write_only=True)
    
    class Meta:
        model = Parent
        fields = '__all__'


class StudentSerializer(serializers.ModelSerializer):
    user = UserSerializer(read_only=True)
    user_id = serializers.PrimaryKeyRelatedField(queryset=User.objects.filter(role='STUDENT'), 
                                                 source='user', write_only=True)
    user_name = serializers.CharField(source='user.get_full_name', read_only=True)
    parent_name = serializers.CharField(source='parent.get_full_name', read_only=True)
    class_name = serializers.SerializerMethodField()
    titulaire_name = serializers.SerializerMethodField()
    school_class_academic_year = serializers.SerializerMethodField()

    def get_class_name(self, obj):
        return obj.school_class.name if obj.school_class else ''
    
    def get_titulaire_name(self, obj):
        if obj.school_class and obj.school_class.titulaire and obj.school_class.titulaire.user:
            return obj.school_class.titulaire.user.get_full_name()
        return None
    
    def get_school_class_academic_year(self, obj):
        if obj.school_class:
            return getattr(obj.school_class, 'academic_year', None) or obj.academic_year
        return obj.academic_year
    
    class Meta:
        model = Student
        fields = '__all__'
