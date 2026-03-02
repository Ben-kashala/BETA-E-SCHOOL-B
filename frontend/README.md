# E-School Management – Frontend Web

Application web **React 18 + TypeScript + Vite** pour la plateforme E-SCHOOL (écoles privées, RDC / Afrique). Interfaces pour tous les rôles : administrateur, enseignant, comptable, responsable discipline, parent, élève.

## 🚀 Démarrage

### Installation

```bash
npm install
```

### Développement

```bash
npm run dev
```

L’application est accessible sur `http://localhost:5173` (ou le port affiché par Vite).

### Build Production

```bash
npm run build
```

## 📁 Structure

```
src/
├── components/           # Composants réutilisables
│   ├── auth/            # Authentification
│   ├── layout/          # Layout principal
│   └── ui/              # Composants UI de base
├── pages/               # Pages par rôle
│   ├── admin/           # Administrateur école
│   ├── teacher/         # Enseignant
│   ├── parent/          # Parent
│   ├── student/         # Élève
│   ├── accountant/      # Comptable (paiements, caisse, dépenses)
│   ├── discipline-officer/  # Responsable discipline
│   ├── auth/            # Connexion
│   └── shared/          # Pages partagées (ex. lecteur de livres)
├── services/            # Services API (axios)
├── store/               # State management (Zustand)
├── types/               # Types TypeScript
└── utils/               # Utilitaires
```

## 🎨 Technologies

- **React 18** – Bibliothèque UI
- **TypeScript** – Typage statique
- **Vite 5** – Build et dev server
- **Tailwind CSS** – Styling
- **React Router v6** – Routing
- **TanStack React Query** – Données serveur et cache
- **Zustand** – State management (auth, UI)
- **React Hook Form** – Formulaires
- **Zod** – Validation (avec @hookform/resolvers)
- **Axios** – Client HTTP
- **Lucide React** – Icônes
- **react-hot-toast** – Notifications

## 👥 Profils utilisateurs

### Administrateur école
- Inscriptions, classes, enseignants
- Statistiques, discipline, bibliothèque
- E-learning, encadrement, réunions
- Paiements

### Enseignant
- Notes, présences, discipline
- Devoirs, quiz, examens, cours e-learning
- Réunions, bibliothèque, encadrement
- Communication

### Comptable
- Paiements et reçus
- Caisse (mouvements)
- Dépenses de l’école

### Responsable discipline
- Suivi des cas disciplinaires
- Réunions, communication

### Parent
- Suivi scolaire (notes des enfants)
- Réunions, paiements
- Bibliothèque, encadrement à domicile
- Communication

### Élève
- Tableau de bord
- Cours, devoirs, examens, quiz
- Bibliothèque, notes, discipline
- Communication

## 🔧 Configuration

Créer un fichier `.env` à la racine de `frontend/` :

```env
VITE_API_URL=http://localhost:8000/api
```

L’API backend doit être démarrée (voir [README principal](../README.md)).

## 📱 Responsive

L'application est entièrement responsive et optimisée pour :
- Desktop
- Tablette
- Mobile

## ⚡ Optimisations

- Lazy loading des routes et des images
- Code splitting (Vite)
- Cache avec TanStack React Query
- Optimisé pour faible débit
- Lint : `npm run lint`
