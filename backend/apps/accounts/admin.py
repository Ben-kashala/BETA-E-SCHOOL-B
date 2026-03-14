from django.contrib import admin
from django.contrib.auth.admin import UserAdmin as BaseUserAdmin
from django.core.exceptions import PermissionDenied
from django.utils.translation import gettext_lazy as _
from .models import User, Teacher, Parent, Student, PlatformSettings
from .constants import SUPERADMIN_USERNAME
from apps.schools.admin_base import SchoolScopedAdminMixin

admin.site.site_header = "E-SCHOOL ADMIN"
admin.site.site_title = "E-SCHOOL ADMIN"
admin.site.index_title = "Tableau de bord E-SCHOOL"


@admin.register(User)
class UserAdmin(SchoolScopedAdminMixin, BaseUserAdmin):
    list_display = ['username', 'email', 'first_name', 'last_name', 'middle_name', 'role', 'school', 'is_active', 'created_at']
    list_filter = ['role', 'is_active', 'is_verified']
    search_fields = ['username', 'email', 'first_name', 'last_name', 'middle_name', 'phone']
    
    def get_list_filter(self, request):
        if request.user.is_superuser:
            return ['role', 'is_active', 'is_verified', 'school']
        return ['role', 'is_active', 'is_verified']
    fieldsets = BaseUserAdmin.fieldsets + (
        ('Postnom (élève)', {'fields': ('middle_name',)}),
        ('Informations supplémentaires', {
            'fields': ('phone', 'school', 'role', 'profile_picture', 'address', 'date_of_birth', 'is_verified')
        }),
    )
    add_fieldsets = BaseUserAdmin.add_fieldsets + (
        ('Informations supplémentaires', {
            'fields': ('email', 'phone', 'school', 'role', 'first_name', 'last_name', 'middle_name')
        }),
    )
    
    def get_queryset(self, request):
        qs = super().get_queryset(request)
        if request.user.is_authenticated and not request.user.is_superuser:
            if request.user.is_admin and request.user.school is None:
                return qs  # Admin plateforme : voit tous les utilisateurs
            if request.user.is_admin and request.user.school:
                return qs.filter(school=request.user.school)
        return qs
    
    def _is_protected_superadmin(self, obj):
        return obj.username == SUPERADMIN_USERNAME and obj.is_superuser

    def save_model(self, request, obj, form, change):
        # Le superadmin protégé ne peut être modifié que par lui-même
        if self._is_protected_superadmin(obj) and request.user != obj:
            raise PermissionDenied(
                "Le compte superadmin propriétaire du système (Alidorsabue) ne peut être modifié que par lui-même."
            )
        # Interdire de créer un autre utilisateur avec le username du superadmin
        if not change and obj.username == SUPERADMIN_USERNAME:
            raise PermissionDenied(
                "Ce nom d'utilisateur est réservé au superadmin du système."
            )
        # Si c'est le superadmin protégé qui crée/modifie, laisser faire
        if request.user.is_superuser:
            if obj.is_admin and not obj.is_superuser and not obj.is_staff:
                obj.is_staff = True
            super().save_model(request, obj, form, change)
            return

        # Pour les admins d'école ou plateforme (non superuser)
        if request.user.is_authenticated and request.user.is_admin:
            # Assigner automatiquement l'école lors de la création (sauf pour admin plateforme)
            if not change and not obj.school and request.user.school:
                obj.school = request.user.school

            # Les admins d'école ne peuvent pas créer d'autres admins d'école
            # Les admins plateforme (sans école) peuvent créer des admins d'école
            if request.user.school and obj.is_admin and obj != request.user:
                from django.core.exceptions import PermissionDenied
                raise PermissionDenied(
                    "Les admins d'école ne peuvent pas créer d'autres admins. "
                    "Seuls les superadmins peuvent créer des admins d'école."
                )
            
            # S'assurer que les admins d'école ont is_staff=True pour accéder à Django admin
            if obj.is_admin and not obj.is_staff:
                obj.is_staff = True
        
        super().save_model(request, obj, form, change)
    
    def has_add_permission(self, request):
        """Superadmin et admins (école ou plateforme) peuvent créer des utilisateurs."""
        if request.user.is_superuser:
            return True
        if request.user.is_authenticated and request.user.is_admin and request.user.is_staff:
            return True
        return False

    def has_change_permission(self, request, obj=None):
        """Le superadmin protégé ne peut être modifié que par lui-même."""
        if obj and self._is_protected_superadmin(obj) and request.user != obj:
            return False
        if request.user.is_superuser:
            return True
        if request.user.is_authenticated and request.user.is_admin and request.user.is_staff:
            if obj is None:
                return True
            if request.user.school is None:
                return True  # Admin plateforme peut modifier (sauf le superadmin, déjà bloqué ci-dessus)
            if obj.school == request.user.school:
                if obj.is_admin and obj != request.user:
                    return False
                return True
        return False

    def has_delete_permission(self, request, obj=None):
        """Le superadmin protégé ne peut être supprimé que par lui-même."""
        if obj and self._is_protected_superadmin(obj) and request.user != obj:
            return False
        if request.user.is_superuser:
            return True
        if request.user.is_authenticated and request.user.is_admin and request.user.is_staff:
            if obj is None:
                return True
            if request.user.school is None:
                return True  # Admin plateforme peut supprimer (sauf le superadmin)
            if obj.school == request.user.school:
                if obj.is_admin and obj != request.user:
                    return False
                return True
        return False


