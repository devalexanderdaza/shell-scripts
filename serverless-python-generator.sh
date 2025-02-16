#!/bin/bash
# 🚀 Serverless Project Generator v1.0
# Author: Alexander Daza
# Email: dev.alexander.daza@gmail.com
# URL: https://github.com/devalexanderdaza
# License: MIT

set -eo pipefail

# ==========================================
# Configuración y Variables Globales
# ==========================================
declare -r RED='\033[0;31m'
declare -r GREEN='\033[0;32m'
declare -r BLUE='\033[0;34m'
declare -r YELLOW='\033[1;33m'
declare -r NC='\033[0m'
declare -r BOLD='\033[1m'

# Versiones mínimas requeridas
declare -r MIN_PYTHON_VERSION="3.8"
declare -r MIN_NODE_VERSION="16"
declare -r CONFIG_FILE="config.json"

# Variables globales
declare -a selected_plugins=()

# ==========================================
# Funciones de Utilidad
# ==========================================
log() { printf "%b%b%b\n" "${2:-$NC}" "$1" "$NC"; }
info() { log "$1" "$BLUE"; }
success() { log "$1" "$GREEN"; }
warning() { log "$1" "$YELLOW" >&2; }
error() { log "$1" "$RED" >&2; exit 1; }

print_step() {
    echo -e "\n${YELLOW}${BOLD}Step $1: $2${NC}\n"
}

# ==========================================
# Validaciones
# ==========================================
validate_project_name() {
    local name=$1
    if [[ ! $name =~ ^[a-zA-Z][-a-zA-Z0-9]{0,38}[a-zA-Z0-9]$ ]]; then
        error "❌ Nombre de proyecto inválido. Debe empezar con letra, usar solo letras, números o guiones, y tener entre 2-40 caracteres."
    fi
    if [[ -d "$name" ]]; then
        error "❌ El directorio '$name' ya existe."
    fi
}

check_environment() {
    info "🔍 Verificando ambiente de desarrollo..."
    
    local -a dependencies=("python3" "pip3" "git" "node" "npm")
    for dep in "${dependencies[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            error "❌ $dep no está instalado"
        fi
    done

    # Verificar versiones
    local python_version=$(python3 -c 'import sys; print(".".join(map(str, sys.version_info[:2])))')
    local node_version=$(node -v | cut -d'v' -f2 | cut -d'.' -f1)

    if ! python3 -c "import sys; exit(0 if sys.version_info >= (${MIN_PYTHON_VERSION//./, }) else 1)" &>/dev/null; then
        error "❌ Se requiere Python >= $MIN_PYTHON_VERSION (actual: $python_version)"
    fi

    if [[ $node_version -lt $MIN_NODE_VERSION ]]; then
        error "❌ Se requiere Node.js >= $MIN_NODE_VERSION (actual: $node_version)"
    fi

    success "✅ Ambiente verificado correctamente"
}

# ==========================================
# Configuración de Entorno
# ==========================================
setup_virtualenv() {
    info "🔧 Configurando entorno virtual..."
    if ! python3 -m venv "$1/.venv"; then
        error "❌ Error al crear entorno virtual"
    fi
    # shellcheck source=/dev/null
    source "$1/.venv/bin/activate" || error "❌ Error al activar entorno virtual"
    pip install --upgrade pip || error "❌ Error al actualizar pip"
    success "✅ Entorno virtual configurado"
}

setup_precommit() {
    info "🔧 Configurando pre-commit..."
    source .venv/bin/activate
    pip install pre-commit || error "❌ Error instalando pre-commit"
    
    # Instalar mypy y tipos específicos
    pip install mypy types-requests types-boto3 types-python-dateutil types-pyyaml types-setuptools || warning "⚠️ Error instalando algunos tipos de mypy"
    
    pre-commit install || error "❌ Error configurando pre-commit hooks"
    pre-commit autoupdate || warning "⚠️ Error actualizando pre-commit hooks"
    
    success "✅ Pre-commit configurado"
}

# ==========================================
# Gestión de Plugins
# ==========================================
print_plugin_menu() {
    local -a plugins=("$@")
    echo -e "\n📌 ${BOLD}Plugins disponibles:${NC}"
    for i in "${!plugins[@]}"; do
      echo -e "  ${GREEN}$((i+1)). ${NC}${plugins[i]}"
    done
}

validate_plugin_selection() {
    local num=$1
    local max=$2
    [[ "$num" =~ ^[0-9]+$ ]] && ((num >= 1 && num <= max))
}

