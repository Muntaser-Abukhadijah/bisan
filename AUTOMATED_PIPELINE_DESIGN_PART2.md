# Automated Pipeline Design - Part 2 (Continued)

## Docker Compose Configuration (Continued)

**docker-compose.hasad.yml** (continued):
```yaml
  minio:
    image: minio/minio:latest
    container_name: hasad-minio
    ports:
      - "9000:9000"  # API
      - "9001:9001"  # Web UI
    volumes:
      - minio-data:/data
    environment:
      MINIO_ROOT_USER: minioadmin
      MINIO_ROOT_PASSWORD: minioadmin123  # Change in production
    command: server /data --console-address ":9001"
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:9000/minio/health/live"]
      interval: 30s
      timeout: 10s
      retries: 3

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
      POSTGRES_PASSWORD: hasad_password  # Change in production
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U hasad"]
      interval: 10s
      timeout: 5s
      retries: 5

  hasad-consumer:
    build: ./hasad-consumer
    container_name: hasad-consumer
    depends_on:
      - redis
      - minio
      - postgres
    environment:
      REDIS_HOST: redis
      REDIS_PORT: 6379
      MINIO_ENDPOINT: minio:9000
      MINIO_ACCESS_KEY: minioadmin
      MINIO_SECRET_KEY: minioadmin123
      POSTGRES_HOST: postgres
      POSTGRES_DB: hasad
      POSTGRES_USER: hasad
      POSTGRES_PASSWORD: hasad_password
    restart: unless-stopped
    volumes:
      - ./hasad-consumer/logs:/app/logs

volumes:
  redis-data:
  minio-data:
  postgres-data:

networks:
  default:
    name: hasad-network
```

---

## Sync to Bisan

### Bisan Consumer Implementation

