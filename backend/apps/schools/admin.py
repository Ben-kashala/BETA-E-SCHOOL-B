from django.contrib import admin
from .models import School, Section, SchoolClass, Subject, ClassSubject, StudentClassEnrollment
from .admin_base import SchoolScopedAdminMixin


@admin.register(School)
class SchoolAdmin(SchoolScopedAdminMixin, admin.ModelAdmin):
    list_display = ['name', 'code', 'city', 'country', 'is_active', 'created_at']
    list_filter = ['is_active', 'country', 'city']
    search_fields = ['name', 'code', 'email']
    readonly_fields = ['created_at', 'updated_at']
    fieldsets = (
        (None, {
            'fields': ('name', 'code', 'school_type', 'is_active'),
        }),
        ('Adresse', {
            'fields': (
                'address_number',
                'address_avenue',
                'address_quarter',
                'commune',
                'city',
                'province',
                'country',
                'address',
            ),
        }),
        ('Contact', {
            'fields': ('phone', 'email', 'website'),
        }),
        ('Configuration', {
            'fields': ('academic_year', 'currency', 'language', 'promoters'),
        }),
        ('Suivi', {
            'fields': ('created_at', 'updated_at'),
        }),
    )
    
    def get_queryset(self, request):
        qs = super().get_queryset(request)
        # Admin plateforme : voit toutes les écoles
        if request.user.is_authenticated and request.user.is_admin and request.user.school is None:
            return qs
        # Les admins d'école ne peuvent voir que leur école
        if request.user.is_authenticated and request.user.is_admin and request.user.school and not request.user.is_superuser:
            return qs.filter(id=request.user.school.id)
        return qs

    def get_list_filter(self, request):
        """Retirer les filtres pour les admins d'école car ils n'ont qu'une seule école"""
        if request.user.is_superuser or (request.user.is_admin and request.user.school is None):
            return ['is_active', 'country', 'city']
        return ['is_active']  # Garder seulement is_active

    def has_add_permission(self, request):
        """Superadmin et admin plateforme peuvent créer des écoles"""
        if request.user.is_superuser:
            return True
        if request.user.is_authenticated and request.user.is_admin and request.user.school is None and request.user.is_staff:
            return True
        return False

    def has_delete_permission(self, request, obj=None):
        """Superadmin et admin plateforme peuvent supprimer des écoles"""
        if request.user.is_superuser:
            return True
        if request.user.is_authenticated and request.user.is_admin and request.user.school is None and request.user.is_staff:
            return True
        return False
    
    def formfield_for_foreignkey(self, db_field, request, **kwargs):
        """Empêcher la modification de l'école pour les admins d'école"""
        if db_field.name == 'school':
            if request.user.is_authenticated and request.user.is_admin and request.user.school and not request.user.is_superuser:
                kwargs['queryset'] = School.objects.filter(id=request.user.school.id)
                kwargs['disabled'] = True
        return super().formfield_for_foreignkey(db_field, request, **kwargs)


@admin.register(Section)
class SectionAdmin(SchoolScopedAdminMixin, admin.ModelAdmin):
    list_display = ['name', 'school', 'is_active', 'created_at']
    list_filter = ['is_active']
    search_fields = ['name', 'school__name']
    readonly_fields = ['created_at']
    
    def get_list_filter(self, request):
        if request.user.is_superuser:
            return ['school', 'is_active']
        return ['is_active']


@admin.register(SchoolClass)
class SchoolClassAdmin(SchoolScopedAdminMixin, admin.ModelAdmin):
    list_display = ['name', 'next_class_name', 'titulaire', 'is_terminal', 'school', 'level', 'grade', 'academic_year', 'is_active']
    list_filter = ['level', 'is_active', 'academic_year', 'titulaire']
    search_fields = ['name', 'school__name', 'titulaire__user__username', 'titulaire__user__last_name']
    
    def get_list_filter(self, request):
        if request.user.is_superuser:
            return ['school', 'level', 'is_active', 'academic_year', 'titulaire']
        return ['level', 'is_active', 'academic_year', 'titulaire']


@admin.register(Subject)
class SubjectAdmin(SchoolScopedAdminMixin, admin.ModelAdmin):
    list_display = ['name', 'code', 'school', 'period_max', 'is_active']
    list_filter = ['is_active']
    search_fields = ['name', 'code', 'school__name']
    
    def get_list_filter(self, request):
        if request.user.is_superuser:
            return ['school', 'is_active']
        return ['is_active']


@admin.register(StudentClassEnrollment)
class StudentClassEnrollmentAdmin(SchoolScopedAdminMixin, admin.ModelAdmin):
    list_display = ['student', 'school_class', 'status', 'enrolled_at', 'left_at']
    list_filter = ['status', 'school_class']
    search_fields = ['student__student_id', 'student__user__first_name', 'student__user__last_name', 'school_class__name']
    readonly_fields = ['enrolled_at']
    
    def get_queryset(self, request):
        qs = super().get_queryset(request)
        if request.user.is_authenticated and request.user.is_admin and request.user.school and not request.user.is_superuser:
            return qs.filter(school_class__school=request.user.school)
        return qs
    
    def get_list_filter(self, request):
        if request.user.is_superuser:
            return ['status', 'school_class__school', 'school_class']
        return ['status', 'school_class']


@admin.register(ClassSubject)
class ClassSubjectAdmin(SchoolScopedAdminMixin, admin.ModelAdmin):
    list_display = ['school_class', 'subject', 'domain', 'period_max', 'created_at']
    list_filter = ['school_class', 'domain']
    search_fields = ['subject__name', 'school_class__name']
    
    def get_queryset(self, request):
        qs = super().get_queryset(request)
        if request.user.is_authenticated and request.user.is_admin and request.user.school and not request.user.is_superuser:
            return qs.filter(school_class__school=request.user.school)
        return qs
    
    def get_list_filter(self, request):
        if request.user.is_superuser:
            return ['school_class__school', 'school_class']
        return ['school_class']
