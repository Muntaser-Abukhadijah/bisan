# Bisan Deployment - Part 2 (Continued)

## Rollback Procedures

### Quick Rollback (Kamal)

**Automatic Rollback:**
```bash
# Kamal keeps previous container running during deployment
# If health checks fail, deployment automatically aborts
# Old container keeps serving traffic
```

**Manual Rollback:**
```bash
# Rollback to previous version (restarts old container)
bin/kamal rollback -c config/deploy.contabo.yml

# Or rollback to specific version
bin/kamal app boot -c config/deploy.contabo.yml --version=PREVIOUS_SHA
```

### Database Rollback

**Rollback Migration:**
```bash
# Rollback last migration
bin/kamal app exec 'bin/rails db:rollback'

# Rollback to specific version
bin/kamal app exec 'bin/rails db:migrate:down VERSION=20250901110628'

# Then restart app
bin/kamal app boot -c config/deploy.contabo.yml
```

**Full Database Restore:**
```bash
# 1. Stop application
bin/kamal app stop -c config/deploy.contabo.yml

# 2. Restore database from backup (see Database Backup section)

# 3. Restart application
bin/kamal app boot -c config/deploy.contabo.yml

# 4. Reindex Meilisearch
bin/kamal app exec -c config/deploy.contabo.yml \
  'bin/rails runner "Article.reindex!; Author.reindex!"'
```

### Rollback Decision Matrix

| Severity | Symptom | Action | Time to Rollback |
|----------|---------|--------|------------------|
| **Critical** | App down (HTTP 5xx) | Immediate rollback | <2 minutes |
| **High** | Data corruption | Stop app → Restore DB → Rollback | <10 minutes |
| **Medium** | Performance degradation | Investigate → Rollback if unfixable | <15 minutes |
| **Low** | Minor UI issues | Deploy hotfix forward | N/A |

---

## Common Failure Modes

### 1. Deployment Fails During Build

**Symptoms:**
- Docker build fails locally
- Error: "gem install failed" or "yarn install failed"

**Likely Causes:**
- Dependency version conflict
- Missing credentials
- Network timeout

**Fast Fix:**
```bash
# Check Gemfile.lock and yarn.lock for conflicts
git status

# Retry with clean build
docker system prune -af
bin/kamal deploy
```

---

### 2. Image Push Fails to Docker Hub

**Symptoms:**
- Error: "unauthorized: authentication required"
- Error: "denied: requested access to the resource is denied"

**Likely Causes:**
- Expired Docker Hub token
- Wrong credentials in KAMAL_REGISTRY_PASSWORD

**Fast Fix:**
```bash
# Regenerate Docker Hub token
# Update .kamal/secrets
export KAMAL_REGISTRY_PASSWORD="new_token"
bin/kamal deploy
```

---

### 3. SSH Connection Fails

**Symptoms:**
- Error: "SSH connection failed"
- Error: "Permission denied (publickey)"

**Likely Causes:**
- SSH key not authorized on server
- Wrong key path in config

**Fast Fix:**
```bash
# Test SSH connection
ssh -i ~/bisan root@185.185.82.142

# If fails, re-copy SSH key
ssh-copy-id -i ~/bisan.pub root@185.185.82.142

# Verify SSH config in deploy.yml
cat config/deploy.contabo.yml | grep ssh -A 2
```

---

### 4. Container Health Check Fails

**Symptoms:**
- Deployment stalls at "Waiting for health check"
- Error: "Health check failed after 3 attempts"

**Likely Causes:**
- Rails app not starting (check logs)
- Port conflict
- Database migration error

**Fast Fix:**
```bash
# Check container logs
bin/kamal app logs -c config/deploy.contabo.yml

# Check if port 80 is accessible
ssh -i ~/bisan root@185.185.82.142 'curl -I localhost:80'

# Manually start container to debug
ssh -i ~/bisan root@185.185.82.142
docker ps -a
docker logs bisan-web-latest
```

---

### 5. Database Migration Fails

**Symptoms:**
- App starts but crashes immediately
- Error in logs: "PendingMigrationError" or "SyntaxError in migration"

**Likely Causes:**
- Syntax error in migration file
- Schema incompatibility
- Locked database file

