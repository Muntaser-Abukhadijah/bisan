# Hasad Data Lake Implementation: Detailed Task Breakdown

## Overview

This document provides a **sequential, ordered task breakdown** for implementing the Hasad Data Lake architecture on Contabo VPS. Follow these tasks in order, checking off each as you complete it.

**Estimated Total Time:** 3-4 weeks (part-time work)  
**Team Size:** 1-2 developers  
**Risk Level:** Low (parallel run minimizes downtime)

---

## Phase 1: Hasad Infrastructure Setup (Week 1)

**Goal:** Deploy Hasad Data Lake infrastructure on Contabo VPS

### Day 1: Environment Preparation

- [ ] **Task 1.1:** SSH into Contabo VPS
  ```bash
  ssh root@185.185.82.142
  ```
  - Verify Docker installed: `docker --version`
  - Verify Docker Compose installed: `docker-compose --version`
  - Check available disk space: `df -h` (need 20GB+)
  - Check available RAM: `free -h` (need 2GB+ free)

- [ ] **Task 1.2:** Create Hasad directory structure
  ```bash
  mkdir -p ~/hasad
  cd ~/hasad
  mkdir -p backups
  ```

- [ ] **Task 1.3:** Generate secure passwords
  ```bash
  # Generate and save passwords
  POSTGRES_PASSWORD=$(openssl rand -base64 32)
  MINIO_ROOT_PASSWORD=$(openssl rand -base64 32)
  
  # Create .env file
  cat > .env << EOF
  POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
  MINIO_ROOT_USER=minioadmin
  MINIO_ROOT_PASSWORD=${MINIO_ROOT_PASSWORD}
  EOF
  
  # Save passwords securely
  echo "Save these passwords in your password manager:"
  cat .env
  ```

### Day 2: Docker Compose Configuration

- [ ] **Task 1.4:** Create docker-compose.yml
  - Copy content from HASAD_IMPLEMENTATION_GUIDE.md
  - Save to `~/hasad/docker-compose.yml`
  - Verify YAML syntax: `docker-compose config`

- [ ] **Task 1.5:** Create PostgreSQL init script
  - Copy SQL schema from HASAD_IMPLEMENTATION_GUIDE.md
  - Save to `~/hasad/init-db.sql`
  - Verify SQL syntax: `cat init-db.sql` (visual check)

- [ ] **Task 1.6:** Start PostgreSQL and MinIO only (test infrastructure)
  ```bash
  # Start just database and storage
  docker-compose up -d postgres minio
  
  # Wait 30 seconds for startup
  sleep 30
  
  # Check status
  docker-compose ps
  docker-compose logs postgres
  docker-compose logs minio
  ```

- [ ] **Task 1.7:** Verify PostgreSQL
  ```bash
  # Connect to database
  docker exec -it hasad-postgres psql -U hasad -d hasad
  
  # Inside psql:
  \dt  # List tables (should see content_metadata, etc.)
  \q   # Quit
  ```
  - Expected: 4 tables created (content_metadata, content_versions, sync_checkpoints, content_audit_log)

- [ ] **Task 1.8:** Verify MinIO
  - Open browser: `http://185.185.82.142:9001`
  - Login with credentials from `.env`
  - Create bucket manually: `hasad-content`
  - Verify bucket created successfully

### Day 3: Fallah Docker Setup

- [ ] **Task 1.9:** Create Fallah directory
  ```bash
  mkdir -p ~/hasad/fallah
  cd ~/hasad/fallah
  ```

- [ ] **Task 1.10:** Create Fallah requirements.txt
  ```bash
  cat > requirements.txt << 'EOF'
  scrapy>=2.11.0
  psycopg2-binary>=2.9.9
  minio>=7.2.0
  EOF
  ```

- [ ] **Task 1.11:** Create Fallah Dockerfile
  - Copy from HASAD_IMPLEMENTATION_GUIDE.md
  - Save to `~/hasad/fallah/Dockerfile`

- [ ] **Task 1.12:** Copy Fallah code from local machine
  ```bash
  # From your local machine:
  cd /path/to/local/fallah
  
  # Copy all Fallah files to server
  scp -r * root@185.185.82.142:~/hasad/fallah/
  
  # Verify on server:
  ssh root@185.185.82.142
  ls -la ~/hasad/fallah/
  ```
  - Expected: scrapy.cfg, fallah/ directory with spiders, etc.