@admin.register(Teacher)
class TeacherAdmin(SchoolScopedAdminMixin, admin.ModelAdmin):
    list_display = ['user', 'employee_id', 'specialization', 'hire_date', 'school']
    list_filter = ['hire_date']
    search_fields = ['user__username', 'employee_id', 'user__first_name', 'user__last_name']
    
    def school(self, obj):
        return obj.user.school
    
    def get_queryset(self, request):
        qs = super().get_queryset(request)
        if request.user.is_authenticated and request.user.is_admin and request.user.school and not request.user.is_superuser:
            return qs.filter(user__school=request.user.school)
        return qs


@admin.register(Parent)
class ParentAdmin(SchoolScopedAdminMixin, admin.ModelAdmin):
    list_display = ['user', 'profession', 'emergency_contact']
    search_fields = ['user__username', 'user__first_name', 'user__last_name']
    
    def get_queryset(self, request):
        qs = super().get_queryset(request)
        if request.user.is_authenticated and request.user.is_admin and request.user.school and not request.user.is_superuser:
            return qs.filter(user__school=request.user.school)
        return qs


@admin.register(Student)
class StudentAdmin(SchoolScopedAdminMixin, admin.ModelAdmin):
    list_display = ['user', 'student_id', 'school_class', 'is_former_student', 'graduation_year', 'parent', 'academic_year', 'enrollment_date', 'get_school']
    list_filter = ['academic_year', 'school_class', 'is_former_student', 'enrollment_date']
    search_fields = ['user__username', 'student_id', 'user__first_name', 'user__last_name', 'user__middle_name']
    
    def get_list_filter(self, request):
        if request.user.is_superuser:
            return ['academic_year', 'school_class', 'is_former_student', 'enrollment_date', 'user__school']
        return ['academic_year', 'school_class', 'is_former_student', 'enrollment_date']
    
    def get_school(self, obj):
        return obj.user.school.name if obj.user.school else '-'
    get_school.short_description = 'École'

    def get_queryset(self, request):
        qs = super().get_queryset(request)
        if request.user.is_authenticated and request.user.is_admin and request.user.school and not request.user.is_superuser:
            return qs.filter(user__school=request.user.school)
        return qs


def _is_protected_superadmin_user(user):
    """True si l'utilisateur est le superadmin protégé (Alidorsabue)."""
    return getattr(user, 'username', None) == SUPERADMIN_USERNAME and getattr(user, 'is_superuser', False)


@admin.register(PlatformSettings)
class PlatformSettingsAdmin(admin.ModelAdmin):
    """
    Paramètres globaux de la plateforme (verrouillage).
    Visible et modifiable uniquement par le superadmin protégé (Alidorsabue).
    """
    list_display = ['id', 'is_platform_locked', 'locked_message', 'updated_at']
    list_editable = ['is_platform_locked']
    readonly_fields = ['updated_at']
    fieldsets = (
        (None, {
            'fields': ('is_platform_locked', 'locked_message'),
            'description': _(
                'Lorsque « Plateforme verrouillée » est coché, seul le superadmin peut se connecter '
                '(API, admin Django, mobile, frontend). Les autres utilisateurs ne pourront plus se connecter.'
            ),
        }),
        (_('Suivi'), {'fields': ('updated_at',)}),
    )

    def get_queryset(self, request):
        qs = super().get_queryset(request)
        return qs.filter(pk=1)  # Singleton

    def has_module_permission(self, request):
        return _is_protected_superadmin_user(request.user)

    def has_add_permission(self, request):
        return False  # Une seule instance (singleton)

    def has_change_permission(self, request, obj=None):
        return _is_protected_superadmin_user(request.user)

    def has_delete_permission(self, request, obj=None):
        return False  # Ne pas supprimer le paramètre global
