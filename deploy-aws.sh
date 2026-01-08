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
INSTANCE_TYPE="${INSTANCE_TYPE:-t3.medium}"  # 2 vCPU, 4GB RAM
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

# User data script para instalação automática
USER_DATA=$(cat <<'EOF'
#!/bin/bash
set -e

# Log
exec > >(tee /var/log/workadventure-setup.log)
exec 2>&1

echo "🚀 Iniciando setup WorkAdventure..."

# Atualizar sistema
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

# Instalar Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
systemctl enable docker
systemctl start docker

# Adicionar usuário ubuntu ao grupo docker
usermod -aG docker ubuntu

# Instalar Docker Compose
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Criar diretório do projeto
mkdir -p /opt/workadventure
cd /opt/workadventure

# Criar flag de conclusão
touch /var/log/workadventure-ready

echo "✅ Setup básico concluído!"
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
echo "   1. Aguarde ~2 minutos para o setup automático concluir"
echo "   2. Execute: ./deploy-project.sh $PUBLIC_IP"
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

Comandos úteis:
---------------
# Conectar SSH
ssh -i ${KEY_NAME}.pem ubuntu@${PUBLIC_IP}

# Ver logs de setup
ssh -i ${KEY_NAME}.pem ubuntu@${PUBLIC_IP} "tail -f /var/log/workadventure-setup.log"

# Parar instância
aws ec2 stop-instances --instance-ids $INSTANCE_ID --region $REGION

# Iniciar instância
aws ec2 start-instances --instance-ids $INSTANCE_ID --region $REGION

# Terminar instância
aws ec2 terminate-instances --instance-ids $INSTANCE_ID --region $REGION
EOL

echo -e "${YELLOW}💡 Aguardando setup automático (2 min)...${NC}"
sleep 120

echo ""
echo -e "${GREEN}✅ Pronto! Agora execute:${NC}"
echo -e "${YELLOW}   ./deploy-project.sh $PUBLIC_IP${NC}"