select_plugins() {
    local -a plugins=(
        "serverless-python-requirements"
        "serverless-iam-roles-per-function" 
        "serverless-offline"
        "serverless-dynamodb-local"
        "serverless-localstack"
        "serverless-plugin-aws-alerts"
        "serverless-plugin-warmup"
        "serverless-prune-plugin"
    )
    
    print_plugin_menu "${plugins[@]}"
    
    local selected_numbers
    read -r -p "Seleccione plugins (números separados por espacio): " -a selected_numbers
    
    selected_plugins=()
    for num in "${selected_numbers[@]}"; do
        if validate_plugin_selection "$num" "${#plugins[@]}"; then
            selected_plugins+=("${plugins[$((num-1))]}")
        else
            warning "⚠️ Número inválido ignorado: $num"
        fi
    done
    
    if [[ ${#selected_plugins[@]} -gt 0 ]]; then
        info "🔌 Plugins seleccionados:"
        for plugin in "${selected_plugins[@]}"; do
            success "✅ $plugin"
        done
    else
        warning "⚠️ No se seleccionaron plugins"
    fi
}

install_serverless_plugins() {
    info "🔧 Instalando plugins..."
    for plugin in "${selected_plugins[@]}"; do
        echo -n "Instalando $plugin... "
        if npm install --save-dev "$plugin" &>/dev/null; then
            success "✅"
        else
            warning "⚠️"
        fi
    done
}

# ==========================================
# Creación de Estructura y Archivos
# ==========================================
create_project_structure() {
    info "📁 Creando estructura del proyecto..."
    local -a dirs=(
        "src/functions"
        "src/models"
        "src/utils"
        "tests/unit"
        "tests/integration"
        "docs"
        "scripts"
        "config"
    )
    
    for dir in "${dirs[@]}"; do
        mkdir -p "$1/$dir" || error "❌ Error al crear directorio $dir"
    done
    
    create_init_files "$1"
    create_readme "$1"
    create_env_example "$1"
    success "✅ Estructura creada"
}

create_init_files() {
    local name="$1"
    local dirs=(
        ""
        "config"
        "docs"
        "scripts"
        "src"
        "src/functions"
        "src/models"
        "src/utils"
        "tests"
        "tests/unit"
        "tests/integration"
    )

    for dir in "${dirs[@]}"; do
        local init_path="$name/${dir}/__init__.py"
        local module_name="${dir//\//.}"
        [[ -z "$module_name" ]] && module_name="$PROJECT_NAME"
        
        cat > "$init_path" <<EOF
"""Módulo $module_name para el proyecto $PROJECT_NAME."""
EOF
    done
}

create_env_example() {
    local name="$1"
    cat > "$name/.env.example" <<EOF
# Variables de entorno de ejemplo
AWS_ACCESS_KEY_ID=your_access_key
AWS_SECRET_ACCESS_KEY=your_secret_key
AWS_DEFAULT_REGION=us-east-1
DATABASE_URL=your_database_url
EOF
}

create_readme() {
   local name="$1"
   cat > "$name/README.md" <<EOF
# Serverless API

## 📋 Descripción
Serverless api scaffolding

## 🚀 Inicio Rápido

### Pre-requisitos
- Python 3.9+
- Node.js 18+
- AWS CLI configurado
- Serverless Framework

### Instalación
\`\`\`bash
# Crear y activar entorno virtual
python3 -m venv .venv
source .venv/bin/activate

# Instalar dependencias
pip install -r requirements.txt
npm install

# Iniciar desarrollo local
serverless offline start
\`\`\`

## 🏗️ Estructura del Proyecto
\`\`\`
├── src/
│   ├── functions/    # Funciones Lambda y handlers
│   ├── models/       # Modelos de datos y esquemas
│   └── utils/        # Utilidades compartidas
├── tests/
│   ├── unit/        # Tests unitarios
│   └── integration/ # Tests de integración
├── docs/           # Documentación del proyecto
├── scripts/        # Scripts de utilidad
└── config/         # Archivos de configuración
\`\`\`

## 🛠️ Desarrollo

### Comandos Principales
\`\`\`bash
# Ejecutar tests
pytest

# Verificar formato y tipos
pre-commit run --all-files

# Desplegar a dev
serverless deploy --stage dev

# Desplegar a prod
serverless deploy --stage prod
\`\`\`

## 📝 Endpoints API

### Órdenes de Trabajo
- GET /orders/{id} - Obtener orden

## 🔧 Configuración
- \`.env.example\` - Variables de entorno requeridas
- \`serverless.yml\` - Configuración de infraestructura
- \`config/\` - Configuraciones adicionales

## ⚡ Características
- Serverless Framework
- DynamoDB para persistencia
- SQS para procesamiento asíncrono
- Testing con pytest
- Validación de tipos con mypy
- Formateo con black y flake8
- Pre-commit hooks

## 📄 Licencia
Distribuido bajo la Licencia MIT. Ver \`LICENSE\` para más información.
EOF
}

create_serverless_config() {
    local name="$1"
    cat > "$name/serverless.yml" <<EOF
service: api

provider:
  name: aws
  runtime: python3.9
  region: \${opt:region, 'us-east-1'}
  stage: \${opt:stage, 'dev'}
  environment:
    STAGE: \${self:provider.stage}
    REGION: \${self:provider.region}

plugins:
$(printf "  - %s\n" "${selected_plugins[@]}")

custom:
  pythonRequirements:
    dockerizePip: true
    layer:
      name: python-deps

functions:
  hello:
    handler: src/functions/hello.handler
    events:
      - http:
          path: /
          method: get
EOF
}

create_docker_config() {
    local name="$1"
    cat > "$name/Dockerfile" <<'EOF'
FROM python:3.9-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY . .
CMD ["python", "src/app.py"]
EOF

    cat > "$name/docker-compose.yml" <<'EOF'
version: '3.8'
services:
  app:
    build: .
    volumes:
      - .:/app
    ports:
      - "3000:3000"
    env_file: .env
    environment:
      - AWS_ACCESS_KEY_ID=dummy
      - AWS_SECRET_ACCESS_KEY=dummy
      - AWS_DEFAULT_REGION=us-east-1
EOF
}

create_sample_lambda() {
    local dir="$1/src/functions"
    cat > "$dir/hello.py" <<'EOF'
"""Handler Lambda para el endpoint hello del proyecto."""

import json
import logging
from typing import Dict, Any

# Configurar logger
logger = logging.getLogger()
logger.setLevel(logging.INFO)


def handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """Manejador de Lambda para el endpoint hello.

    Args:
        event: Evento de API Gateway.
        context: Contexto de Lambda.

    Returns:
        Dict[str, Any]: Respuesta formateada para API Gateway.
    """
    logger.info("Event received: %s", event)

    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({"message": "Hello from Lambda!", "event": event}),
    }
EOF
}

create_requirements() {
    local name="$1"
    cat > "$name/requirements.txt" <<'EOF'
boto3>=1.26.0
pytest>=7.0.0
pytest-cov>=4.0.0
black>=23.0.0
flake8>=6.0.0
pynamodb>=5.0.0
python-dotenv>=1.0.0
requests>=2.28.0
mypy>=1.0.0
EOF
}

create_precommit_config() {
    local name="$1"
    cat > "$name/.pre-commit-config.yaml" <<'EOF'
repos:
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v4.4.0
    hooks:
      - id: trailing-whitespace
      - id: end-of-file-fixer
      - id: check-yaml
      - id: check-added-large-files

  - repo: https://github.com/psf/black
    rev: 23.12.1
    hooks:
      - id: black
        language_version: python3
        args: [--line-length=88]

  - repo: https://github.com/pycqa/flake8
    rev: 7.0.0
    hooks:
      - id: flake8
        args: [--max-line-length=88]
        additional_dependencies: [flake8-docstrings]

  - repo: https://github.com/pre-commit/mirrors-mypy
    rev: v1.8.0
    hooks:
      - id: mypy
        additional_dependencies:
          - types-requests
          - types-boto3
EOF
}

initialize_git() {
    git init
    cat > .gitignore <<'EOF'
.venv/
node_modules/
__pycache__/
.env
.DS_Store
*.pyc
.coverage
htmlcov/
.pytest_cache/
.serverless/
.mypy_cache/
EOF
    
    [[ $USE_PRECOMMIT == "y" ]] && setup_precommit
    git add .
    git commit -m "🚀 Commit inicial"
}

# ==========================================
# Función Principal
# ==========================================
main() {
    check_environment

    print_step "1" "Configuración del proyecto"
    read -r -p "📝 Nombre del proyecto: " PROJECT_NAME
    validate_project_name "$PROJECT_NAME"

    echo -e "\n📦 Características opcionales:"
    read -r -p "¿Usar entorno virtual? (y/n): " USE_VIRTUALENV
    read -r -p "¿Usar Docker? (y/n): " USE_DOCKER
    read -r -p "¿Inicializar Git? (y/n): " INIT_GIT
    read -r -p "¿Usar pre-commit? (y/n): " USE_PRECOMMIT

    print_step "2" "Selección de plugins"
    select_plugins

    print_step "3" "Creando proyecto"
    create_project_structure "$PROJECT_NAME"
    [[ $USE_VIRTUALENV == "y" ]] && setup_virtualenv "$PROJECT_NAME"

    cd "$PROJECT_NAME" || exit 1

    create_serverless_config "."
    [[ $USE_DOCKER == "y" ]] && create_docker_config "."
    create_sample_lambda "."
    create_requirements "."

    # Agregar aquí la creación del archivo .flake8
    cat > .flake8 <<'EOF'
[flake8]
max-line-length = 88
extend-ignore = E203
exclude = .git,__pycache__,build,dist
docstring-convention = google
EOF

    [[ $USE_PRECOMMIT == "y" ]] && create_precommit_config "."
    [[ $INIT_GIT == "y" ]] && initialize_git

    [[ ${#selected_plugins[@]} -gt 0 ]] && install_serverless_plugins

    success "🎉 Proyecto '$PROJECT_NAME' creado exitosamente!"
    
    cat <<EOF

📋 Siguientes pasos:
1. cd $PROJECT_NAME
2. source .venv/bin/activate
3. pip install -r requirements.txt
4. serverless offline start

📚 Documentación:
- Revisa README.md para más información
- La estructura del proyecto está en docs/
- Ejemplo de función Lambda en src/functions/hello.py

EOF
}

# Ejecutar script
main "$@"