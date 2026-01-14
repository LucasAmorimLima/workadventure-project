#!/bin/bash


AWS_REGION="us-east-1"
INSTANCE_TYPE="t3.large"
AMI_ID="ami-0e2c8caa4b6378d8c"
KEY_NAME="workadventure-key"
SECURITY_GROUP_NAME="workadventure-sg"

# ===== CONFIGURAÇÃO DO DOMÍNIO =====
# Altere aqui para seu domínio
DOMAIN="${DOMAIN:-teste.xyz.br}"
ACME_EMAIL="${ACME_EMAIL:-admin@${DOMAIN}}"
START_ROOM_URL="${START_ROOM_URL:-/_/global/maps.${DOMAIN}/starter-kit/office.tmj}"

echo "🚀 Starting WorkAdventure Production Deployment on AWS"
echo "=================================================="
echo "Domain: $DOMAIN"
echo "Email: $ACME_EMAIL"
echo "Start Room: $START_ROOM_URL"
echo ""

# Check if key pair exists
if aws ec2 describe-key-pairs --key-names "$KEY_NAME" --region "$AWS_REGION" &>/dev/null; then
    echo "✅ Key pair already exists: $KEY_NAME"
else
    echo "🔑 Creating key pair..."
    aws ec2 create-key-pair \
        --key-name "$KEY_NAME" \
        --region "$AWS_REGION" \
        --query 'KeyMaterial' \
        --output text > "${KEY_NAME}.pem"
    chmod 400 "${KEY_NAME}.pem"
    echo "✅ Key pair created and saved to ${KEY_NAME}.pem"
fi

# Create security group
echo "🔒 Creating security group..."
SECURITY_GROUP_ID=$(aws ec2 create-security-group \
    --group-name "$SECURITY_GROUP_NAME" \
    --description "WorkAdventure security group" \
    --region "$AWS_REGION" \
    --output text 2>/dev/null || \
    aws ec2 describe-security-groups \
    --group-names "$SECURITY_GROUP_NAME" \
    --region "$AWS_REGION" \
    --query 'SecurityGroups[0].GroupId' \
    --output text)


aws ec2 authorize-security-group-ingress --group-id "$SECURITY_GROUP_ID" --protocol tcp --port 22 --cidr 0.0.0.0/0 --region "$AWS_REGION" 2>/dev/null || true
aws ec2 authorize-security-group-ingress --group-id "$SECURITY_GROUP_ID" --protocol tcp --port 80 --cidr 0.0.0.0/0 --region "$AWS_REGION" 2>/dev/null || true
aws ec2 authorize-security-group-ingress --group-id "$SECURITY_GROUP_ID" --protocol tcp --port 443 --cidr 0.0.0.0/0 --region "$AWS_REGION" 2>/dev/null || true

echo "✅ Security group created: $SECURITY_GROUP_ID"


echo "📝 Creating user-data script..."
cat > user-data.sh << USERDATA_EOF
#!/bin/bash
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

echo "📦 Instalando dependências..."
apt-get update
apt-get install -y git curl docker.io docker-compose-v2 openssl postgresql-client

systemctl start docker
systemctl enable docker
usermod -aG docker ubuntu

echo "⏳ Aguardando Docker..."
sleep 5

echo "🚀 Deploy WorkAdventure com customizações..."
cd /home/ubuntu
mkdir workadventure
cd workadventure

# Baixar docker-compose oficial
echo "📥 Baixando docker-compose.prod.yaml oficial..."
curl -O https://raw.githubusercontent.com/thecodingmachine/workadventure/develop/contrib/docker/docker-compose.prod.yaml

# Baixar template oficial
echo "📥 Baixando .env.prod.template oficial..."
curl -O https://raw.githubusercontent.com/thecodingmachine/workadventure/develop/contrib/docker/.env.prod.template

