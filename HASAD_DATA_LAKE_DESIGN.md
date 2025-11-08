# Hasad Data Lake Architecture: Simple, Extensible, Data-Centric

## Executive Summary

This document designs a **data lake architecture** where **Hasad serves as the central data repository** for all scraped content. Using **MinIO** for object storage and **PostgreSQL** for metadata, Hasad provides a simple, extensible foundation that multiple services can consume independently. Bisan syncs from Hasad via scheduled polling (every 30 minutes), eliminating the need for complex event streaming. This architecture prioritizes: (1) **simplicity** over real-time performance, (2) **extensibility** for future data types (audio, images, transcriptions), and (3) **data-centricity** where Hasad is the single source of truth. All components run on Contabo VPS at zero cloud costs.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Why Data Lake?](#why-data-lake)
3. [Hasad Structure](#hasad-structure)
4. [Fallah Integration](#fallah-integration)
5. [Bisan Sync Mechanism](#bisan-sync-mechanism)
6. [Future Extensibility](#future-extensibility)
7. [Implementation Guide](#implementation-guide)
8. [Operational Runbook](#operational-runbook)
9. [Migration from Current System](#migration-from-current-system)

---

## Architecture Overview

### High-Level Design

```
┌─────────────────────────────────────────────────────────────┐
│                   SOURCE WEBSITES                            │
│          (metras.co, qudsn.co, ...)                         │
└─────────────────────────────────────────────────────────────┘
                         │
                         │ HTTP (sitemap crawl)
                         ▼
┌─────────────────────────────────────────────────────────────┐
│              FALLAH (Scraper - Cron Every 30min)            │
│  • Scrapy spiders (sitemap-based)                           │
│  • Rate limited: 1 req/sec                                  │
│  • Deduplication: requests.seen                             │
└─────────────────────────────────────────────────────────────┘
                         │
                         │ Direct writes
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                   HASAD DATA LAKE                            │
│  ┌──────────────────────────────────────────────────────┐   │
│  │ MinIO (S3-Compatible Object Storage)                 │   │
│  │ Bucket: hasad-content                                │   │
│  │ ├── v2/                                              │   │
│  │ │   ├── metras/                                      │   │
│  │ │   │   ├── articles/{hash}.json                     │   │
│  │ │   │   ├── authors/{hash}.json                      │   │
│  │ │   │   └── images/{hash}.jpg      (future)         │   │
│  │ │   └── qudsn.co/                                    │   │
│  │ │       └── articles/{hash}.json                     │   │
│  │ └── .markers/                                        │   │
│  │     └── last_sync_{source}_{type}.txt               │   │
│  └──────────────────────────────────────────────────────┘   │
│  ┌──────────────────────────────────────────────────────┐   │
│  │ PostgreSQL (Metadata & Index)                        │   │
│  │ • content_metadata (hash, type, minio_key, etc.)    │   │
│  │ • content_versions (url history)                    │   │
│  │ • sync_checkpoints (consumer tracking)              │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                         │
                         │ Polling every 30min (cron)
                         ▼
┌─────────────────────────────────────────────────────────────┐
│            BISAN (Web Application)                           │
│  • Reads new content from Hasad                             │
│  • Upserts to SQLite                                        │
│  • Reindexes Meilisearch                                    │
│  • Tracks checkpoint in .hasad_checkpoint                   │
└─────────────────────────────────────────────────────────────┘
                         │
                         │ Future consumers (no changes needed)
                         ▼
          ┌──────────────┴──────────────┐
          │                             │
    ┌─────────────┐            ┌─────────────┐
    │  Analytics  │            │  Mobile API │
    │  Service    │            │             │
    └─────────────┘            └─────────────┘
```

### Component Responsibilities

**Fallah (Producer)**:
- Runs on cron schedule (every 30 minutes)
- Crawls source websites via sitemaps
- Calculates content hash (SHA256)
- Writes directly to MinIO (objects)
- Writes directly to PostgreSQL (metadata)
- No queues, no events, just direct storage

**Hasad (Data Lake)**:
- **MinIO**: Stores immutable content objects
  - Versioning enabled
  - Content-addressed by hash
  - Organized by source/type
- **PostgreSQL**: Metadata and queryability
  - Content index
  - Version history
  - Sync checkpoints for consumers

**Bisan (Consumer)**:
- Runs sync job via cron (every 30 minutes)
- Queries PostgreSQL for new content since last checkpoint
- Fetches content from MinIO
- Upserts to SQLite + Meilisearch
- Updates checkpoint

**Future Consumers**:
- Read independently from Hasad
- Maintain own checkpoints
- No coordination needed

---

## Why Data Lake?

### Design Principles

1. **Simplicity First**
   - No message brokers (Redis, RabbitMQ, Kafka)
   - No complex event handling
   - Just files + database + cron
   - Easy to understand and debug

2. **Data-Centric**
   - Hasad is authoritative source of truth
   - Immutable storage (objects never change)
   - Multiple consumers can read independently
   - Clear ownership: Fallah writes, others read

3. **Extensible**
   - Add new data types by creating new directories
   - Add new consumers without modifying infrastructure
   - Schema evolution handled gracefully
   - Future-proof for unknown requirements

### Trade-offs Accepted

| Aspect | What We Give Up | What We Gain |
|--------|----------------|--------------|
| **Latency** | ❌ Real-time (seconds) | ✅ Predictable (30min) |
| **Complexity** | ❌ Advanced features | ✅ Simple operations |
| **Coupling** | ❌ Event-driven decoupling | ✅ Explicit dependencies |
| **Scalability** | ❌ Infinite horizontal scale | ✅ Sufficient for use case |

### When This Approach Works

✅ **Good fit:**
- Content updates are not time-sensitive
- Data volume is moderate (<10K items/day)
- Multiple consumers need same data
- Team size is small (easier to coordinate)
- Reliability > Speed

❌ **Not ideal for:**
- Real-time analytics dashboards
- High-frequency trading systems
- Live user notifications
- Massive scale (millions of events/sec)

---

## Hasad Structure

### MinIO Bucket Organization

```
hasad-content/
├── v2/                              # Schema version 2
│   ├── metras/
│   │   ├── articles/
│   │   │   ├── a3f7c8e1...2d4f.json    # Content-addressed
│   │   │   ├── b4e9d2f3...5a6c.json
│   │   │   └── ...
│   │   ├── authors/
│   │   │   ├── c5f0e4g7...8b9d.json
│   │   │   └── ...
│   │   └── images/                     # Future
│   │       ├── d6g1f5h8...9c0e.jpg
│   │       └── ...
│   └── qudsn.co/
│       ├── articles/
│       │   └── ...
│       └── authors/
│           └── ...
├── .markers/                        # Sync markers (optional)
│   ├── last_sync_metras_articles.txt
│   ├── last_sync_metras_authors.txt
│   └── ...
└── legacy/                          # Old NDJSON files (archived)
    └── metras/
        └── article/
            └── parsed.ndjson
```

### PostgreSQL Schema

**Main Tables:**

```sql
-- Content metadata and index
CREATE TABLE content_metadata (
    id SERIAL PRIMARY KEY,
    content_hash VARCHAR(64) NOT NULL UNIQUE,
    source_name VARCHAR(100) NOT NULL,
    content_type VARCHAR(50) NOT NULL,  -- 'article', 'author', 'image', etc.
    url TEXT,
    minio_bucket VARCHAR(100) NOT NULL,
    minio_key TEXT NOT NULL,
    content_size INT,
    scraped_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    scraper_version VARCHAR(50),
    status VARCHAR(20) NOT NULL DEFAULT 'active',  -- active, superseded, deleted
    
    -- Denormalized fields for quick filtering
    title TEXT,
    author_name TEXT,
    publish_date DATE,
    
    -- Metadata
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
    consumer_name VARCHAR(100) NOT NULL UNIQUE,  -- 'bisan', 'analytics', etc.
    last_sync_at TIMESTAMPTZ NOT NULL,
    last_processed_id INT,  -- Last content_metadata.id processed
    metadata JSONB,  -- Consumer-specific metadata
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Audit log (optional but recommended)
CREATE TABLE content_audit_log (
    id SERIAL PRIMARY KEY,
    content_metadata_id INT REFERENCES content_metadata(id),
    action VARCHAR(50) NOT NULL,  -- 'created', 'updated', 'deleted'
    performed_by VARCHAR(100),  -- 'fallah', 'admin', etc.
    performed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    details JSONB
);
```

### Content Object Format

**Article JSON:**
```json
{
  "schema_version": "2.0",
  "content_type": "article",
  "source": {
    "name": "metras",
    "url": "https://metras.co/article/example",
    "scraped_at": "2025-01-08T14:30:00Z",
    "scraper_version": "fallah-v1.0.0"
  },
  "data": {
    "title": "عنوان المقال",
    "author": "اسم الكاتب",
    "publish_date": "2025-01-08",
    "category": "سياسة",
    "tags": ["فلسطين", "القدس"],
    "excerpt": "ملخص المقال...",
    "body_html": "<p>محتوى المقال...</p>",
    "article_image_url": "https://metras.co/images/example.jpg",
    "metadata": {
      "word_count": 1500,
      "reading_time_minutes": 7,
      "language": "ar"
    }
  }
}
```

**Author JSON:**
```json
{
  "schema_version": "2.0",
  "content_type": "author",
  "source": {
    "name": "metras",
    "url": "https://metras.co/author/example",
    "scraped_at": "2025-01-08T14:30:00Z"
  },
  "data": {
    "name": "اسم الكاتب",
    "bio": "نبذة عن الكاتب...",
    "avatar_url": "https://metras.co/avatars/example.jpg",
    "social_links": {
      "twitter": "https://twitter.com/example",
      "email": "example@metras.co"
    },
    "metadata": {
      "articles_count": 42
    }
  }
}
```

---

## Fallah Integration

### Updated Pipeline (fallah/pipelines.py)

```python
import json
import hashlib
import psycopg2
from minio import Minio
from io import BytesIO
from datetime import datetime

class HasadDataLakePipeline:
    """
    Store scraped items to Hasad Data Lake:
    1. Calculate content hash
    2. Store content to MinIO
    3. Store metadata to PostgreSQL
    """
    
    def __init__(self, minio_endpoint, postgres_dsn):
        # MinIO connection
        self.minio = Minio(
            minio_endpoint,
            access_key='minioadmin',  # From env var in production
            secret_key='minioadmin123',
            secure=False
        )
        
        # Ensure bucket exists
        if not self.minio.bucket_exists('hasad-content'):
            self.minio.make_bucket('hasad-content')
        
        # PostgreSQL connection
        self.pg = psycopg2.connect(postgres_dsn)
        self.pg.autocommit = False
    
    @classmethod
    def from_crawler(cls, crawler):
        minio_endpoint = crawler.settings.get('MINIO_ENDPOINT', 'localhost:9000')
        postgres_dsn = crawler.settings.get('POSTGRES_DSN', 
            'host=localhost dbname=hasad user=hasad password=hasad_password')
        return cls(minio_endpoint, postgres_dsn)
    
    def process_item(self, item, spider):
        """Process single scraped item"""
        try:
            # Extract fields
            source_name = item.get('source_name', spider.name)
            content_type = item.get('type', 'article')
            url = item.get('url')
            
            if not url:
                spider.logger.warning("Item missing URL, skipping")
                return item
            
            # Build content object
            content = self._build_content_object(item, source_name, content_type)
            
            # Calculate content hash
            content_json = json.dumps(content, sort_keys=True, ensure_ascii=False)
            content_hash = hashlib.sha256(content_json.encode('utf-8')).hexdigest()
            
            # Check if already exists
            if self._content_exists(content_hash):
                spider.logger.info(f"Content already exists: {url} (hash: {content_hash[:8]}...)")
                return item
            
            # Store to MinIO
            minio_key = self._store_to_minio(
                source_name, content_type, content_hash, content_json
            )
            
            # Store metadata to PostgreSQL
            self._store_metadata(
                content_hash, source_name, content_type, url,
                minio_key, len(content_json), content
            )
            
            self.pg.commit()
            spider.logger.info(f"Stored to Hasad: {url}")
            
        except Exception as e:
            self.pg.rollback()
            spider.logger.error(f"Failed to store item: {e}")
            raise
        
        return item
    
    def _build_content_object(self, item, source_name, content_type):
        """Build standardized content object"""
        return {
            'schema_version': '2.0',
            'content_type': content_type,
            'source': {
                'name': source_name,
                'url': item.get('url'),
                'scraped_at': datetime.utcnow().isoformat() + 'Z',
                'scraper_version': 'fallah-v1.0.0'
            },
            'data': dict(item)  # All item fields
        }
    
    def _content_exists(self, content_hash):
        """Check if content already stored"""
        cursor = self.pg.cursor()
        cursor.execute("""
            SELECT 1 FROM content_metadata
            WHERE content_hash = %s AND status = 'active'
            LIMIT 1
        """, (content_hash,))
        exists = cursor.fetchone() is not None
        cursor.close()
        return exists
    
    def _store_to_minio(self, source_name, content_type, content_hash, content_json):
        """Store content to MinIO"""
        # Generate object key
        minio_key = f"v2/{source_name}/{content_type}/{content_hash}.json"
        
        # Upload
        content_bytes = content_json.encode('utf-8')
        self.minio.put_object(
            'hasad-content',
            minio_key,
            BytesIO(content_bytes),
            length=len(content_bytes),
            content_type='application/json; charset=utf-8'
        )
        
        return minio_key
    
    def _store_metadata(self, content_hash, source_name, content_type, url, 
                       minio_key, content_size, content):
        """Store metadata to PostgreSQL"""
        cursor = self.pg.cursor()
        
        # Mark previous versions as superseded
        cursor.execute("""
            UPDATE content_metadata
            SET status = 'superseded', updated_at = NOW()
            WHERE url = %s AND status = 'active'
        """, (url,))
        
        # Extract denormalized fields
        data = content.get('data', {})
        title = data.get('title')
        author_name = data.get('author')
        publish_date = data.get('publish_date') or data.get('published_at')
        
        # Insert new version
        cursor.execute("""
            INSERT INTO content_metadata 
            (content_hash, source_name, content_type, url, minio_bucket, minio_key,
             content_size, title, author_name, publish_date, scraper_version)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
            RETURNING id
        """, (
            content_hash, source_name, content_type, url,
            'hasad-content', minio_key, content_size,
            title, author_name, publish_date, 'fallah-v1.0.0'
        ))
        
        metadata_id = cursor.fetchone()[0]
        
        # Track version history
        cursor.execute("""
            INSERT INTO content_versions (url, version_number, content_metadata_id)
            SELECT %s, COALESCE(MAX(version_number), 0) + 1, %s
            FROM content_versions
            WHERE url = %s
        """, (url, metadata_id, url))
        
        cursor.close()
    
    def close_spider(self, spider):
        """Cleanup"""
        self.pg.close()
```

### Fallah Settings Update (fallah/settings.py)

```python
# Hasad Data Lake settings
MINIO_ENDPOINT = 'minio:9000'  # Docker service name
POSTGRES_DSN = 'host=postgres dbname=hasad user=hasad password=hasad_password'

# Pipeline
ITEM_PIPELINES = {
    'fallah.pipelines.HasadDataLakePipeline': 300,
}

# Remove old export settings
# EXPORT_BASE = "/Users/mabukhad/Documents/pls_workspace/hasad"  # No longer needed
```

---

## Bisan Sync Mechanism

### Sync Job (lib/tasks/sync_from_hasad.rake)

```ruby
# lib/tasks/sync_from_hasad.rake
namespace :hasad do
  desc "Sync new content from Hasad Data Lake"
  task sync: :environment do
    syncer = HasadSyncer.new
    syncer.sync_new_content
  end
end

# lib/hasad_syncer.rb
require 'pg'
require 'minio'

class HasadSyncer
  CHECKPOINT_FILE = Rails.root.join('.hasad_checkpoint')
  CONSUMER_NAME = 'bisan'
  
  def initialize
    # PostgreSQL connection
    @pg = PG.connect(
      host: ENV.fetch('HASAD_PG_HOST', 'postgres'),
      dbname: ENV.fetch('HASAD_PG_DB', 'hasad'),
      user: ENV.fetch('HASAD_PG_USER', 'hasad'),
      password: ENV.fetch('HASAD_PG_PASSWORD', 'hasad_password')
    )
    
    # MinIO client
    @minio = Minio::Client.new(
      endpoint: ENV.fetch('HASAD_MINIO_ENDPOINT', 'minio:9000'),
      access_key: ENV.fetch('HASAD_MINIO_ACCESS_KEY', 'minioadmin'),
      secret_key: ENV.fetch('HASAD_MINIO_SECRET_KEY', 'minioadmin123'),
      secure: false
    )
    
    @logger = Logger.new(STDOUT)
  end
  
  def sync_new_content
    @logger.info("[HasadSync] Starting sync...")
    start_time = Time.current
    
    # Get last checkpoint
    last_processed_id = get_checkpoint
    @logger.info("[HasadSync] Last processed ID: #{last_processed_id}")
    
    # Query new content
    new_items = fetch_new_content(last_processed_id)
    @logger.info("[HasadSync] Found #{new_items.count} new items")
    
    # Process each item
    processed_count = 0
    new_items.each do |item|
      begin
        process_item(item)
        update_checkpoint(item['id'])
        processed_count += 1
      rescue => e
        @logger.error("[HasadSync] Failed to process item #{item['id']}: #{e.message}")
        @logger.error(e.backtrace.first(5).join("\n"))
        # Continue with next item
      end
    end
    
    duration = Time.current - start_time
    @logger.info("[HasadSync] Completed: #{processed_count}/#{new_items.count} items in #{duration.round(2)}s")
  end
  
  private
  
  def get_checkpoint
    # Try PostgreSQL checkpoint table first
    result = @pg.exec("""
      SELECT last_processed_id FROM sync_checkpoints
      WHERE consumer_name = $1
    """, [CONSUMER_NAME])
    
    return result[0]['last_processed_id'].to_i if result.ntuples > 0
    
    # Fallback to local file
    return File.read(CHECKPOINT_FILE).to_i if File.exist?(CHECKPOINT_FILE)
    
    # Start from beginning
    0
  end
  
  def fetch_new_content(since_id)
    result = @pg.exec("""
      SELECT id, content_hash, source_name, content_type, url,
             minio_bucket, minio_key, scraped_at,
             title, author_name, publish_date
      FROM content_metadata
      WHERE id > $1 AND status = 'active'
      ORDER BY id ASC
      LIMIT 1000
    """, [since_id])
    
    result.to_a
  end
  
  def process_item(metadata)
    # Fetch content from MinIO
    content = fetch_from_minio(metadata['minio_bucket'], metadata['minio_key'])
    
    # Route by content type
    case metadata['content_type']
    when 'article'
      process_article(content, metadata)
    when 'author'
      process_author(content, metadata)
    else
      @logger.warn("[HasadSync] Unknown content type: #{metadata['content_type']}")
    end
  end
  
  def fetch_from_minio(bucket, key)
    object = @minio.get_object(bucket, key)
    JSON.parse(object)
  end
  
  def process_article(content, metadata)
    data = content['data']
    
    ActiveRecord::Base.transaction do
      # Ensure author exists
      author = ensure_author(data['author'])
      return unless author
      
      # Find or initialize article
      article = Article.find_or_initialize_by(source_url: metadata['url'])
      
      # Calculate content hash for deduplication
      body_html = data['body'] || data['content_html']
      new_hash = body_html ? Digest::SHA256.hexdigest(body_html) : nil
      
      # Skip if content unchanged
      if article.persisted? && article.content_hash == new_hash
        @logger.info("[HasadSync] Article unchanged: #{metadata['url']}")
        return
      end
      
      # Update fields
      article.title = data['title']
      article.excerpt = data['excerpt']
      article.body = body_html
      article.article_image = data['article_image_url'] || data['article_image']
      article.category = data['categorie'] || data['category']
      article.tags = parse_tags(data['tags'])
      article.author = author
      article.content_hash = new_hash
      article.ingested_at = Time.current
      
      # Parse publish date
      if metadata['publish_date']
        article.publish_date = Date.parse(metadata['publish_date']) rescue nil
      end
      
      article.save!
      
      # Reindex in Meilisearch if content changed
      article.reindex! if article.saved_change_to_body? || article.saved_change_to_title?
      
      @logger.info("[HasadSync] Upserted article: #{article.title} (id: #{article.id})")
    end
  end
  
  def process_author(content, metadata)
    data = content['data']
    name = data['name'].to_s.strip
    
    return if name.empty?
    
    ActiveRecord::Base.transaction do
      author = Author.find_or_initialize_by(name: name)
      author.bio = data['bio'] if data['bio']
      author.avatar_url = data['avatar_url'] if data['avatar_url']
      author.social_links = data['social_links'] if data['social_links']
      author.save!
      
      @logger.info("[HasadSync] Upserted author: #{name} (id: #{author.id})")
    end
  end
  
  def ensure_author(author_name)
    return nil if author_name.nil? || author_name.strip.empty?
    
    name = author_name.strip
    author = Author.find_by(name: name)
    
    unless author
      author = Author.create!(name: name, bio: '', avatar_url: nil)
      @logger.info("[HasadSync] Created placeholder author: #{name}")
    end
    
    author
  end
  
  def parse_tags(tags_value)
    case tags_value
    when Array then tags_value.join(',')
    when String then tags_value
    else ''
    end
  end
  
  def update_checkpoint(processed_id)
    # Update PostgreSQL
    @pg.exec("""
      INSERT INTO sync_checkpoints (consumer_name, last_processed_id, last_sync_at, updated_at)
      VALUES ($1, $2, NOW(), NOW())
      ON CONFLICT (consumer_name)
      DO UPDATE SET
        last_processed_id = EXCLUDED.last_processed_id,
        last_sync_at = NOW(),
        updated_at = NOW()
    """, [CONSUMER_NAME, processed_id])
    
    # Update local file (backup)
    File.write(CHECKPOINT_FILE, processed_id.to_s)
  end
end
```

### Cron Configuration

**config/schedule.rb** (using whenever gem):
```ruby
# config/schedule.rb
set :output, 'log/cron.log'

# Sync from Hasad every 30 minutes
every 30.minutes do
  rake 'hasad:sync'
end
```

**Or manual crontab:**
```bash
# crontab -e
*/30 * * * * cd /path/to/bisan && bin/rails hasad:sync >> log/hasad_sync.log 2>&1
```

---

## Future Extensibility

### Adding New Data Types

**Example: Adding Audio/Podcast Support**

1. **Fallah scrapes audio**:
```python
# fallah/spiders/metras_audio.py
class MetrasAudioSpider(scrapy.Spider):
    name = "metras_audio"
    
    def parse_audio_page(self, response):
        yield {
            'type': 'audio',
            'source_name': 'metras',
            'url': response.url,
            'title': response.css('h1::text').get(),
            'audio_url': response.css('audio::attr(src)').get(),
            'duration_seconds': 3600,
            'transcript_url': None  # Will be added by transcription service
        }
```

2. **Hasad stores it** (no changes needed - just works!):
```
hasad-content/
└── v2/
    └── metras/
        └── audio/
            ├── d7h2g6i9...0d1f.json     # Metadata
            └── d7h2g6i9...0d1f.mp3      # Audio file (optional)
```

3. **New transcription service consumes**:
```python
# transcription_service.py
def process_audio():
    # Query Hasad for audio content
    audio_items = hasad.query(content_type='audio', processed_by_transcription=False)
    
    for audio in audio_items:
        # Download audio file
        audio_data = download_from_minio(audio.audio_url)
        
        # Transcribe (e.g., using Whisper)
        transcript = whisper_model.transcribe(audio_data)
        
        #