### Day 4: Fallah Pipeline Implementation

- [ ] **Task 1.13:** Create HasadDataLakePipeline
  ```bash
  # On server:
  cd ~/hasad/fallah/fallah
  
  # Create pipelines.py with HasadDataLakePipeline
  # Copy code from HASAD_DATA_LAKE_DESIGN.md
  nano pipelines.py
  ```

- [ ] **Task 1.14:** Update Fallah settings.py
  ```python
  # Edit settings.py
  nano settings.py
  
  # Add/update these lines:
  MINIO_ENDPOINT = 'minio:9000'
  POSTGRES_DSN = 'host=postgres dbname=hasad user=hasad password=hasad_password'
  
  ITEM_PIPELINES = {
      'fallah.pipelines.HasadDataLakePipeline': 300,
  }
  
  # Comment out old EXPORT_BASE if exists
  # EXPORT_BASE = "..."
  ```

- [ ] **Task 1.15:** Test Fallah build (without running)
  ```bash
  cd ~/hasad
  docker-compose build fallah
  ```
  - Expected: Build succeeds without errors
  - If build fails, check Dockerfile and requirements.txt

### Day 5: Integration Testing

- [ ] **Task 1.16:** Start complete Hasad stack
  ```bash
  cd ~/hasad
  docker-compose up -d
  
  # Check all containers running
  docker-compose ps
  ```
  - Expected: 3 containers running (postgres, minio, fallah)

- [ ] **Task 1.17:** Test Fallah scraping manually
  ```bash
  # Run metras spider once
  docker exec -it hasad-fallah scrapy crawl metras -s CLOSESPIDER_ITEMCOUNT=5
  ```
  - Expected: Spider runs, scrapes 5 items, exits cleanly

- [ ] **Task 1.18:** Verify data in PostgreSQL
  ```bash
  docker exec hasad-postgres psql -U hasad -d hasad -c \
    "SELECT id, source_name, content_type, title FROM content_metadata ORDER BY id DESC LIMIT 5;"
  ```
  - Expected: See 5 recent articles from metras

- [ ] **Task 1.19:** Verify objects in MinIO
  - Open browser: `http://185.185.82.142:9001`
  - Navigate to `hasad-content` bucket
  - Check `v2/metras/article/` directory
  - Expected: See JSON files with hash names

- [ ] **Task 1.20:** Check Fallah cron logs
  ```bash
  # Wait for next cron run (*/30 * * * *)
  # Or manually trigger:
  docker exec hasad-fallah /bin/sh -c "cd /app && scrapy crawl metras"
  
  # Check cron logs
  docker exec hasad-fallah cat /var/log/cron.log
  ```
  - Expected: Cron runs every 30 minutes, logs show executions

### Day 6-7: Monitoring & Documentation

- [ ] **Task 1.21:** Create monitoring script
  ```bash
  cat > ~/hasad/check-health.sh << 'EOF'
  #!/bin/bash
  echo "=== Hasad Health Check ==="
  echo ""
  echo "Containers:"
  docker-compose ps
  echo ""
  echo "Disk Usage:"
  df -h | grep -E '(Filesystem|/dev/root)'
  echo ""
  echo "Recent Content:"
  docker exec hasad-postgres psql -U hasad -d hasad -t -c \
    "SELECT COUNT(*), source_name FROM content_metadata 
     WHERE scraped_at > NOW() - INTERVAL '24 hours' 
     GROUP BY source_name;"
  EOF
  
  chmod +x ~/hasad/check-health.sh
  ```

- [ ] **Task 1.22:** Test health check script
  ```bash
  ~/hasad/check-health.sh
  ```

- [ ] **Task 1.23:** Document deployment for team
  - Create `~/hasad/DEPLOYMENT_NOTES.md`
  - Include:
    - Server IP and credentials location
    - Docker commands to start/stop
    - How to check logs
    - Emergency contacts

---

## Phase 2: Bisan Integration (Week 2)

**Goal:** Configure Bisan to sync from Hasad Data Lake

### Day 8: Bisan Dependencies

