# db/seeds.rb

# --- Config ---
ARTICLE_IMG_URL = "https://metras.co/wp-content/uploads/2025/08/Screen-Shot-2025-08-15-at-7.08.12-PM.png"
AUTHOR_IMG_URL  = "https://metras.co/wp-content/uploads/2024/06/ZKlHAQgt_400x400-150x150.jpg"

ARTICLE_COUNT = 150
AUTHOR_COUNT  = 20

CATEGORIES = %w[
  History Politics Culture Economy Society Opinion Biography
  Literature Media Technology Education Religion Geography
].freeze

TAGS_POOL = %w[
  Palestine Gaza Jerusalem WestBank History Nakba Refugees Heritage
  Culture Resistance Ceasefire Diplomacy Rights Economy Diaspora
].freeze

TOPICS = [
  "Historical Perspectives", "Contemporary Politics", "Cultural Identity",
  "Media Narratives", "Economic Outlook", "Social Dynamics",
  "International Law", "Education & Youth", "Technology & Society",
  "Literature & Arts"
].freeze

# simple slug helper for demo social links
def slugify(str) = str.downcase.strip.gsub(/[^a-z0-9]+/, "-").gsub(/^-|-$/, "")

# tiny lorem
LOREM = "Lorem ipsum dolor sit amet, consectetur adipiscing elit. "\
        "Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua."

ApplicationRecord.transaction do
  # Clear in the correct order (FK)
  Article.delete_all
  Author.delete_all

  # --- Create Authors ---
  author_names = [
    "Edward Said", "Rashid Khalidi", "Ilan Pappé", "Hanan Ashrawi", "Ghassan Kanafani",
    "Mahmoud Darwish", "Sari Nusseibeh", "Nadia Abu El-Haj", "Omar Barghouti", "Lila Abu-Lughod",
    "Salman Abu Sitta", "Noura Erakat", "Tareq Baconi", "Amira Hass", "Sawsan Zaher",
    "Alaa Tartir", "Mariam Barghouti", "Diana Buttu", "Yousef Munayyer", "Leila Farsakh"
  ].first(AUTHOR_COUNT)

  authors = author_names.map do |name|
    Author.create!(
      name: name,
      bio:  "#{name} — #{TOPICS.sample} author and commentator.",
      avatar_url: AUTHOR_IMG_URL,
      social_links: {
        website: "https://example.com/#{slugify(name)}",
        twitter: "https://twitter.com/#{slugify(name)}"
      }
    )
  end

  # --- Create Articles ---
  rng = Random.new(42) # deterministic seed
  ARTICLE_COUNT.times do |i|
    author      = authors.sample(random: rng)
    category    = CATEGORIES.sample(random: rng)
    topic       = TOPICS.sample(random: rng)
    days_ago    = rng.rand(0..730) # last ~2 years
    publish_on  = Date.today - days_ago

    tags = TAGS_POOL.sample(rng.rand(0..3), random: rng).join(", ")

    Article.create!(
      title:        "Article #{i + 1}: #{topic}",
      category:     category,
      publish_date: publish_on,
      excerpt:      "#{topic} in focus — a short overview.",
      body:         "<p>#{LOREM}</p><p>#{topic}: #{LOREM}</p>",
      source_url:   "https://example.com/articles/#{i + 1}",
      article_image: ARTICLE_IMG_URL,
      tags:         (tags.presence),
      author:       author
    )
  end
end

puts "✅ Seeded #{Author.count} authors and #{Article.count} articles."