**Fast Fix:**
```bash
# Check migration status
bin/kamal app exec 'bin/rails db:migrate:status'

# Rollback last migration
bin/kamal app exec 'bin/rails db:rollback'

# Fix migration locally, commit, redeploy
git add db/migrate/
git commit -m "fix: migration syntax error"
bin/kamal deploy -c config/deploy.contabo.yml
```

---

### 6. Meilisearch Connection Fails

**Symptoms:**
- Search functionality broken
- Error in logs: "Meilisearch::ApiError: Connection refused"

**Likely Causes:**
- Meilisearch container not running
- Wrong host configuration
- Network issue

**Fast Fix:**
```bash
# Check if Meilisearch is running
ssh -i ~/bisan root@185.185.82.142 'docker ps | grep meilisearch'

# Restart Meilisearch
export KAMAL_REGISTRY_PASSWORD="your_token"
bin/kamal accessory restart meilisearch -c config/deploy.contabo.yml

# Verify connectivity from app
bin/kamal app exec 'bin/rails runner "puts Article.search(\"test\").count"'
```

---

### 7. Out of Disk Space

**Symptoms:**
- Deployment fails with "No space left on device"
- App crashes with disk errors

**Likely Causes:**
- Old Docker images not cleaned
- Log files growing too large
- Database file too large

**Fast Fix:**
```bash
# Check disk space
ssh -i ~/bisan root@185.185.82.142 'df -h'

# Clean Docker images
ssh -i ~/bisan root@185.185.82.142 'docker system prune -af'

# Clean old containers
bin/kamal prune -c config/deploy.contabo.yml

# If database too large, consider moving to Postgres
```

---

### 8. SSL Certificate Issues

**Symptoms:**
- HTTPS not working
- Browser shows "NET::ERR_CERT_AUTHORITY_INVALID"

**Likely Causes:**
- Let's Encrypt rate limit
- DNS not pointing to server
- Kamal proxy misconfigured

**Fast Fix:**
```bash
# Check Kamal proxy logs
ssh -i ~/bisan root@185.185.82.142 'docker logs kamal-proxy | grep -i cert'

# Restart Kamal proxy
bin/kamal proxy reboot -c config/deploy.contabo.yml

# Verify DNS resolution
dig 185.185.82.142.nip.io
```

---

### 9. Assets Not Loading (404)

**Symptoms:**
- Website loads but no CSS/JS
- Browser console shows 404 errors for assets

**Likely Causes:**
- Asset precompilation failed
- Asset path misconfigured
- Volume mount issue

**Fast Fix:**
```bash
# Check if assets exist in container
bin/kamal app exec 'ls -la /rails/public/assets/'

# Rebuild with fresh asset compilation
RAILS_ENV=production bin/rails assets:clobber
bin/kamal deploy -c config/deploy.contabo.yml

# Verify asset_path in deploy.yml
cat config/deploy.contabo.yml | grep asset_path
```

---

### 10. Background Jobs Not Processing

**Symptoms:**
- Jobs stuck in queue
- Solid Queue not processing
- Import jobs hanging

**Likely Causes:**
- Solid Queue not started
- SOLID_QUEUE_IN_PUMA not set
- Worker crash

**Fast Fix:**
```bash
# Check if Solid Queue is running
bin/kamal app logs -c config/deploy.contabo.yml | grep "Solid Queue"

# Verify environment variable
bin/kamal app exec 'bin/rails runner "puts ENV[\"SOLID_QUEUE_IN_PUMA\"]"'

# Restart app to restart workers
bin/kamal app boot -c config/deploy.contabo.yml

# Check job queue status
bin/kamal app exec 'bin/rails runner "puts SolidQueue::Job.count"'
```

---

## Engineer Checklist

### Pre-Deployment Checklist

```markdown
## Pre-Deployment
- [ ] All CI checks passing (security + lint)
- [ ] Code reviewed and approved
- [ ] Local testing completed
- [ ] Database migrations tested locally
- [ ] Asset compilation verified locally
- [ ] No pending migrations in production
- [ ] Backup of production database taken
- [ ] .kamal/secrets file updated with latest credentials
- [ ] KAMAL_REGISTRY_PASSWORD environment variable set
- [ ] Deployment window scheduled (if high-traffic)
```

### Deployment Execution Checklist