- [ ] **Task 2.1:** SSH into Bisan server (104.248.18.215 or Contabo)
  ```bash
  ssh root@104.248.18.215  # Or 185.185.82.142 if on same server
  cd /path/to/bisan
  ```

- [ ] **Task 2.2:** Update Gemfile
  ```ruby
  # Add to Gemfile
  gem 'pg'
  gem 'aws-sdk-s3'  # For MinIO compatibility
  ```

- [ ] **Task 2.3:** Install dependencies
  ```bash
  bundle install
  ```
  - If errors, check Ruby version: `ruby -v` (need 3.2+)

### Day 9: HasadSyncer Implementation

- [ ] **Task 2.4:** Create lib/hasad_syncer.rb
  - Copy full code from HASAD_DATA_LAKE_DESIGN.md
  - Save to `lib/hasad_syncer.rb`

- [ ] **Task 2.5:** Create rake task
  - Create `lib/tasks/sync_from_hasad.rake`
  - Copy code from HASAD_DATA_LAKE_DESIGN.md

- [ ] **Task 2.6:** Add environment variables
  ```bash
  # Edit .env
  nano .env
  
  # Add these lines (get passwords from Hasad server):
  HASAD_PG_HOST=185.185.82.142
  HASAD_PG_DB=hasad
  HASAD_PG_USER=hasad
  HASAD_PG_PASSWORD=<from hasad/.env>
  HASAD_MINIO_ENDPOINT=185.185.82.142:9000
  HASAD_MINIO_ACCESS_KEY=minioadmin
  HASAD_MINIO_SECRET_KEY=<from hasad/.env>
  ```

### Day 10: Connection Testing

- [ ] **Task 2.7:** Test PostgreSQL connection from Bisan
  ```bash
  # From Bisan server:
  psql -h 185.185.82.142 -U hasad -d hasad -c "SELECT COUNT(*) FROM content_metadata;"
  ```
  - If fails, check firewall: `sudo ufw allow 5432/tcp` on Hasad server

- [ ] **Task 2.8:** Test MinIO connection from Bisan
  ```bash
  # Install aws-cli for testing
  curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
  unzip awscliv2.zip
  sudo ./aws/install
  
  # Configure for MinIO
  aws configure set aws_access_key_id minioadmin
  aws configure set aws_secret_access_key <from hasad/.env>
  aws configure set region us-east-1
  
  # Test list buckets
  aws --endpoint-url http://185.185.82.142:9000 s3 ls
  ```
  - Expected: See `hasad-content` bucket
  - If fails, check firewall: `sudo ufw allow 9000/tcp` on Hasad server

- [ ] **Task 2.9:** Test HasadSyncer (dry run)
  ```bash
  # From Bisan directory:
  bin/rails console
  
  # In console:
  syncer = HasadSyncer.new
  syncer.send(:get_checkpoint)  # Should return 0
  items = syncer.send(:fetch_new_content, 0)  # Get first batch
  puts "Found #{items.count} items"
  exit
  ```

### Day 11: First Full Sync

- [ ] **Task 2.10:** Create checkpoint at 0
  ```bash
  # Set checkpoint to start from beginning
  ssh root@185.185.82.142
  docker exec hasad-postgres psql -U hasad -d hasad -c \
    "INSERT INTO sync_checkpoints (consumer_name, last_processed_id, last_sync_at) 
     VALUES ('bisan', 0, NOW());"
  ```

- [ ] **Task 2.11:** Run manual sync (first time)
  ```bash
  # From Bisan server:
  cd /path/to/bisan
  
  # Run with logging
  bin/rails hasad:sync 2>&1 | tee log/hasad_sync_first.log
  ```
  - This may take 10-30 minutes depending on data volume
  - Watch for errors in log

- [ ] **Task 2.12:** Verify sync results
  ```bash
  # Check article count
  bin/rails runner "puts 'Articles: ' + Article.count.to_s"
  bin/rails runner "puts 'Authors: ' + Author.count.to_s"
  
  # Compare with Hasad
  ssh root@185.185.82.142 \
    docker exec hasad-postgres psql -U hasad -d hasad -t -c \
    "SELECT COUNT(*) FROM content_metadata WHERE status='active';"
  ```
  - Counts should match (±few items if scraping is ongoing)

