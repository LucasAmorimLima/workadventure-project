#!/bin/bash
set -e

# ========================================
# Script de Deploy WorkAdventure na AWS EC2
# ========================================

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}🚀 WorkAdventure - Deploy AWS EC2${NC}"
echo ""

# Configurações
INSTANCE_NAME="${INSTANCE_NAME:-workadventure-prod}"
INSTANCE_TYPE="${INSTANCE_TYPE:-t3.large}"  # 2 vCPU, 8GB RAM
REGION="${AWS_REGION:-us-east-1}"
KEY_NAME="${KEY_NAME:-workadventure-key}"
SECURITY_GROUP_NAME="${SECURITY_GROUP_NAME:-workadventure-sg}"
DOMAIN="${DOMAIN:-}"  # Opcional: seu domínio

echo -e "${YELLOW}📋 Configurações:${NC}"
echo "  Instance: $INSTANCE_NAME"
echo "  Type: $INSTANCE_TYPE"
echo "  Region: $REGION"
echo "  Key: $KEY_NAME"
echo ""

# Verificar se já existe instância rodando
echo -e "${YELLOW}🔍 Verificando instâncias existentes...${NC}"
EXISTING_INSTANCE=$(aws ec2 describe-instances \
  --region $REGION \
  --filters "Name=tag:Name,Values=$INSTANCE_NAME" "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].InstanceId" \
  --output text 2>/dev/null || echo "None")

if [ "$EXISTING_INSTANCE" != "None" ] && [ "$EXISTING_INSTANCE" != "" ]; then
    echo -e "${RED}❌ Instância já existe: $EXISTING_INSTANCE${NC}"
    echo "   Use: aws ec2 terminate-instances --instance-ids $EXISTING_INSTANCE --region $REGION"
    exit 1
fi

# Criar Key Pair se não existir
echo -e "${YELLOW}🔑 Verificando chave SSH...${NC}"
if ! aws ec2 describe-key-pairs --key-names $KEY_NAME --region $REGION &>/dev/null; then
    echo "   Criando chave SSH..."
    aws ec2 create-key-pair \
      --key-name $KEY_NAME \
      --region $REGION \
      --query 'KeyMaterial' \
      --output text > ${KEY_NAME}.pem
    chmod 400 ${KEY_NAME}.pem
    echo -e "${GREEN}   ✅ Chave criada: ${KEY_NAME}.pem${NC}"
else
    echo "   ✅ Chave já existe"
    if [ ! -f "${KEY_NAME}.pem" ]; then
        echo -e "${RED}   ⚠️  Arquivo ${KEY_NAME}.pem não encontrado localmente${NC}"
        echo "   Certifique-se de ter o arquivo .pem para conectar via SSH"
    fi
fi

# Criar Security Group
echo -e "${YELLOW}🔒 Configurando Security Group...${NC}"
VPC_ID=$(aws ec2 describe-vpcs --region $REGION --filters "Name=isDefault,Values=true" --query "Vpcs[0].VpcId" --output text)

if ! aws ec2 describe-security-groups --group-names $SECURITY_GROUP_NAME --region $REGION &>/dev/null; then
    echo "   Criando Security Group..."
    SG_ID=$(aws ec2 create-security-group \
      --group-name $SECURITY_GROUP_NAME \
      --description "WorkAdventure Security Group" \
      --vpc-id $VPC_ID \
      --region $REGION \
      --query 'GroupId' \
      --output text)

    # Adicionar regras
    aws ec2 authorize-security-group-ingress --group-id $SG_ID --region $REGION \
      --ip-permissions \
        IpProtocol=tcp,FromPort=22,ToPort=22,IpRanges='[{CidrIp=0.0.0.0/0,Description="SSH"}]' \
        IpProtocol=tcp,FromPort=80,ToPort=80,IpRanges='[{CidrIp=0.0.0.0/0,Description="HTTP"}]' \
        IpProtocol=tcp,FromPort=443,ToPort=443,IpRanges='[{CidrIp=0.0.0.0/0,Description="HTTPS"}]' > /dev/null 2>&1

    echo -e "${GREEN}   ✅ Security Group criado: $SG_ID${NC}"
else
    SG_ID=$(aws ec2 describe-security-groups --group-names $SECURITY_GROUP_NAME --region $REGION --query "SecurityGroups[0].GroupId" --output text)
    echo "   ✅ Security Group já existe: $SG_ID"
fi

