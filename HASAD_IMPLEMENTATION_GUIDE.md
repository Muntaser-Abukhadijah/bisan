# Hasad Data Lake Implementation Guide

This document provides step-by-step instructions for implementing the Hasad Data Lake architecture on your Contabo VPS.

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Docker Compose Setup](#docker-compose-setup)
3. [Database Initialization](#database-initialization)
4. [Fallah Configuration](#fallah-configuration)
5. [Bisan Integration](#bisan-integration)
6. [Testing the Pipeline](#testing-the-pipeline)
7. [Operational Runbook](#operational-runbook)
8. [Migration from Current System](#migration-from-current-system)
9. [Troubleshooting](#troubleshooting)

---

## Prerequisites

**On Contabo VPS (185.185.82.142):**
- Docker & Docker Compose installed
- At least 2GB free RAM
- At least 20GB free disk space
- SSH access with sudo privileges

**Local Development:**
- Git repository access
- Python 3.9+ (for Fallah)
- Ruby 3.2+ (for Bisan)

---

## Docker Compose Setup

### 1. Create Directory Structure

```bash
ssh root@185.185.82.142

# Create Hasad directory
mkdir -p ~/hasad
cd ~/hasad
```

### 2. Create docker-compose.yml

```yaml
# ~/hasad/docker-compose.yml
version: '3.8'

services:
  # PostgreSQL for metadata
  postgres:
    image: postgres:16-alpine
    container_name: hasad-postgres
    ports:
      - "5432:5432"
    volumes:
      - postgres-data:/var/lib/postgresql/data
      - ./init-db.sql:/docker-entrypoint-initdb.d/init.sql
    environment:
      POSTGRES_DB: hasad
      POSTGRES_USER: hasad
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U hasad"]
      interval: 10s
      timeout: 5s
      retries: 5

  # MinIO for object storage
  minio:
    image: minio/minio:latest
    container_name: hasad-minio
    ports:
      - "9000:9000"  # API
      - "9001:9001"  # Web UI
    volumes:
      - minio-data:/data
    environment:
      MINIO_ROOT_USER: ${MINIO_ROOT_USER}
      MINIO_ROOT_PASSWORD: ${MINIO_ROOT_PASSWORD}
    command: server /data --console-address ":9001"
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:9000/minio/health/live"]
      interval: 30s
      timeout: 10s
      retries: 3

  # Fallah scraper (runs on cron)
  fallah:
    build: ./fallah
    container_name: hasad-fallah
    depends_on:
      - postgres
      - minio
    volumes:
      - ./fallah:/app
      - fallah-cache:/app/.scrapy
    environment:
      MINIO_ENDPOINT: minio:9000
      MINIO_ACCESS_KEY: ${MINIO_ROOT_USER}
      MINIO_SECRET_KEY: ${MINIO_ROOT_PASSWORD}
      POSTGRES_DSN: host=postgres dbname=hasad user=hasad password=${POSTGRES_PASSWORD}
    restart: unless-stopped
    # Cron runs inside container
    command: crond -f -l 2

volumes:
  postgres-data:
  minio-data:
  fallah-cache:

networks:
  default:
    name: hasad-network
```

### 3. Create Environment File

```bash
# ~/hasad/.env
POSTGRES_PASSWORD=$(openssl rand -base64 32)
MINIO_ROOT_USER=minioadmin
MINIO_ROOT_PASSWORD=$(openssl rand -base64 32)

echo "Generated passwords - save these securely!"
cat .env
```

---

## Database Initialization

### Create init-db.sql

```bash
cat > ~/hasad/init-db.sql << 'EOF'
-- Hasad Data Lake Database Schema

-- Content metadata and index
CREATE TABLE content_metadata (
    id SERIAL PRIMARY KEY,
    content_hash VARCHAR(64) NOT NULL UNIQUE,
    source_name VARCHAR(100) NOT NULL,
    content_type VARCHAR(50) NOT NULL,
    url TEXT,
    minio_bucket VARCHAR(100) NOT NULL,
    minio_key TEXT NOT NULL,
    content_size INT,
    scraped_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    scraper_version VARCHAR(50),
    status VARCHAR(20) NOT NULL DEFAULT 'active',
    
    -- Denormalized fields for quick filtering
    title TEXT,
    author_name TEXT,
    publish_date DATE,
    
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_content_metadata_type_source ON content_metadata(content_type, source_name);
CREATE INDEX idx_content_metadata_scraped_at ON content_metadata(scraped_at DESC);
CREATE INDEX idx_content_metadata_url ON content_metadata(url);
CREATE INDEX idx_content_metadata_status ON content_metadata(status) WHERE status = 'active';

-- Version history for URLs
CREATE TABLE content_versions (
    id SERIAL PRIMARY KEY,
    url TEXT NOT NULL,
    version_number INT NOT NULL,
    content_metadata_id INT NOT NULL REFERENCES content_metadata(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    CONSTRAINT unique_url_version UNIQUE (url, version_number)
);

CREATE INDEX idx_content_versions_url ON content_versions(url, version_number DESC);

-- Consumer sync checkpoints
CREATE TABLE sync_checkpoints (
    id SERIAL PRIMARY KEY,
    consumer_name VARCHAR(100) NOT NULL UNIQUE,
    last_sync_at TIMESTAMPTZ NOT NULL,
    last_processed_id INT,
    metadata JSONB,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Audit log
CREATE TABLE content_audit_log (
    id SERIAL PRIMARY KEY,
    content_metadata_id INT REFERENCES content_metadata(id),
    action VARCHAR(50) NOT NULL,
    performed_by VARCHAR(100),
    performed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    details JSONB
);

-- Grant permissions
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO hasad;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO hasad;
EOF
```

---

## Fallah Configuration

### 1. Create Fallah Directory

```bash
mkdir -p ~/hasad/fallah
cd ~/hasad/fallah
```

### 2. Create Dockerfile

```dockerfile
# ~/hasad/fallah/Dockerfile
FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    libpq-dev \
    curl \
    cron \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy Fallah code
COPY . .

# Setup cron
RUN echo "*/30 * * * * cd /app && scrapy crawl metras >> /var/log/cron.log 2>&1" > /etc/cron.d/fallah-cron
RUN echo "*/30 * * * * cd /app && scrapy crawl qudsn_co >> /var/log/cron.log 2>&1" >> /etc/cron.d/fallah-cron
RUN chmod 0644 /etc/cron.d/fallah-cron
RUN crontab /etc/cron.d/fallah-cron
RUN touch /var/log/cron.log

# Create scrapy cache directory
RUN mkdir -p /app/.scrapy

CMD ["crond", "-f", "-l", "2"]
```

### 3. Create requirements.txt

```txt
# ~/hasad/fallah/requirements.txt
scrapy>=2.11.0
psycopg2-binary>=2.9.9
minio>=7.2.0
```

### 4. Copy Fallah Code

```bash
# Copy your existing Fallah project
scp -r /path/to/local/fallah/* root@185.185.82.142:~/hasad/fallah/

# Update settings.py to use HasadDataLakePipeline
# (Replace the pipeline code as shown in HASAD_DATA_LAKE_DESIGN.md)
```

---

## Bisan Integration

### 1. Add Dependencies to Gemfile

```ruby
# In Bisan's Gemfile
gem 'pg'
gem 'minio', '~> 0.1.1'  # Or use aws-sdk-s3 with MinIO
```

```bash
# On Bisan server
cd /path/to/bisan
bundle install
```

### 2. Create HasadSyncer

```bash
# Create lib/hasad_syncer.rb
# (Copy code from HASAD_DATA_LAKE_DESIGN.md)
```

### 3. Create Rake Task

```bash
# Create lib/tasks/sync_from_hasad.rake
# (Copy code from HASAD_DATA_LAKE_DESIGN.md)
```

### 4. Configure Environment Variables

```bash
# Add to Bisan's .env
cat >> .env << EOF

# Hasad Data Lake
HASAD_PG_HOST=185.185.82.142
HASAD_PG_DB=hasad
HASAD_PG_USER=hasad
HASAD_PG_PASSWORD=<from ~/hasad/.env>
HASAD_MINIO_ENDPOINT=185.185.82.142:9000
HASAD_MINIO_ACCESS_KEY=minioadmin
HASAD_MINIO_SECRET_KEY=<from ~/hasad/.env>
EOF
```

### 5. Setup Cron Job

```bash
# On Bisan server
crontab -e

# Add this line:
*/30 * * * * cd /path/to/bisan && bin/rails hasad:sync >> log/hasad_sync.log 2>&1
```

---

## Testing the Pipeline

### 1. Start Hasad Stack

```bash
cd ~/hasad
docker-compose up -d

# Check logs
docker-compose logs -f
```

### 2. Verify Services

```bash
# PostgreSQL
docker exec hasad-postgres psql -U hasad -d hasad -c "\dt"

# MinIO Web UI
# Open http://185.185.82.142:9001
# Login with credentials from .env
```

### 3. Manual Fallah Run (Test)

```bash
# Trigger immediate scrape
docker exec hasad-fallah scrapy crawl metras

# Check PostgreSQL for new content
docker exec hasad-postgres psql -U hasad -d hasad -c \
  "SELECT COUNT(*) FROM content_metadata;"
```

### 4. Test Bisan Sync

```bash
# On Bisan server
cd /path/to/bisan
bin/rails hasad:sync

# Check logs
tail -f log/hasad_sync.log

# Verify articles imported
bin/rails runner "puts Article.count"
```

---

## Operational Runbook

### Daily Operations

**Monitor Hasad Health:**
```bash
# Check all services
cd ~/hasad
docker-compose ps

# Check disk usage
df -h

# Check MinIO storage
docker exec hasad-minio mc du local/hasad-content
```

**Check Sync Status:**
```bash
# Last sync time
docker exec hasad-postgres psql -U hasad -d hasad -c \
  "SELECT consumer_name, last_sync_at FROM sync_checkpoints;"

# Recent content
docker exec hasad-postgres psql -U hasad -d hasad -c \
  "SELECT COUNT(*), source_name, content_type FROM content_metadata 
   WHERE scraped_at > NOW() - INTERVAL '24 hours' 
   GROUP BY source_name, content_type;"
```

### Weekly Maintenance

**Database Vacuum:**
```bash
docker exec hasad-postgres psql -U hasad -d hasad -c "VACUUM ANALYZE;"
```

**Check for Stale Content:**
```bash
docker exec hasad-postgres psql -U hasad -d hasad -c \
  "SELECT source_name, MAX(scraped_at) as last_scrape 
   FROM content_metadata 
   GROUP BY source_name;"
```

### Monthly Maintenance

**Backup PostgreSQL:**
```bash
docker exec hasad-postgres pg_dump -U hasad hasad | \
  gzip > ~/backups/hasad-$(date +%Y%m%d).sql.gz
```

**Backup MinIO:**
```bash
# Use MinIO client
docker run --rm --network hasad-network \
  -v ~/backups:/backups \
  minio/mc \
  mirror --overwrite \
  local/hasad-content \
  /backups/minio-$(date +%Y%m%d)
```

### Troubleshooting Commands

**Fallah not scraping:**
```bash
# Check cron logs
docker exec hasad-fallah cat /var/log/cron.log

# Manual test
docker exec -it hasad-fallah scrapy crawl metras
```

**Bisan not syncing:**
```bash
# Check if Hasad is reachable
telnet 185.185.82.142 5432
telnet 185.185.82.142 9000

# Test PostgreSQL connection
psql -h 185.185.82.142 -U hasad -d hasad

# Manual sync with verbose logging
RAILS_LOG_LEVEL=debug bin/rails hasad:sync
```

**Database connection issues:**
```bash
# Check PostgreSQL logs
docker logs hasad-postgres

# Check connections
docker exec hasad-postgres psql -U hasad -d hasad -c \
  "SELECT * FROM pg_stat_activity WHERE datname = 'hasad';"
```

---

## Migration from Current System

### Phase 1: Parallel Run (Week 1-2)

**Goal:** Run new system alongside old system

1. **Deploy Hasad infrastructure** (as per setup above)
2. **Configure Fallah** to write to both:
   - Old NDJSON files (current)
   - New Hasad Data Lake
3. **Keep Bisan** reading from old NDJSON files
4. **Monitor** Hasad for correctness

**Validation:**
```bash
# Compare counts
OLD_COUNT=$(find ~/hasad_old -name "*.ndjson" -exec wc -l {} \; | awk '{sum+=$1} END {print sum}')
NEW_COUNT=$(docker exec hasad-postgres psql -U hasad -d hasad -t -c \
  "SELECT COUNT(*) FROM content_metadata WHERE status='active';")

echo "Old: $OLD_COUNT, New: $NEW_COUNT"
```

### Phase 2: Switch Bisan (Week 3)

**Goal:** Point Bisan to Hasad

1. **Test sync thoroughly** in staging
2. **Create initial checkpoint:**
```bash
# Set checkpoint to ID 0 (will sync everything)
docker exec hasad-postgres psql -U hasad -d hasad -c \
  "INSERT INTO sync_checkpoints (consumer_name, last_processed_id, last_sync_at) 
   VALUES ('bisan', 0, NOW());"
```
3. **Run full sync:**
```bash
bin/rails hasad:sync
```
4. **Verify article count** matches
5. **Enable cron job** for continuous sync
6. **Monitor logs** for 48 hours

### Phase 3: Decommission Old System (Week 4)

**Goal:** Remove old NDJSON-based system

1. **Archive old NDJSON files:**
```bash
cd ~/hasad
mkdir -p legacy
mv ~/hasad_old/* legacy/
```

2. **Remove old Fallah pipeline:**
```python
# Remove ArticlesJsonlPipeline from settings.py
```

3. **Update Bisan** to remove HasadImportJob
```bash
# Remove app/jobs/hasad_import_job.rb
# Remove lib/tasks/hasad_import.rake
```

4. **Clean up cron jobs:**
```bash
crontab -e
# Remove any old import jobs
```

### Rollback Plan

**If issues arise, rollback to old system:**

1. **Stop Hasad sync:**
```bash
crontab -e
# Comment out hasad:sync job
```

2. **Re-enable old import job:**
```bash
crontab -e
# Uncomment old hasad_import job
```

3. **Verify old system working:**
```bash
bin/rails hasad:import
```

4. **Investigate issues** before retry

---

## Troubleshooting

### Issue: Fallah Can't Connect to PostgreSQL

**Symptoms:**
- Fallah logs show connection errors
- No new content in Hasad

**Solutions:**
```bash
# 1. Check PostgreSQL is running
docker ps | grep postgres

# 2. Test connection from Fallah container
docker exec hasad-fallah psql -h postgres -U hasad -d hasad

# 3. Check network
docker network inspect hasad-network

# 4. Restart services
docker-compose restart postgres fallah
```

### Issue: MinIO Out of Disk Space

**Symptoms:**
- Fallah fails to upload
- MinIO errors in logs

**Solutions:**
```bash
# 1. Check disk usage
df -h
docker exec hasad-minio df -h /data

# 2. Clean up old content (if needed)
# Archive to external storage first!

# 3. Increase disk space
# Contact Contabo to upgrade VPS
```

### Issue: Bisan Sync Very Slow

**Symptoms:**
- Sync takes >10 minutes
- High PostgreSQL CPU

**Solutions:**
```bash
# 1. Check query performance
docker exec hasad-postgres psql -U hasad -d hasad -c \
  "SELECT * FROM pg_stat_statements ORDER BY total_time DESC LIMIT 10;"

# 2. Add missing indexes
# Check init-db.sql has all indexes

# 3. Batch size tuning
# Reduce LIMIT in fetch_new_content() from 1000 to 100

# 4. Consider adding read replica (future)
```

### Issue: Content Hash Collisions

**Symptoms:**
- New articles not appearing
- Logs show "Content already exists"

**Solutions:**
```bash
# 1. Verify it's truly a collision
docker exec hasad-postgres psql -U hasad -d hasad -c \
  "SELECT content_hash, COUNT(*) FROM content_metadata 
   GROUP BY content_hash HAVING COUNT(*) > 1;"

# 2. If false collision (same content, different URL)
# This is expected - content deduplication working

# 3. If true collision (SHA256 collision - extremely rare)
# Add URL to hash calculation
```

---

## Performance Tuning

### PostgreSQL Optimization

```sql
-- Increase connection pool
ALTER SYSTEM SET max_connections = 100;

-- Tune memory
ALTER SYSTEM SET shared_buffers = '256MB';
ALTER SYSTEM SET effective_cache_size = '1GB';
ALTER SYSTEM SET maintenance_work_mem = '64MB';

-- Restart to apply
-- docker-compose restart postgres
```

### MinIO Optimization

```bash
# Enable caching
docker exec hasad-minio mc admin config set local cache \
  drives="/cache" \
  exclude="*.ndjson" \
  quota=80
```

### Bisan Sync Optimization

```ruby
# In HasadSyncer, add connection pooling
def initialize
  @pg = PG::Connection.new(
    # ... connection params ...
    connect_timeout: 5,
    keepalives: 1,
    keepalives_idle: 30
  )
  
  # Reuse MinIO client
  @minio = Minio::Client.new(...)
end

# Batch fetches
def fetch_new_content(since_id)
  # Increase LIMIT for faster catch-up
  # But don't exceed 5000 to avoid memory issues
  result = @pg.exec("""
    ...
    LIMIT 5000
  """, [since_id])
end
```

---

## Next Steps

1. **✅ Deploy Hasad infrastructure**
2. **✅ Configure Fallah to write to Hasad**
3. **✅ Test Bisan sync**
4. **📋 Run parallel for 1-2 weeks**
5. **📋 Switch Bisan to Hasad**
6. **📋 Decommission old system**
7. **📋 Setup monitoring & alerts**
8. **📋 Document for team**

For questions or issues, refer to:
- HASAD_DATA_LAKE_DESIGN.md (architecture)
- This guide (implementation)
- Fallah README.md (scraper details)
- Bisan README.md (app details)
