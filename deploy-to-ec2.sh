#!/bin/bash
set -e

# ========================================
# Deploy WorkAdventure EC2 - Versão Correta
# Usa exatamente o que funciona localmente
# ========================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [ -z "$1" ]; then
    echo -e "${RED}Uso: $0 <IP_EC2>${NC}"
    exit 1
fi

SERVER_IP=$1
KEY_FILE="workadventure-key.pem"

# Hosts com nip.io
PLAY_HOST="play.${SERVER_IP}.nip.io"
MAPS_HOST="maps.${SERVER_IP}.nip.io"

echo -e "${GREEN}🚀 Deploy WorkAdventure${NC}"
echo "   IP: $SERVER_IP"
echo "   Play: http://$PLAY_HOST"
echo ""

# Validar conexão
echo -e "${YELLOW}[1/5] Validando conexão SSH...${NC}"
if ! ssh -i $KEY_FILE -o ConnectTimeout=10 -o StrictHostKeyChecking=no ubuntu@$SERVER_IP "echo OK" &>/dev/null; then
    echo -e "${RED}❌ Falha na conexão${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Conectado${NC}"

# Verificar Docker
echo -e "${YELLOW}[2/5] Verificando Docker...${NC}"
if ! ssh -i $KEY_FILE ubuntu@$SERVER_IP "docker --version" &>/dev/null; then
    echo -e "${RED}❌ Docker não instalado${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Docker OK${NC}"

# Clonar projeto
echo -e "${YELLOW}[3/5] Clonando projeto...${NC}"
ssh -i $KEY_FILE ubuntu@$SERVER_IP <<EOFCLONE
set -e
if [ ! -d "/home/ubuntu/workadventure/.git" ]; then
    echo "  📥 Clonando repositório..."
    git clone --depth 1 https://github.com/LucasAmorimLima/workadventure-project.git /home/ubuntu/workadventure
else
    echo "  📋 Repositório já existe"
fi
cd /home/ubuntu/workadventure
git pull origin master || true
EOFCLONE
echo -e "${GREEN}✅ Projeto clonado${NC}"

# Copiar configurações customizadas (maps e keycloak-realm)
echo -e "${YELLOW}[4/5] Enviando configurações customizadas...${NC}"
tar czf /tmp/custom-config.tar.gz maps/ keycloak-realm-import.json
scp -i $KEY_FILE /tmp/custom-config.tar.gz ubuntu@$SERVER_IP:/tmp/
ssh -i $KEY_FILE ubuntu@$SERVER_IP "cd /home/ubuntu/workadventure && tar xzf /tmp/custom-config.tar.gz"
echo -e "${GREEN}✅ Configurações enviadas${NC}"

# Configurar .env com nip.io
echo -e "${YELLOW}[5/5] Configurando ambiente...${NC}"
ssh -i $KEY_FILE ubuntu@$SERVER_IP <<EOFENV
set -e
cd /home/ubuntu/workadventure

# Criar .env baseado no template local mas com nip.io
cat > .env <<EOL
# URLs com nip.io
PUSHER_URL=http://$PLAY_HOST
ADMIN_URL=http://$PLAY_HOST/admin

# Keycloak
KEYCLOAK_ADMIN=admin
KEYCLOAK_ADMIN_PASSWORD=$(openssl rand -base64 32)
KEYCLOAK_DB_PASSWORD=$(openssl rand -base64 32)
OPENID_CLIENT_ID=workadventure
OPENID_CLIENT_SECRET=$(openssl rand -base64 32)
OPENID_CLIENT_ISSUER=http://$PLAY_HOST/keycloak/realms/workadventure
OPENID_LOGOUT_REDIRECT_URL=http://$PLAY_HOST/keycloak/realms/workadventure/protocol/openid-connect/logout
KC_HOSTNAME_URL=http://$PLAY_HOST/keycloak
KC_HOSTNAME_ADMIN_URL=http://$PLAY_HOST/keycloak

