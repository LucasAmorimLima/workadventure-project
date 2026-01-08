#!/bin/bash

# ========================================
# Script Helper para Gerenciar WorkAdventure na AWS
# ========================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Carregar informações do deployment
if [ ! -f "deployment-info.txt" ]; then
    echo -e "${RED}❌ Arquivo deployment-info.txt não encontrado${NC}"
    echo "   Execute o deploy primeiro: ./deploy-aws.sh"
    exit 1
fi

SERVER_IP=$(grep "IP Público:" deployment-info.txt | awk '{print $3}')
KEY_FILE=$(grep "Chave SSH:" deployment-info.txt | awk '{print $3}')
INSTANCE_ID=$(grep "Instance ID:" deployment-info.txt | awk '{print $3}')
REGION=$(grep "Região:" deployment-info.txt | awk '{print $2}')

if [ -z "$SERVER_IP" ] || [ -z "$KEY_FILE" ]; then
    echo -e "${RED}❌ Não foi possível ler informações de deployment${NC}"
    exit 1
fi

PROJECT_DIR="/opt/workadventure"

# Função para executar comando remoto
remote_cmd() {
    ssh -i $KEY_FILE -o StrictHostKeyChecking=no ubuntu@$SERVER_IP "$@"
}

# Função para executar comando docker compose remoto
docker_cmd() {
    remote_cmd "cd $PROJECT_DIR && docker compose $@"
}

# Menu de comandos
show_menu() {
    echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  WorkAdventure - Gerenciamento AWS    ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BLUE}📋 Servidor: ${NC}$SERVER_IP"
    echo -e "${BLUE}🆔 Instance: ${NC}$INSTANCE_ID"
    echo ""
    echo "Comandos disponíveis:"
    echo ""
    echo -e "${YELLOW}📊 LOGS E MONITORAMENTO:${NC}"
    echo "  logs [service]    - Ver logs de todos os serviços ou específico"
    echo "  logs-f [service]  - Ver logs em tempo real (follow)"
    echo "  logs-tail N       - Ver últimas N linhas dos logs"
    echo "  status            - Status de todos os containers"
    echo "  stats             - Uso de CPU/Memória em tempo real"
    echo "  ps                - Lista processos Docker"
    echo ""
    echo -e "${YELLOW}🔧 GERENCIAMENTO:${NC}"
    echo "  restart [service] - Reiniciar serviços (todos ou específico)"
    echo "  stop              - Parar todos os serviços"
    echo "  start             - Iniciar todos os serviços"
    echo "  pull              - Atualizar imagens Docker"
    echo "  recreate          - Recriar containers (down + up)"
    echo ""
    echo -e "${YELLOW}💻 ACESSO:${NC}"
    echo "  ssh               - Conectar via SSH no servidor"
    echo "  shell <service>   - Abrir shell dentro de um container"
    echo "  exec <service> <cmd> - Executar comando em container"
    echo ""
    echo -e "${YELLOW}📁 ARQUIVOS:${NC}"
    echo "  env               - Ver arquivo .env"
    echo "  env-edit          - Editar .env (nano)"
    echo "  upload <file>     - Enviar arquivo para servidor"
    echo "  download <file>   - Baixar arquivo do servidor"
    echo ""
    echo -e "${YELLOW}🔍 DIAGNÓSTICO:${NC}"
    echo "  health            - Verificar saúde dos serviços"
    echo "  disk              - Ver uso de disco"
    echo "  network           - Informações de rede"
    echo ""
    echo -e "${YELLOW}☁️ AWS:${NC}"
    echo "  aws-stop          - Parar instância EC2 (economizar)"
    echo "  aws-start         - Iniciar instância EC2"
    echo "  aws-reboot        - Reiniciar instância EC2"
    echo "  aws-info          - Informações da instância"
    echo ""
    echo "Uso: $0 <comando> [argumentos]"
}

