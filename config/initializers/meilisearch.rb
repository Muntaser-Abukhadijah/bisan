Meilisearch::Rails.configuration = {
  meilisearch_url: ENV.fetch("MEILISEARCH_HOST", "http://localhost:7700"),
  meilisearch_api_key: ENV.fetch("MEILISEARCH_API_KEY", "dev_meili_master_key_123")
}