# Configurações
DISABLE_ANONYMOUS=true
ENABLE_CHAT=false
START_ROOM_URL=/_/global/$MAPS_HOST/starter-kit/office.tmj
MAP_STORAGE_URL=map-storage:50053
EOL

# Atualizar keycloak-realm-import.json com URLs corretas
OPENID_SECRET=\$(grep OPENID_CLIENT_SECRET .env | cut -d'=' -f2)
sed -i "s|\"secret\": \"[^\"]*\"|\"secret\": \"\$OPENID_SECRET\"|" keycloak-realm-import.json
sed -i "s|play.workadventure.localhost|$PLAY_HOST|g" keycloak-realm-import.json
sed -i "s|*.workadventure.localhost|*.$PLAY_HOST|g" keycloak-realm-import.json
sed -i "s|localhost:3000|$PLAY_HOST|g" keycloak-realm-import.json

echo "✅ Ambiente configurado"
EOFENV
echo -e "${GREEN}✅ Configuração completa${NC}"

# Parar containers antigos
echo -e "${YELLOW}🛑 Parando containers antigos...${NC}"
ssh -i $KEY_FILE ubuntu@$SERVER_IP "cd /home/ubuntu/workadventure && docker compose down 2>/dev/null || true"

# Subir serviços - MESMA CONFIGURAÇÃO QUE LOCAL
echo -e "${YELLOW}🚀 Iniciando serviços...${NC}"
ssh -i $KEY_FILE ubuntu@$SERVER_IP <<EOFSTART
set -e
cd /home/ubuntu/workadventure

echo "  📦 Subindo containers..."
docker compose \\
  -f docker-compose.yaml \\
  -f docker-compose.keycloak-simple.yaml \\
  -f docker-compose-no-oidc.yaml \\
  -f docker-compose.no-synapse.yaml \\
  up -d

echo "  ⏳ Aguardando serviços (30s)..."
sleep 30

echo "  📊 Status:"
docker compose ps
EOFSTART

# Obter credenciais
ADMIN_PASS=$(ssh -i $KEY_FILE ubuntu@$SERVER_IP "grep KEYCLOAK_ADMIN_PASSWORD /home/ubuntu/workadventure/.env | cut -d'=' -f2")
CLIENT_SECRET=$(ssh -i $KEY_FILE ubuntu@$SERVER_IP "grep OPENID_CLIENT_SECRET /home/ubuntu/workadventure/.env | cut -d'=' -f2")

echo ""
echo -e "${GREEN}🎉 ========================================${NC}"
echo -e "${GREEN}   Deploy Concluído!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "🌐 URLs:"
echo "   WorkAdventure: http://$PLAY_HOST/"
echo "   Keycloak Admin: http://$PLAY_HOST/keycloak/admin"
echo ""
echo "🔑 Credenciais:"
echo "   Admin: admin / $ADMIN_PASS"
echo "   Client Secret: $CLIENT_SECRET"
echo "   Teste: teste / teste123"
echo ""
echo "📝 Gerenciar:"
echo "   ssh -i $KEY_FILE ubuntu@$SERVER_IP"
echo "   ./manage-aws.sh logs"
echo "   ./manage-aws.sh restart"
echo ""
echo -e "${YELLOW}💡 Aguarde ~2 minutos para npm install completar nos containers${NC}"

# Salvar info
cat > deployment-info.txt <<EOFINFO
WorkAdventure Deploy
====================
IP: $SERVER_IP
Play: http://$PLAY_HOST/
Keycloak: http://$PLAY_HOST/keycloak/admin

Credenciais:
  Admin: admin / $ADMIN_PASS
  Secret: $CLIENT_SECRET
  Teste: teste / teste123

SSH: ssh -i $KEY_FILE ubuntu@$SERVER_IP
Dir: /home/ubuntu/workadventure
EOFINFO