# Buscar AMI Ubuntu 24.04 LTS mais recente
echo -e "${YELLOW}🔍 Buscando AMI Ubuntu 24.04 LTS...${NC}"
AMI_ID=$(aws ec2 describe-images \
  --region $REGION \
  --owners 099720109477 \
  --filters "Name=name,Values=ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*" \
  --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
  --output text)
echo "   AMI: $AMI_ID"

USER_DATA=$(cat <<'EOF'
#!/bin/bash
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

echo "🚀 Iniciando deploy WorkAdventure..."

# Instalar dependências
echo "📦 Instalando Docker e Git..."
apt-get update
apt-get install -y git curl

curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
systemctl enable docker
systemctl start docker
usermod -aG docker ubuntu

curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Detectar IP público ANTES do su
echo "🌐 Obtendo IP público..."
PUBLIC_IP=""
for i in {1..10}; do
    TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" -s)
    PUBLIC_IP=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/public-ipv4)
    if [ ! -z "$PUBLIC_IP" ]; then
        break
    fi
    echo "Tentativa $i: aguardando metadata service..."
    sleep 2
done

if [ -z "$PUBLIC_IP" ]; then
    echo "❌ ERRO: Não foi possível obter o IP público!"
    exit 1
fi

echo "✅ IP detectado: $PUBLIC_IP"
PLAY_HOST="play.$PUBLIC_IP.nip.io"
MAPS_HOST="maps.$PUBLIC_IP.nip.io"

# Configurar WorkAdventure
echo "📥 Clonando repositório..."
su - ubuntu -c "
cd /home/ubuntu
git clone --depth 1 https://github.com/LucasAmorimLima/workadventure-project.git workadventure
cd workadventure

echo \"🌐 Configurando com IP: $PUBLIC_IP\"

echo \"⚙️ Criando .env...\"
cat > .env << 'ENVFILE'
# URLs com nip.io
PUSHER_URL=http://$PLAY_HOST
ADMIN_URL=http://$PLAY_HOST/admin
FRONT_HOST=$PLAY_HOST
FRONT_URL=http://$PLAY_HOST
VITE_URL=http://$PLAY_HOST

# Secret Key (obrigatório)
SECRET_KEY=\$(openssl rand -base64 32)

# Keycloak
KEYCLOAK_ADMIN=admin
KEYCLOAK_ADMIN_PASSWORD=\$(openssl rand -base64 32)
KEYCLOAK_DB_PASSWORD=\$(openssl rand -base64 32)
OPENID_CLIENT_ID=workadventure
OPENID_CLIENT_SECRET=\$(openssl rand -base64 32)
OPENID_CLIENT_ISSUER=http://$PLAY_HOST/keycloak/realms/workadventure
OPENID_LOGOUT_REDIRECT_URL=http://$PLAY_HOST/keycloak/realms/workadventure/protocol/openid-connect/logout
KC_HOSTNAME_URL=http://$PLAY_HOST/keycloak
KC_HOSTNAME_ADMIN_URL=http://$PLAY_HOST/keycloak

# Configurações
DISABLE_ANONYMOUS=true
ENABLE_CHAT=false
START_ROOM_URL=/_/global/$MAPS_HOST/starter-kit/office.tmj
MAP_STORAGE_URL=map-storage:50053
ENVFILE
sed -i \"s|\\\$PLAY_HOST|$PLAY_HOST|g\" .env
sed -i \"s|\\\$MAPS_HOST|$MAPS_HOST|g\" .env

echo \"🔐 Atualizando Keycloak realm...\"
OPENID_SECRET=\$(grep OPENID_CLIENT_SECRET .env | cut -d= -f2-)
sed -i \"s|\\\"secret\\\": \\\"[^\\\"]*\\\"|\\\"secret\\\": \\\"\$OPENID_SECRET\\\"|\" keycloak-realm-import.json
sed -i \"s|play.workadventure.localhost|$PLAY_HOST|g\" keycloak-realm-import.json
sed -i \"s|\\*.workadventure.localhost|*.$PLAY_HOST|g\" keycloak-realm-import.json
sed -i \"s|localhost:3000|$PLAY_HOST|g\" keycloak-realm-import.json

echo \"🚀 Iniciando containers...\"
docker compose \\
  -f docker-compose.yaml \\
  -f docker-compose.keycloak-simple.yaml \\
  -f docker-compose-no-oidc.yaml \\
  -f docker-compose.no-synapse.yaml \\
  up -d

