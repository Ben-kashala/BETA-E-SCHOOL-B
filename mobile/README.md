# 📱 E-School Mobile – Application unifiée

Application mobile **Flutter** du projet **E-SCHOOL** (plateforme scolaire pour écoles privées, RDC / Afrique). Une seule app, plusieurs rôles : **Élève**, **Parent**, et selon les droits **Admin**, **Enseignant**, **Comptable**.

## 🎯 Concept

Une **seule application** qui s’adapte au rôle de l’utilisateur après connexion :
- **Élève** : Cours, devoirs, examens, bibliothèque, notes, communication
- **Parent** : Inscription, suivi scolaire, réunions, paiements, encadrement, bibliothèque
- **Admin / Enseignant / Comptable** : Dashboards et fonctionnalités dédiées (selon configuration)

## ✨ Fonctionnalités

### Pour les Élèves
- ✅ Authentification
- ✅ Tableau de bord personnalisé
- ✅ Cours avec téléchargement offline
- ✅ Devoirs avec soumission
- ✅ Examens en ligne
- ✅ Bibliothèque
- ✅ Consultation des notes

### Pour les Parents
- ✅ Authentification
- ✅ Tableau de bord avec vue des enfants
- ✅ Inscription/Réinscription
- ✅ Suivi scolaire (notes des enfants)
- ✅ Réunions parents-professeurs
- ✅ Paiements en ligne
- ✅ Encadrement domicile
- ✅ Bibliothèque

### Commun
- ✅ Mode offline-first avec synchronisation (Workmanager, Hive, SQLite)
- ✅ Cache intelligent (Hive, cached_network_image)
- ✅ Notifications locales (flutter_local_notifications)
- ✅ Sécurité (flutter_secure_storage, JWT)
- ✅ Optimisé pour faible bande passante

## 🏗️ Architecture

### Gestion des rôles
L'application détecte automatiquement le rôle de l'utilisateur après connexion et :
1. Affiche le dashboard approprié
2. Limite l'accès aux routes selon le rôle
3. Adapte la navigation (bottom bar)
4. Personnalise les fonctionnalités disponibles

### Routing conditionnel
Le router (`lib/core/router/app_router.dart`) vérifie le rôle et :
- Redirige vers le dashboard si accès non autorisé
- Affiche uniquement les routes pertinentes
- Adapte la navigation (bottom bar, menus) au contexte

### Stack technique
- **State** : Riverpod + Provider
- **Navigation** : go_router
- **Réseau** : Dio, connectivity_plus
- **Stockage** : Hive, SQLite (sqflite), flutter_secure_storage
- **PDF** : pdf, syncfusion_flutter_pdfviewer, flutter_pdfview

## 📦 Installation

```bash
# Installer les dépendances
flutter pub get

# Lancer l'application
flutter run
```

## 🔧 Configuration

1. **API** : Modifier l’URL de l’API dans `lib/core/config/app_config.dart` (pointez vers le backend E-SCHOOL).
2. **Sécurité** : En production, configurer une clé de chiffrement adaptée (stockage sécurisé).
3. **Firebase** (optionnel) : Pour les notifications push, ajouter `google-services.json` dans `android/app/` et configurer Firebase.

## 📱 Structure

```
mobile/
├── lib/
│   ├── core/                  # Configuration et services partagés
│   │   ├── config/            # app_config, screen_config
│   │   ├── database/            # Hive, SQLite (database_service)
│   │   ├── network/            # api_service, connectivity_service
│   │   ├── services/           # notification_service, sync_service
│   │   ├── router/             # app_router (navigation + rôles)
│   │   ├── theme/              # Thème Material
│   │   ├── providers/          # auth_provider, etc.
│   │   ├── widgets/            # Composants réutilisables
│   │   └── preferences/        # Préférences utilisateur
│   └── features/
│       ├── auth/               # Connexion, splash
│       ├── dashboard/          # Dashboard selon le rôle
│       ├── admin/              # Admin (classes, enseignants, inscriptions, etc.)
│       ├── teacher/            # Enseignant (cours, notes, présences, quiz…)
│       ├── accountant/         # Comptable (caisse, dépenses)
│       ├── courses/            # (Élèves)
│       ├── assignments/       # (Élèves)
│       ├── exams/              # (Élèves)
│       ├── enrollment/         # (Parents)
│       ├── meetings/           # (Parents)
│       ├── payments/            # (Parents)
│       ├── tutoring/           # (Parents)
│       ├── library/            # (Commun)
│       ├── grades/             # (Commun)
│       ├── discipline/         # Discipline
│       ├── communication/     # Communication
│       ├── profile/            # Profil
│       ├── preferences/       # Paramètres
│       └── students/           # Liste / détail élèves (admin/teacher)
```

## 🔐 Sécurité

- Vérification du rôle côté client ET serveur
- Routes protégées selon le rôle
- Tokens JWT sécurisés
- Validation des permissions

## 🚀 Déploiement

Une seule APK/IPA : l’interface s’adapte au rôle (élève, parent, admin, enseignant, comptable) après connexion.

---

**Projet E-SCHOOL** – [README principal](../README.md) | **Une app, plusieurs rôles** 🎓👨‍👩‍👧
