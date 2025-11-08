# Quick Start: Deploy to Contabo

Follow these commands in order to deploy Bisan to your Contabo server.

## 1. Copy SSH Key to Server
```bash
ssh-copy-id -i ~/bisan.pub root@185.185.82.142
```

## 2. Setup the Server
```bash
# Copy setup script
scp -i ~/bisan setup-contabo-server.sh root@185.185.82.142:~/

# Run setup script on server
ssh -i ~/bisan root@185.185.82.142 'chmod +x setup-contabo-server.sh && ./setup-contabo-server.sh'
```

## 3. Configure Caddy
```bash
# Upload Caddy configuration
scp -i ~/bisan Caddyfile.contabo root@185.185.82.142:/etc/caddy/Caddyfile

# Restart Caddy
ssh -i ~/bisan root@185.185.82.142 'sudo systemctl restart caddy'
```

## 4. Deploy Application
```bash
bin/kamal deploy -c config/deploy.contabo.yml
```

## 5. Verify Deployment
Visit: https://185.185.82.142.nip.io

## Managing Deployments

### Deploy to DigitalOcean (existing)
```bash
bin/kamal deploy
```

### Deploy to Contabo (new)
```bash
bin/kamal deploy -c config/deploy.contabo.yml
```

### View Logs
```bash
# DigitalOcean
bin/kamal logs

# Contabo
bin/kamal logs -c config/deploy.contabo.yml
```

### Access Console
```bash
# DigitalOcean
bin/kamal console

# Contabo
bin/kamal console -c config/deploy.contabo.yml
```

## Troubleshooting

### Test SSH Connection
```bash
ssh -i ~/bisan root@185.185.82.142
```

### Check Deployment Status
```bash
bin/kamal app logs -c config/deploy.contabo.yml
```

### Redeploy from Scratch
```bash
bin/kamal remove -c config/deploy.contabo.yml
bin/kamal setup -c config/deploy.contabo.yml
bin/kamal deploy -c config/deploy.contabo.yml
```

For detailed information, see `DEPLOYMENT_CONTABO_GUIDE.md`
