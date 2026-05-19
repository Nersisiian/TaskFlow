# TaskFlow Microservice Platform

**Enterprise Task Management Backend** – built with Python 3.12, FastAPI, SQLAlchemy 2.0, Redis, Kafka, Docker & Kubernetes.

![architecture](docs/architecture.png)

## 🏗 Architecture
```mermaid
graph TD
    Client -->|HTTPS| Gateway(API Gateway)
    Gateway -->|Auth / Rate Limit| Redis
    Gateway -->|aiohttp| TaskService
    TaskService --> PostgreSQL
    TaskService -->|Kafka Events| NotificationService
    TaskService -->|Kafka Events| AnalyticsService
    AnalyticsService --> PostgreSQL
    AnalyticsService --> Redis
🚀 Quick Start (Docker)
bash
make up          # starts all services
make seed        # populates sample tasks
Then explore:

API Gateway Swagger: http://localhost:8000/docs

Task Service Swagger: http://localhost:8001/docs

Analytics Service: http://localhost:8003/docs

📋 API Examples
bash
# Login (admin role)
curl -X POST "http://localhost:8000/api/v1/auth/login?username=admin&password=adminpass"

# Create a task
curl -X POST "http://localhost:8000/api/v1/tasks" \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{"title":"Deploy to production","priority":"high"}'

# List tasks (paginated)
curl "http://localhost:8000/api/v1/tasks?skip=0&limit=10&status=todo" \
  -H "Authorization: Bearer <token>"
🧪 Testing & CI
bash
make lint          # black, ruff, mypy, isort
make test          # pytest with 80%+ coverage
GitHub Actions CI runs all checks on every push.

📦 Production Deployment
Kubernetes manifests are in deployments/k8s/.
Apply them with kubectl apply -f deployments/k8s/.

🛠 Tech Stack
Python 3.12, FastAPI, async/await everywhere

SQLAlchemy 2.0 (async), Alembic, PostgreSQL

Redis for caching & rate limiting

Apache Kafka for event-driven communication

Docker, Docker Compose, Kubernetes

GitHub Actions CI/CD

Pytest, coverage, pre-commit hooks

📁 Repository Structure
text
taskflow-platform/
├── services/
│   ├── gateway/             # API Gateway (auth, rate limit, proxy)
│   ├── task_service/        # Core CRUD, events producer
│   ├── notification_service/# Kafka consumer, mock notifications
│   └── analytics_service/   # Statistics, Redis cache, scheduler
├── deployments/
│   ├── docker-compose/      # Local dev stack
│   └── k8s/                 # Kubernetes manifests
├── tests/                   # Unit & integration tests
├── scripts/                 # Seed data, utility scripts
└── .github/workflows/       # CI/CD pipeline
MIT License – use it to ace your Middle Python Developer interviews!