```markdown
## Deployment
- [ ] Terminal session ready with KAMAL_REGISTRY_PASSWORD exported
- [ ] Choose deployment target (DO or Contabo)
- [ ] Run deployment command: `bin/kamal deploy -c config/deploy.contabo.yml`
- [ ] Monitor deployment progress (should take 5-10 minutes)
- [ ] Watch for health check success message
- [ ] Deployment completed without errors
```

### Post-Deployment Verification Checklist

```markdown
## Post-Deployment Verification
- [ ] Website loads successfully: curl -I https://185.185.82.142.nip.io
- [ ] Articles displaying on homepage
- [ ] Search functionality working
- [ ] Author pages loading correctly
- [ ] Database count matches expected: `Article.count`, `Author.count`
- [ ] Meilisearch indexes populated
- [ ] No errors in application logs
- [ ] SSL certificate valid (HTTPS working)
- [ ] Background jobs processing (if applicable)
- [ ] Mobile responsive layout working (spot check)
```

### Rollback Checklist

```markdown
## If Rollback Needed
- [ ] Identify issue severity (Critical/High/Medium/Low)
- [ ] Decision: Rollback or hotfix forward?
- [ ] If rollback: Run `bin/kamal rollback -c config/deploy.contabo.yml`
- [ ] Verify old version is serving traffic
- [ ] Check application logs for errors
- [ ] Communicate rollback to team
- [ ] Document root cause for post-mortem
- [ ] Create ticket to fix underlying issue
```

---

## Glossary

| Term | Definition |
|------|------------|
| **Kamal** | Docker deployment tool by Basecamp (formerly MRSK) |
| **Kamal Proxy** | Reverse proxy that handles SSL and zero-downtime deployments |
| **Thruster** | HTTP/2 proxy server that serves Rails apps |
| **Puma** | Ruby web server (multi-threaded) |
| **Solid Queue** | Rails background job processor (uses SQLite/Postgres) |
| **Meilisearch** | Open-source search engine (Rust-based) |
| **Propshaft** | Rails 7+ asset pipeline (simpler than Sprockets) |
| **esbuild** | JavaScript bundler (written in Go, very fast) |
| **Hotwire** | Rails frontend framework (Turbo + Stimulus) |
| **Turbo** | JavaScript library for SPA-like behavior without writing JS |
| **Stimulus** | JavaScript framework for progressive enhancement |
| **nip.io** | Wildcard DNS service (185.185.82.142.nip.io → 185.185.82.142) |
| **Let's Encrypt** | Free SSL/TLS certificate authority |
| **Docker Hub** | Public container registry (like npm for Docker images) |
| **UFW** | Uncomplicated Firewall (Ubuntu firewall interface) |
| **SHA** | Git commit hash used for image tagging |
| **Volume** | Persistent storage for Docker containers |
| **Accessory** | Kamal term for supporting services (like Meilisearch) |

---

## Appendix: Commands & Configs

### Quick Command Reference

```bash
# === DEPLOYMENT ===
# Deploy to DigitalOcean
export KAMAL_REGISTRY_PASSWORD="token" && bin/kamal deploy

# Deploy to Contabo
export KAMAL_REGISTRY_PASSWORD="token" && bin/kamal deploy -c config/deploy.contabo.yml

# === LOGS ===
# Tail application logs
bin/kamal app logs -f -c config/deploy.contabo.yml

# View last 100 lines
bin/kamal app logs --lines 100 -c config/deploy.contabo.yml

# === CONSOLE ACCESS ===
# Rails console
bin/kamal console -c config/deploy.contabo.yml

# Bash shell
bin/kamal app exec --interactive 'bash' -c config/deploy.contabo.yml

# === DATABASE ===
# Run migrations
bin/kamal app exec 'bin/rails db:migrate' -c config/deploy.contabo.yml

# Database console
bin/kamal app exec --interactive 'bin/rails dbconsole' -c config/deploy.contabo.yml

# Check record counts
bin/kamal app exec 'bin/rails runner "puts Article.count; puts Author.count"' -c config/deploy.contabo.yml

# Backup database
ssh -i ~/bisan root@185.185.82.142 \
  'docker run --rm -v bisan_contabo_storage:/source alpine cat /source/production.sqlite3' \
  > backup_$(date +%Y%m%d).sqlite3

# === MEILISEARCH ===
# Restart Meilisearch
export KAMAL_REGISTRY_PASSWORD="token" && \
  bin/kamal accessory restart meilisearch -c config/deploy.contabo.yml

# Reindex all
bin/kamal app exec 'bin/rails runner "Article.reindex!; Author.reindex!"' -c config/deploy.contabo.yml

# === ROLLBACK ===
# Quick rollback
bin/kamal rollback -c config/deploy.contabo.yml

# === MAINTENANCE ===
# Prune old images/containers
bin/kamal prune -c config/deploy.contabo.yml

# Check disk space
ssh -i ~/bisan root@185.185.82.142 'df -h'

# Clean Docker system
ssh -i ~/bisan root@185.185.82.142 'docker system prune -af'
```

