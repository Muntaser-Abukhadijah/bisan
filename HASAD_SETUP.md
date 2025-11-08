# Hasad Data Pipeline - Complete Setup Guide

## Architecture Overview

This guide documents the complete data pipeline connecting the fallah scraper, hasad data lake, and bisan web application.

```
┌─────────────────┐      ┌──────────────┐      ┌─────────────────┐
│  Fallah Scraper │─────>│ Hasad (Git)  │─────>│ Bisan Rails App │
│  (Python/Scrapy)│      │ (NDJSON Data)│      │   (Production)  │
└─────────────────┘      └──────────────┘      └─────────────────┘
        ▼                        ▼                      ▼
   Local Machine           GitHub Repo          185.185.82.142
   Scrapes articles        Version control      Web server + DB
```

### Data Flow

1. **Fallah** scrapes articles from Arabic news sources
2. **Hasad** stores scraped data as NDJSON files, versioned in Git
3. **Bisan** pulls from GitHub and imports into SQLite database
4. **Website** displays articles to users

---

## Prerequisites

- SSH access to production server (185.185.82.142)
- SSH key at `~/bisan`
- GitHub access to https://github.com/Muntaser-Abukhadijah/hasad
- Kamal installed locally (`gem install kamal`)

---

## One-Time Setup

### Step 1: Set Up GitHub Access on Production Server

SSH into the production server:
```bash
ssh -i ~/bisan root@185.185.82.142
```

Generate an SSH deploy key for hasad:
```bash
ssh-keygen -t ed25519 -f ~/.ssh/hasad_deploy_key -N ""
```

Display the public key:
```bash
cat ~/.ssh/hasad_deploy_key.pub
```

**Add the deploy key to GitHub:**
1. Copy the entire public key output
2. Go to: https://github.com/Muntaser-Abukhadijah/hasad/settings/keys
3. Click "Add deploy key"
4. Title: "Production Server Deploy Key"
5. Paste the public key
6. ⚠️ Leave "Allow write access" **unchecked** (read-only is safer)
7. Click "Add key"

Configure SSH to use this key for hasad:
```bash
cat >> ~/.ssh/config << 'EOF'
Host github.com-hasad
    HostName github.com
    User git
    IdentityFile ~/.ssh/hasad_deploy_key
    IdentitiesOnly yes
EOF
```

Clone the hasad repository:
```bash
cd /root
git clone git@github.com-hasad:Muntaser-Abukhadijah/hasad.git
```

Verify the clone succeeded:
```bash
ls -la /root/hasad
```

You should see directories like `metras/`, `qudsn.co/`, etc.

Exit the SSH session:
```bash
exit
```

### Step 2: Deploy Bisan with Hasad Volume Mount

The `config/deploy.contabo.yml` file has been updated to mount hasad:

```yaml
volumes:
  - "bisan_contabo_storage:/rails/storage"
  - "bisan_contabo_db:/rails/db"
  - "/root/hasad:/rails/hasad"  # <- Hasad mount
```

Deploy to production:
```bash
cd bisan
bin/kamal deploy -d contabo
```

This will:
- Build the Docker image
- Deploy to production server
- Mount `/root/hasad` from server into `/rails/hasad` in container

### Step 3: Verify Setup

Verify hasad is accessible in the container:
```bash
bin/kamal app exec -d contabo "ls -la /rails/hasad"
```

You should see the hasad directory structure with NDJSON files.

### Step 4: Run Initial Import

Import existing hasad data into the database:
```bash
bin/kamal app exec -d contabo "rake hasad:import"
```

Check that data was imported:
```bash
bin/kamal app exec -d contabo "bin/rails runner 'puts \"Articles: #{Article.count}, Authors: #{Author.count}\"'"
```

---

## Daily Usage Workflow

### When You Scrape New Data

1. **Run scrapers locally:**
   ```bash
   cd fallah
   scrapy crawl metras
   scrapy crawl qudsn_co
   ```

2. **Commit and push to GitHub:**
   ```bash
   cd ../hasad
   git add .
   git commit -m "New scrape: $(date '+%Y-%m-%d %H:%M')"
   git push
   ```

3. **Sync to production and import:**
   ```bash
   cd ../bisan
   ./sync_hasad.sh
   ```

That's it! The `sync_hasad.sh` script will:
- Pull latest data from GitHub on the production server
- Run the import job via Kamal
- Show you the results

---

## Manual Operations

### Pull Latest Hasad Data (Without Import)

