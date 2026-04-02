# E-School Management Platform

Plateforme scolaire digitale complète pour les écoles privées en RDC et autres pays africains.

## 🎯 Vue d'ensemble

Cette plateforme couvre tout le cycle de vie de l'élève :
- ✅ Inscription & Réinscription
- ✅ Suivi scolaire (notes, absences, discipline)
- ✅ Communication école–parents (SMS, WhatsApp, annonces)
- ✅ E-learning (cours, devoirs, quiz)
- ✅ Évaluations & bulletins
- ✅ Bibliothèque numérique
- ✅ Encadrement à domicile (tutoring)
- ✅ Réunions parents-enseignants
- ✅ Paiements (frais scolaires & contenus)

## 👥 Rôles utilisateurs

- **Administrateur école** : Gestion complète de l'école (inscriptions, classes, enseignants, statistiques, paiements)
- **Enseignant** : Gestion des cours, notes, présences, devoirs, examens, réunions
- **Comptable** : Gestion des paiements, mouvements de caisse, reçus
- **Responsable discipline** : Suivi et traitement des cas disciplinaires
- **Parent** : Suivi des enfants, réunions, paiements, encadrement, bibliothèque
- **Élève** : Tableau de bord, cours, devoirs, examens en ligne, bibliothèque, notes

## 🏗️ Architecture

### Backend
- **Framework** : Django 4.2.x + Django REST Framework
- **Base de données** : PostgreSQL (production) / SQLite (développement)
- **Authentification** : JWT (Simple JWT)
- **Architecture** : Multi-tenant (multi-écoles)
- **Tâches asynchrones** : Celery + Redis (SMS, WhatsApp, notifications)
- **Paiements** : Intégration Stripe
- **Documentation API** : drf-yasg (Swagger)
- **PDF** : ReportLab, WeasyPrint, PyMuPDF
- **Tests** : pytest, pytest-django, pytest-cov

### Frontend Web
- **Stack** : React 18, TypeScript, Vite
- **UI** : Tailwind CSS, React Hook Form, Zod
- **État** : Zustand, React Query
- **Usage** : Interfaces administrateur, enseignant, parent, élève (desktop, tablette, mobile)

### Application Mobile
- **Framework** : Flutter
- **Application unifiée** : Élèves & Parents (une seule app, rôle détecté à la connexion)
- **Plateformes** : Android, iOS
- **Optimisations** : Mode offline-first, cache (Hive), synchronisation, notifications push (Firebase)

## 📁 Structure du projet

```
E-SCHOOL/
├── backend/                 # API Django
│   ├── config/              # Configuration Django (settings, Celery, etc.)
│   ├── apps/                # Modules fonctionnels
│   │   ├── accounts/        # Authentification & utilisateurs (rôles, profils)
│   │   ├── schools/         # Gestion multi-écoles (classes, matières, périodes)
│   │   ├── enrollment/      # Inscription & réinscription
│   │   ├── academics/       # Suivi scolaire (notes, présences, discipline, bulletins)
│   │   ├── elearning/       # E-learning (cours, devoirs, quiz)
│   │   ├── library/         # Bibliothèque numérique
│   │   ├── payments/        # Paiements (frais, plans, reçus)
│   │   ├── communication/  # Communication (notifications, messages, 
├── frontend/                # Application web React + Vite
│   ├── src/
│   │   ├── components/      # Composants (auth, layout, ui)
│   │   ├── pages/           # Pages par rôle (admin, teacher, parent, student, accountant, discipline)
│   │   ├── services/        # Services API
│   │   ├── store/           # Zustand
│   │   └── types/           # Types TypeScript
│   └── package.json
└── mobile/                  # Application Flutter (Élèves & Parents)
    └── pubspec.yaml
```

## 🚀 Installation

### Prérequis

- Python 3.9+
- Node.js 16+
- PostgreSQL (ou SQLite pour le développement)
- Redis (optionnel, pour Celery)
- Flutter (pour l’application mobile)

### Backend

```bash
cd backend
python -m venv venv

# Windows
venv\Scripts\activate

# Linux / Mac
source venv/bin/activate

pip install -r requirements.txt
```

Copier `.env.example` vers `.env` et configurer les variables. Puis :

```bash
# Avec SQLite (développement) sous Windows PowerShell par exemple :
$env:USE_SQLITE="True"
python manage.py migrate
python manage.py createsuperuser
python manage.py runserver
```

Le serveur est accessible sur `http://localhost:8000`.

### Frontend Web

```bash
cd frontend
npm install
```

Créer un fichier `.env` avec `VITE_API_URL=http://localhost:8000/api`, puis :

```bash
npm run dev
```

L’application web est accessible sur `http://localhost:3000` (ou le port indiqué par Vite).

### Mobile (Flutter)

```bash
cd mobile
flutter pub get
flutter run
```

### Celery (optionnel)

Pour les tâches asynchrones (SMS, WhatsApp, notifications) :

```bash
# Démarrer Redis puis :
cd backend
celery -A config worker -l info
celery -A config beat -l info
```

Pour plus de détails, voir les README des sous-projets (frontend, mobile) et **backend/.env.example** pour les variables d'environnement.

## 🔧 Configuration

- **Backend** : copier `.env.example` vers `.env` (base de données, clés API, Stripe, Twilio, etc.).
- **Frontend** : créer `.env` avec `VITE_API_URL=http://localhost:8000/api`.

## 📱 Fonctionnalités principales

### Mode hors-ligne (mobile)
- Synchronisation automatique lors de la reconnexion
- Cache local pour les contenus fréquents (offline-first)

### Sécurité
- Authentification JWT (refresh tokens)
- Isolation des données par école (multi-tenant)
- Permissions selon les rôles
- AXES : 

### Optimisations pour faible connectivité
- Compression des données
- Synchronisation incrémentale
- Cache agressif
- Mode hors-ligne complet (mobile)

## 📚 Documentation

- **Frontend web** : [frontend/README.md](frontend/README.md)
- **Mobile** : [mobile/README.md](mobile/README.md)
- **Backend** : [backend/BACKEND_IMPROVEMENTS.md](backend/BACKEND_IMPROVEMENTS.md) — pistes d’évolution
- **Frontend** : [frontend/FRONTEND_SUMMARY.md](frontend/FRONTEND_SUMMARY.md) — résumé du projet
- **Configuration** : `backend/.env.example` pour les variables d’environnement de l’API

## 🚂 Déploiement (Railpack / Railway)

Ce dépôt est un **monorepo**. Railpack ne doit pas être lancé à la racine (où il ne voit que le README) mais sur le sous-dossier à déployer.

### Backend (API Django)

1. Dans votre projet Railway (ou plateforme utilisant Railpack), créez un service pour l’**API**.
2. Définissez le **répertoire racine** (Root Directory) du service sur **`backend`** (et non la racine du repo).
3. Railpack détectera alors Python (`requirements.txt`, `manage.py`) et utilisera `backend/railpack.json` pour la commande de démarrage (migrations, collectstatic, gunicorn).
4. Configurez les variables d’environnement (base de données, clés API, etc.) comme indiqué dans `backend/.env.example`.

### Frontend (React)

Pour déployer l’application web, créez un **second service** avec le répertoire racine sur **`frontend`**, afin que Railpack détecte Node et exécute `npm install` puis `npm run build`. Configurez la variable d’API (ex. `VITE_API_URL`) vers l’URL de votre backend déployé.

## 📄 Licence

Propriétaire - Tous droits réservés