### Key Configuration Files

**deploy.yml (Kamal Config)**
```yaml
service: bisan
image: abukhadijah/bisan

servers:
  web:
    - 185.185.82.142

proxy:
  ssl: true
  host: 185.185.82.142.nip.io

registry:
  username: abukhadijah
  password:
    - KAMAL_REGISTRY_PASSWORD

env:
  secret:
    - RAILS_MASTER_KEY
  clear:
    SOLID_QUEUE_IN_PUMA: true
    MEILISEARCH_HOST: http://bisan-meilisearch:7700

volumes:
  - "bisan_contabo_storage:/rails/storage"
  - "bisan_contabo_db:/rails/db"

asset_path: /rails/public/assets

builder:
  arch: amd64

ssh:
  keys:
    - ~/bisan

accessories:
  meilisearch:
    image: getmeili/meilisearch:v1.5
    host: 185.185.82.142
    port: 7700
    directories:
      - contabo_data:/meili_data
```

**database.yml (Database Config)**
```yaml
production:
  primary:
    adapter: sqlite3
    database: storage/production.sqlite3
    pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>
  cache:
    adapter: sqlite3
    database: storage/production_cache.sqlite3
  queue:
    adapter: sqlite3
    database: storage/production_queue.sqlite3
  cable:
    adapter: sqlite3
    database: storage/production_cable.sqlite3
```

**Dockerfile (Multi-stage Build)**
```dockerfile
ARG RUBY_VERSION=3.2.2
FROM ruby:$RUBY_VERSION-slim AS base
WORKDIR /rails

# Install dependencies
RUN apt-get update && apt-get install -y \
    curl libjemalloc2 libvips sqlite3

ENV RAILS_ENV="production"

# Build stage
FROM base AS build
RUN apt-get install -y build-essential git node-gyp pkg-config

# Install Node.js
ARG NODE_VERSION=20.11.1
RUN curl -sL https://github.com/nodenv/node-build/archive/master.tar.gz | \
    tar xz -C /tmp/ && \
    /tmp/node-build-master/bin/node-build "${NODE_VERSION}" /usr/local/node

COPY . .
RUN bundle install && yarn install --immutable
RUN bundle exec bootsnap precompile app/ lib/
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile

# Final stage
FROM base
COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --from=build /rails /rails

RUN useradd rails --uid 1000 --gid 1000 --create-home && \
    chown -R rails:rails db log storage tmp
USER 1000:1000

ENTRYPOINT ["/rails/bin/docker-entrypoint"]
EXPOSE 80
CMD ["./bin/thrust", "./bin/rails", "server"]
```

**GitHub Actions CI (.github/workflows/ci.yml)**
```yaml
name: CI

on:
  pull_request:
  push:
    branches: [ main ]

jobs:
  scan_ruby:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: .ruby-version
          bundler-cache: true
      - run: bin/brakeman --no-pager

  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: .ruby-version
          bundler-cache: true
      - run: bin/rubocop -f github
```

---

## Document History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2025-11-08 | System | Initial comprehensive deployment documentation |

---

## Related Documentation

- [DEPLOYMENT_CONTABO_GUIDE.md](./DEPLOYMENT_CONTABO_GUIDE.md) - Contabo-specific deployment guide
- [CONTABO_QUICKSTART.md](./CONTABO_QUICKSTART.md) - Quick reference for Contabo commands
- [README.md](./README.md) - Project overview and local setup
- [Kamal Documentation](https://kamal-deploy.org) - Official Kamal docs
- [Rails Guides](https://guides.rubyonrails.org) - Official Rails documentation

---

**END OF DOCUMENT**
