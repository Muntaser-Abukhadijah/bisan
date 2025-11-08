# Deployment Guide: Bisan on Contabo Server

This guide explains how to deploy the Bisan application to your new Contabo server (185.185.82.142) while keeping the existing DigitalOcean deployment (104.248.18.215) completely unchanged.

## Overview

- **DigitalOcean Server**: 104.248.18.215 (unchanged)
- **Contabo Server**: 185.185.82.142 (new deployment)
- **Configuration Files**:
  - `config/deploy.yml` → DigitalOcean (unchanged)
  - `config/deploy.contabo.yml` → Contabo (new)
  - `Caddyfile` → DigitalOcean (unchanged)
  - `Caddyfile.contabo` → Contabo (new)

## Deployment Steps

### Step 1: Set Up SSH Access

First, copy your SSH public key to the Contabo server:

```bash
ssh-copy-id -i ~/bisan.pub root@185.185.82.142
```

Test the SSH connection:

```bash
ssh -i ~/bisan root@185.185.82.142
```

If successful, you should be logged into the Contabo server. Type `exit` to return to your local machine.

### Step 2: Prepare the Contabo Server

Copy the setup script to the server and run it:

```bash
# Copy the setup script to the server
scp -i ~/bisan setup-contabo-server.sh root@185.185.82.142:~/

# SSH into the server
ssh -i ~/bisan root@185.185.82.142

# Make the script executable and run it
chmod +x setup-contabo-server.sh
./setup-contabo-server.sh

# Exit the server
exit
```

This script will:
- Update system packages
- Install Docker
- Install Caddy
- Configure firewall (ports 22, 80, 443, 7700, 8080)
- Set up Caddy logging

### Step 3: Upload Caddy Configuration

Upload the Caddy configuration file to the server:

```bash
scp -i ~/bisan Caddyfile.contabo root@185.185.82.142:/etc/caddy/Caddyfile
```

Restart Caddy to apply the configuration:

```bash
ssh -i ~/bisan root@185.185.82.142 'sudo systemctl restart caddy'
```

Verify Caddy is running:

```bash
ssh -i ~/bisan root@185.185.82.142 'sudo systemctl status caddy'
```

### Step 4: Deploy the Application

From your local machine, deploy the application using Kamal:

```bash
# Set the Docker registry password
export KAMAL_REGISTRY_PASSWORD="your_docker_hub_token"

# Deploy to Contabo server using the Contabo-specific configuration
bin/kamal deploy -c config/deploy.contabo.yml
```

This command will:
1. Build and push the Docker image to Docker Hub
2. Set up Docker containers on the Contabo server
3. Start Meilisearch accessory
4. Deploy the Rails application
5. Run database migrations automatically

**Important**: The initial deployment creates an empty database. You'll need to migrate your data in the next steps.

### Step 5: Migrate Your Local Data to Contabo

After the initial deployment, you'll want to migrate your existing data from your local development database to the Contabo server.

#### 5.1 Copy Local Database to Server

First, copy your local development database to the server:

```bash
# Copy the local SQLite database to the Contabo server
scp -i ~/bisan storage/development.sqlite3 root@185.185.82.142:~/production.sqlite3
```

This uploads your local database (which can be 70-80MB) to the server's home directory.

#### 5.2 Import Database to Docker Volume

The Rails application expects the database in the `storage/` directory within the Docker volume. Import it:

```bash
# Copy database from server home to the storage Docker volume
ssh -i ~/bisan root@185.185.82.142 'docker run --rm -v bisan_contabo_db:/source -v bisan_contabo_storage:/target alpine sh -c "cp /source/../production.sqlite3 /target/production.sqlite3 && chown 1000:1000 /target/production.sqlite3"'
```

**What this does**:
- Mounts both the `db` volume (where we initially uploaded) and `storage` volume
- Copies the database file to the correct location (`storage/production.sqlite3`)
- Sets correct ownership (UID 1000 = rails user in container)

#### 5.3 Restart Application

Restart the application to pick up the new database:

```bash
export KAMAL_REGISTRY_PASSWORD="your_docker_hub_token"
bin/kamal app boot -c config/deploy.contabo.yml
```

#### 5.4 Verify Data Was Imported

Check that your data is now available:

```bash
export KAMAL_REGISTRY_PASSWORD="your_docker_hub_token"
bin/kamal app exec -c config/deploy.contabo.yml 'bin/rails runner "puts \"Articles: #{Article.count}\"; puts \"Authors: #{Author.count}\""'
```

You should see the correct counts of your articles and authors.

#### 5.5 Reindex Meilisearch

After importing the database, you need to reindex Meilisearch for search functionality:

```bash
export KAMAL_REGISTRY_PASSWORD="your_docker_hub_token"
bin/kamal app exec -c config/deploy.contabo.yml 'bin/rails runner "Article.reindex!; Author.reindex!; puts \"Reindexing complete!\""'
```

This process may take a few minutes depending on the amount of data.

### Step 6: Verify the Deployment

Once deployment is complete, verify everything is working:

1. **Check the application**:
   - Visit: https://185.185.82.142.nip.io
   - You should see the Bisan homepage

2. **Check SSL certificate**:
   - The site should have a valid Let's Encrypt certificate
   - Look for the padlock icon in your browser

3. **Check logs**:
   ```bash
   # View application logs
   bin/kamal logs -c config/deploy.contabo.yml
   
   # View Caddy logs on server
   ssh -i ~/bisan root@185.185.82.142 'sudo tail -f /var/log/caddy/access.log'
   ```

## Managing Both Deployments

