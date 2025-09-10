#!/bin/bash

# Script de build de produção para Linux
# Baseado no build-producao.ps1

set -e  # Para na primeira falha

# Configurações padrão
VERSION="v4.4"
REGISTRY="witrocha"
IMAGE_NAME="chatwit"
LATEST=false
NO_ENTERPRISE=false
DISABLE_TELEMETRY=true
NO_CACHE=false
NO_PUSH=false
DOCKER_USER=""
SKIP_LOGIN=false
USE_SYSTEM_DOCKER_CONFIG=false

# Carrega token do Docker Hub de .env (chave: docker_dckr_pat) sem executar o arquivo
load_docker_pat_from_dotenv() {
  if [ -n "${DOCKER_PWD:-}" ]; then
    echo "$DOCKER_PWD"
    return 0
  fi
  if [ -n "${DOCKER_PAT:-}" ]; then
    echo "$DOCKER_PAT"
    return 0
  fi
  if [ -f .env ]; then
    local line
    line=$(grep -m1 -E "^\s*docker_dckr_pat\s*=" .env 2>/dev/null || true)
    if [ -n "$line" ]; then
      local value
      value=$(printf '%s' "$line" | sed -E 's/^[^=]*=//')
      value="${value%\"}"
      value="${value#\"}"
      value="${value%\'}"
      value="${value#\'}"
      echo "$value"
      return 0
    fi
  fi
  return 1
}

# Função de ajuda
show_help() {
    cat << EOF
Script de Build de Produção - Chatwit

USAGE:
    ./build-producao.sh [OPTIONS]

OPTIONS:
    -v, --version VERSION     Versão da imagem (padrão: v4.4)
    -r, --registry REGISTRY  Nome do registry (padrão: witrocha)
    -i, --image IMAGE         Nome da imagem (padrão: chatwit)
    -l, --latest              Adiciona tag 'latest'
    --no-enterprise           Usa Dockerfile padrão em vez do enterprise
    --enable-telemetry        Habilita telemetria (padrão: desabilitada)
    --no-cache                Build sem cache
    --no-push                 Não faz push para o registry
    --docker-user USER        Usuário para docker login (padrão: REGISTRY)
    --skip-login              Pula docker login
    --system-docker-config    Usa ~/.docker/config.json (padrão: usa config temporário limpo)
    -h, --help                Mostra esta ajuda

EXAMPLES:
    ./build-producao.sh -v v5.0.0 --latest
    ./build-producao.sh --no-push
    ./build-producao.sh --no-enterprise --latest

EOF
}

# Processamento de argumentos
while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--version)
            VERSION="$2"
            shift 2
            ;;
        -r|--registry)
            REGISTRY="$2"
            shift 2
            ;;
        -i|--image)
            IMAGE_NAME="$2"
            shift 2
            ;;
        -l|--latest)
            LATEST=true
            shift
            ;;
        --no-enterprise)
            NO_ENTERPRISE=true
            shift
            ;;
        --enable-telemetry)
            DISABLE_TELEMETRY=false
            shift
            ;;
        --no-cache)
            NO_CACHE=true
            shift
            ;;
        --no-push)
            NO_PUSH=true
            shift
            ;;
        --docker-user)
            DOCKER_USER="$2"
            shift 2
            ;;
        --skip-login)
            SKIP_LOGIN=true
            shift
            ;;
        --system-docker-config)
            USE_SYSTEM_DOCKER_CONFIG=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Opção desconhecida: $1"
            show_help
            exit 1
            ;;
    esac
done

# Construir array de tags
TAGS=("$VERSION")
if [ "$LATEST" = true ]; then
    TAGS+=("latest")
fi

FULL_IMAGE="$REGISTRY/$IMAGE_NAME"

# Definir Dockerfile
if [ "$NO_ENTERPRISE" = true ]; then
    DOCKERFILE="Dockerfile"
    echo -e "\033[36m[INFO] Usando: Dockerfile (padrão)\033[0m"
else
    DOCKERFILE="Dockerfile.enterprise"
    echo -e "\033[36m[INFO] Usando: Dockerfile.enterprise\033[0m"
fi

echo -e "\033[32m[BUILD] Building ${FULL_IMAGE} with tags: ${TAGS[*]}\033[0m"

# Definir usuário de login no Docker (padrão: mesmo valor de REGISTRY)
if [ -z "$DOCKER_USER" ]; then
  DOCKER_USER="$REGISTRY"
fi

# Configurar DOCKER_CONFIG temporário por padrão para evitar helpers do sistema (ex.: docker-credential-desktop.exe)
TMP_DOCKER_CONFIG=""
if [ "$USE_SYSTEM_DOCKER_CONFIG" = false ]; then
  TMP_DOCKER_CONFIG=$(mktemp -d)
  umask 077
  mkdir -p "$TMP_DOCKER_CONFIG"
  echo '{}' > "$TMP_DOCKER_CONFIG/config.json"
  export DOCKER_CONFIG="$TMP_DOCKER_CONFIG"
  trap 'if [ -n "$TMP_DOCKER_CONFIG" ] && [ -d "$TMP_DOCKER_CONFIG" ]; then rm -rf "$TMP_DOCKER_CONFIG"; fi' EXIT
  echo -e "\033[36m[INFO] Usando DOCKER_CONFIG temporário em $DOCKER_CONFIG\033[0m"
