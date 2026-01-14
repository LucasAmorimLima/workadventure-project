#!/bin/bash
# Script de diagnóstico para WorkAdventure na AWS

echo "=========================================="
echo "🔍 Diagnóstico WorkAdventure"
echo "=========================================="
echo ""

# Verificar containers
echo "📦 Status dos containers:"
docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | head -20
echo ""

# Verificar se o domínio foi configurado
if [ -f ".env" ]; then
    DOMAIN=$(grep "^DOMAIN=" .env | cut -d'=' -f2)
    echo "🌐 Domínio configurado: $DOMAIN"
else
    echo "⚠️ Arquivo .env não encontrado!"
fi
echo ""

# Verificar logs do Play (últimas 30 linhas)
echo "📋 Últimas 30 linhas do log do Play:"
docker logs workadventure-play-1 --tail 30 2>&1 || echo "Container play não encontrado"
echo ""

# Verificar logs do Keycloak
echo "📋 Últimas 20 linhas do log do Keycloak:"
docker logs workadventure-keycloak-1 --tail 20 2>&1 || echo "Container keycloak não encontrado"
echo ""

# Verificar conectividade do Keycloak
echo "🔗 Testando conectividade do Keycloak..."
if [ -n "$DOMAIN" ]; then
    echo "  - Testando https://$DOMAIN/keycloak/health/ready"
    curl -sf "https://$DOMAIN/keycloak/health/ready" && echo " ✅ OK" || echo " ❌ FALHOU"
    
    echo "  - Testando OIDC discovery endpoint"
    curl -sf "https://$DOMAIN/keycloak/realms/workadventure/.well-known/openid-configuration" > /dev/null && echo " ✅ OK" || echo " ❌ FALHOU"
fi
echo ""

# Verificar variáveis OIDC no .env
echo "🔑 Variáveis OIDC configuradas:"
if [ -f ".env" ]; then
    grep -E "^OPENID_|^DISABLE_ANONYMOUS" .env | head -10
fi
echo ""

# Verificar certificado SSL
echo "🔒 Verificando certificado SSL..."
if [ -n "$DOMAIN" ]; then
    echo | openssl s_client -connect "$DOMAIN:443" -servername "$DOMAIN" 2>/dev/null | openssl x509 -noout -dates 2>/dev/null || echo "⚠️ Certificado não encontrado ou inválido"
fi
echo ""

# Verificar reverse-proxy
echo "📋 Logs do reverse-proxy (Traefik):"
docker logs workadventure-reverse-proxy-1 --tail 15 2>&1 || echo "Container reverse-proxy não encontrado"
echo ""

echo "=========================================="
echo "💡 Dicas:"
echo "  - Se o Play está com erro, verifique se o Keycloak está acessível"
echo "  - Se o certificado não foi emitido, verifique se o DNS está configurado"
echo "  - Para reiniciar todos os serviços: docker compose -f docker-compose.prod.yaml -f docker-compose.keycloak-simple.yaml -f docker-compose.maps.yaml restart"
echo "=========================================="