### Deploy to DigitalOcean (existing)
```bash
bin/kamal deploy
# or explicitly:
bin/kamal deploy -c config/deploy.yml
```

### Deploy to Contabo (new)
```bash
bin/kamal deploy -c config/deploy.contabo.yml
```

### View logs
```bash
# DigitalOcean
bin/kamal logs

# Contabo
bin/kamal logs -c config/deploy.contabo.yml
```

### Access Rails console
```bash
# DigitalOcean
bin/kamal console

# Contabo
bin/kamal console -c config/deploy.contabo.yml
```

### Run database migrations
```bash
# DigitalOcean
bin/kamal app exec 'bin/rails db:migrate'

# Contabo
bin/kamal app exec -c config/deploy.contabo.yml 'bin/rails db:migrate'
```

## Data Management

### Updating Data on Contabo

If you make changes to your local database and want to update the Contabo server:

```bash
# 1. Copy updated local database
scp -i ~/bisan storage/development.sqlite3 root@185.185.82.142:~/production.sqlite3

# 2. Import to storage volume with correct permissions
ssh -i ~/bisan root@185.185.82.142 'docker run --rm -v bisan_contabo_db:/source -v bisan_contabo_storage:/target alpine sh -c "cp /source/../production.sqlite3 /target/production.sqlite3 && chown 1000:1000 /target/production.sqlite3"'

# 3. Restart application
export KAMAL_REGISTRY_PASSWORD="your_docker_hub_token"
bin/kamal app boot -c config/deploy.contabo.yml

# 4. Reindex Meilisearch
bin/kamal app exec -c config/deploy.contabo.yml 'bin/rails runner "Article.reindex!; Author.reindex!"'
```

### Database Backup

To backup the production database from Contabo:

```bash
# Download the database from the Docker volume
ssh -i ~/bisan root@185.185.82.142 'docker run --rm -v bisan_contabo_storage:/source alpine cat /source/production.sqlite3' > contabo_backup_$(date +%Y%m%d).sqlite3
```

### Meilisearch Management

**Check Meilisearch status**:
```bash
ssh -i ~/bisan root@185.185.82.142 'docker ps | grep meilisearch'
```

**View Meilisearch logs**:
```bash
ssh -i ~/bisan root@185.185.82.142 'docker logs bisan-meilisearch'
```

**Restart Meilisearch**:
```bash
export KAMAL_REGISTRY_PASSWORD="your_docker_hub_token"
bin/kamal accessory restart meilisearch -c config/deploy.contabo.yml
```

**Clear and reindex all data**:
```bash
export KAMAL_REGISTRY_PASSWORD="your_docker_hub_token"
bin/kamal app exec -c config/deploy.contabo.yml 'bin/rails runner "Article.clear_index!; Author.clear_index!; Article.reindex!; Author.reindex!"'
```

## Important Notes

1. **Database Location**: The Rails application expects the database at `storage/production.sqlite3` (not `db/production.sqlite3`). This is configured in `config/database.yml`.

2. **Database Volumes**: The Contabo deployment uses completely separate database volumes:
   - Storage volume: `bisan_contabo_storage` (contains `production.sqlite3`)
   - DB volume: `bisan_contabo_db` (contains migrations and schema files)
   - These are separate from DigitalOcean volumes (`bisan_storage` and `bisan_db`)

3. **File Permissions**: Database files must be owned by UID/GID 1000:1000 (the `rails` user in the container).

4. **Meilisearch**: The Contabo deployment has its own Meilisearch instance with separate data directory (`contabo_data` vs `data`). Always reindex after importing new data.

5. **SSL Certificates**: Kamal proxy automatically provisions SSL certificates using Let's Encrypt. No manual Caddy configuration needed for SSL.

6. **Firewall**: The firewall is configured to allow only necessary ports (22, 80, 443, 7700, 8080). If you need to open additional ports, SSH into the server and use `ufw`.

7. **Docker Registry**: Remember to set `KAMAL_REGISTRY_PASSWORD` environment variable before running any Kamal commands.

## Troubleshooting

### If deployment fails

1. **Check SSH connection**:
   ```bash
   ssh -i ~/bisan root@185.185.82.142
   ```

2. **Check Docker is running**:
   ```bash
   ssh -i ~/bisan root@185.185.82.142 'docker ps'
   ```

3. **Check Caddy status**:
   ```bash
   ssh -i ~/bisan root@185.185.82.142 'sudo systemctl status caddy'
   ```

4. **View Kamal setup logs**:
   ```bash
   bin/kamal app logs -c config/deploy.contabo.yml
   ```

### If SSL certificate is not working

1. Wait 2-3 minutes for Let's Encrypt to provision the certificate
2. Check Caddy logs:
   ```bash
   ssh -i ~/bisan root@185.185.82.142 'sudo journalctl -u caddy -f'
   ```

### If you need to redeploy

```bash
# Redeploy application only
bin/kamal deploy -c config/deploy.contabo.yml

# Remove everything and start fresh
bin/kamal remove -c config/deploy.contabo.yml
bin/kamal setup -c config/deploy.contabo.yml
bin/kamal deploy -c config/deploy.contabo.yml
```

## Security Recommendations

1. **Change SSH Port**: Consider changing the default SSH port (22) to a custom port
2. **Fail2Ban**: Install fail2ban to protect against brute force attacks
3. **Regular Updates**: Keep the system updated with security patches
4. **Backups**: Set up regular backups of the database volumes

## Support

For issues or questions:
- Check Kamal documentation: https://kamal-deploy.org
- Check Caddy documentation: https://caddyserver.com/docs
- Review application logs: `bin/kamal logs -c config/deploy.contabo.yml`
