"""
Base admin classes for school-scoped administration
"""
from django.contrib import admin
from django.core.exceptions import PermissionDenied
from apps.schools.models import School


class SchoolScopedAdminMixin:
    """
    Mixin pour filtrer automatiquement les objets par école pour les admins d'école.
    Les super-admins Django peuvent voir toutes les écoles.
    """
    
    def get_queryset(self, request):
        qs = super().get_queryset(request)
        
        # Si l'utilisateur est un super-admin Django, il voit tout
        if request.user.is_superuser:
            return qs
        
        # Admin plateforme (ADMIN sans école) : voit tout comme le superadmin
        if request.user.is_authenticated and request.user.is_admin and request.user.school is None:
            return qs
        # Si l'utilisateur est un admin d'école, filtrer par son école
        if request.user.is_authenticated and request.user.is_admin and request.user.school:
            # Vérifier si le modèle a un champ 'school'
            if hasattr(self.model, 'school'):
                return qs.filter(school=request.user.school)
            # Si le modèle a une relation vers un modèle avec 'school' (ex: User -> School)
            elif hasattr(self.model, 'user') and hasattr(self.model.user.field.related_model, 'school'):
                return qs.filter(user__school=request.user.school)
            # Pour les modèles liés via ForeignKey vers des modèles avec school
            elif hasattr(self.model, '_meta'):
                # Chercher les relations vers des modèles avec school
                for field in self.model._meta.get_fields():
                    if hasattr(field, 'related_model') and hasattr(field.related_model, 'school'):
                        return qs.filter(**{f'{field.name}__school': request.user.school})
        
        # Si l'utilisateur n'est pas admin d'école, ne rien retourner
        if request.user.is_authenticated and not request.user.is_superuser:
            if not request.user.is_admin or not request.user.school:
                return qs.none()
        
        return qs
    
    def has_module_permission(self, request):
        """Permet aux admins (plateforme ou école) de voir les modules dans Django Admin"""
        if request.user.is_superuser:
            return True
        if request.user.is_authenticated and request.user.is_admin and request.user.is_staff:
            return True
        return False

    def has_add_permission(self, request):
        """Superadmin et admins (plateforme ou école) peuvent ajouter des objets"""
        if request.user.is_superuser:
            return True
        if request.user.is_authenticated and request.user.is_admin and request.user.is_staff:
            return True
        return False
    
    def has_view_permission(self, request, obj=None):
        """Les admins (plateforme ou école) peuvent voir les objets"""
        if request.user.is_superuser:
            return True
        if request.user.is_authenticated and request.user.is_admin and request.user.is_staff:
            if obj is None:
                return True
            # Admin plateforme : peut tout voir
            if request.user.school is None:
                return True
            # Vérifier que l'objet appartient à l'école de l'admin
            if hasattr(obj, 'school'):
                return obj.school == request.user.school
            elif hasattr(obj, 'user') and hasattr(obj.user, 'school'):
                return obj.user.school == request.user.school
            return True
        return False

    def has_change_permission(self, request, obj=None):
        """Les admins (plateforme ou école) peuvent modifier les objets"""
        if request.user.is_superuser:
            return True
        if request.user.is_authenticated and request.user.is_admin and request.user.is_staff:
            if obj is None:
                return True
            if request.user.school is None:
                return True
            # Vérifier que l'objet appartient à l'école de l'admin
            if hasattr(obj, 'school'):
                return obj.school == request.user.school
            elif hasattr(obj, 'user') and hasattr(obj.user, 'school'):
                return obj.user.school == request.user.school
            return True
        return False

    def has_delete_permission(self, request, obj=None):
        """Les admins (plateforme ou école) peuvent supprimer les objets"""
        if request.user.is_superuser:
            return True
        if request.user.is_authenticated and request.user.is_admin and request.user.is_staff:
            if obj is None:
                return True
            if request.user.school is None:
                return True
            # Vérifier que l'objet appartient à l'école de l'admin
            if hasattr(obj, 'school'):
                return obj.school == request.user.school
            elif hasattr(obj, 'user') and hasattr(obj.user, 'school'):
                return obj.user.school == request.user.school
            return True
        return False

    def formfield_for_foreignkey(self, db_field, request, **kwargs):
        """
        Filtre les choix dans les ForeignKey pour ne montrer que l'école de l'admin
        """
        # Si c'est un champ ForeignKey vers School, filtrer par l'école de l'admin
        if db_field.name == 'school' and db_field.related_model == School:
            if request.user.is_authenticated and request.user.is_admin and request.user.school and not request.user.is_superuser:
                # Ne montrer que l'école de l'admin
                kwargs['queryset'] = School.objects.filter(id=request.user.school.id)
                # Rendre le champ en lecture seule pour les admins d'école
                kwargs['disabled'] = True
        
        # Pour les autres ForeignKey qui pointent vers des modèles avec un champ 'school'
        elif hasattr(db_field, 'related_model'):
            related_model = db_field.related_model
            if hasattr(related_model, 'school'):
                if request.user.is_authenticated and request.user.is_admin and request.user.school and not request.user.is_superuser:
                    # Filtrer les objets par l'école de l'admin
                    kwargs['queryset'] = related_model.objects.filter(school=request.user.school)
        
        return super().formfield_for_foreignkey(db_field, request, **kwargs)
    
    def get_form(self, request, obj=None, **kwargs):
        """
        Personnalise le formulaire pour les admins d'école
        """
        form = super().get_form(request, obj, **kwargs)
        
        # Pour les admins d'école, rendre le champ 'school' en lecture seule et le pré-remplir
        if request.user.is_authenticated and request.user.is_admin and request.user.school and not request.user.is_superuser:
            if 'school' in form.base_fields:
                form.base_fields['school'].disabled = True
                form.base_fields['school'].required = False
                # Pré-remplir avec l'école de l'admin si c'est une nouvelle création
                if obj is None:
                    form.base_fields['school'].initial = request.user.school.id
        
        return form
    
    def get_list_filter(self, request):
        """
        Filtre les list_filter pour ne montrer que l'école de l'admin
        """
        list_filter = super().get_list_filter(request) if hasattr(super(), 'get_list_filter') else self.list_filter
        
        if request.user.is_authenticated and request.user.is_admin and request.user.school and not request.user.is_superuser:
            # Remplacer le filtre 'school' par un filtre personnalisé qui ne montre que l'école de l'admin
            if list_filter:
                # Retirer 'school' des filtres car il n'y a qu'une seule école
                list_filter = [f for f in list_filter if f != 'school']
        
        return list_filter
    
    def save_model(self, request, obj, form, change):
        """
        Assigner automatiquement l'école lors de la création et empêcher la modification
        """
        # Pour les admins d'école, toujours assigner leur école
        if request.user.is_authenticated and request.user.is_admin and request.user.school and not request.user.is_superuser:
            if hasattr(obj, 'school'):
                # Toujours assigner l'école de l'admin, même si modifié dans le formulaire
                # Cela garantit qu'un admin ne peut pas créer/modifier des objets pour d'autres écoles
                obj.school = request.user.school
        
        super().save_model(request, obj, form, change)
