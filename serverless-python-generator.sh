#!/usr/bin/env bash
# 🚀 Serverless Project Generator v1.0
# Author: Alexander Daza
# Email: dev.alexander.daza@gmail.com
# URL: https://github.com/devalexanderdaza
# License: MIT

# Habilitar modo estricto
set -euo pipefail
IFS=$'\n\t'

# ==========================================
# Constantes de Teclas
# ==========================================
declare -r KEY_SPACE=" "
declare -r KEY_ENTER=$'\n'
declare -r KEY_UP=$'\x1b[A'
declare -r KEY_DOWN=$'\x1b[B'
declare -r KEY_K="k"
declare -r KEY_J="j"
declare -r KEY_Q="q"

# Lista de plugins disponibles
declare -ra AVAILABLE_PLUGINS=(
    "serverless-python-requirements"
    "serverless-iam-roles-per-function"
    "serverless-offline"
    "serverless-dynamodb-local"
    "serverless-localstack"
    "serverless-plugin-warmup"
    "serverless-prune-plugin"
)

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
declare -r MIN_PYTHON_VERSION="3.9"
declare -r MIN_PIP_VERSION="24.0"
declare -r MIN_NODE_VERSION="18"
declare -r CONFIG_FILE=".generator-config"

# Directorio actual del script obtenido sin importar la shell utilizada
declare -r SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || {
    printf "❌ Error al obtener el directorio del script\n" >&2
    exit 1
}

# Variables globales (usar readonly para arrays)
declare -A CONFIG
declare -a SELECTED_PLUGINS=()
readonly REQUIRED_CMDS=(python3 pip3 git node npm serverless java aws)

# ==========================================
# Funciones de Utilidad
# ==========================================
log() {
    printf "%b%b%b\n" "${2:-$NC}" "$1" "$NC"
}

info() { log "$1" "$BLUE"; }
success() { log "$1" "$GREEN"; }
warning() { log "$1" "$YELLOW" >&2; }
error() {
    log "$1" "$RED" >&2
    exit 1
}

# Mejorada la función de verificación de root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        error "❌ Este script no debe ejecutarse como root por razones de seguridad"
    fi
}

print_step() {
    echo -e "\n${YELLOW}${BOLD}Step $1: $2${NC}\n"
}

# Verificar comando
check_command() {
    if ! command -v "$1" &>/dev/null; then
        error "❌ $1 no está instalado. Por favor, instálalo primero."
    fi
}

# Verificar puerto
check_port() {
    if lsof -i :"$1" >/dev/null 2>&1; then
        warning "⚠️ Puerto $1 en uso. Intentando liberar..."
        lsof -ti :"$1" | xargs -r kill -9
    fi
}

# Esperar servicio
wait_for_service() {
    local host="$1"
    local port="$2"
    local service_name="$3"
    local max_attempts="$4"
    local attempt=0

    info "⏳ Esperando a que $service_name esté disponible..."
    while ! nc -z "$host" "$port" >/dev/null 2>&1; do
        attempt=$((attempt + 1))
        if [ $attempt -eq "$max_attempts" ]; then
            error "❌ $service_name no respondió después de $max_attempts intentos"
        fi
        echo -n "."
        sleep 1
    done
    echo ""
    success "✅ $service_name está listo"
}

# ==========================================
# Validaciones Mejoradas
# ==========================================
validate_project_name() {
    local name="$1"
    if [[ ! $name =~ ^[a-zA-Z][-a-zA-Z0-9]{0,38}[a-zA-Z0-9]$ ]]; then
        error "❌ Nombre de proyecto inválido. Debe empezar con letra, usar solo letras, números o guiones, y tener entre 2-40 caracteres."
    fi
    if [[ -d "$name" ]]; then
        error "❌ El directorio '$name' ya existe."
    fi
}