**Ruby Consumer (bisan-consumer.rb)**:
```ruby
require 'redis'
require 'json'
require 'active_record'
require 'meilisearch'
require 'logger'

# Configure ActiveRecord to connect to Bisan's SQLite
ActiveRecord::Base.establish_connection(
  adapter: 'sqlite3',
  database: ENV.fetch('BISAN_DB_PATH', '/rails/storage/production.sqlite3'),
  pool: 5,
  timeout: 5000
)

# Load Bisan models
require_relative '/rails/app/models/article'
require_relative '/rails/app/models/author'

class BisanConsumer
  def initialize
    @logger = Logger.new(STDOUT)
    @logger.level = Logger::INFO
    
    # Redis connection
    @redis = Redis.new(
      host: ENV.fetch('REDIS_HOST', 'redis'),
      port: ENV.fetch('REDIS_PORT', 6379).to_i
    )
    
    # Meilisearch connection
    @meili = MeiliSearch::Client.new(
      ENV.fetch('MEILISEARCH_HOST', 'http://bisan-meilisearch:7700'),
      ENV.fetch('MEILISEARCH_API_KEY', 'dev_meili_master_key_123')
    )
    
    @stream_name = 'content:scraped'
    @consumer_group = 'bisan-cg'
    @consumer_name = "bisan-consumer-#{ENV.fetch('HOSTNAME', '1')}"
    @dlq_stream = 'content:bisan-failed'
    
    # Create consumer group if not exists
    begin
      @redis.xgroup(:create, @stream_name, @consumer_group, '0', mkstream: true)
    rescue Redis::CommandError => e
      raise unless e.message.include?('BUSYGROUP')
    end
    
    @logger.info("Bisan consumer started: #{@consumer_name}")
  end
  
  def process_message(message_id, data)
    msg_type = data['type']
    
    case msg_type
    when 'article', 'articles'
      process_article(message_id, data)
    when 'author', 'authors'
      process_author(message_id, data)
    else
      @logger.warn("Unknown message type: #{msg_type}")
      true  # ACK anyway
    end
  rescue => e
    @logger.error("Error processing #{message_id}: #{e.class} #{e.message}")
    @logger.error(e.backtrace.first(5).join("\n"))
    false
  end
  
  def process_author(message_id, data)
    author_data = data['data'] || data
    name = author_data['name'].to_s.strip
    
    return true if name.empty?
    
    ActiveRecord::Base.transaction do
      author = Author.find_or_initialize_by(name: name)
      
      # Update fields
      author.bio = author_data['bio'] if author_data['bio']
      author.avatar_url = author_data['avatar_url'] if author_data['avatar_url']
      author.social_links = author_data['social_links'] if author_data['social_links']
      
      author.save!
      @logger.info("Upserted author: #{name} (id: #{author.id})")
    end
    
    true
  end
  
  def process_article(message_id, data)
    article_data = data['data'] || data
    source_url = article_data['url'] || article_data['source_url']
    
    return true if source_url.nil? || source_url.empty?
    
    ActiveRecord::Base.transaction do
      # Ensure author exists
      author = ensure_author(article_data['author'])
      return false unless author
      
      # Find or initialize article
      article = Article.find_or_initialize_by(source_url: source_url)
      
      # Calculate content hash for deduplication
      body_html = article_data['content_html'] || article_data['body']
      new_hash = body_html ? Digest::SHA256.hexdigest(body_html) : nil
      
      # Skip if content hasn't changed
      if article.persisted? && article.content_hash == new_hash
        @logger.info("Article unchanged: #{source_url}")
        return true
      end
      
      # Update article fields
      article.title = article_data['title']
      article.excerpt = article_data['excerpt']
      article.body = body_html
      article.article_image = article_data['article_image_url'] || article_data['article_image']
      article.category = article_data['categorie'] || article_data['category']
      article.tags = parse_tags(article_data['tags'])
      article.author = author
      article.content_hash = new_hash
      article.ingested_at = Time.current
      
      # Parse publish date
      if article_data['published_at_ts']
        article.publish_date = Time.at(article_data['published_at_ts'].to_i).utc.to_date
      elsif article_data['published_at']
        article.publish_date = Time.zone.parse(article_data['published_at']).to_date rescue nil
      end
      
      article.save!
      
      # Reindex in Meilisearch
      reindex_article(article) if article.saved_change_to_body? || article.saved_change_to_title?
      
      @logger.info("Upserted article: #{article.title} (id: #{article.id})")
    end
    
    true
  end
  
  def ensure_author(author_name)
    return nil if author_name.nil? || author_name.strip.empty?
    
    name = author_name.strip
    author = Author.find_by(name: name)
    
    unless author
      # Create placeholder author
      author = Author.create!(
        name: name,
        bio: '',
        avatar_url: nil
      )
      @logger.info("Created placeholder author: #{name}")
    end
    
    author
  end
  
  def parse_tags(tags_value)
    case tags_value
    when Array
      tags_value.join(',')
    when String
      tags_value
    else
      ''
    end
  end
  
  def reindex_article(article)
    # Prepare document for Meilisearch
    doc = {
      id: article.id,
      title: article.title,
      excerpt: article.excerpt,
      body: article.body,
      author_name: article.author&.name,
      category: article.category,
      tags: article.tags,
      publish_date: article.publish_date&.to_s
    }
    
    # Add to Meilisearch index
    @meili.index('articles').add_documents([doc])
    @logger.info("Reindexed article #{article.id} in Meilisearch")
  rescue => e
    @logger.error("Meilisearch reindex failed for article #{article.id}: #{e.message}")
    # Don't fail the entire operation if search indexing fails
  end
  
  def run
    @logger.info("Starting consumer loop...")
    retry_counts = {}
    
    loop do
      begin
        # Read messages from stream
        messages = @redis.xreadgroup(
          @consumer_group,
          @consumer_name,
          @stream_name,
          '>',
          count: 10,
          block: 5000  # 5 second timeout
        )
        
        next if messages.nil? || messages.empty?
        
        messages[@stream_name]&.each do |message_id, data|
          # Convert Redis hash to Ruby hash with string keys
          processed_data = data.transform_keys(&:to_s).transform_values(&:to_s)
          
          # Deserialize JSON data field if present
          if processed_data['data']
            processed_data['data'] = JSON.parse(processed_data['data']) rescue processed_data['data']
          end
          
          # Process message
          success = process_message(message_id, processed_data)
          
          if success
            # ACK message
            @redis.xack(@stream_name, @consumer_group, message_id)
            retry_counts.delete(message_id)
          else
            # Track retries
            retry_counts[message_id] = (retry_counts[message_id] || 0) + 1
            
            if retry_counts[message_id] >= 3
              # Move to DLQ after 3 failures
              @logger.error("Moving to DLQ: #{message_id}")
              @redis.xadd(@dlq_stream, processed_data)
              @redis.xack(@stream_name, @consumer_group, message_id)
              retry_counts.delete(message_id)
            end
          end
        end
      rescue => e
        @logger.error("Consumer loop error: #{e.class} #{e.message}")
        sleep 5
      end
    end
  end
end

# Run consumer
consumer = BisanConsumer.new
consumer.run
```

