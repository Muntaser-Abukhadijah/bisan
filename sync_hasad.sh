#!/bin/bash

# Sync hasad data to production and import into bisan
# Usage: ./sync_hasad.sh

set -e  # Exit on error

echo "🔄 Syncing hasad data to production server..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Step 1: Pull latest hasad data from GitHub on production server
echo "📥 Step 1: Pulling latest hasad from GitHub..."
ssh -i ~/bisan root@185.185.82.142 << 'EOF'
  cd /root/hasad
  git pull
  echo "✓ hasad data updated"
EOF

# Step 2: Run import job via Kamal
echo ""
echo "📊 Step 2: Running import job..."
cd "$(dirname "$0")"
bin/kamal app exec -d contabo --reuse "bin/rails runner 'HasadImportJob.perform_now'"

# Step 3: Reindex Meilisearch
echo ""
echo "🔍 Step 3: Reindexing Meilisearch..."
bin/kamal app exec -d contabo --reuse "bin/rails runner 'Article.reindex!'"

# Step 4: Show results
echo ""
echo "📈 Step 4: Checking import results..."
bin/kamal app exec -d contabo --reuse "bin/rails runner 'puts \"✓ Articles: #{Article.count}, Authors: #{Author.count}\"'"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Sync complete!"
