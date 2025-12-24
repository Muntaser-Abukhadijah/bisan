# Meilisearch Auto-Indexing Fix

## Problem Identified

**Database**: 20,331 articles  
**Meilisearch Index**: 5,309 articles  
**Website Display**: 266 pages (5,320 articles expected)

**Root Cause**: `HasadImportJob` uses `Article.insert_all` which bypasses ActiveRecord callbacks, so articles are saved to database but NOT indexed to Meilisearch.

---

## The Fix (Two Parts)

### Part 1: Fix Future Imports (Already Done)

**File**: `bisan/app/jobs/hasad_import_job.rb`

**Change**:
```ruby
def insert_articles!(rows)
  result = Article.insert_all(rows, unique_by: %i[source_url])
  
  # NEW: Manually trigger Meilisearch indexing
  if result.rows.any?
    newly_inserted_ids = result.rows.map { |row| row[0] }
    newly_inserted = Article.where(id: newly_inserted_ids)
    Article.index_documents(newly_inserted)
    puts "[HasadImport] Indexed #{newly_inserted.count} articles to Meilisearch"
  end
  
  rows.size
end
```

**Result**: All future article imports will automatically index to Meilisearch!

### Part 2: Reindex Existing Articles

**File**: `bisan/lib/tasks/reindex_meilisearch.rake` (created)

**Command**:
```bash
# SSH to server
ssh -i ~/bisan root@185.185.82.142

# Run rake task
docker exec -it bisan-web-[CONTAINER_ID] bin/rails meilisearch:reindex_articles
```

This will:
1. Show current stats (database vs Meilisearch)
2. Reindex all 20,331 articles
3. Verify indexing completed

---

## Deployment Steps

### 1. Commit Changes
```bash
cd bisan
git add app/jobs/hasad_import_job.rb lib/tasks/reindex_meilisearch.rake
git commit -m "Fix: Auto-index articles to Meilisearch on import"
git push origin main
```

### 2. Deploy to Server
```bash
# On your Mac
cd bisan
bin/kamal deploy
```

OR manually:
```bash
ssh -i ~/bisan root@185.185.82.142
cd /root/bisan-deploy
git pull origin main
# Restart the app or trigger redeploy
```

### 3. Reindex Existing Articles
```bash
ssh -i ~/bisan root@185.185.82.142

# Find exact container name
docker ps | grep bisan-web

# Run reindex
docker exec -it bisan-web-[FULL_CONTAINER_ID] bin/rails meilisearch:reindex_articles
```

**Expected Output**:
```
============================================================
Reindexing Articles to Meilisearch
============================================================
Total articles in database: 20331
Currently indexed in Meilisearch: 5309
Missing from index: 15022

Starting reindex...

============================================================
Reindexing complete!
============================================================
Now indexed in Meilisearch: 10000
⚠️  10331 articles still missing
   This might be due to max_total_hits limit (currently: 10000)
```

### 4. Increase max_total_hits (Optional)

If you want ALL articles visible (not just 10,000):

**File**: `bisan/app/models/article.rb`
```ruby
meilisearch do
  attribute :title, :excerpt, :body
  searchable_attributes [ :title, :excerpt, :body ]
  attributes_to_highlight [ "*" ]
  pagination max_total_hits: 25000  # Increased from 10000
end
```

Then reindex again.

---

## Verification

### Check Meilisearch Index
```bash
curl http://localhost:7700/indexes/Article/stats | jq '.numberOfDocuments'
```

### Check Website
- Refresh the articles page
- Should now show more pages
- Maximum pages = (indexed_count / 20)

---

## How It Works Now

### Before Fix
```
Article scraped → Saved to DB → ❌ NOT indexed → Website doesn't show
```

### After Fix
```
Article scraped → Saved to DB → ✅ Auto-indexed → Website shows immediately!
```

### Future Imports
```
HasadImportJob runs:
  1. Imports 100 new articles to database (insert_all)
  2. Gets IDs of newly inserted articles
  3. Calls Article.index_documents(new_articles)
  4. Articles appear on website immediately!
```

---

## Testing the Fix

### 1. Import New Articles
```bash
# On server
docker exec -it bisan-web-[ID] bin/rails hasad_import:import
```

### 2. Check Log Output
Look for:
```
[HasadImport] Indexed 15 articles to Meilisearch
```

### 3. Verify on Website
- Count should increase immediately
- New articles should appear on website

---

## Summary

✅ **Root cause fixed**: HasadImportJob now indexes articles automatically  
✅ **Rake task created**: Can reindex existing 15,000 missing articles  
✅ **Future-proof**: All new imports will auto-index  
⚠️ **Note**: max_total_hits: 10000 limits pagination (increase if needed)

The fix ensures articles are searchable and visible on the website as soon as they're imported!