# Processar comando
case "$1" in
    # LOGS E MONITORAMENTO
    logs)
        echo -e "${YELLOW}📊 Logs do WorkAdventure${NC}"
        if [ -z "$2" ]; then
            docker_cmd "logs --tail=100"
        else
            docker_cmd "logs --tail=100 $2"
        fi
        ;;

    logs-f)
        echo -e "${YELLOW}📊 Logs em tempo real (Ctrl+C para sair)${NC}"
        if [ -z "$2" ]; then
            docker_cmd "logs -f"
        else
            docker_cmd "logs -f $2"
        fi
        ;;

    logs-tail)
        N=${2:-50}
        echo -e "${YELLOW}📊 Últimas $N linhas dos logs${NC}"
        docker_cmd "logs --tail=$N"
        ;;

    status)
        echo -e "${YELLOW}📊 Status dos containers${NC}"
        docker_cmd "ps"
        ;;

    stats)
        echo -e "${YELLOW}📊 Uso de recursos (Ctrl+C para sair)${NC}"
        remote_cmd "docker stats"
        ;;

    ps)
        echo -e "${YELLOW}📊 Processos Docker${NC}"
        docker_cmd "ps -a"
        ;;

    # GERENCIAMENTO
    restart)
        if [ -z "$2" ]; then
            echo -e "${YELLOW}🔄 Reiniciando todos os serviços...${NC}"
            docker_cmd "restart"
        else
            echo -e "${YELLOW}🔄 Reiniciando $2...${NC}"
            docker_cmd "restart $2"
        fi
        echo -e "${GREEN}✅ Reiniciado${NC}"
        ;;

    stop)
        echo -e "${YELLOW}⏸️  Parando serviços...${NC}"
        docker_cmd "stop"
        echo -e "${GREEN}✅ Serviços parados${NC}"
        ;;

    start)
        echo -e "${YELLOW}▶️  Iniciando serviços...${NC}"
        docker_cmd "start"
        echo -e "${GREEN}✅ Serviços iniciados${NC}"
        ;;

    pull)
        echo -e "${YELLOW}📥 Atualizando imagens Docker...${NC}"
        docker_cmd "-f docker-compose.yaml -f docker-compose.keycloak-simple.yaml -f docker-compose-no-oidc.yaml -f docker-compose.no-synapse.yaml pull"
        echo -e "${GREEN}✅ Imagens atualizadas${NC}"
        ;;

    recreate)
        echo -e "${YELLOW}♻️  Recriando containers...${NC}"
        docker_cmd "-f docker-compose.yaml -f docker-compose.keycloak-simple.yaml -f docker-compose-no-oidc.yaml -f docker-compose.no-synapse.yaml down"
        docker_cmd "-f docker-compose.yaml -f docker-compose.keycloak-simple.yaml -f docker-compose-no-oidc.yaml -f docker-compose.no-synapse.yaml up -d"
        echo -e "${GREEN}✅ Containers recriados${NC}"
        ;;

    # ACESSO
    ssh)
        echo -e "${YELLOW}🔌 Conectando via SSH...${NC}"
        ssh -i $KEY_FILE ubuntu@$SERVER_IP
        ;;

    shell)
        if [ -z "$2" ]; then
            echo -e "${RED}❌ Especifique o serviço: $0 shell <play|back|keycloak|...>${NC}"
            exit 1
        fi
        echo -e "${YELLOW}💻 Abrindo shell em $2...${NC}"
        docker_cmd "exec -it $2 /bin/sh"
        ;;

    exec)
        if [ -z "$2" ] || [ -z "$3" ]; then
            echo -e "${RED}❌ Uso: $0 exec <service> <command>${NC}"
            exit 1
        fi
        SERVICE=$2
        shift 2
        docker_cmd "exec $SERVICE $@"
        ;;

    # ARQUIVOS
    env)
        echo -e "${YELLOW}📄 Arquivo .env${NC}"
        remote_cmd "cd $PROJECT_DIR && cat .env"
        ;;

    env-edit)
        echo -e "${YELLOW}✏️  Editando .env (nano)${NC}"
        ssh -i $KEY_FILE -t ubuntu@$SERVER_IP "cd $PROJECT_DIR && nano .env"
        echo -e "${YELLOW}💡 Reinicie os serviços para aplicar: $0 restart${NC}"
        ;;

    upload)
        if [ -z "$2" ]; then
            echo -e "${RED}❌ Uso: $0 upload <arquivo>${NC}"
            exit 1
        fi
        echo -e "${YELLOW}📤 Enviando $2...${NC}"
        scp -i $KEY_FILE "$2" ubuntu@$SERVER_IP:$PROJECT_DIR/
        echo -e "${GREEN}✅ Arquivo enviado${NC}"
        ;;

    download)
        if [ -z "$2" ]; then
            echo -e "${RED}❌ Uso: $0 download <arquivo>${NC}"
            exit 1
        fi
        echo -e "${YELLOW}📥 Baixando $2...${NC}"
        scp -i $KEY_FILE ubuntu@$SERVER_IP:$PROJECT_DIR/"$2" .
        echo -e "${GREEN}✅ Arquivo baixado${NC}"
        ;;

    # DIAGNÓSTICO
    health)
        echo -e "${YELLOW}🏥 Verificando saúde dos serviços${NC}"
        echo ""
        echo "=== Containers ==="
        docker_cmd "ps --format 'table {{.Names}}\t{{.Status}}'"
        echo ""
        echo "=== Disco ==="
        remote_cmd "df -h / | tail -1"
        echo ""
        echo "=== Memória ==="
        remote_cmd "free -h | grep Mem"
        echo ""
        echo "=== URLs ==="
        echo "WorkAdventure: http://$SERVER_IP/"
        echo "Keycloak: http://$SERVER_IP/keycloak/admin"
        ;;

    disk)
        echo -e "${YELLOW}💾 Uso de disco${NC}"
        remote_cmd "df -h"
        echo ""
        echo "=== Docker ==="
        remote_cmd "docker system df"
        ;;

    network)
        echo -e "${YELLOW}🌐 Informações de rede${NC}"
        echo "IP Público: $SERVER_IP"
        echo ""
        remote_cmd "ip addr show | grep 'inet '"
        ;;

    # AWS
    aws-stop)
        echo -e "${YELLOW}⏸️  Parando instância EC2...${NC}"
        aws ec2 stop-instances --instance-ids $INSTANCE_ID --region $REGION
        echo -e "${GREEN}✅ Instância parando (economizando custos)${NC}"
        ;;

    aws-start)
        echo -e "${YELLOW}▶️  Iniciando instância EC2...${NC}"
        aws ec2 start-instances --instance-ids $INSTANCE_ID --region $REGION
        echo -e "${YELLOW}⏳ Aguardando...${NC}"
        aws ec2 wait instance-running --instance-ids $INSTANCE_ID --region $REGION
        NEW_IP=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --region $REGION --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
        echo -e "${GREEN}✅ Instância iniciada${NC}"
        echo -e "${YELLOW}💡 Novo IP: $NEW_IP${NC}"
        echo "   Atualize deployment-info.txt se necessário"
        ;;

    aws-reboot)
        echo -e "${YELLOW}🔄 Reiniciando instância EC2...${NC}"
        aws ec2 reboot-instances --instance-ids $INSTANCE_ID --region $REGION
        echo -e "${GREEN}✅ Instância reiniciando${NC}"
        ;;

    aws-info)
        echo -e "${YELLOW}☁️  Informações da instância${NC}"
        aws ec2 describe-instances --instance-ids $INSTANCE_ID --region $REGION \
          --query 'Reservations[0].Instances[0].{ID:InstanceId,Type:InstanceType,State:State.Name,IP:PublicIpAddress}' \
          --output table
        ;;

    # HELP
    help|"")
        show_menu
        ;;

    *)
        echo -e "${RED}❌ Comando desconhecido: $1${NC}"
        echo ""
        show_menu
        exit 1
        ;;
esac