# Baixar CUSTOMIZAÇÕES do seu repositório
echo "📥 Baixando customizações (Keycloak + Mapas)..."
curl -o docker-compose.keycloak-simple.yaml https://raw.githubusercontent.com/LucasAmorimLima/workadventure-project/master/docker-compose.keycloak-simple.yaml
curl -o keycloak-realm-import.json https://raw.githubusercontent.com/LucasAmorimLima/workadventure-project/master/keycloak-realm-import.json

# Baixar mapas completos com tilesets do repositório oficial
echo "📥 Baixando mapas starter-kit do WorkAdventure (repositório oficial)..."

# Mapa starter-kit (escritório completo com várias salas)
mkdir -p maps/starter-kit/tilesets
cd maps/starter-kit

# Baixar mapas TMJ do repositório oficial
curl -sfLO "https://raw.githubusercontent.com/workadventure/map-starter-kit/master/office.tmj"
curl -sfLO "https://raw.githubusercontent.com/workadventure/map-starter-kit/master/meeting-room.tmj"

# Baixar TODOS os tilesets necessários do repositório oficial
cd tilesets
echo "📥 Baixando tilesets..."
curl -sfLO "https://raw.githubusercontent.com/workadventure/map-starter-kit/master/tilesets/WA_Decoration.png"
curl -sfLO "https://raw.githubusercontent.com/workadventure/map-starter-kit/master/tilesets/WA_Exterior.png"
curl -sfLO "https://raw.githubusercontent.com/workadventure/map-starter-kit/master/tilesets/WA_Logo_Long.png"
curl -sfLO "https://raw.githubusercontent.com/workadventure/map-starter-kit/master/tilesets/WA_Miscellaneous.png"
curl -sfLO "https://raw.githubusercontent.com/workadventure/map-starter-kit/master/tilesets/WA_Other_Furniture.png"
curl -sfLO "https://raw.githubusercontent.com/workadventure/map-starter-kit/master/tilesets/WA_Room_Builder.png"
curl -sfLO "https://raw.githubusercontent.com/workadventure/map-starter-kit/master/tilesets/WA_Seats.png"
curl -sfLO "https://raw.githubusercontent.com/workadventure/map-starter-kit/master/tilesets/WA_Special_Zones.png"
curl -sfLO "https://raw.githubusercontent.com/workadventure/map-starter-kit/master/tilesets/WA_Tables.png"
curl -sfLO "https://raw.githubusercontent.com/workadventure/map-starter-kit/master/tilesets/WA_User_Interface.png"
echo "✅ Tilesets baixados!"

cd /home/ubuntu/workadventure