```bash
ssh -i ~/bisan root@185.185.82.142 "cd /root/hasad && git pull"
```

### Run Import Job Manually

```bash
cd bisan
bin/kamal app exec -d contabo "rake hasad:import"
```

### Check Database Counts

```bash
bin/kamal app exec -d contabo "bin/rails runner 'puts \"Articles: #{Article.count}, Authors: #{Author.count}\"'"
```

### SSH into Production Server

```bash
ssh -i ~/bisan root@185.185.82.142
```

### Access Rails Console on Production

```bash
cd bisan
bin/kamal console -d contabo
```

---

## How It Works

### HasadImportJob

The `HasadImportJob` (at `app/jobs/hasad_import_job.rb`):

1. Scans `/rails/hasad/**/*.ndjson` for all NDJSON files
2. Reads each line as JSON
3. Determines record type (article or author)
4. Batch inserts/updates records
5. Updates article counts for authors

**Key Features:**
- Processes 1,000 records per batch
- Prevents duplicates (authors by name, articles by source_url)
- Handles both local and production environments
- Automatic content hashing for duplicate detection

### Fallah Pipeline

The `ArticlesJsonlPipeline` (at `fallah/fallah/pipelines.py`):

1. Receives scraped items from Scrapy spiders
2. Writes each item as a JSON line to appropriate file
3. File structure: `{EXPORT_BASE}/{source_name}/{type}/parsed.ndjson`
4. Example: `hasad/metras/article/parsed.ndjson`

### Hasad Repository Structure

```
hasad/
├── metras/
│   ├── article/
│   │   └── parsed.ndjson
│   └── author/
│       └── parsed.ndjson
└── qudsn.co/
    ├── article/
    │   └── parsed.ndjson
    └── author/
        └── parsed.ndjson
```

---

## Troubleshooting

### Problem: Import job fails with "HASAD_ROOT not found"

**Solution:** The volume mount might not be working. Verify:
```bash
bin/kamal app exec -d contabo "ls -la /rails/hasad"
```

If empty, redeploy:
```bash
bin/kamal deploy -d contabo
```

### Problem: No data after import

**Check 1:** Verify NDJSON files exist on server:
```bash
ssh -i ~/bisan root@185.185.82.142 "find /root/hasad -name '*.ndjson' -type f"
```

**Check 2:** Run import with verbose output:
```bash
bin/kamal app exec -d contabo "rake hasad:import"
```

Look for lines like:
```
[HasadImport] Root=/rails/hasad ndjson_files=4
[HasadImport] <= /rails/hasad/metras/article/parsed.ndjson
[HasadImport] DONE authors_inserted≈15 articles_inserted≈237
```

### Problem: Git pull fails on production

**Solution:** SSH key might not be configured. Re-run Step 1 of the setup.

Verify SSH key works:
```bash
ssh -i ~/bisan root@185.185.82.142 "ssh -T git@github.com-hasad"
```

Should say: "Hi Muntaser-Abukhadijah! You've successfully authenticated..."

### Problem: sync_hasad.sh fails

**Check permissions:**
```bash
ls -la bisan/sync_hasad.sh
```

Should show: `-rwxr-xr-x` (executable)

If not:
```bash
chmod +x bisan/sync_hasad.sh
```

---

## Environment Details

### Production Server
- **IP:** 185.185.82.142
- **SSH Key:** `~/bisan`
- **Hasad Location:** `/root/hasad`
- **Container Path:** `/rails/hasad`

### Repository URLs
- **Bisan:** (Your bisan repo URL)
- **Fallah:** (Your fallah repo URL)
- **Hasad:** https://github.com/Muntaser-Abukhadijah/hasad

### Kamal Configuration
- **Service:** bisan
- **Image:** abukhadijah/bisan
- **Deployment:** `-d contabo` flag for Contabo server

---

## Next Steps

### Automating the Pipeline

Currently, you manually run scrapers and sync. To automate:

1. **Schedule scrapers:** Run fallah on a cron job or GitHub Actions
2. **Auto-import:** Add to `config/recurring.yml`:
   ```yaml
   hasad_sync:
     class: HasadImportJob
     schedule: every 4 hours
   ```

3. **Monitoring:** Add logging/alerting for failed imports

### Scaling

If data grows large:
- Move from SQLite to PostgreSQL
- Add job server (separate from web server)
- Implement incremental imports (track last processed file)

---

## Support

For issues or questions:
1. Check this guide first
2. Review logs: `bin/kamal logs -d contabo`
3. SSH into server to debug manually