echo \"✅ Deploy concluído!\"
echo \"🌐 URL: http://$PLAY_HOST\"
echo \"🔑 Keycloak: http://$PLAY_HOST/keycloak/admin\"
echo \"👤 Usuário teste: teste / teste123\"

# Salvar info
echo \"http://$PLAY_HOST\" > /home/ubuntu/workadventure-url.txt
"

echo "✅ WorkAdventure configurado e rodando!"
EOF
)

# Criar instância EC2
echo -e "${YELLOW}🚀 Criando instância EC2...${NC}"
INSTANCE_ID=$(aws ec2 run-instances \
  --region $REGION \
  --image-id $AMI_ID \
  --instance-type $INSTANCE_TYPE \
  --key-name $KEY_NAME \
  --security-group-ids $SG_ID \
  --user-data "$USER_DATA" \
  --block-device-mappings 'DeviceName=/dev/sda1,Ebs={VolumeSize=30,VolumeType=gp3}' \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]" \
  --query 'Instances[0].InstanceId' \
  --output text)

echo -e "${GREEN}✅ Instância criada: $INSTANCE_ID${NC}"

# Aguardar instância ficar running
echo -e "${YELLOW}⏳ Aguardando instância iniciar...${NC}"
aws ec2 wait instance-running --instance-ids $INSTANCE_ID --region $REGION 2>&1 | grep -v "^$" || true
echo "   ✅ Instância rodando"

# Obter IP público
PUBLIC_IP=$(aws ec2 describe-instances \
  --instance-ids $INSTANCE_ID \
  --region $REGION \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text)

echo ""
echo -e "${GREEN}🎉 ============================================${NC}"
echo -e "${GREEN}   Instância EC2 criada com sucesso!${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo "📋 Informações:"
echo "   Instance ID: $INSTANCE_ID"
echo "   IP Público: $PUBLIC_IP"
echo "   Região: $REGION"
echo "   Tipo: $INSTANCE_TYPE"
echo ""
echo "🔌 Conectar via SSH:"
echo "   ssh -i ${KEY_NAME}.pem ubuntu@${PUBLIC_IP}"
echo ""
echo "📦 Próximos passos:"
echo "   1. Aguarde ~5 minutos para instalação completa"
echo "   2. Acesse: http://play.$PUBLIC_IP.nip.io"
echo "   3. Login: teste / teste123"
echo ""
echo "📝 Arquivo de informações salvo em: deployment-info.txt"

# Salvar informações
cat > deployment-info.txt <<EOL
WorkAdventure - Informações de Deploy
=====================================

Instance ID: $INSTANCE_ID
IP Público: $PUBLIC_IP
Região: $REGION
Chave SSH: ${KEY_NAME}.pem
Security Group: $SG_ID

URLs:
-----
Play: http://play.$PUBLIC_IP.nip.io
Keycloak Admin: http://play.$PUBLIC_IP.nip.io/keycloak/admin
Maps: http://maps.$PUBLIC_IP.nip.io

Login Teste:
  Usuário: teste
  Senha: teste123

Comandos úteis:
---------------
# Conectar SSH
ssh -i ${KEY_NAME}.pem ubuntu@${PUBLIC_IP}

# Ver logs de deploy
ssh -i ${KEY_NAME}.pem ubuntu@${PUBLIC_IP} "tail -f /var/log/user-data.log"

# Ver containers
ssh -i ${KEY_NAME}.pem ubuntu@${PUBLIC_IP} "cd workadventure && docker compose ps"

# Ver logs de containers
ssh -i ${KEY_NAME}.pem ubuntu@${PUBLIC_IP} "cd workadventure && docker compose logs -f"

# Parar instância
aws ec2 stop-instances --instance-ids $INSTANCE_ID --region $REGION

# Iniciar instância
aws ec2 start-instances --instance-ids $INSTANCE_ID --region $REGION

# Terminar instância
aws ec2 terminate-instances --instance-ids $INSTANCE_ID --region $REGION
EOL

echo -e "${YELLOW}💡 Deploy automático em andamento...${NC}"
echo -e "${YELLOW}⏳ Tempo estimado: 5-10 minutos${NC}"

echo ""
echo -e "${GREEN}✅ Instância criada! Aguarde a instalação completar.${NC}"
echo -e "${YELLOW}   Acompanhe: ssh -i ${KEY_NAME}.pem ubuntu@${PUBLIC_IP} 'tail -f /var/log/user-data.log'${NC}"
