from rest_framework import viewsets, permissions, status
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.parsers import MultiPartParser, FormParser, JSONParser
from django.utils import timezone
from .models import EnrollmentApplication, ReEnrollment
from .serializers import EnrollmentApplicationSerializer, ReEnrollmentSerializer
from apps.accounts.models import User, Student, Parent
from apps.schools.models import SchoolClass
from django.db.models import Q


def _parse_parent_name(parent_name):
    """
    Parse parent_name (ex: "SABUE Alidor" or "Alidor SABUE") into first_name and last_name.
    Format attendu : "NOM Prénom" ou "Prénom Nom"
    """
    if not parent_name or not parent_name.strip():
        return None, None
    parts = parent_name.strip().split()
    if len(parts) == 0:
        return None, None
    if len(parts) == 1:
        return parts[0], parts[0]
    # Format "NOM Prénom" : première partie = nom, reste = prénom
    last_name = parts[0]
    first_name = " ".join(parts[1:])
    return first_name, last_name


def _get_or_create_parent_user(application):
    """
    Crée ou récupère un utilisateur Parent à partir des infos du parent/tuteur.
    - Username : prénom+nom en minuscules (ex: alidor.sabue)
    - Mot de passe par défaut : Prénom+Nom@ (ex: AlidorSABUE@)
    Retourne (parent_user, created) ou (None, False) en cas d'erreur.
    """
    first_name, last_name = _parse_parent_name(application.parent_name)
    if not first_name or not last_name:
        return None, False

    # Email du parent (prioritaire pour unicité)
    parent_email = (application.parent_email or "").strip()
    if not parent_email:
        parent_email = f"{first_name.lower()}.{last_name.lower()}@eschool.rdc"

    # Username : prénom.nom en minuscules (ex: alidor.sabue)
    base_username = f"{first_name.lower()}.{last_name.lower()}".replace(" ", ".")
    username = base_username
    counter = 1
    while User.objects.filter(username=username).exists():
        username = f"{base_username}.{counter}"
        counter += 1

    # Vérifier si un parent avec cet email existe déjà dans la même école
    existing_parent = User.objects.filter(
        role='PARENT',
        school=application.school,
        email__iexact=parent_email
    ).first()
    if existing_parent:
        return existing_parent, False

    # Mot de passe par défaut pour les parents
    from django.conf import settings
    default_password = getattr(settings, 'DEFAULT_PARENT_PASSWORD', 'Parent@@')

    try:
        parent_user = User.objects.create_user(
            username=username,
            email=parent_email,
            first_name=first_name,
            last_name=last_name,
            password=default_password,
            phone=application.parent_phone or "",
            role='PARENT',
            school=application.school,
            address=application.parent_address or ""
        )

        # Créer le profil Parent
        Parent.objects.get_or_create(
            user=parent_user,
            defaults={
                'profession': application.parent_profession or "",
                'emergency_contact': application.parent_phone or ""
            }
        )
        return parent_user, True
    except Exception as e:
        import logging
        logger = logging.getLogger(__name__)
        logger.error(f"Erreur création parent user: {e}")
        return None, False