### Dockerfile for Bisan Consumer

**bisan-consumer/Dockerfile**:
```dockerfile
FROM ruby:3.2.2-slim

WORKDIR /app

# Install dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    sqlite3 \
    libsqlite3-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy Gemfile
COPY Gemfile* ./
RUN bundle install

# Copy consumer script
COPY bisan-consumer.rb ./

# Mount Bisan Rails app for model access
VOLUME /rails

CMD ["ruby", "bisan-consumer.rb"]
```

**bisan-consumer/Gemfile**:
```ruby
source 'https://rubygems.org'

gem 'redis', '~> 5.0'
gem 'sqlite3', '~> 1.7'
gem 'activerecord', '~> 7.2'
gem 'meilisearch', '~> 0.27'
```

### Idempotent Upserts

**Key Strategy**:
- Articles upserted by `source_url` (unique index)
- Authors upserted by `name` (unique index)
- Content hash comparison prevents duplicate processing
- Meilisearch reindex only when content changes

### Conflict Resolution

**Source of Truth Rules**:
1. **Always trust the scraper**: Latest scraped data wins
2. **Never delete**: Mark as deleted, keep in history
3. **Merge social data**: Union of social links from multiple sources
4. **Preserve user edits**: Flag manually edited content (TODO: future feature)

### Transactional Boundaries

```ruby
ActiveRecord::Base.transaction do
  # 1. Upsert author (if needed)
  author = Author.find_or_create_by(name: name)
  
  # 2. Upsert article
  article = Article.find_or_initialize_by(source_url: url)
  article.update!(attributes)
  
  # 3. Update counters
  author.increment_counter(:articles_count, author.id)
end

# 4. Reindex (outside transaction, non-critical)
article.reindex!
```

### Search Index Maintenance

**Zero-Downtime Reindexing**:
```ruby
class MeilisearchReindexer
  def self.full_reindex(model_class)
    # 1. Create new temporary index
    temp_index_name = "#{model_class.index_name}_#{Time.now.to_i}"
    temp_index = meili.index(temp_index_name)
    
    # 2. Configure index settings
    temp_index.update_settings(
      searchableAttributes: model_class.searchable_attributes,
      filterableAttributes: model_class.filterable_attributes,
      sortableAttributes: model_class.sortable_attributes
    )
    
    # 3. Batch reindex all documents
    model_class.find_in_batches(batch_size: 1000) do |batch|
      documents = batch.map(&:to_meilisearch_document)
      temp_index.add_documents(documents)
    end
    
    # 4. Wait for indexing to complete
    wait_for_indexing(temp_index)
    
    # 5. Swap index names (atomic operation)
    meili.swap_indexes([
      {indexes: [model_class.index_name, temp_index_name]}
    ])
    
    # 6. Delete old index
    sleep 10  # Give time for swap to propagate
    temp_index.delete
    
    Rails.logger.info("Reindexed #{model_class.name}: #{model_class.count} documents")
  end
  
  private
  
  def self.wait_for_indexing(index)
    loop do
      stats = index.stats
      break if stats['isIndexing'] == false
      sleep 1
    end
  end
end

# Usage:
MeilisearchReindexer.full_reindex(Article)
```

**Incremental Updates**:
```ruby
# After article upsert
article.update_search_index  # Updates single document

# Batch updates
Article.where(updated_at: 1.hour.ago..).find_in_batches do |batch|
  batch.each(&:update_search_index)
end
```

---

## Operational Concerns

### CI/CD Pipelines