- [ ] **Task 2.13:** Verify Meilisearch indexed
  ```bash
  # Check Meilisearch
  curl http://localhost:7700/indexes/articles/stats \
    -H "Authorization: Bearer <meili-key>"
  ```
  - Expected: numberOfDocuments matches Article.count

### Day 12: Cron Setup

- [ ] **Task 2.14:** Setup cron job for continuous sync
  ```bash
  # On Bisan server:
  crontab -e
  
  # Add this line:
  */30 * * * * cd /path/to/bisan && bin/rails hasad:sync >> log/hasad_sync.log 2>&1
  
  # Save and exit
  ```

- [ ] **Task 2.15:** Verify cron job registered
  ```bash
  crontab -l | grep hasad
  ```

- [ ] **Task 2.16:** Wait for next cron run and verify
  ```bash
  # Wait 30 minutes, then check:
  tail -n 50 log/hasad_sync.log
  ```
  - Expected: See sync completed with 0-N new items

### Day 13-14: Parallel Run Monitoring

- [ ] **Task 2.17:** Enable parallel run
  - Hasad scrapes and stores to data lake ✓
  - Bisan syncs from Hasad every 30 min ✓
  - OLD system still active (reading old NDJSON files)
  - Keep both running for 1-2 weeks

- [ ] **Task 2.18:** Create comparison script
  ```bash
  cat > ~/compare-systems.sh << 'EOF'
  #!/bin/bash
  echo "=== System Comparison ==="
  echo ""
  echo "Hasad (new):"
  ssh root@185.185.82.142 \
    docker exec hasad-postgres psql -U hasad -d hasad -t -c \
    "SELECT COUNT(*) FROM content_metadata WHERE status='active';"
  echo ""
  echo "Bisan articles:"
  cd /path/to/bisan && bin/rails runner "puts Article.count"
  echo ""
  echo "Last sync:"
  tail -n 1 /path/to/bisan/log/hasad_sync.log
  EOF
  
  chmod +x ~/compare-systems.sh
  ```

- [ ] **Task 2.19:** Run daily comparisons
  - Run `~/compare-systems.sh` once per day
  - Document any discrepancies
  - Investigate and fix issues

- [ ] **Task 2.20:** Monitor for issues
  - Check logs daily: `tail -f /path/to/bisan/log/hasad_sync.log`
  - Check Hasad health: `ssh root@185.185.82.142 ~/hasad/check-health.sh`
  - Verify no errors in Fallah: `docker logs hasad-fallah | grep -i error`

---

## Phase 3: Cutover & Decommission (Week 3-4)

**Goal:** Switch fully to new system and remove old infrastructure

### Day 15-20: Validation Period

- [ ] **Task 3.1:** Validate data consistency
  ```bash
  # Run comprehensive comparison
  ~/compare-systems.sh
  
  # Check for missing articles
  bin/rails runner "
    missing = Article.where('ingested_at IS NULL')
    puts \"Missing ingested_at: #{missing.count}\"
    puts missing.pluck(:id, :title).first(10)
  "
  ```

- [ ] **Task 3.2:** Performance testing
  ```bash
  # Measure sync time
  time bin/rails hasad:sync
  ```
  - Should complete in <5 minutes for incremental sync
  - Should complete in <30 minutes for full re-sync

- [ ] **Task 3.3:** Test failure scenarios
  ```bash
  # Stop PostgreSQL temporarily
  ssh root@185.185.82.142
  docker-compose stop postgres
  
  # Try sync (should fail gracefully)
  bin/rails hasad:sync
  
  # Restart
  docker-compose start postgres
  
  # Verify recovery
  bin/rails hasad:sync
  ```

- [ ] **Task 3.4:** Load testing
  - Manually trigger Fallah to scrape multiple sites
  - Verify Bisan handles backlog
  ```bash
  # Trigger multiple scrapes
  docker exec hasad-fallah scrapy crawl metras
  docker exec hasad-fallah scrapy crawl qudsn_co
  
  # Wait 30 min, check sync
  tail -f /path/to/bisan/log/hasad_sync.log
  ```

- [ ] **Task 3.5:** Stakeholder sign-off
  - Demo new system to team
  - Show monitoring dashboards
  - Get approval to proceed with cutover