class EnrollmentApplicationViewSet(viewsets.ModelViewSet):
    serializer_class = EnrollmentApplicationSerializer
    permission_classes = [permissions.IsAuthenticated]
    parser_classes = [MultiPartParser, FormParser, JSONParser]  # Support pour l'upload de fichiers
    filterset_fields = ['school', 'status', 'academic_year', 'requested_class']
    search_fields = ['first_name', 'last_name', 'middle_name', 'parent_name', 'mother_name', 'parent_phone', 'phone']
    
    def get_queryset(self):
        """
        - Admin / staff : toutes les demandes de leur école.
        - Parent : uniquement les demandes soumises par lui-même (pour inscrire ses enfants).
        """
        try:
            user = self.request.user
            queryset = EnrollmentApplication.objects.select_related('school', 'requested_class', 'submitted_by', 'reviewed_by').all()
            if user.school:
                queryset = queryset.filter(school=user.school)
            # Les parents ne voient que leurs propres demandes
            if getattr(user, 'is_parent', False):
                queryset = queryset.filter(submitted_by=user)
            return queryset
        except Exception as e:
            print(f"DEBUG ENROLLMENT GET_QUERYSET: ERREUR: {type(e).__name__}: {str(e)}")
            import logging
            logger = logging.getLogger(__name__)
            logger.error(f"Erreur dans get_queryset de EnrollmentApplicationViewSet: {str(e)}")
            import traceback
            traceback.print_exc()
            # Retourner un queryset vide en cas d'erreur
            return EnrollmentApplication.objects.none()
    
    def list(self, request, *args, **kwargs):
        """Override list to handle errors gracefully"""
        try:
            return super().list(request, *args, **kwargs)
        except Exception as e:
            import logging
            logger = logging.getLogger(__name__)
            logger.error(f"Erreur dans list de EnrollmentApplicationViewSet: {str(e)}")
            import traceback
            traceback.print_exc()
            from rest_framework.response import Response
            from rest_framework import status
            return Response({'results': [], 'count': 0}, status=status.HTTP_200_OK)
    
    def get_serializer_context(self):
        """Add request context to serializer for URL generation"""
        context = super().get_serializer_context()
        context['request'] = self.request
        return context
    
    def create(self, request, *args, **kwargs):
        """Override create to add debug logging and validation"""
        user = request.user
        print(f"DEBUG ENROLLMENT CREATE: User: {user.username}, Role: {user.role}, School: {user.school}")
        print(f"DEBUG ENROLLMENT CREATE: Request data: {request.data}")
        
        # Vérifier si l'utilisateur a une école
        if not user.school:
            print(f"DEBUG ENROLLMENT CREATE: ERREUR - L'utilisateur {user.username} n'a pas d'école associée")
            return Response({
                'non_field_errors': ['Vous devez être associé à une école pour créer une inscription. Veuillez contacter l\'administrateur système.']
            }, status=status.HTTP_400_BAD_REQUEST)
        
        try:
            serializer = self.get_serializer(data=request.data, context={'request': request})
            serializer.is_valid(raise_exception=True)
            self.perform_create(serializer)
            headers = self.get_success_headers(serializer.data)
            print(f"DEBUG ENROLLMENT CREATE: Succès - Inscription créée")
            return Response(serializer.data, status=status.HTTP_201_CREATED, headers=headers)
        except Exception as e:
            print(f"DEBUG ENROLLMENT CREATE: ERREUR lors de la création: {type(e).__name__}: {str(e)}")
            import traceback
            traceback.print_exc()
            # Retourner une erreur formatée au lieu de laisser l'exception se propager
            return Response({
                'non_field_errors': [f'Erreur lors de la création de l\'inscription: {str(e)}']
            }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)
    
    def perform_create(self, serializer):
        serializer.save(
            school=self.request.user.school,
            submitted_by=self.request.user
        )
    
    @action(detail=True, methods=['post'])
    def approve(self, request, pk=None):
        """Approve an enrollment application and generate student ID. Comptable cannot approve."""
        if getattr(request.user, 'is_accountant', False):
            return Response(
                {'error': 'Le comptable ne peut pas approuver les inscriptions. Seul l\'administrateur peut approuver.'},
                status=status.HTTP_403_FORBIDDEN
            )
        application = self.get_object()
        if application.status != 'PENDING':
            return Response({'error': 'Application already processed'}, status=status.HTTP_400_BAD_REQUEST)
        
        # Gestion des doublons : vérifier s'il existe déjà un élève avec le même
        # prénom, nom et postnom dans la même classe (et école) avant de créer un nouvel élève.
        confirm_duplicate = str(request.data.get('confirm_duplicate', '')).lower() in ['1', 'true', 'yes', 'on']
        if application.requested_class and not confirm_duplicate:
            duplicates_qs = Student.objects.filter(
                school_class=application.requested_class,
                user__school=application.school,
                user__first_name__iexact=application.first_name.strip(),
                user__last_name__iexact=application.last_name.strip(),
            )
            # middle_name peut être null/blank, on fait une comparaison tolérante
            if application.middle_name:
                duplicates_qs = duplicates_qs.filter(
                    Q(user__middle_name__iexact=application.middle_name.strip()) |
                    Q(user__middle_name__isnull=True) |
                    Q(user__middle_name__exact='')
                )
            if duplicates_qs.exists():
                # Retourner une erreur structurée pour que le frontend puisse proposer
                # à l'utilisateur de confirmer ou de modifier les informations.
                duplicates = []
                for s in duplicates_qs.select_related('user', 'school_class')[:5]:
                    u = s.user
                    duplicates.append({
                        'student_id': s.student_id,
                        'full_name': u.get_full_name() if u else '',
                        'class_name': s.school_class.name if s.school_class else '',
                    })
                return Response(
                    {
                        'code': 'duplicate_student',
                        'detail': "Un élève avec le même nom existe déjà dans cette classe. "
                                  "Voulez-vous confirmer l'inscription malgré tout ou modifier les informations ?",
                        'duplicates': duplicates,
                    },
                    status=status.HTTP_400_BAD_REQUEST,
                )
        
        # Generate unique student ID
        from datetime import datetime
        year = datetime.now().year
        school_code = application.school.code
        # Format: SCHOOLCODE-YEAR-XXXX (e.g., ABC-2024-0001)
        last_student = Student.objects.filter(
            user__school=application.school,
            student_id__startswith=f"{school_code}-{year}"
        ).order_by('-student_id').first()
        
        if last_student and last_student.student_id:
            try:
                last_num = int(last_student.student_id.split('-')[-1])
                new_num = last_num + 1
            except:
                new_num = 1
        else:
            new_num = 1
        
        student_id = f"{school_code}-{year}-{str(new_num).zfill(4)}"
        
        # Create user and student - username: prénom.nom (sans numéro si pas de doublon)
        base_username = f"{application.first_name.lower()}.{application.last_name.lower()}".replace(" ", ".")
        username = base_username
        counter = 1
        while User.objects.filter(username=username).exists():
            username = f"{base_username}.{counter}"
            counter += 1
        
        # Créer ou récupérer l'utilisateur parent à partir des infos parent/tuteur
        parent_user, parent_created = _get_or_create_parent_user(application)

        # Mot de passe par défaut pour les élèves
        from django.conf import settings
        default_student_password = getattr(settings, 'DEFAULT_STUDENT_PASSWORD', 'Eleve@@')
        
        user = User.objects.create_user(
            username=username,
            email=application.email or f"{username}@eschool.rdc",
            first_name=application.first_name,
            last_name=application.last_name,
            middle_name=application.middle_name or None,
            phone=application.phone,
            role='STUDENT',
            school=application.school,
            date_of_birth=application.date_of_birth,
            address=application.address,
            password=default_student_password
        )
        
        # Create student profile (lié au parent si créé)
        student = Student.objects.create(
            user=user,
            student_id=student_id,
            parent=parent_user,
            school_class=application.requested_class,
            enrollment_date=application.created_at.date(),
            academic_year=application.academic_year
        )
        
        application.status = 'APPROVED'
        application.reviewed_by = request.user
        application.generated_student_id = student_id
        application.save()
        
        response_data = {
            'message': 'Enrollment approved',
            'student_id': student.student_id,
            'user_id': user.id,
            'username': user.username
        }
        if parent_user:
            response_data['parent_username'] = parent_user.username
            response_data['parent_created'] = parent_created
            # Mot de passe par défaut : Prénom+Nom@ (communiquer au parent)
        
        return Response(response_data, status=status.HTTP_200_OK)
    
    @action(detail=True, methods=['post'])
    def reject(self, request, pk=None):
        """Reject an enrollment application. Comptable cannot reject."""
        if getattr(request.user, 'is_accountant', False):
            return Response(
                {'error': 'Le comptable ne peut pas rejeter les inscriptions. Seul l\'administrateur peut rejeter.'},
                status=status.HTTP_403_FORBIDDEN
            )
        application = self.get_object()
        application.status = 'REJECTED'
        application.reviewed_by = request.user
        application.notes = request.data.get('notes', '')
        application.save()
        return Response({'message': 'Enrollment rejected'}, status=status.HTTP_200_OK)


class ReEnrollmentViewSet(viewsets.ModelViewSet):
    serializer_class = ReEnrollmentSerializer
    permission_classes = [permissions.IsAuthenticated]
    filterset_fields = ['student', 'academic_year', 'status', 'is_paid', 'school_class']
    search_fields = ['student__user__first_name', 'student__user__last_name', 'student__student_id']
    
    def get_queryset(self):
        queryset = ReEnrollment.objects.all()
        if self.request.user.school:
            queryset = queryset.filter(student__user__school=self.request.user.school)
        # Parents can only see their children's re-enrollments
        if self.request.user.is_parent:
            queryset = queryset.filter(student__parent=self.request.user)
        return queryset
    
    @action(detail=True, methods=['post'])
    def complete(self, request, pk=None):
        """Mark re-enrollment as completed"""
        reenrollment = self.get_object()
        reenrollment.status = 'COMPLETED'
        reenrollment.completed_at = timezone.now()
        reenrollment.save()
        return Response({'message': 'Re-enrollment completed'}, status=status.HTTP_200_OK)