cat > docker-compose.maps.yaml << 'MAPS_EOF'
services:
  maps:
    image: nginx:alpine
    volumes:
      - ./maps:/usr/share/nginx/html:ro
    environment:
      - AUTHENTICATION_USER=admin
      - AUTHENTICATION_PASSWORD=uma_senha_forte
      - NODE_TLS_REJECT_UNAUTHORIZED=0
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.maps.rule=Host(\`maps.${DOMAIN:-maps.workadventure.localhost}\`)"
      - "traefik.http.routers.maps.entryPoints=web"
      - "traefik.http.routers.maps-ssl.rule=Host(\`maps.${DOMAIN:-maps.workadventure.localhost}\`)"
      - "traefik.http.routers.maps-ssl.entryPoints=websecure"
      - "traefik.http.routers.maps-ssl.tls=true"
      - "traefik.http.routers.maps-ssl.tls.certresolver=myresolver"
      - "traefik.http.services.maps.loadbalancer.server.port=80"
      - "traefik.http.middlewares.maps-cors.headers.accesscontrolallowmethods=GET,OPTIONS"
      - "traefik.http.middlewares.maps-cors.headers.accesscontrolalloworiginlist=https://\${DOMAIN:-workadventure.localhost}"
      - "traefik.http.middlewares.maps-cors.headers.accesscontrolmaxage=100"
      - "traefik.http.middlewares.maps-cors.headers.addvaryheader=true"
      - "traefik.http.routers.maps-ssl.middlewares=maps-cors"
MAPS_EOF

# Gerar secrets
SECRET_KEY=\$(openssl rand -base64 32)
ADMIN_TOKEN=\$(openssl rand -base64 32)
JITSI_SECRET=\$(openssl rand -base64 32)
MAP_STORAGE_TOKEN=\$(openssl rand -base64 32)
KEYCLOAK_ADMIN_PASS=\$(openssl rand -base64 16)
KEYCLOAK_DB_PASS=\$(openssl rand -base64 16)
OPENID_SECRET="n8YspAn3RoaJNhNmYmtVl2FeepaoLlgQ"

echo "⚙️ Criando configuração (.env)..."
cp .env.prod.template .env

# Configurar domínio e variáveis básicas
sed -i "s|DOMAIN=.*|DOMAIN=${DOMAIN}|" .env
sed -i "s|START_ROOM_URL=.*|START_ROOM_URL=${START_ROOM_URL}|" .env
sed -i "s|ACME_EMAIL=.*|ACME_EMAIL=${ACME_EMAIL}|" .env
sed -i "s|HTTP_PROTOCOL=http|HTTP_PROTOCOL=https|" .env
sed -i "s|SECRET_KEY=.*|SECRET_KEY=\$SECRET_KEY|" .env
sed -i "s|VERSION=.*|VERSION=master|" .env
sed -i "s|ADMIN_API_TOKEN=.*|ADMIN_API_TOKEN=\$ADMIN_TOKEN|" .env
sed -i "s|SECRET_JITSI_KEY=.*|SECRET_JITSI_KEY=\$JITSI_SECRET|" .env

# Adicionar FRONT_HOST (necessário para evitar erros de DNS)
if ! grep -q "^FRONT_HOST=" .env; then
    echo "FRONT_HOST=${DOMAIN}" >> .env
else
    sed -i "s|FRONT_HOST=.*|FRONT_HOST=${DOMAIN}|" .env
fi

# Desabilitar chat (Matrix não configurado)
sed -i "s|ENABLE_CHAT=true|ENABLE_CHAT=false|" .env

# Configurar limite de pessoas por bolha
sed -i "s|MAX_PER_GROUP=.*|MAX_PER_GROUP=6|" .env
grep -q "^MAX_PER_GROUP=" .env || echo "MAX_PER_GROUP=6" >> .env

# MAP_STORAGE_API_TOKEN
sed -i "s|^MAP_STORAGE_API_TOKEN=.*|MAP_STORAGE_API_TOKEN=\$MAP_STORAGE_TOKEN|" .env
grep -q "^MAP_STORAGE_API_TOKEN=" .env || echo "MAP_STORAGE_API_TOKEN=\$MAP_STORAGE_TOKEN" >> .env

# Configuração Keycloak
sed -i "s|^KEYCLOAK_ADMIN_PASSWORD=.*|KEYCLOAK_ADMIN_PASSWORD=\$KEYCLOAK_ADMIN_PASS|" .env
grep -q "^KEYCLOAK_ADMIN_PASSWORD=" .env || echo "KEYCLOAK_ADMIN_PASSWORD=\$KEYCLOAK_ADMIN_PASS" >> .env
sed -i "s|^KEYCLOAK_DB_PASSWORD=.*|KEYCLOAK_DB_PASSWORD=\$KEYCLOAK_DB_PASS|" .env
grep -q "^KEYCLOAK_DB_PASSWORD=" .env || echo "KEYCLOAK_DB_PASSWORD=\$KEYCLOAK_DB_PASS" >> .env

# URLs HTTPS
sed -i "s|^PLAY_URL=.*|PLAY_URL=https://${DOMAIN}|" .env
grep -q "^PLAY_URL=" .env || echo "PLAY_URL=https://${DOMAIN}" >> .env
sed -i "s|^PUSHER_URL=.*|PUSHER_URL=https://${DOMAIN}/|" .env
grep -q "^PUSHER_URL=" .env || echo "PUSHER_URL=https://${DOMAIN}/" >> .env
sed -i "s|^FRONT_URL=.*|FRONT_URL=https://${DOMAIN}|" .env
grep -q "^FRONT_URL=" .env || echo "FRONT_URL=https://${DOMAIN}" >> .env

# Keycloak hostname URLs HTTPS
sed -i "s|^KC_HOSTNAME_URL=.*|KC_HOSTNAME_URL=https://${DOMAIN}/keycloak|" .env
grep -q "^KC_HOSTNAME_URL=" .env || echo "KC_HOSTNAME_URL=https://${DOMAIN}/keycloak" >> .env
sed -i "s|^KC_HOSTNAME_ADMIN_URL=.*|KC_HOSTNAME_ADMIN_URL=https://${DOMAIN}/keycloak|" .env
grep -q "^KC_HOSTNAME_ADMIN_URL=" .env || echo "KC_HOSTNAME_ADMIN_URL=https://${DOMAIN}/keycloak" >> .env

# OpenID config
sed -i "s|^OPENID_CLIENT_ID=.*|OPENID_CLIENT_ID=workadventure|" .env
sed -i "s|^OPENID_CLIENT_SECRET=.*|OPENID_CLIENT_SECRET=\$OPENID_SECRET|" .env
sed -i "s|^OPENID_CLIENT_ISSUER=.*|OPENID_CLIENT_ISSUER=https://${DOMAIN}/keycloak/realms/workadventure|" .env
sed -i "s|^OPENID_PROFILE_SCREEN_PROVIDER=.*|OPENID_PROFILE_SCREEN_PROVIDER=Keycloak|" .env
sed -i "s|^OPENID_WOKA_NAME_POLICY=.*|OPENID_WOKA_NAME_POLICY=force_opid|" .env
grep -q "^OPENID_WOKA_NAME_POLICY=" .env || echo "OPENID_WOKA_NAME_POLICY=force_opid" >> .env
sed -i "s|^DISABLE_ANONYMOUS=.*|DISABLE_ANONYMOUS=true|" .env
sed -i "s|^OPENID_USERNAME_CLAIM=.*|OPENID_USERNAME_CLAIM=preferred_username|" .env
grep -q "^OPENID_USERNAME_CLAIM=" .env || echo "OPENID_USERNAME_CLAIM=preferred_username" >> .env

# Adicionar NODE_TLS_REJECT_UNAUTHORIZED para evitar erros de SSL
grep -q "^NODE_TLS_REJECT_UNAUTHORIZED=" .env || echo "NODE_TLS_REJECT_UNAUTHORIZED=0" >> .env

# Não precisamos de AUTHENTICATION_STRATEGY - o WorkAdventure detecta automaticamente pelo OPENID_CLIENT_ID

# Atualizar redirect URIs no Keycloak realm
echo "🔧 Configurando Keycloak redirect URIs..."
sed -i "s|http://play.workadventure.localhost|https://${DOMAIN}|g" keycloak-realm-import.json
sed -i "s|http://localhost:3000|https://${DOMAIN}|g" keycloak-realm-import.json
sed -i "s|http://\*.workadventure.localhost|https://${DOMAIN}|g" keycloak-realm-import.json

# Adicionar NODE_TLS_REJECT_UNAUTHORIZED ao serviço play no docker-compose.prod.yaml
echo "🔧 Adicionando NODE_TLS_REJECT_UNAUTHORIZED ao docker-compose..."
if ! grep -q "NODE_TLS_REJECT_UNAUTHORIZED" docker-compose.prod.yaml; then
  sed -i '/- DISABLE_ANONYMOUS/a\      - NODE_TLS_REJECT_UNAUTHORIZED=0' docker-compose.prod.yaml
fi

# IMPORTANTE: Iniciar primeiro apenas os serviços base (sem play) para que o Keycloak possa iniciar e obter certificados
echo "🚀 Iniciando serviços base (reverse-proxy, redis, keycloak)..."
docker compose \
  -f docker-compose.prod.yaml \
  -f docker-compose.keycloak-simple.yaml \
  -f docker-compose.maps.yaml \
  up -d reverse-proxy redis keycloak-db keycloak maps

# Aguardar Keycloak ficar saudável antes de continuar
echo "⏳ Aguardando Keycloak iniciar (pode levar até 5 minutos na primeira vez)..."
for i in {1..60}; do
  if docker exec workadventure-keycloak-1 curl -sf http://localhost:8080/keycloak/health/ready > /dev/null 2>&1; then
    echo "✅ Keycloak está pronto!"
    break
  fi
  echo "   Aguardando Keycloak... (\$i/60)"
  sleep 5
done

# Verificar se o certificado Let's Encrypt foi emitido
echo "⏳ Aguardando certificado SSL ser emitido..."
sleep 30

# Agora iniciar todos os serviços restantes (back, play, map-storage, uploader, icon)
echo "🚀 Iniciando demais serviços (play, back, map-storage)..."
docker compose \
  -f docker-compose.prod.yaml \
  -f docker-compose.keycloak-simple.yaml \
  -f docker-compose.maps.yaml \
  up -d

echo "⏳ Aguardando serviços estabilizarem (60 segundos)..."
sleep 60

# Verificar se o Play consegue conectar ao Keycloak
echo "🔍 Verificando conectividade com Keycloak..."
if curl -sf "https://${DOMAIN}/keycloak/realms/workadventure/.well-known/openid-configuration" > /dev/null 2>&1; then
  echo "✅ Keycloak OIDC endpoint está acessível!"
else
  echo "⚠️ Keycloak OIDC endpoint ainda não está acessível. Reiniciando play..."
  docker compose \
    -f docker-compose.prod.yaml \
    -f docker-compose.keycloak-simple.yaml \
    -f docker-compose.maps.yaml \
    restart play
  sleep 30
fi

# Corrigir redirect_uri no Keycloak database (se necessário)
echo "🔧 Verificando configuração de redirect_uri no Keycloak..."
docker exec workadventure-keycloak-db-1 psql -U keycloak -d keycloak -c "UPDATE redirect_uris SET value = 'https://${DOMAIN}/*' WHERE client_id = (SELECT id FROM client WHERE client_id = 'workadventure') AND value NOT LIKE 'https://%';" 2>/dev/null || echo "⚠️ Aviso: Não foi possível atualizar redirect_uri"

# Atualizar web_origins para CORS
docker exec workadventure-keycloak-db-1 psql -U keycloak -d keycloak -c "UPDATE web_origins SET value = 'https://${DOMAIN}' WHERE client_id = (SELECT id FROM client WHERE client_id = 'workadventure') AND value NOT LIKE 'https://%';" 2>/dev/null || true

echo ""
echo "=========================================="
echo "✅ Deploy concluído com sucesso!"
echo "=========================================="
echo ""
echo "🌐 URL Principal: https://${DOMAIN}"
echo "🗺️  URL dos Mapas: https://maps.${DOMAIN}/starter-kit/"
echo ""
echo "👤 USUÁRIO DE TESTE:"
echo "   Username: teste"
echo "   Password: teste123"
echo ""
echo "🔐 KEYCLOAK ADMIN:"
echo "   URL: https://${DOMAIN}/keycloak"
echo "   Username: admin"
echo "   Password: \$KEYCLOAK_ADMIN_PASS"
echo ""
echo "📝 IMPORTANTE:"
echo "   - DNS deve apontar ${DOMAIN} para este servidor"
echo "   - DNS deve apontar maps.${DOMAIN} para este servidor"
echo "   - Let's Encrypt gerará certificados automaticamente"
echo ""
echo "📋 Verificar logs:"
echo "   docker compose -f docker-compose.prod.yaml -f docker-compose.keycloak-simple.yaml -f docker-compose.maps.yaml logs -f"
echo ""

# Salvar informações
cat > deployment-info.txt << INFO_EOF
WorkAdventure Deployment Information
=====================================
Domain: ${DOMAIN}
Maps Domain: maps.${DOMAIN}
Email: ${ACME_EMAIL}
Start Room: ${START_ROOM_URL}

URLs:
- Main: https://${DOMAIN}
- Keycloak: https://${DOMAIN}/keycloak
- Maps: https://maps.${DOMAIN}/starter-kit/

Test User:
- Username: teste
- Password: teste123

Keycloak Admin:
- Username: admin
- Password: \$KEYCLOAK_ADMIN_PASS

Credentials:
- SECRET_KEY: \$SECRET_KEY
- ADMIN_API_TOKEN: \$ADMIN_TOKEN
- MAP_STORAGE_API_TOKEN: \$MAP_STORAGE_TOKEN
- OPENID_CLIENT_SECRET: \$OPENID_SECRET
INFO_EOF

chown ubuntu:ubuntu deployment-info.txt

USERDATA_EOF

# Launch EC2 instance
echo "🚀 Launching EC2 instance..."
INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_NAME" \
    --security-group-ids "$SECURITY_GROUP_ID" \
    --user-data file://user-data.sh \
    --region "$AWS_REGION" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=WorkAdventure-${DOMAIN}}]" \
    --block-device-mappings 'DeviceName=/dev/sda1,Ebs={VolumeSize=30,VolumeType=gp3}' \
    --query 'Instances[0].InstanceId' \
    --output text)

echo "✅ Instance launched: $INSTANCE_ID"
echo "⏳ Waiting for instance to be running..."

aws ec2 wait instance-running --instance-ids "$INSTANCE_ID" --region "$AWS_REGION"

PUBLIC_IP=$(aws ec2 describe-instances \
    --instance-ids "$INSTANCE_ID" \
    --region "$AWS_REGION" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text)

echo ""
echo "=========================================="
echo "✅ EC2 Instance Created Successfully!"
echo "=========================================="
echo ""
echo "Instance ID: $INSTANCE_ID"
echo "Public IP: $PUBLIC_IP"
echo ""
echo "📋 PRÓXIMOS PASSOS:"
echo ""
echo "1. Configure DNS (Cloudflare, Route53, etc):"
echo "   - A record: ${DOMAIN} -> ${PUBLIC_IP}"
echo "   - A record: maps.${DOMAIN} -> ${PUBLIC_IP}"
echo ""
echo "2. Aguarde instalação (~5 minutos)"
echo "   ssh -i ${KEY_NAME}.pem ubuntu@${PUBLIC_IP} 'tail -f /var/log/user-data.log'"
echo ""
echo "3. Acesse quando DNS propagar:"
echo "   https://${DOMAIN}"
echo ""
echo "4. Monitorar containers:"
echo "   ssh -i ${KEY_NAME}.pem ubuntu@${PUBLIC_IP}"
echo "   cd workadventure"
echo "   docker compose -f docker-compose.prod.yaml -f docker-compose.keycloak-simple.yaml -f docker-compose.maps.yaml ps"
echo ""

# Save deployment info locally
cat > "deployment-${DOMAIN}-$(date +%Y%m%d-%H%M%S).txt" << LOCAL_INFO
WorkAdventure Deployment
========================
Date: $(date)
Domain: ${DOMAIN}
Instance ID: $INSTANCE_ID
Public IP: $PUBLIC_IP
Region: $AWS_REGION
Key: ${KEY_NAME}.pem

DNS Configuration:
- ${DOMAIN} A ${PUBLIC_IP}
- maps.${DOMAIN} A ${PUBLIC_IP}

SSH Access:
ssh -i ${KEY_NAME}.pem ubuntu@${PUBLIC_IP}

URLs (after DNS propagation):
- https://${DOMAIN}
- https://${DOMAIN}/keycloak
- https://maps.${DOMAIN}/starter-kit/

Test User: teste / teste123
LOCAL_INFO

echo "💾 Deployment info saved locally"