### Day 21: Cutover

- [ ] **Task 3.6:** Announce maintenance window
  - Notify users: "System will be read-only for 1 hour"
  - Schedule during low-traffic period

- [ ] **Task 3.7:** Final sync from old system
  ```bash
  # If old system still writing, do final import
  bin/rails hasad:import  # Old rake task
  ```

- [ ] **Task 3.8:** Disable old import job
  ```bash
  crontab -e
  # Comment out old hasad:import job
  # */30 * * * * cd /path/to/bisan && bin/rails hasad:import...
  ```

- [ ] **Task 3.9:** Final Hasad sync
  ```bash
  bin/rails hasad:sync
  ```

- [ ] **Task 3.10:** Verify everything working
  - Check website loads: `curl http://your-domain.com`
  - Check search working
  - Check articles display correctly
  - Check author pages working

- [ ] **Task 3.11:** Announce completion
  - Notify users: "Maintenance complete, system restored"

### Day 22-23: Decommissioning

- [ ] **Task 3.12:** Archive old NDJSON files
  ```bash
  # On Hasad server (or wherever NDJSON files are):
  cd ~/hasad
  mkdir -p legacy
  mv /path/to/old/hasad/* legacy/
  
  # Create archive
  tar -czf legacy-ndjson-$(date +%Y%m%d).tar.gz legacy/
  
  # Move to secure backup location
  mv legacy-ndjson-*.tar.gz ~/backups/
  ```

- [ ] **Task 3.13:** Remove old Fallah pipeline code
  ```bash
  cd ~/hasad/fallah/fallah
  
  # Backup first
  cp pipelines.py pipelines.py.backup
  
  # Edit pipelines.py
  nano pipelines.py
  
  # Remove ArticlesJsonlPipeline class (if exists)
  # Keep only HasadDataLakePipeline
  ```

- [ ] **Task 3.14:** Update Fallah settings
  ```python
  # Remove old EXPORT_BASE completely
  # Ensure only HasadDataLakePipeline in ITEM_PIPELINES
  ```

- [ ] **Task 3.15:** Rebuild Fallah container
  ```bash
  cd ~/hasad
  docker-compose build fallah
  docker-compose up -d fallah
  ```

- [ ] **Task 3.16:** Remove old Bisan code
  ```bash
  cd /path/to/bisan
  
  # Backup first
  git add -A
  git commit -m "Backup before removing old import code"
  
  # Remove old files
  rm app/jobs/hasad_import_job.rb
  rm lib/tasks/hasad_import.rake
  
  # Remove old ingestion services if not used
  # rm -rf app/services/ingestion/  # Only if not needed
  ```

- [ ] **Task 3.17:** Commit changes
  ```bash
  git add -A
  git commit -m "Remove old NDJSON import system, fully using Hasad Data Lake"
  git push origin main
  ```

### Day 24-28: Post-Cutover Monitoring

- [ ] **Task 3.18:** Daily health checks
  ```bash
  # Run daily for one week
  ~/hasad/check-health.sh
  ~/compare-systems.sh  # Compare with archived counts
  ```

- [ ] **Task 3.19:** Monitor logs for errors
  ```bash
  # Check Fallah
  docker logs hasad-fallah --tail 100 | grep -i error
  
  # Check Bisan sync
  tail -n 100 /path/to/bisan/log/hasad_sync.log | grep -i error
  
  # Check PostgreSQL
  docker logs hasad-postgres --tail 100 | grep -i error
  ```

- [ ] **Task 3.20:** Performance monitoring
  - Measure average sync time
  - Measure Hasad disk usage growth
  - Measure database size growth

- [ ] **Task 3.21:** User feedback collection
  - Ask users if they notice any issues
  - Check if search results are accurate
  - Verify new articles appearing correctly

