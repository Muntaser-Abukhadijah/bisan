namespace :meilisearch do
  desc "Reindex all articles to Meilisearch"
  task reindex_articles: :environment do
    puts "=" * 60
    puts "Reindexing Articles to Meilisearch"
    puts "=" * 60
    
    total_articles = Article.count
    puts "Total articles in database: #{total_articles}"
    
    # Get current Meilisearch count
    begin
      response = Article.ms_index.stats
      indexed_count = response["numberOfDocuments"]
      puts "Currently indexed in Meilisearch: #{indexed_count}"
      puts "Missing from index: #{total_articles - indexed_count}"
    rescue => e
      puts "Could not get Meilisearch stats: #{e.message}"
    end
    
    puts ""
    puts "Starting reindex..."
    
    # Reindex all articles
    Article.reindex!
    
    puts ""
    puts "=" * 60
    puts "Reindexing complete!"
    puts "=" * 60
    
    # Verify
    begin
      response = Article.ms_index.stats
      new_count = response["numberOfDocuments"]
      puts "Now indexed in Meilisearch: #{new_count}"
      
      if new_count >= total_articles
        puts "✅ All articles successfully indexed!"
      else
        puts "⚠️  #{total_articles - new_count} articles still missing"
        puts "   This might be due to max_total_hits limit (currently: 10000)"
      end
    rescue => e
      puts "Could not verify: #{e.message}"
    end
  end
  
  desc "Index only missing articles to Meilisearch"
  task index_missing: :environment do
    puts "Checking for missing articles..."
    
    # This will index articles that aren't in Meilisearch yet
    # Useful after the HasadImportJob fix is deployed
    Article.reindex!
    
    puts "Done!"
  end
end