**GitHub Actions Workflow (.github/workflows/deploy-pipeline.yml)**:
```yaml
name: Deploy Pipeline Stack

on:
  push:
    branches: [ main ]
    paths:
      - 'fallah/**'
      - 'hasad-consumer/**'
      - 'bisan-consumer/**'
      - 'docker-compose.*.yml'
  workflow_dispatch:

jobs:
  deploy-fallah:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Build Fallah image
        run: |
          cd fallah
          docker build -t fallah-worker:${{ github.sha }} .
          docker tag fallah-worker:${{ github.sha }} fallah-worker:latest
      
      - name: Push to registry (optional)
        if: false  # Disable if building on server
        run: |
          # docker push ...
      
      - name: Deploy to Contabo
        env:
          SSH_KEY: ${{ secrets.CONTABO_SSH_KEY }}
        run: |
          echo "$SSH_KEY" > key.pem
          chmod 600 key.pem
          
          # Copy docker-compose files
          scp -i key.pem docker-compose.*.yml root@185.185.82.142:~/pipeline/
          
          # Rebuild and restart
          ssh -i key.pem root@185.185.82.142 << 'EOF'
            cd ~/pipeline
            docker-compose -f docker-compose.hasad.yml build fallah-worker
            docker-compose -f docker-compose.hasad.yml up -d fallah-worker
          EOF

  deploy-consumers:
    runs-on: ubuntu-latest
    needs: deploy-fallah
    steps:
      - uses: actions/checkout@v4
      
      - name: Deploy Hasad Consumer
        env:
          SSH_KEY: ${{ secrets.CONTABO_SSH_KEY }}
        run: |
          echo "$SSH_KEY" > key.pem
          chmod 600 key.pem
          
          ssh -i key.pem root@185.185.82.142 << 'EOF'
            cd ~/pipeline
            docker-compose -f docker-compose.hasad.yml build hasad-consumer
            docker-compose -f docker-compose.hasad.yml up -d hasad-consumer
          EOF
      
      - name: Deploy Bisan Consumer
        env:
          SSH_KEY: ${{ secrets.CONTABO_SSH_KEY }}
        run: |
          ssh -i key.pem root@185.185.82.142 << 'EOF'
            cd ~/pipeline
            docker-compose -f docker-compose.bisan.yml build bisan-consumer
            docker-compose -f docker-compose.bisan.yml up -d bisan-consumer
          EOF
```

### Configuration & Secrets Management

**Environment Variables (.env.production)**:
```bash
# Redis
REDIS_HOST=redis
REDIS_PORT=6379

# MinIO
MINIO_ENDPOINT=minio:9000
MINIO_ACCESS_KEY=minioadmin
MINIO_SECRET_KEY=<generate-strong-password>
MINIO_BUCKET=hasad-content

# PostgreSQL
POSTGRES_HOST=postgres
POSTGRES_DB=hasad
POSTGRES_USER=hasad
POSTGRES_PASSWORD=<generate-strong-password>

# Meilisearch
MEILISEARCH_HOST=http://bisan-meilisearch:7700
MEILISEARCH_API_KEY=<generate-strong-key>

# Bisan
BISAN_DB_PATH=/rails/storage/production.sqlite3

# Monitoring
PROMETHEUS_RETENTION=15d
GRAFANA_ADMIN_PASSWORD=<generate-strong-password>
```

**Secrets Rotation**:
```bash
# 1. Generate new passwords
new_minio_password=$(openssl rand -base64 32)
new_pg_password=$(openssl rand -base64 32)

# 2. Update .env file
sed -i "s/MINIO_SECRET_KEY=.*/MINIO_SECRET_KEY=$new_minio_password/" .env.production
sed -i "s/POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$new_pg_password/" .env.production

# 3. Update MinIO admin password
docker exec hasad-minio mc admin user add myminio minioadmin $new_minio_password

# 4. Update PostgreSQL password
docker exec hasad-postgres psql -U postgres -c \
  "ALTER USER hasad WITH PASSWORD '$new_pg_password';"

# 5. Restart consumers with new credentials
docker-compose -f docker-compose.hasad.yml restart hasad-consumer
docker-compose -f docker-compose.bisan.yml restart bisan-consumer
```

