# 🧠 MindFlow

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Flutter](https://img.shields.io/badge/Flutter-v3+-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Supabase](https://img.shields.io/badge/Supabase-Backend-3ECF8E?logo=supabase&logoColor=white)](https://supabase.com)
[![FastAPI](https://img.shields.io/badge/FastAPI-Python-009688?logo=fastapi&logoColor=white)](https://fastapi.tiangolo.com)
[![Go](https://img.shields.io/badge/Go-Backend-00ADD8?logo=go&logoColor=white)](https://go.dev)
[![Docker](https://img.shields.io/badge/Docker-Dev-2496ED?logo=docker&logoColor=white)](https://www.docker.com)

**MindFlow** is a modern mobile application designed for mental wellness and personal productivity. It integrates focus tracking, meditation, ambient audio mixing, curated videos, and daily motivation into a cohesive, beautifully designed user experience.

---

## 🚀 Key Modules

| Module | Description | Status |
| :--- | :--- | :--- |
| **🧠 Flow / Pomodoro** | Focus timer with customized work/break cycle alerts to sustain deep work. | ✅ Active |
| **🧘 Meditation** | Guided breathing exercises, timers, and meditation sessions. | ✅ Active |
| **🎵 Music** | Real-time AI-generated white noise and ambient sounds mixer. | ✅ Active |
| **🎬 Video** | Curated lifestyle, mindfulness, and educational video library. | ✅ Active |
| **💡 Quote** | Motivational quotes delivered on morning schedules or custom time slots. | ✅ Active |

---

## 🛠 Tech Stack

- **Frontend:** Flutter (iOS & Android)
- **Backend Stack (Hybrid/Mixed):**
  - **Supabase:** Database (PostgreSQL), Auth, Edge Functions
  - **FastAPI (Python):** Async workers, scheduled jobs, Celery processing
  - **Go:** High-performance REST APIs
- **Database & Caching:** PostgreSQL & Redis
- **Background Tasks:** Celery + Redis (Python backend)
- **Push Notifications:** Firebase Cloud Messaging (FCM)
- **Containerization & Dev Env:** Docker, Docker Compose, Supabase Local Emulator

---

## 📂 Repository Structure

```text
mindflow/
├── AGENTS.md                  # Critical guidelines and rules for AI agents/developers
├── docker-compose.yml         # Full dev stack (API, Worker, Beat, DB, Redis)
├── docker-compose.prod.yml    # Production compose setup
├── .env.example               # Example environment variables template
├── frontend/                  # Flutter mobile application
│   └── lib/
│       ├── core/              # Theme, routing, dependency injection, constants
│       ├── features/          # quote/, meditation/, flow/, music/, video/
│       └── shared/            # Shared reusable widgets & utilities
├── backend/                   # Python (FastAPI) and/or Go backend codebase
└── supabase/                  # Supabase database config, migrations, and Edge Functions
```

---

## 💻 Local Development Setup

### Prerequisites
Make sure you have the following installed on your system:
- **Docker & Docker Compose**
- **Flutter SDK** (v3+)
- **Supabase CLI** (for local DB/emulator development)

### 1. Backend Services (Docker Compose)
Inside the root directory, create a `.env` file from the example:
```bash
cp .env.example .env
```

Start the local stack in the background:
```bash
docker compose up -d
```

Useful commands for the FastAPI backend:
```bash
# Tail API logs
docker compose logs -f api

# Run database migrations
docker compose exec api alembic upgrade head

# Run tests
docker compose exec api pytest
```

### 2. Supabase Local Emulator
To run the local Supabase instance (which runs via Docker internally):
```bash
# Start the Supabase local emulator
supabase start

# Reset local database and apply migrations
supabase db reset

# Pull schema changes from a remote project
supabase db pull

# Push local migrations to production
supabase db push
```

### 3. Frontend App (Flutter)
Navigate to the `frontend` folder and get the dependencies:
```bash
cd frontend
flutter pub get
```

Run the application:
```bash
flutter run
```

---

## 🤖 AI Agent Guidelines
This repository is configured for AI agent collaboration. **Before making any modifications to the codebase**, agents and developers **MUST** read [AGENTS.md](file:///home/thanh/pxmindflow/AGENTS.md) in full.

Important rules include:
- Always use Docker/Supabase Local Emulator for running services. Do not run them directly on the host.
- Update the relevant specification files under `docs/` after any meaningful database, API, environment, or feature changes.
- Ensure strict adherence to the coding standards (lint rules, naming conventions, and file structures) listed in [AGENTS.md](file:///home/thanh/pxmindflow/AGENTS.md).
