# Deploy WorkAdventure na AWS

Scripts automatizados para deploy do WorkAdventure em instância EC2.

## 📋 Pré-requisitos

- AWS CLI configurado (`aws configure`)
- Conta AWS com permissões para criar EC2, Security Groups, Key Pairs
- Docker e Docker Compose instalados localmente

## 🚀 Deploy Rápido

### 1. Criar instância EC2

```bash
./deploy-aws.sh
```

Isso irá:
- ✅ Criar chave SSH (`workadventure-key.pem`)
- ✅ Criar Security Group (portas 22, 80, 443)
- ✅ Criar instância EC2 (t3.medium - 2 vCPU, 4GB RAM)
- ✅ Instalar Docker e Docker Compose automaticamente
- ✅ Retornar IP público da instância

### 2. Deploy do projeto

```bash
./deploy-project.sh <IP_PUBLICO>
```

Exemplo:
```bash
./deploy-project.sh 54.123.45.67
```

Isso irá:
- ✅ Enviar arquivos do projeto para EC2
- ✅ Gerar credenciais seguras automaticamente
- ✅ Configurar Keycloak com import automático
- ✅ Iniciar todos os serviços via Docker Compose
- ✅ Salvar credenciais em `deployment-info.txt`

## ⚙️ Configurações Opcionais

Personalizar instância antes de criar:

```bash
# Tipo de instância
export INSTANCE_TYPE=t3.large  # Padrão: t3.medium

# Nome da instância
export INSTANCE_NAME=meu-workadventure  # Padrão: workadventure-prod

# Região AWS
export AWS_REGION=us-west-2  # Padrão: us-east-1

# Nome da chave SSH
export KEY_NAME=minha-chave  # Padrão: workadventure-key

# Depois execute
./deploy-aws.sh
```

## 🔑 Acessar após deploy

Após deploy bem-sucedido:

**WorkAdventure:**
```
http://<IP_PUBLICO>/
```

**Keycloak Admin:**
```
http://<IP_PUBLICO>/keycloak/admin
```

Credenciais salvas em: `deployment-info.txt`

**Usuário de teste:**
- Usuário: `teste`
- Senha: `teste123`

## 📊 Gerenciar instância

### Conectar via SSH

```bash
ssh -i workadventure-key.pem ubuntu@<IP_PUBLICO>
```

### Ver logs

```bash
ssh -i workadventure-key.pem ubuntu@<IP_PUBLICO> \
  'cd /opt/workadventure && docker compose logs -f'
```

### Reiniciar serviços

```bash
ssh -i workadventure-key.pem ubuntu@<IP_PUBLICO> \
  'cd /opt/workadventure && docker compose restart'
```

### Parar serviços

```bash
ssh -i workadventure-key.pem ubuntu@<IP_PUBLICO> \
  'cd /opt/workadventure && docker compose down'
```

### Parar instância EC2 (economizar custos)

```bash
aws ec2 stop-instances --instance-ids <INSTANCE_ID> --region us-east-1
```

### Iniciar instância EC2

```bash
aws ec2 start-instances --instance-ids <INSTANCE_ID> --region us-east-1
```

### Terminar instância (deletar)

```bash
aws ec2 terminate-instances --instance-ids <INSTANCE_ID> --region us-east-1
```

## 💰 Custos Estimados

**t3.medium** (2 vCPU, 4GB RAM):
- ~$0.0416/hora
- ~$30/mês (730 horas)

**t3.large** (2 vCPU, 8GB RAM):
- ~$0.0832/hora
- ~$60/mês

**Armazenamento** (30GB SSD):
- ~$3/mês

**Transferência de dados**: Grátis até 100GB/mês

## 🔒 Segurança

- ✅ Keycloak com senhas geradas aleatoriamente
- ✅ Anonymous login desabilitado
- ✅ HTTPS recomendado para produção (não incluído)
- ✅ Security Group permite apenas portas necessárias
- ✅ Chave SSH privada não compartilhada

## 🌐 Produção com Domínio

Para usar com domínio próprio:

1. Configure DNS apontando para o IP da instância
2. Atualize `.env` no servidor:
   ```bash
   ssh -i workadventure-key.pem ubuntu@<IP> \
     'cd /opt/workadventure && nano .env'
   ```
3. Atualize URLs:
   ```
   PUSHER_URL=https://seu-dominio.com
   OPENID_CLIENT_ISSUER=https://seu-dominio.com/keycloak/realms/workadventure
   ```
4. Configure certificado SSL (Let's Encrypt recomendado)

## 🐛 Troubleshooting

### Erro "Permission denied (publickey)"
- Verifique se está usando a chave correta: `-i workadventure-key.pem`
- Verifique permissões: `chmod 400 workadventure-key.pem`

### Serviços não iniciam
```bash
ssh -i workadventure-key.pem ubuntu@<IP> \
  'cd /opt/workadventure && docker compose logs'
```

### "Invalid client credentials" no login
- Verifique se o secret do Keycloak está correto no realm
- Verifique logs: `docker compose logs keycloak`

### Porta 80 não acessível
- Verifique Security Group no AWS Console
- Verifique se serviços estão rodando: `docker compose ps`

## 📞 Suporte

Informações salvas em: `deployment-info.txt`

Logs de setup automático: `/var/log/workadventure-setup.log`
