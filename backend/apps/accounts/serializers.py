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

    # Username (par défaut)
    try:
        return User.objects.get(username=identifier)
    except User.DoesNotExist:
        return None


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
        
        user = get_user_from_login_identifier(identifier)
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
                    'Seul le superadmin peut se connecter.'
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