# Función mejorada para comprobar versiones
version_check() {
    local version=$1
    local min_version=$2
    local IFS=.
    read -ra v1 <<<"$version"
    read -ra v2 <<<"$min_version"
    local len=${#v1[@]}
    [[ ${#v2[@]} -gt $len ]] && len=${#v2[@]}

    for ((i = 0; i < len; i++)); do
        [[ ${v1[i]:-0} -gt ${v2[i]:-0} ]] && return 0
        [[ ${v1[i]:-0} -lt ${v2[i]:-0} ]] && return 1
    done
    return 0
}

check_dependencies() {
    local UPGRADE_PYTHON=false
    local UPGRADE_PIP=false
    local UPGRADE_NODE=false

    if [[ CONFIG["upgrade_python"] == "y" ]]; then
        UPGRADE_PYTHON=true
    fi

    if [[ CONFIG["upgrade_pip"] == "y" ]]; then
        UPGRADE_PIP=true
    fi

    if [[ CONFIG["upgrade_node"] == "y" ]]; then
        UPGRADE_NODE=true
    fi

    info "🔍 Verificando dependencias del sistema..."

    local missing_deps=()
    for cmd in "${REQUIRED_CMDS[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            missing_deps+=("$cmd")
        fi
    done

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        error "❌ Faltan las siguientes dependencias: ${missing_deps[*]}"
    fi

    # Verificar versiones
    local python_version
    python_version=$(python3 -c 'import sys; print(".".join(map(str, sys.version_info[:2])))')
    if ! version_check "$python_version" "$MIN_PYTHON_VERSION"; then
        error "❌ Se requiere Python >= $MIN_PYTHON_VERSION (actual: $python_version)"
        # Verificar si se requiere actualizar Python
        if $UPGRADE_PYTHON; then
            warning "⚠️ Se recomienda actualizar Python a la última versión estable"
        fi
    fi

    local pip_version
    pip_version=$(pip3 --version | cut -d' ' -f2)
    if ! version_check "$pip_version" "$MIN_PIP_VERSION"; then
        error "❌ Se requiere pip >= $MIN_PIP_VERSION (actual: $pip_version)"
        # Verificar si se requiere actualizar pip
        if $UPGRADE_PIP; then
            warning "⚠️ Intentando actualizar pip..."
            if ! pip3 install --upgrade pip; then
                error "❌ Error al actualizar pip"
            fi

            # Verificar versión actualizada
            pip_version=$(pip3 --version | cut -d' ' -f2)
            if ! version_check "$pip_version" "$MIN_PIP_VERSION"; then
                error "❌ Se requiere pip >= $MIN_PIP_VERSION (actual: $pip_version)"
            fi

            success "✅ pip actualizado correctamente a la versión $pip_version"
        fi
    fi

    local node_version
    node_version=$(node -v | cut -d'v' -f2)
    if ! version_check "$node_version" "$MIN_NODE_VERSION"; then
        error "❌ Se requiere Node.js >= $MIN_NODE_VERSION (actual: $node_version)"
        # Verificar si se requiere actualizar Node.js
        if $UPGRADE_NODE; then
            warning "⚠️ Intentando actualizar Node.js..."
            if ! npm install -g n; then # Instalar n (Node.js version manager) globalmente
                error "❌ Error al instalar n"
            fi

            if ! n stable; then
                error "❌ Error al instalar la última versión estable de Node.js"
            fi

            # Verificar versión actualizada
            node_version=$(node -v | cut -d'v' -f2)
            if ! version_check "$node_version" "$MIN_NODE_VERSION"; then
                error "❌ Se requiere Node.js >= $MIN_NODE_VERSION (actual: $node_version)"
            fi

            success "✅ Node.js actualizado correctamente a la versión $node_version"
        fi
    fi

    success "✅ Todas las dependencias están instaladas correctamente"
}

# ==========================================
# Configuración de Entorno Mejorada
# ==========================================
setup_virtualenv() {
    local project_dir="$1"
    info "🔧 Configurando entorno virtual..."

    if ! python3 -m venv "${project_dir}/.venv"; then
        error "❌ Error al crear entorno virtual"
    fi

    # Usar BASH_SOURCE para obtener la ruta del script
    # shellcheck source=/dev/null
    if ! source "${project_dir}/.venv/bin/activate"; then
        error "❌ Error al activar entorno virtual"
    fi

    # Actualizar pip y setuptools en el entorno virtual (si se requiere)
     info "🔧 Actualizando pip y setuptools..."
        if ! pip install --upgrade pip setuptools; then
            warning "⚠️ Error al actualizar pip y setuptools"
        fi

    success "✅ active_screenEn=false && break virtual configurado"
}

setup_precommit() {
    info "🔧 Configurando pre-commit..."
    if [[ ! -f .venv/bin/activate ]]; then
    acti
        error "❌ Entorno virtual no encontrado"
    fi

    # shellcheck source=/dev/null
    source .venv/bin/activate

    pip install pre-commit mypy types-requests types-boto3 types-python-dateutil types-pyyaml types-setuptools || {
        warning "⚠️ Error instalando dependencias de pre-commit"
        return 1
    }

    pre-commit install && pre-commit autoupdate
    success "✅ Pre-commit configurado"
}

# ==========================================
# Gestión de Plugins Mejorada
# ==========================================
select_plugins_old() {
    local active_screen=true

    local -a available_plugins=(
        "serverless-python-requirements"
        "serverless-iam-roles-per-function"
        "serverless-offline"
        "serverless-dynamodb-local"
        "serverless-localstack"
        "serverless-plugin-aws-alerts"
        "serverless-plugin-warmup"
        "serverless-prune-plugin"
    )

    local -a selected_states
    local i current_pos=0 key # Inicializar array de estados y posición actual del cursor en 0 (primer elemento) y tecla presionada en vacío

    # Inicializar array de estados
    selected_states=($(for ((i=0; i<${#available_plugins[@]}; i++)); do echo 0; done))

    clear_screen() {
        tput clear
        tput cup 0 0
    }

    render_menu() {
        clear_screen
        echo -e "🔌 ${BOLD}Selecciona los plugins a instalar:${NC}\n"

        # Mostrar contador de seleccionados
        local selected_count=0
        for state in "${selected_states[@]}"; do
            if [[ $state -eq 1 ]]; then
                ((selected_count++))
            fi
        done
        echo -e "Plugins seleccionados: ${GREEN}${selected_count}${NC}/${#available_plugins[@]}\n"

        for i in "${!available_plugins[@]}"; do
            local checkmark="[ ]"

            if [[ ${selected_states[i]} -eq 1 ]]; then
                checkmark="[✔️]"
            fi

            if [[ $i -eq $current_pos ]]; then
                echo -e "${YELLOW}${checkmark} ${available_plugins[i]}${NC}"
            else
                echo -e "${checkmark} ${available_plugins[i]}"
            fi
        done

        # Mostrar instrucciones
        echo -e "\n[Space] Seleccionar/Deseleccionar  [↑/↓] Mover  [Enter] Confirmar  [Q] Salir\n"
    }

    local saved_stty
    saved_stty=$(stty -g)
    stty raw -echo

    # Función para validar selección de plugins al salir del menú
    validate_plugin_selection() {
        for state in "${selected_states[@]}"; do
            if [[ $state -eq 1 ]]; then # Si al menos un plugin está seleccionado
                return 0 # Salir con éxito
            fi
        done
        return 1
    }

    listen_keys() {
        while true; do
            read -s -n 1 key
            echo -en "\033[1A\033[2K" # Limpiar línea actual en la terminal
            echo -en "\033[1A\033[2K" # Limpiar línea anterior en la terminal
            echo  -e "Presionada la tecla: ${key}" # Imprimir tecla presionada
            log "Log presionada la tecla: ${key}" # Imprimir tecla presionada

            case $key in
                " ") # Barra espaciadora
                    selected_states[current_pos]=$((1 - selected_states[current_pos]))
                ;;
                "j"|$'\x1b[B') # Abajo (j o flecha abajo)
                    ((current_pos++))
                    ;;
                "k"|$'\x1b[A') # Arriba (k o flecha arriba)
                    ((current_pos--))
                    ;;
                "q") # Salir sin selección
                    active_screen=false
                    clear_screen
                    SELECTED_PLUGINS=()
                    stty "$saved_stty"
                    return 1
                    ;;
                $'\n') # Enter
                    if validate_plugin_selection; then
                        active_screen=false
                        clear_screen
                        stty "$saved_stty"
                        return 0
                    else
                        warning "⚠️ Debes seleccionar al menos un plugin"
                    fi
                    break
                    ;;
                *) # Otra tecla
                    continue
                ;;
            esac
        done
        render_menu
    }

    while $active_screen; do
        # render_menu
        listen_keys
    done

    # Restaurar terminal
    stty "$saved_stty"

    # Guardar plugins seleccionados en variable global
    for i in "${!available_plugins[@]}"; do
        if [[ ${selected_states[i]} -eq 1 ]]; then
            SELECTED_PLUGINS+=("${available_plugins[i]}")
        fi
    done

    clear_screen
}

# ==========================================
# Instalación de Plugins Mejorada
# ==========================================
install_serverless_plugins() {
    [[ ${#SELECTED_PLUGINS[@]} -eq 0 ]] && return 0
    
    info "🔧 Instalando plugins..."
    local install_errors=0
    
    for plugin in "${SELECTED_PLUGINS[@]}"; do
        echo -n "Instalando $plugin... "
        if npm install --save-dev "$plugin"; then
            success "✅"
        else
            warning "⚠️"
            ((install_errors++))
        fi
    done
    
    if [[ $install_errors -gt 0 ]]; then
        warning "⚠️ Algunos plugins no se instalaron correctamente"
        return 1
    fi
    
    success "✅ Plugins instalados correctamente"
    return 0
}

# ==========================================
# Creación de Estructura y Archivos Mejorada
# ==========================================
create_project_structure() {
    local project_dir="$1"
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
        ".dynamodb"
    )

    for dir in "${dirs[@]}"; do
        if ! mkdir -p "${project_dir}/${dir}"; then
            error "❌ Error al crear directorio ${dir}"
        fi
    done

    create_init_files "$project_dir"
    create_readme "$project_dir"
    create_env_example "$project_dir"
    success "✅ Estructura creada"
}

# ==========================================
# Creación de archivos iniciales
# ==========================================
create_init_files() {
    local name="$1"
    [[ -z "$name" ]] && error "❌ Nombre de proyecto no especificado"

    # Definir la estructura de directorios como un array readonly
    local -r dirs=(
        "."
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

    # Crear todos los __init__.py en paralelo
    for dir in "${dirs[@]}"; do
        (
            # Normalizar el path del directorio
            local normalized_dir="${dir#./}"
            [[ "$normalized_dir" == "." ]] && normalized_dir=""

            # Construir el path del archivo
            local init_path="${name}/${normalized_dir}/__init__.py"

            # Generar el nombre del módulo
            local module_name="${normalized_dir//\//.}"
            [[ -z "$module_name" ]] && module_name="$PROJECT_NAME"

            # Asegurar que el directorio existe
            mkdir -p "$(dirname "$init_path")"

            # Crear el archivo con el docstring
            printf '"""Módulo %s para el proyecto %s."""\n' "$module_name" "$PROJECT_NAME" >"$init_path"
        ) &
    done

    # Esperar a que todos los procesos en segundo plano terminen
    wait

    # Verificar que todos los archivos se crearon correctamente
    local errors=0
    for dir in "${dirs[@]}"; do
        local normalized_dir="${dir#./}"
        [[ "$normalized_dir" == "." ]] && normalized_dir=""
        local init_path="${name}/${normalized_dir}/__init__.py"

        if [[ ! -f "$init_path" ]]; then
            warning "⚠️ No se pudo crear: $init_path"
            ((errors++))
        fi
    done

    [[ $errors -gt 0 ]] && error "❌ Error creando archivos __init__.py"

    success "✅ Archivos __init__.py creados correctamente"
}

# ==========================================
# Creación de archivos .env y .env.example
# ==========================================
create_env_example() {
    local project_dir="$1"
    local env_file="${project_dir}/.env.example"
    
    # Verificar si el directorio existe
    if [[ ! -d "$project_dir" ]]; then
        error "❌ Directorio del proyecto no encontrado: $project_dir"
    fi

    cat > "$env_file" <<EOF
# ===========================================
# Configuración de Ambiente
# ===========================================
# Ambiente (development, staging, production)
NODE_ENV=development
STAGE=dev

# ===========================================
# AWS Configuration
# ===========================================
AWS_ACCESS_KEY_ID=DUMMYIDEXAMPLE
AWS_SECRET_ACCESS_KEY=DUMMYEXAMPLEKEY
AWS_DEFAULT_REGION=us-east-1
AWS_PROFILE=default

# ===========================================
# DynamoDB Configuration
# ===========================================
DYNAMODB_ENDPOINT=http://localhost:8000
DYNAMODB_TABLE_PREFIX=my-app
DYNAMODB_READ_CAPACITY=1
DYNAMODB_WRITE_CAPACITY=1

# ===========================================
# Application Configuration
# ===========================================
# API Configuration
API_VERSION=v1
API_PREFIX=/api
API_PORT=3000

# Logging Configuration
LOG_LEVEL=debug # debug, info, warn, error
ENABLE_API_LOGGING=true
ENABLE_REQUEST_LOGGING=true

# Security Configuration
JWT_SECRET=your-jwt-secret-key
JWT_EXPIRATION=1h
CORS_ORIGIN=http://localhost:3000
ENABLE_API_AUTHENTICATION=false

# ===========================================
# Monitoring & Alerting
# ===========================================
ENABLE_XRAY_TRACING=false
ENABLE_CLOUDWATCH_METRICS=false
ALERT_EMAIL=alerts@example.com
ERROR_NOTIFICATION_SNS_TOPIC=

# ===========================================
# Testing Configuration
# ===========================================
TEST_DYNAMODB_ENDPOINT=http://localhost:8000
SKIP_INTEGRATION_TESTS=false
MOCK_EXTERNAL_SERVICES=true

# ===========================================
# Performance Configuration
# ===========================================
LAMBDA_MEMORY=128
LAMBDA_TIMEOUT=30
ENABLE_LAMBDA_WARMUP=false
CONNECTION_POOL_SIZE=5

# ===========================================
# Feature Flags
# ===========================================
FEATURE_NEW_USER_WORKFLOW=false
FEATURE_ADVANCED_ANALYTICS=false

# ===========================================
# External Services
# ===========================================
# Redis Configuration (si se usa)
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_PASSWORD=

# Elasticsearch Configuration (si se usa)
ELASTICSEARCH_NODE=http://localhost:9200
ELASTICSEARCH_USERNAME=
ELASTICSEARCH_PASSWORD=

# ===========================================
# Backup & Recovery
# ===========================================
BACKUP_S3_BUCKET=
BACKUP_RETENTION_DAYS=30

# ===========================================
# Deployment Configuration
# ===========================================
DEPLOYMENT_NOTIFICATION_WEBHOOK=
ENABLE_CANARY_DEPLOYMENT=false
CANARY_TRAFFIC_PERCENTAGE=10
EOF

    # Crear también un .env con valores por defecto para desarrollo
    cp "$env_file" "${project_dir}/.env"
    
    # Asegurar que .env no se incluya en git
    if [[ -d "${project_dir}/.git" ]]; then
        echo ".env" >> "${project_dir}/.gitignore"
    fi
    
    success "✅ Archivo .env.example creado en $env_file"
    info "ℹ️  Se ha creado una copia como .env con valores por defecto para desarrollo"
}

# ==========================================
# Creación de README.md
# ==========================================
create_readme() {
    local project_dir="$1"
    local current_year
    current_year=$(date +"%Y")
    
    cat > "${project_dir}/README.md" <<EOF
# 🚀 Serverless API Project

## 📋 Descripción
API Serverless moderna construida con Python, AWS Lambda y DynamoDB. Este proyecto proporciona una base sólida para construir APIs escalables y mantenibles usando la arquitectura serverless.

## 🎯 Características Principales
- ⚡ Serverless Framework para despliegue y gestión
- 🗄️ DynamoDB para almacenamiento persistente
- 📨 SQS para procesamiento asíncrono
- 🔍 Monitoreo y logging integrado
- 🔒 Seguridad y autenticación incorporada
- 📊 Métricas y alertas configurables
- 🧪 Testing completo (unitario e integración)
- 🔄 CI/CD listo para usar

## 🚀 Inicio Rápido

### Pre-requisitos
- Python 3.9+
- Node.js 18+
- AWS CLI configurado
- Serverless Framework
- Java Runtime (para DynamoDB local)
- Docker (opcional, para contenedorización)

### Configuración Inicial
1. **Clonar el repositorio**
   \`\`\`bash
   git clone [URL_REPOSITORIO]
   cd [NOMBRE_PROYECTO]
   \`\`\`

2. **Configurar ambiente de desarrollo**
   \`\`\`bash
   # Crear y activar entorno virtual
   python3 -m venv .venv
   source .venv/bin/activate  # En Windows: .venv\\Scripts\\activate
   
   # Instalar dependencias
   pip install -r requirements.txt
   npm install
   
   # Configurar pre-commit hooks
   pre-commit install
   \`\`\`

3. **Configurar variables de entorno**
   \`\`\`bash
   cp .env.example .env
   # Editar .env con tus configuraciones
   \`\`\`

4. **Iniciar desarrollo local**
   \`\`\`bash
   # Iniciar servicios locales
   ./scripts/start-local.sh
   \`\`\`

## 🏗️ Estructura del Proyecto
\`\`\`
├── src/
│   ├── functions/     # Funciones Lambda y handlers
│   │   ├── orders/    # Módulo de órdenes
│   │   ├── users/     # Módulo de usuarios
│   │   └── common/    # Funcionalidad compartida
│   ├── models/        # Modelos de datos y esquemas
│   │   ├── dynamo/    # Modelos DynamoDB
│   │   └── dto/       # Objetos de transferencia de datos
│   └── utils/         # Utilidades compartidas
│       ├── auth/      # Utilidades de autenticación
│       ├── logging/   # Configuración de logging
│       └── validation/# Validadores
├── tests/
│   ├── unit/         # Tests unitarios
│   ├── integration/  # Tests de integración
│   └── fixtures/     # Datos de prueba
├── docs/            # Documentación
│   ├── api/         # Documentación de API
│   ├── setup/       # Guías de configuración
│   └── development/ # Guías de desarrollo
├── scripts/         # Scripts de utilidad
├── config/          # Configuraciones
└── infrastructure/  # IaC y configuración de AWS
\`\`\`

## 🛠️ Desarrollo

### Comandos Principales
\`\`\`bash
# Desarrollo local
npm run dev           # Inicia servidor local
npm run build         # Construye el proyecto
npm run test         # Ejecuta tests

# Testing
pytest                # Ejecuta todos los tests
pytest tests/unit     # Solo tests unitarios
pytest tests/integration  # Solo tests de integración
coverage run -m pytest   # Tests con cobertura

# Linting y Formato
pre-commit run --all-files  # Ejecuta todas las validaciones
black src tests            # Formatea código Python
flake8 src tests          # Verifica estilo
mypy src                  # Verifica tipos

# Despliegue
serverless deploy --stage dev   # Despliega a desarrollo
serverless deploy --stage prod  # Despliega a producción
serverless remove --stage dev   # Elimina stack de desarrollo
\`\`\`

## 📝 API Reference

### Autenticación
Todas las rutas (excepto /health) requieren autenticación via Bearer token JWT.

### Endpoints Principales

#### Órdenes
- \`GET /api/v1/orders\` - Lista órdenes
- \`GET /api/v1/orders/{id}\` - Obtiene orden por ID
- \`POST /api/v1/orders\` - Crea nueva orden
- \`PUT /api/v1/orders/{id}\` - Actualiza orden
- \`DELETE /api/v1/orders/{id}\` - Elimina orden

#### Usuarios
- \`POST /api/v1/auth/login\` - Login de usuario
- \`POST /api/v1/auth/refresh\` - Actualiza token
- \`GET /api/v1/users/me\` - Obtiene perfil actual

### Gestión
- \`GET /health\` - Health check
- \`GET /metrics\` - Métricas de aplicación

## ⚙️ Configuración

### Variables de Entorno
Ver \`.env.example\` para todas las variables disponibles:
- \`AWS_*\` - Credenciales AWS
- \`DYNAMODB_*\` - Configuración DynamoDB
- \`API_*\` - Configuración de API
- \`LOG_*\` - Configuración de logging

### Archivos de Configuración
- \`serverless.yml\` - Configuración principal
- \`config/*.yml\` - Configuraciones por ambiente
- \`infrastructure/*.tf\` - Configuración Terraform

## 🔍 Monitoreo y Logging

### CloudWatch
- Logs automáticos de Lambda
- Métricas personalizadas
- Alarmas configurables

### X-Ray
- Trazabilidad distribuida
- Análisis de latencia
- Diagnóstico de errores

## 🧪 Testing

### Unitarios
\`\`\`bash
pytest tests/unit
\`\`\`
- Pruebas aisladas
- Mocking de servicios
- Cobertura de código

### Integración
\`\`\`bash
pytest tests/integration
\`\`\`
- Pruebas end-to-end
- DynamoDB local
- API Gateway local

## 📈 CI/CD

### GitHub Actions
- Build y test automático
- Despliegue continuo
- Validación de PR

### Ambientes
- Development
- Staging
- Production

## 🔐 Seguridad

### Autenticación
- JWT Tokens
- Refresh Tokens
- Rate Limiting

### Autorización
- IAM Roles
- CORS configurado
- Secrets Management

## 🤝 Contribución
1. Fork el proyecto
2. Crea una rama (\`git checkout -b feature/nueva-caracteristica\`)
3. Commit cambios (\`git commit -am 'Agrega nueva característica'\`)
4. Push a la rama (\`git push origin feature/nueva-caracteristica\`)
5. Crea un Pull Request

## 📄 Licencia
Copyright © $current_year. Distribuido bajo la Licencia MIT.
Ver \`LICENSE\` para más información.

## 👥 Autores
- **Nombre del Autor** - *Trabajo Inicial* - [GitHub](https://github.com/usuario)

## 🙏 Agradecimientos
- Serverless Framework
- AWS Lambda
- Python Community
EOF

    success "✅ README.md creado exitosamente"
}

# ==========================================
# Creación del archivo serverless.yml
# ==========================================
create_serverless_config() {
    local project_dir="$1"
    
    # Crear serverless.yml principal
    cat > "${project_dir}/serverless.yml" <<EOF
service: api

frameworkVersion: '4'

useDotenv: true

package:
  individually: true
  exclude:
    - .git/**
    - .venv/**
    - node_modules/**
    - tests/**
    - '**/__pycache__/**'
    - '**/*.pyc'
    - .pytest_cache/**
    - .coverage
    - htmlcov/**
    - .mypy_cache/**

provider:
  name: aws
  runtime: python3.9
  architecture: arm64
  memorySize: 256
  timeout: 30
  logRetentionInDays: 14
  region: \${opt:region, 'us-east-1'}
  stage: \${opt:stage, 'dev'}
  deploymentBucket:
    name: \${self:service}-\${self:provider.stage}-deployments-\${aws:accountId}
    serverSideEncryption: AES256
  tracing:
    lambda: true
    apiGateway: true
  environment:
    SERVICE_NAME: \${self:service}
    STAGE: \${self:provider.stage}
    REGION: \${self:provider.region}
    DYNAMODB_TABLE: \${self:service}-\${self:provider.stage}
    DYNAMODB_ENDPOINT: \${opt:dynamodb_endpoint, 'http://localhost:8000'}
    LOG_LEVEL: \${self:custom.logLevels.\${self:provider.stage}, 'INFO'}
    POWERTOOLS_SERVICE_NAME: \${self:service}
    POWERTOOLS_METRICS_NAMESPACE: \${self:service}-\${self:provider.stage}
  tags:
    Environment: \${self:provider.stage}
    Service: \${self:service}
    ManagedBy: serverless
  iam:
    role:
      name: \${self:service}-\${self:provider.stage}-lambda-role
      path: /\${self:service}/\${self:provider.stage}/
      permissionsBoundary: arn:aws:iam::\${aws:accountId}:policy/GlobalPermissionsBoundary
      statements:
        - Effect: Allow
          Action:
            - dynamodb:Query
            - dynamodb:Scan
            - dynamodb:GetItem
            - dynamodb:PutItem
            - dynamodb:UpdateItem
            - dynamodb:DeleteItem
            - dynamodb:BatchGetItem
            - dynamodb:BatchWriteItem
          Resource: 
            - !GetAtt OrdersTable.Arn
            - !Join ['', [!GetAtt OrdersTable.Arn, '/index/*']]
        - Effect: Allow
          Action:
            - xray:PutTraceSegments
            - xray:PutTelemetryRecords
          Resource: "*"

plugins:
$(printf "  - %s\n" "${selected_plugins[@]}")

custom:
  logLevels:
    dev: DEBUG
    staging: INFO
    prod: WARN
    
  prune:
    automatic: true
    number: 3
    
  alerts:
    stages:
      - prod
    topics:
      alarm:
        topic: \${self:service}-\${self:provider.stage}-alerts
        notifications:
          - protocol: email
            endpoint: alerts@example.com
    alarms:
      - functionErrors
      - functionThrottles
      - functionDuration
      
  warmup:
    enabled: true
    prewarm: true
    concurrency: 1
    events:
      - schedule: rate(5 minutes)
    stages:
      - prod
      
  pythonRequirements:
    dockerizePip: true
    layer:
      name: python-deps-\${self:provider.stage}
    noDeploy:
      - coverage
      - pytest
      - black
      - flake8
      - mypy
    useStaticCache: true
    useDownloadCache: true
    caching: true

  dynamodb:
    start:
      port: 8000
      inMemory: true
      migrate: true
      seed: true
      noStart: false
    stages:
      - dev
    seed:
      domain:
        sources:
          - table: \${self:provider.environment.DYNAMODB_TABLE}-orders
            sources: [./config/dynamodb/orders.json]

  serverless-offline:
    httpPort: 3000
    lambdaPort: 3002
    noPrependStageInUrl: true
    useChildProcesses: true
    corsConfig:
      origin: '*'
      headers:
        - Content-Type
        - X-Amz-Date
        - Authorization
        - X-Api-Key
        - X-Amz-Security-Token
        - X-Amz-User-Agent
      allowCredentials: false

functions:
  health:
    handler: src/functions/health.handler
    events:
      - http:
          path: /health
          method: get
          cors: true
    description: Health check endpoint
    
  getOrders:
    handler: src/functions/orders/get.handler
    events:
      - http:
          path: /api/v1/orders
          method: get
          cors: true
          authorizer:
            name: jwtAuthorizer
            type: CUSTOM
            identitySource: method.request.header.Authorization
    environment:
      DYNAMODB_TABLE: \${self:provider.environment.DYNAMODB_TABLE}-orders
    iamRoleStatements:
      - Effect: Allow
        Action:
          - dynamodb:Query
          - dynamodb:Scan
        Resource: !GetAtt OrdersTable.Arn
        
  createOrder:
    handler: src/functions/orders/create.handler
    events:
      - http:
          path: /api/v1/orders
          method: post
          cors: true
          authorizer:
            name: jwtAuthorizer
          request:
            schemas:
              application/json:
                schema: \${file(src/schemas/order-create.json)}
    environment:
      DYNAMODB_TABLE: \${self:provider.environment.DYNAMODB_TABLE}-orders

resources:
  Resources:
    OrdersTable:
      Type: AWS::DynamoDB::Table
      DeletionPolicy: Retain
      Properties:
        TableName: \${self:provider.environment.DYNAMODB_TABLE}-orders
        AttributeDefinitions:
          - AttributeName: id
            AttributeType: S
          - AttributeName: status
            AttributeType: S
          - AttributeName: userId
            AttributeType: S
          - AttributeName: createdAt
            AttributeType: S
        KeySchema:
          - AttributeName: id
            KeyType: HASH
        GlobalSecondaryIndexes:
          - IndexName: StatusIndex
            KeySchema:
              - AttributeName: status
                KeyType: HASH
              - AttributeName: createdAt
                KeyType: RANGE
            Projection:
              ProjectionType: ALL
          - IndexName: UserIndex
            KeySchema:
              - AttributeName: userId
                KeyType: HASH
              - AttributeName: createdAt
                KeyType: RANGE
            Projection:
              ProjectionType: ALL
        BillingMode: PAY_PER_REQUEST
        PointInTimeRecoverySpecification:
          PointInTimeRecoveryEnabled: true
        SSESpecification:
          SSEEnabled: true
        Tags:
          - Key: Environment
            Value: \${self:provider.stage}
          - Key: Service
            Value: \${self:service}
    
    ApiGatewayLogGroup:
      Type: AWS::Logs::LogGroup
      Properties:
        LogGroupName: /aws/apigateway/\${self:service}-\${self:provider.stage}
        RetentionInDays: 14

    LambdaLogGroup:
      Type: AWS::Logs::LogGroup
      Properties:
        LogGroupName: /aws/lambda/\${self:service}-\${self:provider.stage}
        RetentionInDays: 14

  Outputs:
    ApiUrl:
      Description: API Gateway URL
      Value: 
        Fn::Join:
          - ""
          - - "https://"
            - !Ref ApiGatewayRestApi
            - ".execute-api.\${self:provider.region}.amazonaws.com/\${self:provider.stage}"
    OrdersTableName:
      Description: Orders DynamoDB table name
      Value: !Ref OrdersTable
    OrdersTableArn:
      Description: Orders DynamoDB table ARN
      Value: !GetAtt OrdersTable.Arn
EOF

    # Crear archivo de seed para DynamoDB Local
    mkdir -p "${project_dir}/config/dynamodb"
    cat > "${project_dir}/config/dynamodb/orders.json" <<EOF
{
  "OrdersTable": [
    {
      "PutRequest": {
        "Item": {
          "id": { "S": "ORD-001" },
          "userId": { "S": "USR-001" },
          "status": { "S": "PENDING" },
          "description": { "S": "Sample order 1" },
          "amount": { "N": "99.99" },
          "createdAt": { "S": "2024-02-16T12:00:00Z" },
          "updatedAt": { "S": "2024-02-16T12:00:00Z" }
        }
      }
    },
    {
      "PutRequest": {
        "Item": {
          "id": { "S": "ORD-002" },
          "userId": { "S": "USR-002" },
          "status": { "S": "COMPLETED" },
          "description": { "S": "Sample order 2" },
          "amount": { "N": "149.99" },
          "createdAt": { "S": "2024-02-16T13:00:00Z" },
          "updatedAt": { "S": "2024-02-16T14:30:00Z" }
        }
      }
    }
  ]
}
EOF

    # Crear esquema de validación para creación de órdenes
    mkdir -p "${project_dir}/src/schemas"
    cat > "${project_dir}/src/schemas/order-create.json" <<EOF
{
  "\$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "required": ["description", "amount"],
  "properties": {
    "description": {
      "type": "string",
      "minLength": 1,
      "maxLength": 500
    },
    "amount": {
      "type": "number",
      "minimum": 0
    },
    "metadata": {
      "type": "object",
      "additionalProperties": true
    }
  },
  "additionalProperties": false
}
EOF

    success "✅ Configuración de Serverless creada exitosamente"
}

# ==========================================
# Creación de archivos de docker
# ==========================================
create_docker_config() {
    local project_dir="$1"
    
    # Crear Dockerfile optimizado
    cat > "${project_dir}/Dockerfile" <<'EOF'
# ===== Build Stage =====
FROM python:3.9-slim as builder

# Establecer variables de construcción
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /build

# Instalar dependencias del sistema
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    python3-dev \
    && rm -rf /var/lib/apt/lists/*

# Instalar dependencias de Python
COPY requirements.txt .
RUN python -m venv /opt/venv && \
    . /opt/venv/bin/activate && \
    pip install --no-cache-dir -r requirements.txt

# ===== Runtime Stage =====
FROM python:3.9-slim

# Establecer variables de runtime
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/opt/venv/bin:$PATH" \
    PYTHONPATH="/app"

WORKDIR /app

# Copiar el entorno virtual del stage anterior
COPY --from=builder /opt/venv /opt/venv

# Instalar dependencias mínimas de runtime
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copiar el código de la aplicación
COPY . .

# Usuario no root para seguridad
RUN useradd -m appuser && \
    chown -R appuser:appuser /app
USER appuser

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:3000/health || exit 1

# Comando por defecto
CMD ["python", "src/app.py"]
EOF

    # Crear docker-compose.yml con servicios adicionales
    cat > "${project_dir}/docker-compose.yml" <<'EOF'
version: '3.8'

services:
  app:
    build:
      context: .
      dockerfile: Dockerfile
      target: builder
    volumes:
      - .:/app
      - python-packages:/opt/venv
    ports:
      - "3000:3000"
    env_file: .env
    environment:
      - AWS_ACCESS_KEY_ID=DUMMYIDEXAMPLE
      - AWS_SECRET_ACCESS_KEY=DUMMYEXAMPLEKEY
      - AWS_DEFAULT_REGION=us-east-1
      - DYNAMODB_ENDPOINT=http://dynamodb:8000
      - STAGE=local
    depends_on:
      - dynamodb
    networks:
      - app-network
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/health"]
      interval: 30s
      timeout: 3s
      retries: 3
      start_period: 10s

  dynamodb:
    image: amazon/dynamodb-local:latest
    command: -jar DynamoDBLocal.jar -sharedDb
    ports:
      - "8000:8000"
    volumes:
      - dynamodb-data:/home/dynamodblocal/data
    networks:
      - app-network
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000"]
      interval: 30s
      timeout: 3s
      retries: 3

  dynamodb-admin:
    image: aaronshaf/dynamodb-admin:latest
    ports:
      - "8001:8001"
    environment:
      - DYNAMO_ENDPOINT=http://dynamodb:8000
    depends_on:
      - dynamodb
    networks:
      - app-network

volumes:
  python-packages:
  dynamodb-data:

networks:
  app-network:
    driver: bridge
EOF

    # Crear .dockerignore
    cat > "${project_dir}/.dockerignore" <<'EOF'
# Git
.git
.gitignore
.gitattributes

# Python
__pycache__
*.pyc
*.pyo
*.pyd
.Python
*.py[cod]
*$py.class
.pytest_cache
.coverage
htmlcov/
.tox/
.nox/
.hypothesis/
.mypy_cache

# Virtual Environment
.env
.venv
env/
venv/
ENV/

# IDE
.idea
.vscode
*.swp
*.swo
.DS_Store

# Project specific
tests/
docs/
*.md
docker-compose*.yml
Dockerfile*
.dockerignore

# Node
node_modules/
npm-debug.log
package-lock.json

# Serverless
.serverless/
EOF

    # Crear script para gestionar Docker
    mkdir -p "${project_dir}/scripts"
    cat > "${project_dir}/scripts/docker-utils.sh" <<'EOF'
#!/bin/bash
set -e

# Colores para output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# Función para imprimir mensajes
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

# Construir imágenes
build() {
    log "🔨 Construyendo imágenes Docker..."
    docker-compose build
}

# Iniciar servicios
start() {
    log "🚀 Iniciando servicios..."
    docker-compose up -d
    log "✅ Servicios disponibles en:"
    log "   - API: http://localhost:3000"
    log "   - DynamoDB Admin: http://localhost:8001"
}

# Detener servicios
stop() {
    log "🛑 Deteniendo servicios..."
    docker-compose down
}

# Limpiar recursos
clean() {
    log "🧹 Limpiando recursos..."
    docker-compose down -v
    docker system prune -f
}

# Mostrar logs
logs() {
    log "📋 Mostrando logs..."
    docker-compose logs -f
}

# Ejecutar tests
test() {
    log "🧪 Ejecutando tests..."
    docker-compose run --rm app pytest
}

# Menú de ayuda
show_help() {
    echo -e "${GREEN}Docker Utilities${NC}"
    echo "Uso: $0 [comando]"
    echo ""
    echo "Comandos:"
    echo "  build   - Construir imágenes Docker"
    echo "  start   - Iniciar servicios"
    echo "  stop    - Detener servicios"
    echo "  clean   - Limpiar recursos"
    echo "  logs    - Mostrar logs"
    echo "  test    - Ejecutar tests"
    echo "  help    - Mostrar esta ayuda"
}

# Procesar comando
case "$1" in
    build)  build ;;
    start)  start ;;
    stop)   stop ;;
    clean)  clean ;;
    logs)   logs ;;
    test)   test ;;
    help)   show_help ;;
    *)      show_help ;;
esac
EOF

    # Hacer ejecutable el script
    chmod +x "${project_dir}/scripts/docker-utils.sh"

    success "✅ Configuración Docker creada exitosamente"
    info "ℹ️  Utiliza ./scripts/docker-utils.sh para gestionar los contenedores"
}

# ==========================================
# Creación de archivos base para API
# ==========================================
create_sample_lambda() {
    local functions_dir="$1/src/functions"
    local utils_dir="$1/src/utils"
    
    # Crear utilidades comunes
    mkdir -p "$utils_dir/middleware"
    
    # Crear middleware de error handling
    cat > "$utils_dir/middleware/error_handler.py" <<'EOF'
"""Middleware para manejo de errores."""
import functools
import logging
from typing import Any, Callable, Dict
from aws_lambda_powertools.utilities.typing import LambdaContext
from aws_lambda_powertools.utilities.validation import validate_input, validate_output

# Configurar logger
logger = logging.getLogger()

class AppError(Exception):
    """Error base para la aplicación."""
    def __init__(self, message: str, status_code: int = 500):
        self.message = message
        self.status_code = status_code
        super().__init__(self.message)

def handle_errors(func: Callable) -> Callable:
    """Decorator para manejo consistente de errores.
    
    Args:
        func: Función a decorar.
        
    Returns:
        Callable: Función decorada.
    """
    @functools.wraps(func)
    def wrapper(*args: Any, **kwargs: Any) -> Dict[str, Any]:
        try:
            return func(*args, **kwargs)
        except AppError as e:
            logger.error("Application error: %s", str(e))
            return {
                "statusCode": e.status_code,
                "headers": {"Content-Type": "application/json"},
                "body": {"error": str(e), "status": "error"}
            }
        except Exception as e:
            logger.error("Unexpected error: %s", str(e), exc_info=True)
            return {
                "statusCode": 500,
                "headers": {"Content-Type": "application/json"},
                "body": {"error": "Internal server error", "status": "error"}
            }
    return wrapper
EOF

    # Crear utilidad para DynamoDB
    cat > "$utils_dir/dynamodb.py" <<'EOF'
"""Utilidades para DynamoDB."""
import os
import boto3
from typing import Optional
from botocore.config import Config

def get_dynamodb_client(timeout: int = 5):
    """Obtiene cliente de DynamoDB configurado.
    
    Args:
        timeout: Timeout en segundos para las operaciones.
        
    Returns:
        boto3.client: Cliente de DynamoDB configurado.
    """
    config = Config(
        retries=dict(max_attempts=3),
        connect_timeout=timeout,
        read_timeout=timeout
    )
    
    return boto3.client(
        "dynamodb",
        endpoint_url=os.getenv("DYNAMODB_ENDPOINT"),
        config=config,
        region_name=os.getenv("AWS_REGION", "us-east-1")
    )
EOF

    # Crear utilidad para respuestas HTTP
    cat > "$utils_dir/http.py" <<'EOF'
"""Utilidades para respuestas HTTP."""
import json
from typing import Any, Dict, Optional

def create_response(
    status_code: int = 200,
    body: Optional[Dict[str, Any]] = None,
    headers: Optional[Dict[str, str]] = None
) -> Dict[str, Any]:
    """Crea una respuesta HTTP formateada.
    
    Args:
        status_code: Código de estado HTTP.
        body: Cuerpo de la respuesta.
        headers: Headers adicionales.
        
    Returns:
        Dict[str, Any]: Respuesta formateada para API Gateway.
    """
    default_headers = {
        "Content-Type": "application/json",
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Credentials": True
    }
    
    return {
        "statusCode": status_code,
        "headers": {**default_headers, **(headers or {})},
        "body": json.dumps(body or {})
    }
EOF

    # Crear handler principal
    cat > "$functions_dir/health.py" <<'EOF'
"""Health check endpoint para el servicio."""

import json
import os
from typing import Dict, Any
from aws_lambda_powertools import Logger, Metrics, Tracer
from aws_lambda_powertools.utilities.typing import LambdaContext
from aws_lambda_powertools.utilities.validation import validate_input, validate_output

from ..utils.middleware.error_handler import handle_errors, AppError
from ..utils.dynamodb import get_dynamodb_client
from ..utils.http import create_response

# Inicializar utilidades
logger = Logger(service="health-check")
tracer = Tracer(service="health-check")
metrics = Metrics(namespace="Serverless", service="health-check")

@tracer.capture_lambda_handler
@logger.inject_lambda_context
@metrics.log_metrics
@handle_errors
def handler(event: Dict[str, Any], context: LambdaContext) -> Dict[str, Any]:
    """Handler para health check del servicio.
    
    Verifica la conexión con DynamoDB y retorna estado del servicio.
    
    Args:
        event: Evento de API Gateway.
        context: Contexto de Lambda.
        
    Returns:
        Dict[str, Any]: Respuesta con estado del servicio.
        
    Raises:
        AppError: Si hay problemas con la conexión a DynamoDB.
    """
    logger.debug("Health check iniciado", extra={"event": event})
    
    try:
        # Verificar conexión a DynamoDB
        dynamodb = get_dynamodb_client()
        tables = dynamodb.list_tables()
        table_name = os.environ.get("DYNAMODB_TABLE")
        
        # Recolectar métricas
        metrics.add_metric(name="HealthCheckSuccess", unit="Count", value=1)
        
        return create_response(
            status_code=200,
            body={
                "status": "healthy",
                "version": os.environ.get("SERVICE_VERSION", "1.0.0"),
                "environment": os.environ.get("STAGE", "dev"),
                "dynamodb": {
                    "status": "connected",
                    "tables": tables.get("TableNames", []),
                    "primary_table": table_name,
                    "endpoint": os.environ.get("DYNAMODB_ENDPOINT")
                }
            }
        )
        
    except Exception as e:
        # Registrar métrica de error
        metrics.add_metric(name="HealthCheckError", unit="Count", value=1)
        logger.error("Error en health check", exc_info=True)
        
        raise AppError(
            message="Error verificando estado del servicio",
            status_code=500
        ) from e

if __name__ == "__main__":
    # Para pruebas locales
    test_event = {"httpMethod": "GET", "path": "/health"}
    test_context = type("TestContext", (), {"function_name": "health-check"})()
    print(json.dumps(handler(test_event, test_context), indent=2))
EOF

    # Crear tests para el handler
    mkdir -p "$1/tests/unit/functions"
    cat > "$1/tests/unit/functions/test_health.py" <<'EOF'
"""Tests para el health check endpoint."""
import os
import pytest
from unittest.mock import patch, MagicMock
from src.functions.health import handler

@pytest.fixture
def lambda_context():
    """Fixture para contexto de Lambda."""
    return type("TestContext", (), {"function_name": "test-function"})()

@pytest.fixture
def mock_dynamodb():
    """Fixture para mock de DynamoDB."""
    with patch("boto3.client") as mock_client:
        mock_instance = MagicMock()
        mock_instance.list_tables.return_value = {"TableNames": ["test-table"]}
        mock_client.return_value = mock_instance
        yield mock_instance

def test_health_check_success(lambda_context, mock_dynamodb):
    """Test de health check exitoso."""
    # Configurar ambiente
    os.environ["DYNAMODB_TABLE"] = "test-table"
    os.environ["STAGE"] = "test"
    
    # Ejecutar handler
    response = handler({}, lambda_context)
    
    # Verificar respuesta
    assert response["statusCode"] == 200
    assert "healthy" in response["body"]
    assert mock_dynamodb.list_tables.called

def test_health_check_error(lambda_context):
    """Test de health check con error."""
    # Simular error en DynamoDB
    with patch("boto3.client") as mock_client:
        mock_client.side_effect = Exception("Test error")
        
        # Ejecutar handler
        response = handler({}, lambda_context)
        
        # Verificar respuesta de error
        assert response["statusCode"] == 500
        assert "error" in response["body"]
EOF

    success "✅ Código Lambda creado exitosamente"
    info "ℹ️  Se crearon también utilidades y tests unitarios"
}

# ==========================================
# Creación de archivos de requerimientos
# ==========================================
create_requirements() {
    local project_dir="$1"
    
    # Crear requirements.txt principal
    cat > "${project_dir}/requirements.txt" <<'EOF'
# ===========================================
# Core Dependencies
# ===========================================
boto3==1.34.39
pynamodb==5.5.1
aws-lambda-powertools==2.30.2
python-dotenv==1.0.1
PyYAML==6.0.1
marshmallow==3.20.2
requests==2.31.0

# ===========================================
# AWS Extensions
# ===========================================
aws-xray-sdk==2.12.1
boto3-stubs[dynamodb,s3,sqs]==1.34.39
types-boto3==1.0.2
aioboto3==12.3.0
aws-encryption-sdk==3.1.1

# ===========================================
# Development Tools
# ===========================================
black==24.1.1
flake8==7.0.0
mypy==1.8.0
pre-commit==3.6.0
isort==5.13.2
bandit==1.7.7
pylint==3.0.3

# ===========================================
# Testing
# ===========================================
pytest==7.4.4
pytest-cov==4.1.0
pytest-mock==3.12.0
pytest-asyncio==0.23.5
pytest-env==1.1.3
pytest-xdist==3.5.0
moto==4.2.13
coverage==7.4.1

# ===========================================
# Performance & Monitoring
# ===========================================
datadog==0.47.0
newrelic==9.6.0
opentelemetry-api==1.22.0
opentelemetry-sdk==1.22.0
prometheus-client==0.19.0

# ===========================================
# Security
# ===========================================
cryptography==42.0.2
bcrypt==4.1.2
PyJWT==2.8.0
python-jose[cryptography]==3.3.0
passlib==1.7.4

# ===========================================
# Utilities
# ===========================================
pydantic==2.6.1
fastjsonschema==2.19.1
structlog==24.1.0
python-dateutil==2.8.2
pytz==2024.1
cachetools==5.3.2
EOF

    # Crear requirements-dev.txt para dependencias de desarrollo
    cat > "${project_dir}/requirements-dev.txt" <<'EOF'
-r requirements.txt

# ===========================================
# Development Only Dependencies
# ===========================================
ipython==8.21.0
jupyter==1.0.0
debugpy==1.8.0
httpie==3.2.2
locust==2.23.1
pip-tools==7.3.0
safety==2.3.5
black[jupyter]==24.1.1
pytype==2024.1.24
ruff==0.2.1

# ===========================================
# Documentation
# ===========================================
mkdocs==1.5.3
mkdocs-material==9.5.3
mkdocstrings[python]==0.24.0
pdoc3==0.10.0

# ===========================================
# Code Analysis
# ===========================================
radon==6.0.1
xenon==0.9.1
prospector==1.10.3

# ===========================================
# Testing Extras
# ===========================================
faker==22.6.0
hypothesis==6.98.2
pytest-benchmark==4.0.0
pytest-clarity==1.0.1
pytest-sugar==0.9.7
pytest-timeout==2.2.0
responses==0.24.1
EOF

    # Crear constraints.txt para fijar versiones exactas
    cat > "${project_dir}/constraints.txt" <<'EOF'
# Este archivo se genera automáticamente con pip-compile
# Para actualizar, ejecuta:
# pip-compile --upgrade requirements.txt
# pip-compile --upgrade requirements-dev.txt
EOF

    # Crear setup.py para hacer el proyecto instalable
    cat > "${project_dir}/setup.py" <<'EOF'
"""Setup configuration for the package."""
from setuptools import setup, find_packages

setup(
    name="serverless-api",
    version="1.0.0",
    packages=find_packages(),
    include_package_data=True,
    install_requires=[
        line.strip()
        for line in open("requirements.txt")
        if line.strip() and not line.startswith("#")
    ],
    extras_require={
        "dev": [
            line.strip()
            for line in open("requirements-dev.txt")
            if line.strip() and not line.startswith("#") and not line.startswith("-r")
        ],
    },
    python_requires=">=3.9",
)
EOF

    # Crear script para gestionar dependencias
    mkdir -p "${project_dir}/scripts"
    cat > "${project_dir}/scripts/manage-deps.sh" <<'EOF'
#!/bin/bash
set -e

# Colores para output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# Función para imprimir mensajes
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

# Actualizar todas las dependencias
update_deps() {
    log "🔄 Actualizando dependencias..."
    pip-compile --upgrade requirements.txt
    pip-compile --upgrade requirements-dev.txt
    pip-sync requirements.txt requirements-dev.txt
}

# Instalar dependencias
install_deps() {
    log "📦 Instalando dependencias..."
    pip install -r requirements.txt
    if [[ "$1" == "--dev" ]]; then
        pip install -r requirements-dev.txt
    fi
}

# Verificar seguridad
check_security() {
    log "🔒 Verificando seguridad de dependencias..."
    safety check
    bandit -r src/
}

# Limpiar cache y archivos temporales
clean() {
    log "🧹 Limpiando archivos temporales..."
    find . -type d -name "__pycache__" -exec rm -r {} +
    find . -type f -name "*.pyc" -delete
    find . -type f -name "*.pyo" -delete
    find . -type f -name "*.pyd" -delete
    find . -type d -name "*.egg-info" -exec rm -r {} +
    find . -type d -name "*.egg" -exec rm -r {} +
    find . -type d -name ".pytest_cache" -exec rm -r {} +
    find . -type d -name ".coverage" -delete
    find . -type d -name "htmlcov" -exec rm -r {} +
}

# Mostrar ayuda
show_help() {
    echo -e "${GREEN}Dependency Management Utilities${NC}"
    echo "Uso: $0 [comando]"
    echo ""
    echo "Comandos:"
    echo "  update  - Actualizar todas las dependencias"
    echo "  install - Instalar dependencias (--dev para incluir desarrollo)"
    echo "  check   - Verificar seguridad de dependencias"
    echo "  clean   - Limpiar archivos temporales"
    echo "  help    - Mostrar esta ayuda"
}

# Procesar comando
case "$1" in
    update)  update_deps ;;
    install) install_deps $2 ;;
    check)   check_security ;;
    clean)   clean ;;
    help)    show_help ;;
    *)       show_help ;;
esac
EOF

    # Hacer ejecutable el script
    chmod +x "${project_dir}/scripts/manage-deps.sh"

    success "✅ Archivos de dependencias creados exitosamente"
    info "ℹ️  Utiliza ./scripts/manage-deps.sh para gestionar dependencias"
}

# ==========================================
# Creación de archivos de pre-commit
# ==========================================
create_precommit_config() {
    local project_dir="$1"

    # Crear configuración principal de pre-commit
    cat > "${project_dir}/.pre-commit-config.yaml" <<'EOF'
# See https://pre-commit.com for more information
default_language_version:
    python: python3.9

# Define el comportamiento por defecto para todos los hooks
default_stages: [commit, push]

repos:
  # Pre-commit hooks básicos
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v4.5.0
    hooks:
      - id: trailing-whitespace
      - id: end-of-file-fixer
      - id: check-yaml
        args: [--allow-multiple-documents]
      - id: check-json
      - id: check-toml
      - id: check-xml
      - id: check-added-large-files
        args: ['--maxkb=500']
      - id: check-case-conflict
      - id: check-merge-conflict
      - id: check-executables-have-shebangs
      - id: check-shebang-scripts-are-executable
      - id: detect-private-key
      - id: mixed-line-ending
        args: [--fix=lf]
      - id: no-commit-to-branch
        args: [--branch, main, --branch, master]

  # Formateo con Black
  - repo: https://github.com/psf/black
    rev: 24.1.1
    hooks:
      - id: black
        language_version: python3
        args: &black-args
          - --line-length=88
          - --target-version=py39
          - --include='\.pyi?$'
        additional_dependencies: ['click==8.0.4']

  # Ordenamiento de imports
  - repo: https://github.com/pycqa/isort
    rev: 5.13.2
    hooks:
      - id: isort
        name: isort (python)
        args: ["--profile", "black", "--filter-files"]

  # Análisis estático con Flake8
  - repo: https://github.com/pycqa/flake8
    rev: 7.0.0
    hooks:
      - id: flake8
        additional_dependencies:
          - flake8-docstrings==1.7.0
          - flake8-bugbear==24.1.17
          - flake8-comprehensions==3.14.0
          - flake8-debugger==4.1.2
          - flake8-eradicate==1.5.0
          - flake8-logging-format==0.9.0
          - flake8-print==5.0.0
          - flake8-pytest-style==1.7.2
          - flake8-quotes==3.3.2
          - flake8-multiline-containers==0.0.19
          - flake8-use-fstring==1.4
        args: &flake8-args
          - --max-line-length=88
          - --extend-ignore=E203
          - --max-complexity=10

  # Verificación de tipos con MyPy
  - repo: https://github.com/pre-commit/mirrors-mypy
    rev: v1.8.0
    hooks:
      - id: mypy
        additional_dependencies:
          - types-requests
          - types-boto3
          - types-python-dateutil
          - types-PyYAML
          - types-setuptools
          - pydantic
        args: &mypy-args
          - --ignore-missing-imports
          - --disallow-untyped-defs
          - --disallow-incomplete-defs
          - --check-untyped-defs
          - --disallow-untyped-decorators
          - --no-implicit-optional
          - --warn-redundant-casts
          - --warn-unused-ignores
          - --warn-return-any
          - --strict-optional
          - --strict-equality

  # Análisis de seguridad con Bandit
  - repo: https://github.com/PyCQA/bandit
    rev: 1.7.7
    hooks:
      - id: bandit
        args: ["-ll", "-iii", "-r", "src"]
        files: ^src/.*\.py$

  # Verificación de dependencias con Safety
  - repo: https://github.com/pyupio/safety
    rev: 2.3.5
    hooks:
      - id: safety
        args: ["check", "--full-report"]
        files: requirements.*\.txt$

  # Linting de Dockerfile
  - repo: https://github.com/hadolint/hadolint
    rev: v2.12.0
    hooks:
      - id: hadolint
        args: ["--ignore", "DL3013", "--ignore", "DL3018"]

  # Verificar secretos
  - repo: https://github.com/Yelp/detect-secrets
    rev: v1.4.0
    hooks:
      - id: detect-secrets
        args: ['--baseline', '.secrets.baseline']
        exclude: package.lock.json

  # Linting de markdown
  - repo: https://github.com/igorshubovych/markdownlint-cli
    rev: v0.39.0
    hooks:
      - id: markdownlint
        args: ["--fix"]

  # Validación de conventional commits
  - repo: https://github.com/compilerla/conventional-pre-commit
    rev: v3.1.0
    hooks:
      - id: conventional-pre-commit
        stages: [commit-msg]
        args: []
EOF

    # Crear archivo de configuración para flake8
    cat > "${project_dir}/.flake8" <<'EOF'
[flake8]
max-line-length = 88
extend-ignore = E203, W503
max-complexity = 10
docstring-convention = google
per-file-ignores =
    __init__.py:F401
    tests/*:S101,D103
exclude =
    .git,
    __pycache__,
    build,
    dist,
    *.egg-info,
    .eggs,
    .tox,
    .venv,
    .mypy_cache,
    .pytest_cache
EOF

    # Crear archivo de configuración para mypy
    cat > "${project_dir}/mypy.ini" <<'EOF'
[mypy]
python_version = 3.9
warn_return_any = True
warn_unused_configs = True
disallow_untyped_defs = True
disallow_incomplete_defs = True
check_untyped_defs = True
disallow_untyped_decorators = True
no_implicit_optional = True
warn_redundant_casts = True
warn_unused_ignores = True
warn_no_return = True
warn_unreachable = True
strict_optional = True
strict_equality = True

[mypy.plugins.pydantic.*]
init_forbid_extra = True
init_typed = True
warn_required_dynamic_aliases = True
warn_untyped_fields = True

[mypy-boto3.*]
ignore_missing_imports = True

[mypy-botocore.*]
ignore_missing_imports = True

[mypy-pytest.*]
ignore_missing_imports = True
EOF

    # Crear baseline para detect-secrets
    cat > "${project_dir}/.secrets.baseline" <<'EOF'
{
  "version": "1.4.0",
  "plugins_used": [
    {
      "name": "ArtifactoryDetector"
    },
    {
      "name": "AWSKeyDetector"
    },
    {
      "name": "AzureStorageKeyDetector"
    },
    {
      "name": "Base64HighEntropyString",
      "limit": 4.5
    },
    {
      "name": "BasicAuthDetector"
    },
    {
      "name": "CloudantDetector"
    },
    {
      "name": "GitHubTokenDetector"
    },
    {
      "name": "HexHighEntropyString",
      "limit": 3.0
    },
    {
      "name": "IbmCloudIamDetector"
    },
    {
      "name": "IbmCosHmacDetector"
    },
    {
      "name": "JwtTokenDetector"
    },
    {
      "name": "KeywordDetector",
      "keyword_exclude": ""
    },
    {
      "name": "MailchimpDetector"
    },
    {
      "name": "NpmDetector"
    },
    {
      "name": "PrivateKeyDetector"
    },
    {
      "name": "SendGridDetector"
    },
    {
      "name": "SlackDetector"
    },
    {
      "name": "SoftlayerDetector"
    },
    {
      "name": "SquareOAuthDetector"
    },
    {
      "name": "StripeDetector"
    },
    {
      "name": "TwilioKeyDetector"
    }
  ],
  "filters_used": [
    {
      "path": "detect_secrets.filters.allowlist.is_line_allowlisted"
    },
    {
      "path": "detect_secrets.filters.common.is_baseline_file",
      "filename": ".secrets.baseline"
    },
    {
      "path": "detect_secrets.filters.common.is_ignored_due_to_verification_policies",
      "min_level": 2
    },
    {
      "path": "detect_secrets.filters.heuristic.is_indirect_reference"
    },
    {
      "path": "detect_secrets.filters.heuristic.is_likely_id_string"
    },
    {
      "path": "detect_secrets.filters.heuristic.is_lock_file"
    },
    {
      "path": "detect_secrets.filters.heuristic.is_not_alphanumeric_string"
    },
    {
      "path": "detect_secrets.filters.heuristic.is_potential_uuid"
    },
    {
      "path": "detect_secrets.filters.heuristic.is_prefixed_with_dollar_sign"
    },
    {
      "path": "detect_secrets.filters.heuristic.is_sequential_string"
    },
    {
      "path": "detect_secrets.filters.heuristic.is_swagger_file"
    },
    {
      "path": "detect_secrets.filters.heuristic.is_templated_secret"
    }
  ],
  "results": {},
  "generated_at": "2024-02-16T12:00:00Z"
}
EOF

    success "✅ Configuración de pre-commit creada exitosamente"
    info "ℹ️  Ejecuta 'pre-commit install' para activar los hooks"
}

# ==========================================
# Inicialización de repositorio Git
# ==========================================
initialize_git() {
    local project_dir="$1"
    local project_name="$2"
    local use_precommit="$3"
    
    # Verificar si git ya está inicializado
    if [[ -d "${project_dir}/.git" ]]; then
        warning "⚠️  Git ya está inicializado en este directorio"
        return 1
    fi
    
    # Inicializar git
    info "🔄 Inicializando repositorio Git..."
    git init
    
    # Configurar .gitignore
    cat > "${project_dir}/.gitignore" <<'EOF'
# Python
__pycache__/
*.py[cod]
*$py.class
*.so
.Python
build/
develop-eggs/
dist/
downloads/
eggs/
.eggs/
lib/
lib64/
parts/
sdist/
var/
wheels/
*.egg-info/
.installed.cfg
*.egg

# Virtual Environment
.env
.venv
env/
venv/
ENV/
env.bak/
venv.bak/

# Testing
.coverage
.coverage.*
htmlcov/
.tox/
.nox/
.pytest_cache/
.hypothesis/
.pytest_cache/
coverage.xml
*.cover
*.py,cover
.hypothesis/

# Node
node_modules/
npm-debug.log*
yarn-debug.log*
yarn-error.log*
.pnpm-debug.log*
.npm
.yarn

# Serverless
.serverless/
.dynamodb/
.webpack/

# IDE
.idea/
.vscode/
*.swp
*.swo
*~
.project
.classpath
.settings/
*.sublime-workspace
*.sublime-project

# OS
.DS_Store
.DS_Store?
._*
.Spotlight-V100
.Trashes
ehthumbs.db
Thumbs.db

# Logs
logs
*.log
npm-debug.log*
yarn-debug.log*
yarn-error.log*

# Local development
*.env
*.env.*
!.env.example
.localstack
.aws-sam/

# Build
*.pyc
__pycache__/
.mypy_cache/
.dmypy.json
dmypy.json
.pyre/
.pytype/

# Documentation
/site
docs/_build/
.pdoc/

# Cache
.cache/
.pytest_cache/
.mypy_cache/
.ruff_cache/

# Secrets
.env
.aws/
credentials
.ssh/
*.pem
*.key
*.crt
*.p12

# Temporary files
*.tmp
*.bak
*.swp
*.swo
*~
EOF

    # Configurar .gitattributes
    cat > "${project_dir}/.gitattributes" <<'EOF'
# Auto detect text files and perform LF normalization
* text=auto eol=lf

# Python files
*.py text diff=python
*.pyi text diff=python
*.pyw text diff=python
*.ipynb text

# Documentation
*.md text diff=markdown
*.rst text
*.txt text
*.pdf binary

# Data files
*.csv text
*.json text
*.yaml text
*.yml text
*.xml text

# Scripts
*.sh text eol=lf
*.bat text eol=crlf
*.cmd text eol=crlf
*.ps1 text eol=crlf

# Docker
Dockerfile text
docker-compose*.yml text
.dockerignore text

# Serverless
serverless.yml text
.env.* text

# Web
*.js text
*.ts text
*.html text diff=html
*.css text diff=css
*.scss text diff=css

# Binary files
*.db binary
*.p binary
*.pkl binary
*.pyc binary
*.pyd binary
*.pyo binary
*.zip binary
*.gz binary
*.tar binary
*.7z binary
*.jpg binary
*.jpeg binary
*.png binary
*.gif binary
*.ico binary
*.svg text
EOF

    # Configurar Git hooks directory
    git config core.hooksPath .githooks

    # Crear directorio de hooks personalizado
    mkdir -p "${project_dir}/.githooks"
    
    # Crear pre-push hook para validaciones
    cat > "${project_dir}/.githooks/pre-push" <<'EOF'
#!/bin/bash
set -e

echo "🔍 Ejecutando validaciones pre-push..."

# Verificar tests
echo "🧪 Ejecutando tests..."
pytest || exit 1

# Verificar typing
echo "📝 Verificando tipos..."
mypy src/ || exit 1

# Verificar seguridad
echo "🔒 Analizando seguridad..."
bandit -r src/ || exit 1

echo "✅ Todas las validaciones pasaron exitosamente"
EOF
    chmod +x "${project_dir}/.githooks/pre-push"

    # Configurar commit-msg hook para conventional commits
    cat > "${project_dir}/.githooks/commit-msg" <<'EOF'
#!/bin/bash

commit_msg_file=$1
commit_msg=$(cat "$commit_msg_file")

# Patrón para conventional commits
conventional_pattern="^(build|chore|ci|docs|feat|fix|perf|refactor|revert|style|test)(\([a-z]+\))?: .+"

if ! [[ "$commit_msg" =~ $conventional_pattern ]]; then
    echo "❌ Error: El mensaje del commit no sigue el formato conventional commits"
    echo "Formato esperado: <type>[optional scope]: <description>"
    echo "Types permitidos: build|chore|ci|docs|feat|fix|perf|refactor|revert|style|test"
    echo "Ejemplo: feat(auth): add login functionality"
    exit 1
fi
EOF
    if [ "$use_precommit" = "y" ]; then
        chmod +x "${project_dir}/.githooks/commit-msg"
    fi

    # Configurar git
    info "⚙️  Configurando Git..."
    git config --local core.autocrlf input
    git config --local core.eol lf
    git config --local core.whitespace trailing-space,space-before-tab
    git config --local apply.whitespace fix
    git config --local pull.rebase true
    git config --local push.default current
    git config --local fetch.prune true
    git config --local init.defaultBranch main

    # Configurar pre-commit si está habilitado
    if [ "$use_precommit" = "y" ]; then
        info "🔧 Configurando pre-commit..."
        pre-commit install
    fi

    # Crear rama principal y hacer commit inicial
    info "📝 Creando commit inicial..."
    git checkout -b main
    git add .
    git commit -m "🎉 feat: commit inicial

Este commit incluye:
- Configuración inicial del proyecto
- Estructura base de directorios
- Configuración de desarrollo
- Documentación básica

Co-authored-by: $USER <${USER}@$(hostname)>"

    success "✅ Repositorio Git inicializado exitosamente"
    info "ℹ️  Rama principal: main"
    info "ℹ️  Pre-commit: ${use_precommit}"
}

create_start_script() {
    local project_dir="$1"
    local scripts_dir="${project_dir}/scripts"
    
    mkdir -p "$scripts_dir"

    # Crear script de utilidades
    cat > "${scripts_dir}/utils.sh" <<'EOF'
#!/bin/bash

# Colores para output
declare -r RED='\033[0;31m'
declare -r GREEN='\033[0;32m'
declare -r YELLOW='\033[1;33m'
declare -r BLUE='\033[0;34m'
declare -r NC='\033[0m'

# Función para logging
log() {
    echo -e "${2:-$BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

info() { log "$1" "$BLUE"; }
success() { log "$1" "$GREEN"; }
warning() { log "$1" "$YELLOW"; }
error() { log "$1" "$RED"; exit 1; }

# Verificar comando
check_command() {
    if ! command -v "$1" &>/dev/null; then
        error "❌ $1 no está instalado. Por favor, instálalo primero."
    fi
}

# Verificar puerto
check_port() {
    if lsof -i :"$1" >/dev/null 2>&1; then
        warning "⚠️ Puerto $1 en uso. Intentando liberar..."
        lsof -ti :"$1" | xargs -r kill -9
    fi
}

# Esperar servicio
wait_for_service() {
    local host="$1"
    local port="$2"
    local service_name="$3"
    local max_attempts="$4"
    local attempt=0

    info "⏳ Esperando a que $service_name esté disponible..."
    while ! nc -z "$host" "$port" >/dev/null 2>&1; do
        attempt=$((attempt + 1))
        if [ $attempt -eq "$max_attempts" ]; then
            error "❌ $service_name no respondió después de $max_attempts intentos"
        fi
        echo -n "."
        sleep 1
    done
    echo ""
    success "✅ $service_name está listo"
}
EOF

    # Crear script principal de inicio
    cat > "${scripts_dir}/start-local.sh" <<'EOF'
#!/bin/bash
set -euo pipefail

# Cargar utilidades
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./utils.sh
source "${SCRIPT_DIR}/utils.sh"

# Configuración
declare -r DYNAMO_PORT=8000
declare -r API_PORT=3000
declare -r MAX_ATTEMPTS=30
declare -r JAVA_MEMORY=512

# Verificar dependencias
check_command java
check_command aws
check_command serverless
check_command nc

# Configurar ambiente
setup_environment() {
    info "🔧 Configurando ambiente de desarrollo..."
    
    # Cargar variables de entorno
    if [[ -f .env ]]; then
        # shellcheck source=/dev/null
        source .env
    fi
    
    # Configurar credenciales de desarrollo
    export AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID:-'DUMMYIDEXAMPLE'}
    export AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY:-'DUMMYEXAMPLEKEY'}
    export AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION:-'us-east-1'}
    export STAGE=${STAGE:-'dev'}
    export DYNAMODB_ENDPOINT="http://localhost:${DYNAMO_PORT}"
}

# Iniciar DynamoDB Local
start_dynamodb() {
    info "🔄 Iniciando DynamoDB Local..."
    
    # Verificar puerto
    check_port $DYNAMO_PORT
    
    # Configurar opciones de Java
    export JAVA_OPTS="-Xms${JAVA_MEMORY}m -Xmx${JAVA_MEMORY}m"
    
    # Iniciar DynamoDB
    serverless dynamodb start &
    DYNAMO_PID=$!
    
    # Esperar a que DynamoDB esté listo
    wait_for_service "localhost" $DYNAMO_PORT "DynamoDB" $MAX_ATTEMPTS
    
    # Crear tablas si no existen
    create_tables
}

# Crear tablas en DynamoDB
create_tables() {
    info "📦 Configurando tablas..."
    
    # Función para crear tabla
    create_table() {
        local table_name="$1"
        if ! aws dynamodb describe-table \
            --table-name "$table_name" \
            --endpoint-url "$DYNAMODB_ENDPOINT" >/dev/null 2>&1; then
            
            info "Creating table: $table_name"
            aws dynamodb create-table \
                --table-name "$table_name" \
                --attribute-definitions \
                    AttributeName=id,AttributeType=S \
                    AttributeName=status,AttributeType=S \
                    AttributeName=createdAt,AttributeType=S \
                --key-schema \
                    AttributeName=id,KeyType=HASH \
                --global-secondary-indexes \
                    IndexName=StatusIndex,\
                    KeySchema=["{AttributeName=status,KeyType=HASH}",\
                             "{AttributeName=createdAt,KeyType=RANGE}"],\
                    Projection="{ProjectionType=ALL}" \
                --billing-mode PAY_PER_REQUEST \
                --tags Key=Environment,Value="$STAGE" \
                --endpoint-url "$DYNAMODB_ENDPOINT" || error "❌ Error creando tabla $table_name"
        fi
    }
    
    # Crear tablas necesarias
    create_table "api-${STAGE}"
    create_table "api-${STAGE}-orders"
}

# Iniciar API local
start_api() {
    info "🚀 Iniciando API local..."
    
    # Verificar puerto
    check_port $API_PORT
    
    # Iniciar Serverless Offline
    serverless offline start
}

# Función de limpieza
cleanup() {
    info "🧹 Limpiando recursos..."
    
    # Detener DynamoDB
    if [[ -n "${DYNAMO_PID:-}" ]]; then
        kill $DYNAMO_PID 2>/dev/null || true
    fi
    
    # Detener procesos en puertos
    lsof -ti :$DYNAMO_PORT | xargs -r kill -9
    lsof -ti :$API_PORT | xargs -r kill -9
    
    # Eliminar archivos temporales
    rm -f /tmp/dynamodb-local.*
}

# Registrar cleanup para salida
trap cleanup EXIT INT TERM

# Función principal
main() {
    setup_environment
    start_dynamodb
    start_api
}

# Ejecutar
main "$@"
EOF

    # Hacer ejecutables los scripts
    chmod +x "${scripts_dir}/utils.sh"
    chmod +x "${scripts_dir}/start-local.sh"
    
    success "✅ Scripts de desarrollo local creados"
}

install_dynamodb_local_from_url() {
    local project_dir="$1"
    local use_docker="$2"
    local dynamodb_dir="${project_dir}/.dynamodb"
    local temp_dir="/tmp/dynamodb-install"

    # Verificar si Docker está disponible
    if [[ "$use_docker" == "y" ]]; then
      check_command docker
    fi
    
    # Descargar archivo
    info "📦 Instalando DynamoDB Local..."
    
    # Crear directorios
    mkdir -p "$dynamodb_dir" "$temp_dir"

    # URL y versión de DynamoDB
    local VERSION="latest"
    local DOWNLOAD_URL="https://s3-us-west-2.amazonaws.com/dynamodb-local/dynamodb_local_${VERSION}.zip"
    local ZIP_FILE="${temp_dir}/dynamodb_local_${VERSION}.zip"
    
    # Descargar archivo
    info "⬇️  Descargando DynamoDB Local..."
    if ! wget -P "$temp_dir" "$DOWNLOAD_URL"; then
      error "❌ Error descargando DynamoDB Local"
    fi
    
    # Descomprimir archivo
    info "📂 Descomprimiendo archivos..."
    if ! unzip "$ZIP_FILE" -d "$dynamodb_dir"; then
      error "❌ Error descomprimiendo archivos"
    fi
    
    # Crear script de inicio
    cat > "${dynamodb_dir}/start.sh" <<'EOF'
#!/bin/bash
set -e

# Configuración
PORT=${1:-8000}
MEMORY=${2:-512}

# Iniciar DynamoDB
java -Djava.library.path=./DynamoDBLocal_lib \
     -Xms${MEMORY}m \
     -Xmx${MEMORY}m \
     -jar DynamoDBLocal.jar \
     -port $PORT \
     -sharedDb
EOF
    chmod +x "${dynamodb_dir}/start.sh"
    
    # Limpiar archivos temporales
    rm -rf "$temp_dir"
    
    success "✅ DynamoDB Local instalado en $dynamodb_dir"
    info "ℹ️  Usa ${dynamodb_dir}/start.sh para iniciar DynamoDB Local"
}

# ==========================================
# Función Principal Mejorada
# ==========================================
# main() {
#     # Verificar que no se ejecute como root
#     check_root

#     print_step "0" "Verificando dependencias"
#     check_dependencies

#     print_step "1" "Configuración del proyecto"
#     local PROJECT_NAME
#     read -r -p "📝 Nombre del proyecto: " PROJECT_NAME
#     validate_project_name "$PROJECT_NAME"

#     local USE_VIRTUALENV="y"
#     local USE_DOCKER="y"
#     local INIT_GIT="y"
#     local USE_PRECOMMIT="n"

#     echo -e "\n📦 Características opcionales:"
#     read -r -p "¿Usar entorno virtual? (y/n): " USE_VIRTUALENV
#     read -r -p "¿Usar Docker? (y/n): " USE_DOCKER
#     read -r -p "¿Inicializar Git? (y/n): " INIT_GIT
#     read -r -p "¿Usar pre-commit? (y/n): " USE_PRECOMMIT

#     print_step "2" "Selección de plugins"
#     select_plugins

#     print_step "3" "Creando proyecto"
#     create_project_structure "$PROJECT_NAME"

#     if [[ $USE_VIRTUALENV == "y" ]]; then
#         setup_virtualenv "$PROJECT_NAME"
#     fi

#     cd "$PROJECT_NAME" || error "❌ No se pudo acceder al directorio del proyecto"

#     # Crear archivos de configuración
#     create_serverless_config "."
#     [[ $USE_DOCKER == "y" ]] && create_docker_config "."
#     create_sample_lambda "."
#     create_requirements "."
#     create_start_script "."

#     # Configuración adicional
#     if [[ $USE_PRECOMMIT == "y" ]]; then
#         create_precommit_config "."
#         setup_precommit
#     fi

#     if [[ $INIT_GIT == "y" ]]; then
#         initialize_git
#     fi

#     if [[ ${#SELECTED_PLUGINS[@]} -gt 0 ]]; then
#         install_serverless_plugins
#     fi

#     success "🎉 Proyecto '$PROJECT_NAME' creado exitosamente!"

#     cat <<EOF

# 📋 Siguientes pasos:
# 1. cd $PROJECT_NAME
# 2. source .venv/bin/activate
# 3. pip install -r requirements.txt
# 4. npm install
# 5. ./scripts/start-local.sh

# 📚 Documentación:
# - Revisa README.md para más información
# - La estructura del proyecto está en docs/
# - Ejemplo de función Lambda en src/functions/hello.py

# EOF
# }

# # Ejecutar script solo si no es sourced
# if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
#     main "$@"
# fi


# Función principal
main() {
    # Error handler
    trap 'error_handler $? $LINENO ${BASH_LINENO[@]} "$BASH_COMMAND" ${FUNCNAME[@]}' ERR
    
    # Mostrar banner
    show_banner
    
    # Verificar permisos y ambiente
    validate_environment
    
    # Cargar configuración guardada si existe
    load_saved_config
    
    # Solicitar configuración del proyecto
    configure_project
    
    # Crear y configurar proyecto
    create_project
    
    # Mostrar resumen y siguientes pasos
    show_summary
}

# Manejador de errores mejorado
error_handler() {
    local exit_code=$1 # Código de salida del comando
    local line_no=$2 # Número de línea de Bash
    local bash_lineno=$3 # Array de números de línea de Bash
    local last_command=$4 # Comando que falló
    local func_trace=$5 # Array de funciones

    error "❌ Error en línea $line_no: comando '$last_command' falló con código $exit_code"
    error "⚠️  Traza de la función: $func_trace"

    # Mostrar traza de Bash si está disponible (opcional)
    if [[ $exit_code -eq 0 ]]; then
        return
    fi

    # Mostrar traza de Bash
    error "⚠️  Traza de Bash:"
    for lineno in "${bash_lineno[@]}"; do
        error "  - Línea $lineno: ${FUNCNAME[$lineno]}"
    done

    # Mostrar mensaje de error según el código de salida
    if [[ $exit_code -eq 1 ]]; then
        error "❌ Error desconocido"
        exit 1
    fi

    # Interrupción por usuario (Ctrl+C)
    if [[ $exit_code -eq 130 ]]; then
        error "❌ Proceso interrumpido por el usuario"
        exit 130
    fi

    # Comando no encontrado
    if [[ $exit_code -eq 127 ]]; then
        error "❌ Comando no encontrado: '$last_command'"
    fi

    # KILL signal (128 + N)
    if [[ $exit_code -ge 128 && $exit_code -lt 192 ]]; then
        local signal=$((exit_code - 128))
        error "❌ Proceso terminado por señal $signal"
    fi

    # Kill process on exit
    if [[ $exit_code -eq 255 ]]; then
        error "❌ Proceso hijo terminado con código de salida 255"
    fi

    # Otros errores
    error "❌ Error inesperado: código de salida $exit_code"

    # Salir con código de error
    exit "$exit_code"
}

kill_process_on_exit() {
    local pid=$1
    trap "kill $pid 2>/dev/null" EXIT
}

# Mostrar banner del proyecto
show_banner() {
    cat <<'EOF'
╔═══════════════════════════════════════════╗
║         🚀 Serverless API Generator        ║
║         Versión 2.0.0                     ║
╚═══════════════════════════════════════════╝
EOF
}

# Validar ambiente de ejecución
validate_environment() {
    print_step "0" "Validando ambiente de ejecución"
    
    # Verificar que no se ejecute como root
    check_root
    
    # Verificar dependencias requeridas
    check_dependencies
    
    # Verificar espacio en disco
    check_disk_space
    
    # Verificar permisos de escritura
    check_write_permissions
}

# Verificar espacio en disco
check_disk_space() {
    local required_space=500 # MB
    local available_space
    
    available_space=$(df -m . | awk 'NR==2 {print $4}')
    
    if ((available_space < required_space)); then
        error "❌ Espacio insuficiente. Se requieren ${required_space}MB, hay ${available_space}MB disponibles"
    fi
}

# Verificar permisos de escritura
check_write_permissions() {
    if ! touch .write_test 2>/dev/null; then
        error "❌ No hay permisos de escritura en el directorio actual"
    fi
    rm -f .write_test
}

# Cargar configuración guardada
load_saved_config() {
    local config_file=".generator-config"
    
    if [[ -f $config_file ]]; then
        info "📂 Cargando configuración guardada..."
        # shellcheck source=/dev/null
        source "$config_file"
    fi
}

# Configurar proyecto
configure_project() {
    print_step "1" "Configuración del proyecto"
    
    # Solicitar nombre del proyecto
    while true; do
        read -r -p "📝 Nombre del proyecto: " PROJECT_NAME
        if validate_project_name "$PROJECT_NAME"; then
            CONFIG[project_name]=$PROJECT_NAME
            break
        fi
    done
    
    # Configuración del proyecto
    configure_options
    
    # Selección de plugins
    print_step "2" "Selección de plugins"
    select_plugins
    
    # Guardar configuración
    save_config
}

# Configurar opciones del proyecto
configure_options() {
    echo -e "\n📦 Características del proyecto:"
    
    # Función para preguntar sí/no
    ask_yes_no() {
        local prompt="$1"
        local default="${2:-y}"
        local response=""

        # Validar el valor por defecto
        if [[ ! $default =~ ^[yn]$ ]]; then
            error "❌ Valor por defecto inválido: $default. Debe ser 'y' o 'n'"
            return 1
        fi

        # Preparar el texto del prompt según el valor por defecto
        local prompt_text
        if [[ $default == "y" ]]; then
            prompt_text="$prompt [Y/n]"
        else
            prompt_text="$prompt [y/N]"
        fi

        while true; do
            # Mostrar el prompt y leer la respuesta
            read -r -p "$prompt_text: " response

            # Si la respuesta está vacía, usar el valor por defecto
            if [[ -z $response ]]; then
                # echo "$default"
                return $([ "$default" = "y" ] && echo 0 || echo 1)
            fi

            # Convertir la respuesta a minúsculas
            response=$(echo "$response" | tr '[:upper:]' '[:lower:]')

            # Validar y procesar la respuesta
            case "$response" in
                y|yes)
                    # echo "y"
                    return 0
                    ;;
                n|no)
                    # echo "n"
                    return 1
                    ;;
                *)
                    echo "Por favor responde 'y' (yes) o 'n' (no)" >&2
                    ;;
            esac
        done
    }

    # Función auxiliar para actualizar la configuración
    update_config() {
        local key="$1"
        local prompt="$2"
        local default="${3:-y}"

        if ask_yes_no "$prompt" "$default"; then
            CONFIG[$key]="y"
        else
            CONFIG[$key]="n"
        fi
    }

    # Configurar opciones básicas
    update_config "use_virtualenv" "¿Usar entorno virtual?" "y"
    update_config "use_docker" "¿Usar Docker?" "y"
    update_config "init_git" "¿Inicializar Git?" "y"
    update_config "use_precommit" "¿Usar pre-commit?" "n"

    # Configurar opciones avanzadas
    if ask_yes_no "¿Configurar opciones avanzadas?" "n"; then
        update_config "use_typescript" "¿Usar TypeScript?" "n"
        update_config "use_terraform" "¿Incluir configuración Terraform?" "n"
        update_config "use_cicd" "¿Configurar CI/CD?" "n"
    fi

    # Configurar actualizaciones automáticas
    update_config "auto_update" "¿Actualizar automáticamente las dependencias?" "y"
    update_config "upgrade_python" "¿Actualizar Python a la última versión?" "n"
    update_config "upgrade_pip" "¿Actualizar pip a la última versión?" "n"
    update_config "upgrade_node" "¿Actualizar Node.js a la última versión?" "n"
}

# Guardar configuración
save_config() {
    local config_file=".generator-config"
    
    {
        echo "# Configuración generada el $(date)"
        for key in "${!CONFIG[@]}"; do
            echo "CONFIG[$key]='${CONFIG[$key]}'"
        done
    } > "$config_file"
}

# Crear proyecto
create_project() {
    print_step "3" "Creando proyecto"
    
    # Crear estructura base
    create_project_structure "${CONFIG[project_name]}"
    
    # Cambiar al directorio del proyecto
    cd "${CONFIG[project_name]}" || error "❌ No se pudo acceder al directorio del proyecto"
    
    # Configurar ambiente virtual si está habilitado
    if [[ ${CONFIG[use_virtualenv]} == "y" ]]; then
        setup_virtualenv "."
    fi
    
    # Crear archivos de configuración
    create_serverless_config "."
    [[ ${CONFIG[use_docker]} == "y" ]] && create_docker_config "."
    create_sample_lambda "."
    create_requirements "."
    create_start_script "."
    
    # Configuración adicional
    if [[ ${CONFIG[use_precommit]} == "y" ]]; then
        create_precommit_config "."
        setup_precommit
    fi
    
    # Configurar TypeScript si está habilitado
    if [[ ${CONFIG[use_typescript]:-n} == "y" ]]; then
        setup_typescript
    fi
    
    # Configurar Terraform si está habilitado
    if [[ ${CONFIG[use_terraform]:-n} == "y" ]]; then
        setup_terraform "."
    fi
    
    # Configurar CI/CD si está habilitado
    if [[ ${CONFIG[use_cicd]:-n} == "y" ]]; then
        setup_cicd "." "${CONFIG[project_name]}"
    fi
    
    # Inicializar Git si está habilitado
    if [[ ${CONFIG[init_git]} == "y" ]]; then
        initialize_git "." "${CONFIG[project_name]}" "${CONFIG[use_precommit]}"
    fi
    
    # Instalar plugins seleccionados
    if [[ ${#SELECTED_PLUGINS[@]} -gt 0 ]]; then
        install_serverless_plugins

        # Instalar DynamoDB Local si está habilitado
        install_dynamodb_local_from_url "." "${CONFIG[use_docker]}"
    fi
}

# Mostrar resumen y siguientes pasos
show_summary() {
    success "🎉 Proyecto '${CONFIG[project_name]}' creado exitosamente!"
    
    # Mostrar resumen de la configuración
    echo -e "\n📋 Resumen de la configuración:"
    for key in "${!CONFIG[@]}"; do
        echo "  - ${key}: ${CONFIG[$key]}"
    done
    
    # Mostrar siguientes pasos
    cat <<EOF

📋 Siguientes pasos:
1. cd ${CONFIG[project_name]}
2. source .venv/bin/activate  # Si se usa entorno virtual
3. pip install -r requirements.txt
4. npm install
5. ./scripts/start-local.sh

📚 Documentación:
- Revisa README.md para más información
- La estructura del proyecto está en docs/
- Ejemplo de función Lambda en src/functions/hello.py

🔧 Herramientas disponibles:
- scripts/start-local.sh: Iniciar ambiente de desarrollo
- scripts/manage-deps.sh: Gestionar dependencias
- scripts/docker-utils.sh: Gestionar contenedores (si Docker está habilitado)

💡 Tips:
- Usa 'pre-commit run --all-files' para verificar el código
- Revisa la documentación en docs/ para guías detalladas
- Consulta serverless.yml para la configuración del servicio

EOF

    # Si hay advertencias, mostrarlas
    if [[ ${WARNINGS[@]:-0} -gt 0 ]]; then
        echo -e "\n⚠️  Advertencias durante la instalación:"
        printf '%s\n' "${WARNINGS[@]}"
    fi
}

# Cleanup al salir
cleanup() {
    if [[ -n ${CONFIG[project_name]:-} && -d ${CONFIG[project_name]} ]]; then
        info "🧹 Limpiando recursos..."
        rm -rf "${CONFIG[project_name]}"
    fi
}

# Clase PluginSelector
select_plugins() {
    local -a selected_states=()
    local current_pos=0
    local is_active=true
    local saved_tty_state

    initialize() {
        # Inicializar estados de selección
        selected_states=($(for ((i=0; i<${#AVAILABLE_PLUGINS[@]}; i++)); do echo 0; done))
        
        # Guardar y configurar estado de la terminal
        saved_tty_state=$(stty -g)
        stty raw -echo
        
        # Limpiar pantalla inicial
        clear_screen
    }

    clear_screen() {
        tput clear
        tput cup 0 0
    }

    get_selected_count() {
        local count=0
        for state in "${selected_states[@]}"; do
            ((count += state))
        done
        echo "$count"
    }

    render_menu() {
        clear_screen
        
        # Encabezado
        echo -e "🔌 ${BOLD}Selecciona los plugins a instalar:${NC}\n"
        
        # Contador de selección
        local selected_count
        selected_count=$(get_selected_count)
        echo -e "Plugins seleccionados: ${GREEN}${selected_count}${NC}/${#AVAILABLE_PLUGINS[@]}\n"
        
        # Lista de plugins
        for i in "${!AVAILABLE_PLUGINS[@]}"; do
            local checkmark=" "
            [[ ${selected_states[i]} -eq 1 ]] && checkmark="✔"
            
            if [[ $i -eq $current_pos ]]; then
                echo -e "${YELLOW}  [${checkmark}] ${AVAILABLE_PLUGINS[i]}${NC}"
            else
                echo -e "  [${checkmark}] ${AVAILABLE_PLUGINS[i]}"
            fi
        done
        
        # Instrucciones
        echo -e "\n[Space] Seleccionar/Deseleccionar  [↑/↓] Mover  [Enter] Confirmar  [Q] Salir\n"
    }

    handle_key_press() {
        local key
        read -rsN1 key
        
        # Detectar teclas de flecha (secuencia de escape)
        if [[ $key == $'\x1b' ]]; then
            read -rsN2 key
        fi

        case $key in
        " ") # Espacio
            selected_states[current_pos]=$((1 - selected_states[current_pos]))
            ;;
        "[A"|"k") # Arriba
            if ((current_pos == 0)); then
                # Si está en el primer elemento, ir al último
                current_pos=$((${#AVAILABLE_PLUGINS[@]} - 1))
            else
                # Si no, subir una posición
                current_pos=$((current_pos - 1))
            fi
            ;;
        "[B"|"j") # Abajo
            if ((current_pos >= ${#AVAILABLE_PLUGINS[@]} - 1)); then
                # Si está en el último elemento, ir al primero
                current_pos=0
            else
                # Si no, bajar una posición
                current_pos=$((current_pos + 1))
            fi
            ;;
        "q") # Salir
            SELECTED_PLUGINS=()
            is_active=false
            stty "$saved_tty_state" # Restaurar terminal
            clear_screen
            break
            ;;
        $'\n') # Enter
            if validate_selection; then
                save_selection
                break
            else
                warning "⚠️ Debes seleccionar al menos un plugin"
                sleep 1
            fi
            ;;
        esac
    }

    validate_selection() {
        for state in "${selected_states[@]}"; do
            [[ $state -eq 1 ]] && return 0
        done
        return 1
    }

    save_selection() {
        SELECTED_PLUGINS=()
        for i in "${!AVAILABLE_PLUGINS[@]}"; do
            [[ ${selected_states[i]} -eq 1 ]] && SELECTED_PLUGINS+=("${AVAILABLE_PLUGINS[i]}")
        done

        echo -e "\n✅ Plugins seleccionados: ${SELECTED_PLUGINS[*]}"

        is_active=false

        # Restaurar terminal
        stty "$saved_tty_state"

        clear_screen
    }

    main_loop() {
        while $is_active; do
            render_menu
            handle_key_press
        done
    }

    # Ejecución principal
    initialize
    main_loop
    stty "$saved_tty_state" # Restaurar terminal
    clear_screen
}

# ==========================================
# Configuracion de Terraform
# ==========================================
setup_terraform() {
    local project_dir="$1"
    info "🔧 Configurando Terraform..."

    # Crear estructura de directorios
    mkdir -p "${project_dir}/terraform/environments/"{dev,staging,prod}
    mkdir -p "${project_dir}/terraform/modules/"{dynamodb,lambda,api-gateway}

    # Crear archivo principal
    cat > "${project_dir}/terraform/main.tf" <<'EOF'
terraform {
  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    # Se configurará por ambiente
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "terraform"
    }
  }
}

# Variables locales
locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# Módulos
module "dynamodb" {
  source = "./modules/dynamodb"

  name_prefix = local.name_prefix
  environment = var.environment
  tables      = var.dynamodb_tables
}

module "lambda" {
  source = "./modules/lambda"

  name_prefix = local.name_prefix
  environment = var.environment
  functions   = var.lambda_functions
}

module "api_gateway" {
  source = "./modules/api-gateway"

  name_prefix = local.name_prefix
  environment = var.environment
  api_name    = var.api_name
  endpoints   = var.api_endpoints
}
EOF

    # Crear variables
    cat > "${project_dir}/terraform/variables.tf" <<'EOF'
variable "project_name" {
  description = "Nombre del proyecto"
  type        = string
}

variable "environment" {
  description = "Ambiente de despliegue (dev, staging, prod)"
  type        = string
}

variable "aws_region" {
  description = "Región de AWS"
  type        = string
  default     = "us-east-1"
}

variable "dynamodb_tables" {
  description = "Configuración de tablas DynamoDB"
  type = list(object({
    name             = string
    hash_key         = string
    range_key        = optional(string)
    billing_mode     = optional(string)
    read_capacity    = optional(number)
    write_capacity   = optional(number)
    stream_enabled   = optional(bool)
    attributes       = list(object({
      name = string
      type = string
    }))
    global_secondary_indexes = optional(list(object({
      name               = string
      hash_key          = string
      range_key         = optional(string)
      projection_type   = string
      non_key_attributes = optional(list(string))
    })))
  }))
  default = []
}

variable "lambda_functions" {
  description = "Configuración de funciones Lambda"
  type = list(object({
    name        = string
    handler     = string
    runtime     = string
    memory_size = optional(number)
    timeout     = optional(number)
    environment_variables = optional(map(string))
  }))
  default = []
}

variable "api_endpoints" {
  description = "Configuración de endpoints de API Gateway"
  type = list(object({
    path        = string
    method      = string
    function    = string
    auth        = optional(bool)
    cors        = optional(bool)
  }))
  default = []
}

variable "api_name" {
  description = "Nombre de la API"
  type        = string
}
EOF

    # Crear outputs
    cat > "${project_dir}/terraform/outputs.tf" <<'EOF'
output "dynamodb_table_arns" {
  description = "ARNs de las tablas DynamoDB"
  value       = module.dynamodb.table_arns
}

output "lambda_function_arns" {
  description = "ARNs de las funciones Lambda"
  value       = module.lambda.function_arns
}

output "api_gateway_url" {
  description = "URL de la API Gateway"
  value       = module.api_gateway.api_url
}

output "api_gateway_stage" {
  description = "Stage de la API Gateway"
  value       = module.api_gateway.stage_name
}
EOF

    # Crear módulo DynamoDB
    cat > "${project_dir}/terraform/modules/dynamodb/main.tf" <<'EOF'
resource "aws_dynamodb_table" "tables" {
  for_each = { for table in var.tables : table.name => table }

  name           = "${var.name_prefix}-${each.value.name}"
  billing_mode   = each.value.billing_mode != null ? each.value.billing_mode : "PAY_PER_REQUEST"
  hash_key       = each.value.hash_key
  range_key      = each.value.range_key

  dynamic "attribute" {
    for_each = each.value.attributes
    content {
      name = attribute.value.name
      type = attribute.value.type
    }
  }

  dynamic "global_secondary_index" {
    for_each = each.value.global_secondary_indexes != null ? each.value.global_secondary_indexes : []
    content {
      name               = global_secondary_index.value.name
      hash_key          = global_secondary_index.value.hash_key
      range_key         = global_secondary_index.value.range_key
      projection_type   = global_secondary_index.value.projection_type
      non_key_attributes = global_secondary_index.value.non_key_attributes
    }
  }

  stream_enabled = each.value.stream_enabled

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  tags = {
    Name        = "${var.name_prefix}-${each.value.name}"
    Environment = var.environment
  }
}
EOF

    # Crear configuraciones por ambiente
    for env in dev staging prod; do
        cat > "${project_dir}/terraform/environments/${env}/main.tf" <<EOF
terraform {
  backend "s3" {
    bucket         = "your-terraform-state-bucket"
    key            = "${env}/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-lock"
    encrypt        = true
  }
}

module "main" {
  source = "../../"

  project_name = "your-project"
  environment  = "${env}"
  aws_region   = "us-east-1"

  dynamodb_tables = [
    {
      name      = "orders"
      hash_key  = "id"
      attributes = [
        {
          name = "id"
          type = "S"
        },
        {
          name = "status"
          type = "S"
        }
      ]
      global_secondary_indexes = [
        {
          name            = "StatusIndex"
          hash_key       = "status"
          projection_type = "ALL"
        }
      ]
    }
  ]

  lambda_functions = [
    {
      name        = "get-orders"
      handler     = "src/functions/orders/get.handler"
      runtime     = "python3.9"
      memory_size = 128
      timeout     = 30
    }
  ]

  api_endpoints = [
    {
      path     = "/orders"
      method   = "GET"
      function = "get-orders"
      cors     = true
    }
  ]
}
EOF
    done

    # Crear .gitignore específico para Terraform
    cat >> "${project_dir}/.gitignore" <<'EOF'

# Terraform
**/.terraform/*
*.tfstate
*.tfstate.*
.terraform.lock.hcl
*.tfvars
EOF

    # Crear README específico para Terraform
    cat > "${project_dir}/terraform/README.md" <<'EOF'
# Infraestructura Terraform

## 📋 Descripción
Configuración de infraestructura como código usando Terraform para el proyecto.

## 🚀 Uso

### Pre-requisitos
- Terraform >= 1.0.0
- AWS CLI configurado
- S3 bucket para estado remoto
- DynamoDB table para bloqueo de estado

### Inicialización
```bash
# Configurar ambiente
cd environments/dev

# Inicializar Terraform
terraform init

# Planear cambios
terraform plan

# Aplicar cambios
terraform apply
```

## 📁 Estructura
```
terraform/
├── environments/          # Configuraciones por ambiente
│   ├── dev/
│   ├── staging/
│   └── prod/
├── modules/              # Módulos reutilizables
│   ├── dynamodb/
│   ├── lambda/
│   └── api-gateway/
├── main.tf              # Configuración principal
├── variables.tf         # Definición de variables
└── outputs.tf           # Outputs definidos
```

## ⚙️ Configuración
1. Configurar backend S3 en cada ambiente
2. Ajustar variables según necesidades
3. Revisar configuraciones de seguridad

## 🔒 Seguridad
- Encriptación en reposo habilitada
- Point-in-time recovery configurado
- Least privilege IAM roles
EOF

    success "✅ Configuración de Terraform creada exitosamente"
    info "ℹ️  Revisa terraform/README.md para instrucciones de uso"
}

# ==========================================
# Configuración de CI/CD
# ==========================================
setup_cicd() {
    local project_dir="$1"
    info "🔧 Configurando CI/CD..."

    # Crear directorios para GitHub Actions
    mkdir -p "${project_dir}/.github/workflows"

    # Crear workflow principal
    cat > "${project_dir}/.github/workflows/main.yml" <<'EOF'
name: CI/CD Pipeline

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]
  workflow_dispatch:

env:
  PYTHON_VERSION: '3.9'
  NODE_VERSION: '16'
  AWS_REGION: 'us-east-1'

jobs:
  validate:
    name: 🔍 Validate
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Set up Python
        uses: actions/setup-python@v4
        with:
          python-version: ${{ env.PYTHON_VERSION }}

      - name: Set up Node.js
        uses: actions/setup-node@v3
        with:
          node-version: ${{ env.NODE_VERSION }}

      - name: Cache pip packages
        uses: actions/cache@v3
        with:
          path: ~/.cache/pip
          key: ${{ runner.os }}-pip-${{ hashFiles('**/requirements*.txt') }}
          restore-keys: |
            ${{ runner.os }}-pip-

      - name: Cache node modules
        uses: actions/cache@v3
        with:
          path: ~/.npm
          key: ${{ runner.os }}-node-${{ hashFiles('**/package-lock.json') }}
          restore-keys: |
            ${{ runner.os }}-node-

      - name: Install dependencies
        run: |
          python -m pip install --upgrade pip
          pip install -r requirements.txt
          pip install -r requirements-dev.txt
          npm ci

      - name: Run linters
        run: |
          pre-commit run --all-files

      - name: Run tests
        run: |
          pytest --cov=src --cov-report=xml

      - name: Upload coverage
        uses: codecov/codecov-action@v3
        with:
          file: ./coverage.xml
          fail_ci_if_error: true

  deploy-dev:
    name: 🚀 Deploy to Dev
    needs: validate
    if: github.ref == 'refs/heads/main' && github.event_name == 'push'
    runs-on: ubuntu-latest
    environment: development
    
    steps:
      - uses: actions/checkout@v3

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v2
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ${{ env.AWS_REGION }}

      - name: Set up Python
        uses: actions/setup-python@v4
        with:
          python-version: ${{ env.PYTHON_VERSION }}

      - name: Set up Node.js
        uses: actions/setup-node@v3
        with:
          node-version: ${{ env.NODE_VERSION }}

      - name: Install dependencies
        run: |
          python -m pip install --upgrade pip
          pip install -r requirements.txt
          npm ci

      - name: Deploy to dev
        run: |
          npx serverless deploy --stage dev
        env:
          NODE_ENV: development
          STAGE: dev

  deploy-staging:
    name: 🚀 Deploy to Staging
    needs: deploy-dev
    if: github.ref == 'refs/heads/main' && github.event_name == 'push'
    runs-on: ubuntu-latest
    environment: staging
    
    steps:
      - uses: actions/checkout@v3

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v2
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ${{ env.AWS_REGION }}

      - name: Deploy to staging
        run: |
          npx serverless deploy --stage staging
        env:
          NODE_ENV: staging
          STAGE: staging

  deploy-prod:
    name: 🚀 Deploy to Production
    needs: deploy-staging
    if: github.ref == 'refs/heads/main' && github.event_name == 'push'
    runs-on: ubuntu-latest
    environment: production
    
    steps:
      - uses: actions/checkout@v3

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v2
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ${{ env.AWS_REGION }}

      - name: Deploy to production
        run: |
          npx serverless deploy --stage prod
        env:
          NODE_ENV: production
          STAGE: prod
EOF

    # Crear workflow para pruebas
    cat > "${project_dir}/.github/workflows/tests.yml" <<'EOF'
name: Tests

on:
  push:
    branches-ignore: [ main ]
  pull_request:
    branches-ignore: [ main ]

env:
  PYTHON_VERSION: '3.9'
  NODE_VERSION: '16'

jobs:
  test:
    name: 🧪 Run Tests
    runs-on: ubuntu-latest
    
    steps:
      - uses: actions/checkout@v3

      - name: Set up Python
        uses: actions/setup-python@v4
        with:
          python-version: ${{ env.PYTHON_VERSION }}

      - name: Set up Node.js
        uses: actions/setup-node@v3
        with:
          node-version: ${{ env.NODE_VERSION }}

      - name: Install dependencies
        run: |
          python -m pip install --upgrade pip
          pip install -r requirements.txt
          pip install -r requirements-dev.txt
          npm ci

      - name: Run linters
        run: |
          pre-commit run --all-files

      - name: Run tests
        run: |
          pytest --cov=src --cov-report=xml

      - name: Upload coverage
        uses: codecov/codecov-action@v3
        with:
          file: ./coverage.xml
          fail_ci_if_error: true
EOF

    # Crear workflow para seguridad
    cat > "${project_dir}/.github/workflows/security.yml" <<'EOF'
name: Security Scan

on:
  schedule:
    - cron: '0 0 * * *'  # Diariamente a medianoche
  workflow_dispatch:

jobs:
  security-scan:
    name: 🔒 Security Scan
    runs-on: ubuntu-latest
    
    steps:
      - uses: actions/checkout@v3

      - name: Run Snyk to check for vulnerabilities
        uses: snyk/actions/python@master
        env:
          SNYK_TOKEN: ${{ secrets.SNYK_TOKEN }}
        with:
          args: --severity-threshold=high

      - name: Run safety check
        run: |
          pip install safety
          safety check

      - name: Run bandit
        run: |
          pip install bandit
          bandit -r src/

      - name: Run dependency review
        uses: actions/dependency-review-action@v2
EOF

    # Crear workflow para releases
    cat > "${project_dir}/.github/workflows/release.yml" <<'EOF'
name: Release

on:
  push:
    tags:
      - 'v*'

jobs:
  release:
    name: 📦 Create Release
    runs-on: ubuntu-latest
    
    steps:
      - uses: actions/checkout@v3
        with:
          fetch-depth: 0

      - name: Generate changelog
        id: changelog
        uses: metcalfc/changelog-generator@v4.0.1
        with:
          myToken: ${{ secrets.GITHUB_TOKEN }}

      - name: Create release
        uses: softprops/action-gh-release@v1
        with:
          body: ${{ steps.changelog.outputs.changelog }}
          draft: false
          prerelease: false
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
EOF

    # Crear archivos de configuración adicionales
    mkdir -p "${project_dir}/.github/ISSUE_TEMPLATE"
    
    # Template para bugs
    cat > "${project_dir}/.github/ISSUE_TEMPLATE/bug_report.md" <<'EOF'
---
name: Bug report
about: Create a report to help us improve
title: '[BUG] '
labels: bug
assignees: ''

---

**Describe the bug**
A clear and concise description of what the bug is.

**To Reproduce**
Steps to reproduce the behavior:
1. Go to '...'
2. Click on '....'
3. Scroll down to '....'
4. See error

**Expected behavior**
A clear and concise description of what you expected to happen.

**Screenshots**
If applicable, add screenshots to help explain your problem.

**Environment:**
 - OS: [e.g. Ubuntu 20.04]
 - Python Version: [e.g. 3.9]
 - Node Version: [e.g. 16]

**Additional context**
Add any other context about the problem here.
EOF

    # Template para features
    cat > "${project_dir}/.github/ISSUE_TEMPLATE/feature_request.md" <<'EOF'
---
name: Feature request
about: Suggest an idea for this project
title: '[FEATURE] '
labels: enhancement
assignees: ''

---

**Is your feature request related to a problem? Please describe.**
A clear and concise description of what the problem is. Ex. I'm always frustrated when [...]

**Describe the solution you'd like**
A clear and concise description of what you want to happen.

**Describe alternatives you've considered**
A clear and concise description of any alternative solutions or features you've considered.

**Additional context**
Add any other context or screenshots about the feature request here.
EOF

    # Crear pull request template
    cat > "${project_dir}/.github/pull_request_template.md" <<'EOF'
## Description
Please include a summary of the change and which issue is fixed. Please also include relevant motivation and context.

Fixes # (issue)

## Type of change
Please delete options that are not relevant.

- [ ] Bug fix (non-breaking change which fixes an issue)
- [ ] New feature (non-breaking change which adds functionality)
- [ ] Breaking change (fix or feature that would cause existing functionality to not work as expected)
- [ ] This change requires a documentation update

## How Has This Been Tested?
Please describe the tests that you ran to verify your changes.

- [ ] Test A
- [ ] Test B

## Checklist:
- [ ] My code follows the style guidelines of this project
- [ ] I have performed a self-review of my own code
- [ ] I have commented my code, particularly in hard-to-understand areas
- [ ] I have made corresponding changes to the documentation
- [ ] My changes generate no new warnings
- [ ] I have added tests that prove my fix is effective or that my feature works
- [ ] New and existing unit tests pass locally with my changes
- [ ] Any dependent changes have been merged and published in downstream modules
EOF

    success "✅ Configuración de CI/CD creada exitosamente"
    info "ℹ️  Revisa los workflows en .github/workflows/"
}

# Ejecutar script solo si no es sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
