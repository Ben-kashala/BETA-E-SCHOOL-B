"""
Script pour créer une école et l'associer à l'utilisateur ADMIN
Usage: python manage.py shell < create_school.py
Ou: python manage.py runscript create_school (si django-extensions est installé)
"""
import os
import django

# Configuration Django
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings')
django.setup()

from apps.schools.models import School
from apps.accounts.models import User


def create_default_school():
    """Crée une école par défaut et l'associe à l'utilisateur ADMIN"""
    
    # Vérifier si une école existe déjà
    existing_school = School.objects.first()
    if existing_school:
        print(f"Une école existe déjà : {existing_school.name} (Code: {existing_school.code})")
        school = existing_school
    else:
        # Créer une nouvelle école
        school = School.objects.create(
            name="École par défaut",
            code="DEFAULT",
            address="Adresse de l'école",
            city="Kinshasa",
            country="RDC",
            phone="+243000000000",
            email="admin@ecole.com",
            school_type="PRIMAIRE",
            academic_year="2024-2025",
            currency="CDF",
            language="fr",
            is_active=True
        )
        print(f"✓ École créée : {school.name} (Code: {school.code}, ID: {school.id})")
    
    # Trouver tous les utilisateurs ADMIN sans école
    admin_users = User.objects.filter(role='ADMIN', school__isnull=True)
    
    if admin_users.exists():
        count = 0
        for admin_user in admin_users:
            admin_user.school = school
            admin_user.save()
            count += 1
            print(f"✓ Utilisateur {admin_user.username} associé à l'école {school.name}")
        
        print(f"\n✓ {count} utilisateur(s) ADMIN associé(s) à l'école")
    else:
        # Vérifier si des admins ont déjà une école
        admins_with_school = User.objects.filter(role='ADMIN', school__isnull=False)
        if admins_with_school.exists():
            print(f"\n✓ {admins_with_school.count()} utilisateur(s) ADMIN ont déjà une école associée")
        else:
            print("\n⚠ Aucun utilisateur ADMIN trouvé")
            print("   Créez d'abord un utilisateur avec le rôle ADMIN")
    
    return school


if __name__ == '__main__':
    print("=" * 60)
    print("Création d'une école et association aux utilisateurs ADMIN")
    print("=" * 60)
    print()
    
    school = create_default_school()
    
    print()
    print("=" * 60)
    print("Terminé !")
    print("=" * 60)
    print()
    print("Vous pouvez maintenant créer des classes dans l'application.")
