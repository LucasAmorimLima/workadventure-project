#!/bin/bash
set -e

echo "🚀 Deploy WorkAdventure AWS - Produção"
echo "========================================="

# Configuração
INSTANCE_TYPE="t3.large"
AMI_ID="ami-0e2c8caa4b6378d8c"  # Ubuntu 24.04 LTS us-east-1
KEY_NAME="workadventure-key"
SECURITY_GROUP="workadventure-sg"

echo "📋 Criando Security Group..."
aws ec2 describe-security-groups --group-names $SECURITY_GROUP 2>/dev/null || \
aws ec2 create-security-group \
  --group-name $SECURITY_GROUP \
  --description "WorkAdventure security group" \
  --output text

SG_ID=$(aws ec2 describe-security-groups --group-names $SECURITY_GROUP --query 'SecurityGroups[0].GroupId' --output text)

echo "🔓 Configurando regras de firewall..."
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 22 --cidr 0.0.0.0/0 2>/dev/null || true
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 80 --cidr 0.0.0.0/0 2>/dev/null || true
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 443 --cidr 0.0.0.0/0 2>/dev/null || true

echo "🔑 Verificando chave SSH..."
if [ ! -f "$KEY_NAME.pem" ]; then
  echo "Criando par de chaves..."
  aws ec2 create-key-pair --key-name $KEY_NAME --query 'KeyMaterial' --output text > $KEY_NAME.pem
  chmod 400 $KEY_NAME.pem
fi

echo "🖥️  Criando instância EC2..."
INSTANCE_ID=$(aws ec2 run-instances \
  --image-id $AMI_ID \
  --instance-type $INSTANCE_TYPE \
  --key-name $KEY_NAME \
  --security-group-ids $SG_ID \
  --block-device-mappings 'DeviceName=/dev/sda1,Ebs={VolumeSize=30,VolumeType=gp3}' \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=WorkAdventure-Prod}]' \
  --user-data file://- << 'USERDATA' \
  --query 'Instances[0].InstanceId' \
  --output text << 'EOF'
#!/bin/bash
set -e
exec > >(tee /var/log/user-data.log)
exec 2>&1

echo "🔧 Instalando dependências..."
apt-get update
apt-get install -y docker.io docker-compose git curl

systemctl start docker
systemctl enable docker
usermod -aG docker ubuntu

echo "📦 Clonando repositório..."
cd /home/ubuntu
sudo -u ubuntu git clone https://github.com/LucasAmorimLima/workadventure-project.git workadventure
cd workadventure

echo "🔍 Detectando IP público (IMDSv2)..."
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" 2>/dev/null)
PUBLIC_IP=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null)
PLAY_HOST="play.$PUBLIC_IP.nip.io"
MAPS_HOST="maps.$PUBLIC_IP.nip.io"

echo "📝 Criando .env..."
cat > .env << ENVFILE
# URLs públicas
PUSHER_URL=http://$PLAY_HOST
ADMIN_URL=http://$PLAY_HOST/admin
FRONT_HOST=$PLAY_HOST
FRONT_URL=http://$PLAY_HOST
VITE_URL=http://$PLAY_HOST
MAPS_HOST=$MAPS_HOST

# Segurança
SECRET_KEY=$(openssl rand -base64 32)
MAP_STORAGE_API_TOKEN=$(openssl rand -base64 32)

# Keycloak
KEYCLOAK_ADMIN=admin
KEYCLOAK_ADMIN_PASSWORD=$(openssl rand -base64 32)
KEYCLOAK_DB_PASSWORD=$(openssl rand -base64 32)

# OpenID Connect
OPENID_CLIENT_ID=workadventure
OPENID_CLIENT_SECRET=$(openssl rand -base64 32)
OPENID_CLIENT_ISSUER=http://$PLAY_HOST/keycloak/realms/workadventure
OPENID_CLIENT_ISSUER_INTERNAL=http://$PLAY_HOST/keycloak/realms/workadventure
OPENID_LOGOUT_REDIRECT_URL=http://$PLAY_HOST/keycloak/realms/workadventure/protocol/openid-connect/logout
KC_HOSTNAME_URL=http://$PLAY_HOST/keycloak
KC_HOSTNAME_ADMIN_URL=http://$PLAY_HOST/keycloak

# Configuração
DISABLE_ANONYMOUS=false
ENABLE_CHAT=false
START_ROOM_URL=/_/global/$MAPS_HOST/starter-kit/office.tmj
MAP_STORAGE_URL=map-storage:50053
PUBLIC_MAP_STORAGE_URL=http://map-storage.$PUBLIC_IP.nip.io
ICON_URL=/icon
ALLOWED_CORS_ORIGIN=*

# Desempenho
DEBUG_MODE=false
DISABLE_NOTIFICATIONS=true
SKIP_RENDER_OPTIMIZATIONS=false
MAX_PER_GROUP=4
MAX_USERNAME_LENGTH=10
ENVFILE

echo "🔐 Atualizando Keycloak realm..."
OPENID_SECRET=$(grep OPENID_CLIENT_SECRET .env | cut -d= -f2-)
sed -i "s|\"secret\": \"[^\"]*\"|\"secret\": \"$OPENID_SECRET\"|" keycloak-realm-import.json
sed -i "s|play.workadventure.localhost|$PLAY_HOST|g" keycloak-realm-import.json
sed -i "s|\\*.workadventure.localhost|*.$PLAY_HOST|g" keycloak-realm-import.json

echo "🚀 Iniciando containers (PRODUÇÃO)..."
docker compose \
  -f docker-compose.prod-simple.yaml \
  -f docker-compose.keycloak-simple.yaml \
  -f docker-compose.yaml \
  -f docker-compose.no-synapse.yaml \
  up -d

echo "✅ Deploy concluído!"
echo "🌐 URL: http://$PLAY_HOST"
echo "🔑 Keycloak: http://$PLAY_HOST/keycloak/admin"
echo "👤 Usuário teste: teste / teste123"
echo "http://$PLAY_HOST" > /home/ubuntu/workadventure-url.txt
EOF
)

echo "⏳ Aguardando instância iniciar..."
aws ec2 wait instance-running --instance-ids $INSTANCE_ID

PUBLIC_IP=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)

echo ""
echo "✅ Instância criada!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📍 Instance ID: $INSTANCE_ID"
echo "🌐 IP Público: $PUBLIC_IP"
echo "🔗 URL: http://play.$PUBLIC_IP.nip.io"
echo "🔑 Keycloak: http://play.$PUBLIC_IP.nip.io/keycloak/admin"
echo "👤 Login teste: teste / teste123"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "⏳ Aguarde 5-10 minutos para a instalação completar"
echo "📊 Acompanhe: ssh -i $KEY_NAME.pem ubuntu@$PUBLIC_IP 'tail -f /var/log/user-data.log'"