- [ ] **Task 3.22:** Create incident response plan
  ```markdown
  # Hasad Incident Response
  
  ## If Fallah stops scraping:
  1. Check docker logs: docker logs hasad-fallah
  2. Check cron: docker exec hasad-fallah cat /var/log/cron.log
  3. Manual trigger: docker exec hasad-fallah scrapy crawl metras
  
  ## If Bisan sync fails:
  1. Check logs: tail -f /path/to/bisan/log/hasad_sync.log
  2. Test connection: psql -h 185.185.82.142 -U hasad
  3. Manual sync: bin/rails hasad:sync
  
  ## If data missing:
  1. Check Hasad: docker exec hasad-postgres psql -U hasad -d hasad
  2. Check checkpoint: SELECT * FROM sync_checkpoints;
  3. Reset checkpoint if needed
  ```

---

## Phase 4: Optimization & Documentation (Ongoing)

### Week 4+: Continuous Improvement

- [ ] **Task 4.1:** Setup automated backups
  ```bash
  # Create backup script
  cat > ~/hasad/backup.sh << 'EOF'
  #!/bin/bash
  DATE=$(date +%Y%m%d)
  
  # Backup PostgreSQL
  docker exec hasad-postgres pg_dump -U hasad hasad | \
    gzip > ~/backups/hasad-${DATE}.sql.gz
  
  # Backup MinIO (sync to external storage)
  # TODO: Configure external backup location
  
  # Cleanup old backups (keep 30 days)
  find ~/backups -name "hasad-*.sql.gz" -mtime +30 -delete
  EOF
  
  chmod +x ~/hasad/backup.sh
  
  # Add to cron (daily at 2 AM)
  (crontab -l; echo "0 2 * * * ~/hasad/backup.sh") | crontab -
  ```

- [ ] **Task 4.2:** Setup monitoring alerts (optional)
  - Consider setting up email alerts for:
    - Disk space >80%
    - No new content in 24 hours
    - Sync failures

- [ ] **Task 4.3:** Document for team
  - Share HASAD_DATA_LAKE_DESIGN.md
  - Share HASAD_IMPLEMENTATION_GUIDE.md
  - Create runbook for common operations
  - Train team members on new system

- [ ] **Task 4.4:** Performance tuning
  - Tune PostgreSQL based on actual usage
  - Adjust sync frequency if needed (30min → 15min?)
  - Optimize Bisan sync batch size

- [ ] **Task 4.5:** Plan future enhancements
  - Images support?
  - Audio/podcast support?
  - Analytics consumer?
  - Mobile API?

---

## Summary Checklist

### Phase 1: Infrastructure (Week 1)
- [ ] All 23 tasks completed
- [ ] Hasad running on Contabo
- [ ] Fallah scraping to data lake
- [ ] Data visible in PostgreSQL & MinIO

### Phase 2: Bisan Integration (Week 2)
- [ ] All 20 tasks completed
- [ ] Bisan syncing from Hasad
- [ ] Cron job running every 30 minutes
- [ ] Parallel run with old system

### Phase 3: Cutover (Week 3-4)
- [ ] All 22 tasks completed
- [ ] Old system decommissioned
- [ ] New system fully operational
- [ ] No data loss, no downtime

### Phase 4: Ongoing
- [ ] Backups configured
- [ ] Team trained
- [ ] Documentation complete
- [ ] Monitoring in place

---

## Emergency Rollback Procedure

If critical issues arise during Phase 3:

1. **Stop Hasad sync:**
   ```bash
   crontab -e
   # Comment out: */30 * * * * ... hasad:sync
   ```

2. **Re-enable old system:**
   ```bash
   crontab -e
   # Uncomment: */30 * * * * ... hasad:import
   ```

3. **Verify old system working:**
   ```bash
   bin/rails hasad:import
   ```

4. **Investigate issues:**
   - Check logs
   - Run diagnostics
   - Fix problems

5. **Retry cutover when ready**

---

## Success Criteria

✅ **System is successful when:**
- Fallah scrapes reliably (>95% uptime)
- Bisan syncs within 10 minutes of new content
- No data loss or corruption
- Search results are accurate
- Team can operate system independently
- Monitoring shows healthy metrics

---

## Support & Resources

- Architecture: HASAD_DATA_LAKE_DESIGN.md
- Implementation: HASAD_IMPLEMENTATION_GUIDE.md
- This task list: HASAD_IMPLEMENTATION_TASKS.md
- Fallah docs: ~/hasad/fallah/README.md (if exists)
- Bisan docs: /path/to/bisan/README.md

**Questions?** Review docs or check troubleshooting sections.