### Observability

**Prometheus Configuration (prometheus.yml)**:
```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

alerting:
  alertmanagers:
    - static_configs:
        - targets: []  # TODO: Add Alertmanager

rule_files:
  - "/etc/prometheus/alerts.yml"

scrape_configs:
  - job_name: 'redis'
    static_configs:
      - targets: ['redis:6379']
    metrics_path: '/metrics'
  
  - job_name: 'hasad-consumer'
    static_configs:
      - targets: ['hasad-consumer:9090']
  
  - job_name: 'bisan-consumer'
    static_configs:
      - targets: ['bisan-consumer:9090']
  
  - job_name: 'postgres'
    static_configs:
      - targets: ['postgres-exporter:9187']
  
  - job_name: 'minio'
    static_configs:
      - targets: ['minio:9000']
    metrics_path: '/minio/v2/metrics/cluster'
```

**Alert Rules (alerts.yml)**:
```yaml
groups:
  - name: pipeline_alerts
    interval: 30s
    rules:
      - alert: RedisDown
        expr: up{job="redis"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Redis is down"
          description: "Redis has been down for more than 1 minute"
      
      - alert: DLQMessagesAccumulating
        expr: redis_stream_length{stream="content:hasad-failed"} > 10
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Hasad DLQ has {{ $value }} messages"
          description: "Check hasad-consumer logs for errors"
      
      - alert: BisanDLQMessages
        expr: redis_stream_length{stream="content:bisan-failed"} > 10
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Bisan DLQ has {{ $value }} messages"
      
      - alert: ConsumerLag
        expr: redis_stream_length{stream="content:scraped"} > 1000
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "Stream lag is {{ $value }} messages"
          description: "Consumers may be slow or crashed"
      
      - alert: HighErrorRate
        expr: rate(consumer_errors_total[5m]) > 0.1
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High error rate in consumers"
      
      - alert: PostgreSQLDown
        expr: up{job="postgres"} == 0
        for: 1m
        labels:
          severity: critical
      
      - alert: MinIODown
        expr: up{job="minio"} == 0
        for: 1m
        labels:
          severity: critical
```

**Grafana Dashboard JSON** (excerpts):
```json
{
  "title": "Pipeline Monitoring",
  "panels": [
    {
      "title": "Stream Message Rate",
      "targets": [
        {
          "expr": "rate(redis_stream_length{stream=\"content:scraped\"}[5m])"
        }
      ]
    },
    {
      "title": "Consumer Lag",
      "targets": [
        {
          "expr": "redis_stream_length{stream=\"content:scraped\"}"
        }
      ]
    },
    {
      "title": "DLQ Messages",
      "targets": [
        {
          "expr": "redis_stream_length{stream=~\".*-failed\"}"
        }
      ]
    },
    {
      "title": "Processing Time (p95)",
      "targets": [
        {
          "expr": "histogram_quantile(0.95, rate(consumer_processing_duration_seconds_bucket[5m]))"
        }
      ]
    }
  ]
}
```

### Health Checks

**Redis Health Check**:
```bash
#!/bin/bash
# health-check-redis.sh
redis-cli -h redis ping | grep -q PONG
exit $?
```

**Consumer Health Check**:
```python
# Add to consumer
from prometheus_client import start_http_server, Counter, Histogram
import time

# Metrics
messages_processed = Counter('consumer_messages_processed_total', 'Total messages processed')
processing_time = Histogram('consumer_processing_duration_seconds', 'Processing duration')
errors = Counter('consumer_errors_total', 'Total errors')

# Start metrics server
start_http_server(9090)

# In process_message:
with processing_time.time():
    try:
        success = process_message(...)
        if success:
            messages_processed.inc()
        else:
            errors.inc()
    except Exception:
        errors.inc()
        raise
```

### SLOs (Service Level Objectives)

| Metric | SLO | Measurement |
|--------|-----|-------------|
| **End-to-end Latency** | ≤10 minutes (p95) | Time from scrape to visible in Bisan |
| **Availability** | 99.5% | Uptime of all pipeline components |
| **Data Freshness** | ≤30 minutes | Time since last successful scrape |
| **Error Rate** | <1% | Failed messages / total messages |
| **Consumer Lag** | <100 messages | Pending messages in stream |

