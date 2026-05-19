.PHONY: help install dev lint test docker-build up down seed

help:
@echo "TaskFlow Platform Commands:"
@echo "  make install      Install all dependencies"
@echo "  make lint         Run linters (black, ruff, mypy, isort)"
@echo "  make test         Run tests with coverage"
@echo "  make docker-build Build all Docker images"
@echo "  make up           Start all services via docker-compose"
@echo "  make down         Stop all services"
@echo "  make seed         Seed database with sample data"

install:
pip install -r services/gateway/requirements.txt
pip install -r services/task_service/requirements.txt
pip install -r services/notification_service/requirements.txt
pip install -r services/analytics_service/requirements.txt

lint:
black --check services/ tests/
ruff check services/ tests/
mypy services/ --ignore-missing-imports
isort --check-only services/ tests/

test:
pytest -v --cov=services --cov-report=term-missing tests/

docker-build:
docker-compose -f deployments/docker-compose/docker-compose.yml build

up:
docker-compose -f deployments/docker-compose/docker-compose.yml up -d

down:
docker-compose -f deployments/docker-compose/docker-compose.yml down

seed:
docker-compose -f deployments/docker-compose/docker-compose.yml exec task-service python /app/../scripts/seed_data.py