else
  echo -e "\033[36m[INFO] Usando DOCKER_CONFIG do sistema (~/.docker)\033[0m"
fi

# Login no Docker Hub (se não pulado)
if [ "$SKIP_LOGIN" = false ]; then
  DOCKER_PAT=$(load_docker_pat_from_dotenv || true)
  if [ -n "$DOCKER_PAT" ]; then
    echo -e "\033[36m[LOGIN] Autenticando docker user '$DOCKER_USER' via --password-stdin\033[0m"
    if ! printf '%s' "$DOCKER_PAT" | docker login --username "$DOCKER_USER" --password-stdin; then
      echo -e "\033[31m[ERROR] Falha no docker login com token do .env/variável.\033[0m"
      exit 1
    fi
  else
    echo -e "\033[33m[LOGIN] Token não encontrado (.env docker_dckr_pat ou DOCKER_PWD). Tentando login interativo...\033[0m"
    if ! docker login --username "$DOCKER_USER"; then
      echo -e "\033[31m[ERROR] Falha no docker login interativo.\033[0m"
      exit 1
    fi
  fi
else
  echo -e "\033[33m[INFO] Login docker pulado (--skip-login).\033[0m"
fi

# Preparar argumentos de build
BUILD_ARGS=()
if [ "$DISABLE_TELEMETRY" = true ]; then
    echo -e "\033[32m[PRIVACY] Desabilitando telemetria na imagem...\033[0m"
    BUILD_ARGS+=(--build-arg DISABLE_TELEMETRY=true)
    BUILD_ARGS+=(--build-arg ANALYTICS_TOKEN=)
    BUILD_ARGS+=(--build-arg CHATWOOT_HUB_URL=http://localhost:9999)
fi

# Build com a primeira tag (versão principal)
PRIMARY_TAG="${TAGS[0]}"
echo -e "\033[33m[BUILD] Building ${FULL_IMAGE}:${PRIMARY_TAG}...\033[0m"

# Preparar comando de build
DOCKER_BUILD_CMD=(docker build -f "$DOCKERFILE")

if [ "$NO_CACHE" = true ]; then
    DOCKER_BUILD_CMD+=(--no-cache)
    echo -e "\033[33m[INFO] Build sem cache habilitado\033[0m"
fi

if [ ${#BUILD_ARGS[@]} -gt 0 ]; then
    DOCKER_BUILD_CMD+=("${BUILD_ARGS[@]}")
fi

DOCKER_BUILD_CMD+=(-t "${FULL_IMAGE}:${PRIMARY_TAG}" .)

# Executar comando de build
echo -e "\033[36m[EXEC] ${DOCKER_BUILD_CMD[*]}\033[0m"
"${DOCKER_BUILD_CMD[@]}"

# Verificar se o build foi bem-sucedido
if [ $? -eq 0 ]; then
    echo -e "\033[32m[SUCCESS] Build successful!\033[0m"
    
    # Tag com as tags adicionais
    if [ ${#TAGS[@]} -gt 1 ]; then
        for ((i=1; i<${#TAGS[@]}; i++)); do
            ADDITIONAL_TAG="${TAGS[$i]}"
            docker tag "${FULL_IMAGE}:${PRIMARY_TAG}" "${FULL_IMAGE}:${ADDITIONAL_TAG}"
            echo -e "\033[32m[TAG] Tagged as ${ADDITIONAL_TAG}\033[0m"
        done
    fi
    
    echo -e "\033[32m[COMPLETE] Imagem criada com sucesso:\033[0m"
    for tag in "${TAGS[@]}"; do
        echo -e "\033[36m  -> ${FULL_IMAGE}:${tag}\033[0m"
    done
    
    # Push para o registry
    if [ "$NO_PUSH" = false ]; then
        echo -e "\033[33m[PUSH] Iniciando push para o registro (padrão)...\033[0m"
        echo -e "\033[36m[INFO] Para desabilitar, use a flag --no-push.\033[0m"
        
        for tag in "${TAGS[@]}"; do
            echo -e "\033[36m[PUSH] Enviando ${FULL_IMAGE}:${tag}...\033[0m"
            docker push "${FULL_IMAGE}:${tag}"
            
            if [ $? -ne 0 ]; then
                echo -e "\033[31m[ERROR] Falha no push da tag ${tag}!\033[0m"
                exit 1
            else
                echo -e "\033[32m[SUCCESS] Push da tag ${tag} concluído.\033[0m"
            fi
        done
        
        echo -e "\033[32m[COMPLETE] Todas as tags foram enviadas para o registro.\033[0m"
    else
        echo -e "\033[33m[INFO] Push automático desabilitado pela flag --no-push.\033[0m"
        echo -e "\033[33m[INFO] Para fazer push manualmente:\033[0m"
        for tag in "${TAGS[@]}"; do
            echo -e "\033[37m  docker push ${FULL_IMAGE}:${tag}\033[0m"
        done
    fi
    
    if [ "$DISABLE_TELEMETRY" = true ]; then
        echo ""
        echo -e "\033[32m[PRIVACY] TELEMETRIA DESABILITADA NA IMAGEM!\033[0m"
    fi
    
else
    echo -e "\033[31m[ERROR] Build failed!\033[0m"
    exit 1
fi