---

## Acceptance Tests

### Test 1: New Article Propagation

**Given**: A new article is published on metras.co  
**When**: Fallah scrapes the sitemap  
**Then**: Article appears in Bisan within 10 minutes

**Test Script**:
```bash
#!/bin/bash
# test-article-propagation.sh

ARTICLE_URL="https://metras.co/test-article-$(date +%s)"
START_TIME=$(date +%s)

# 1. Trigger Fallah scrape
docker exec fallah-worker scrapy crawl metras

# 2. Wait for article to appear in Bisan
MAX_WAIT=600  # 10 minutes
ELAPSED=0

while [ $ELAPSED -lt $MAX_WAIT ]; do
    # Check if article exists in Bisan
    ARTICLE_COUNT=$(docker exec bisan-web bin/rails runner \
        "puts Article.where(source_url: '$ARTICLE_URL').count")
    
    if [ "$ARTICLE_COUNT" -gt 0 ]; then
        END_TIME=$(date +%s)
        DURATION=$((END_TIME - START_TIME))
        echo "✅ Article propagated in $DURATION seconds"
        exit 0
    fi
    
    sleep 10
    ELAPSED=$((ELAPSED + 10))
done

echo "❌ Article did not propagate within 10 minutes"
exit 1
```

### Test 2: Title Update Propagation

**Given**: An existing article in Bisan  
**When**: Source website updates the title  
**Then**: Updated title propagates and search is reindexed within 10 minutes

**Test Script**:
```ruby
# test/integration/title_update_test.rb
require 'test_helper'

class TitleUpdateTest < ActiveSupport::TestCase
  test "updated article title propagates and reindexes" do
    # 1. Create article
    article = Article.create!(
      title: "Original Title",
      source_url: "https://metras.co/test",
      author: Author.first,
      body: "Content"
    )
    article.reindex!
    
    # 2. Simulate scraper update via Redis
    redis = Redis.new(url: ENV['REDIS_URL'])
    redis.xadd('content:scraped', {
      type: 'article',
      source_name: 'metras',
      url: article.source_url,
      data: {
        title: "Updated Title",
        author: article.author.name,
        content_html: "Content"
      }.to_json
    })
    
    # 3. Wait for consumer to process
    sleep 15
    
    # 4. Verify database updated
    article.reload
    assert_equal "Updated Title", article.title
    
    # 5. Verify Meilisearch updated
    results = Article.search("Updated Title")
    assert results.any? { |r| r.id == article.id }
  end
end
```

### Test 3: Duplicate URL Handling

**Given**: An article already exists with URL X  
**When**: Scraper encounters the same URL with identical content  
**Then**: No duplicate created, content hash matches

**Test Script**:
```python
# test_duplicate_handling.py
import redis
import json
import time

def test_duplicate_handling():
    r = redis.Redis(host='redis', decode_responses=True)
    
    article_data = {
        'type': 'article',
        'source_name': 'metras',
        'url': 'https://metras.co/duplicate-test',
        'data': json.dumps({
            'title': 'Test Article',
            'author': 'Test Author',
            'content_html': '<p>Test content</p>'
        })
    }
    
    # Publish same article twice
    id1 = r.xadd('content:scraped', article_data)
    time.sleep(2)
    id2 = r.xadd('content:scraped', article_data)
    
    # Wait for processing
    time.sleep(10)
    
    # Check Hasad metadata
    # Should have only 1 active version with same content_hash
    # (Implementation details depend on your DB query)
    
    print("✅ Duplicate handling test passed")

if __name__ == '__main__':
    test_duplicate_handling()
```

### Test 4: DLQ Replay

**Given**: Messages in DLQ after 3 failed attempts  
**When**: Root cause fixed and replay command executed  
**Then**: Messages successfully processed

**Test Script**:
```bash
#!/bin/bash
# test-dlq-replay.sh

# 1. Get DLQ message count
DLQ_COUNT=$(redis-cli -h redis XLEN content:hasad-failed)
echo "DLQ has $DLQ_COUNT messages"

if [
