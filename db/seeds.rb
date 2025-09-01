# db/seeds.rb
require "json"

SEEDS_DIR = Rails.root.join("db", "seeds", "metras")

AR_MONTHS = {
  "يناير" => 1, "فبراير" => 2, "مارس" => 3,
  "أبريل" => 4, "ابريل" => 4,
  "مايو" => 5,
  "يونيو" => 6, "يوليو" => 7,
  "أغسطس" => 8, "اغسطس" => 8,
  "سبتمبر" => 9,
  "أكتوبر" => 10, "اكتوبر" => 10,
  "نوفمبر" => 11, "ديسمبر" => 12
}.freeze

def parse_arabic_date(str)
  return if str.nil? || str.strip.empty?
  # Matches: "31 مايو 2018" (day month year)
  if str.strip =~ /\A(\d{1,2})\s+([^\s]+)\s+(\d{4})\z/
    day  = Regexp.last_match(1).to_i
    monn = Regexp.last_match(2)
    year = Regexp.last_match(3).to_i
    month = AR_MONTHS[monn]
    return Date.new(year, month, day) if month
  end
  # Fallback: let Date parse if possible
  Date.parse(str) rescue nil
end

def safe_excerpt(text, length = 280)
  return nil if text.nil?
  t = text.strip.gsub(/\s+/, " ")
  t.length > length ? "#{t[0, length].rstrip}…" : t
end

imported = 0
updated  = 0

Dir.glob(SEEDS_DIR.join("*.json")).sort.each do |path|
  raw = File.read(path, encoding: "utf-8")
  data = JSON.parse(raw)

  # --- Author ---
  author_name = data["author"]&.strip
  author = if author_name.present?
    Author.find_or_create_by!(name: author_name)
  end

  if author && author.avatar_url.blank? && data["author_image_url"].present?
    author.update!(avatar_url: data["author_image_url"])
  end

  # --- Article attrs mapping ---
  attrs = {
    title:         data["title"],
    article_image: data["image_url"],
    excerpt:       data["excerpt"].presence || safe_excerpt(data["content"]),
    category:      data["category"],
    publish_date:  parse_arabic_date(data["date"]),
    body:          data["content"],
    source_url:    data["url"],
    tags:          nil,
    author_id:     author&.id || (raise "Missing author for #{data['title']}")
  }

  # Idempotent upsert by source_url
  if (existing = Article.find_by(source_url: attrs[:source_url]))
    existing.update!(attrs)
    updated += 1
    puts "↻ Updated: #{existing.title}"
  else
    Article.create!(attrs)
    imported += 1
    puts "➕ Imported: #{attrs[:title]}"
  end
end

puts "Done. Imported #{imported}, updated #{updated}."



# # db/seeds.rb

# # --- Config ---
# ARTICLE_IMG_URL = "https://metras.co/wp-content/uploads/2025/08/Screen-Shot-2025-08-15-at-7.08.12-PM.png"
# AUTHOR_IMG_URL  = "https://metras.co/wp-content/uploads/2024/06/ZKlHAQgt_400x400-150x150.jpg"

# ARTICLE_COUNT = 150
# AUTHOR_COUNT  = 20

# CATEGORIES = %w[
#   History Politics Culture Economy Society Opinion Biography
#   Literature Media Technology Education Religion Geography
# ].freeze

# TAGS_POOL = %w[
#   Palestine Gaza Jerusalem WestBank History Nakba Refugees Heritage
#   Culture Resistance Ceasefire Diplomacy Rights Economy Diaspora
# ].freeze

# TOPICS = [
#   "Historical Perspectives", "Contemporary Politics", "Cultural Identity",
#   "Media Narratives", "Economic Outlook", "Social Dynamics",
#   "International Law", "Education & Youth", "Technology & Society",
#   "Literature & Arts"
# ].freeze

# # simple slug helper for demo social links
# def slugify(str) = str.downcase.strip.gsub(/[^a-z0-9]+/, "-").gsub(/^-|-$/, "")

# # tiny lorem
# LOREM = "Lorem ipsum dolor sit amet, consectetur adipiscing elit. "\
#         "Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua."

# ApplicationRecord.transaction do
#   # Clear in the correct order (FK)
#   Article.delete_all
#   Author.delete_all

#   # --- Create Authors ---
#   author_names = [
#     "Edward Said", "Rashid Khalidi", "Ilan Pappé", "Hanan Ashrawi", "Ghassan Kanafani",
#     "Mahmoud Darwish", "Sari Nusseibeh", "Nadia Abu El-Haj", "Omar Barghouti", "Lila Abu-Lughod",
#     "Salman Abu Sitta", "Noura Erakat", "Tareq Baconi", "Amira Hass", "Sawsan Zaher",
#     "Alaa Tartir", "Mariam Barghouti", "Diana Buttu", "Yousef Munayyer", "Leila Farsakh"
#   ].first(AUTHOR_COUNT)

#   authors = author_names.map do |name|
#     Author.create!(
#       name: name,
#       bio:  "#{name} — #{TOPICS.sample} author and commentator.",
#       avatar_url: AUTHOR_IMG_URL,
#       social_links: {
#         website: "https://example.com/#{slugify(name)}",
#         twitter: "https://twitter.com/#{slugify(name)}"
#       }
#     )
#   end

#   # --- Create Articles ---
#   rng = Random.new(42) # deterministic seed
#   ARTICLE_COUNT.times do |i|
#     author      = authors.sample(random: rng)
#     category    = CATEGORIES.sample(random: rng)
#     topic       = TOPICS.sample(random: rng)
#     days_ago    = rng.rand(0..730) # last ~2 years
#     publish_on  = Date.today - days_ago

#     tags = TAGS_POOL.sample(rng.rand(0..3), random: rng).join(", ")

#     Article.create!(
#       title:        "Article #{i + 1}: #{topic}",
#       category:     category,
#       publish_date: publish_on,
#       excerpt:      "#{topic} in focus — a short overview.",
#       body:         "<p>#{LOREM}</p><p>#{topic}: #{LOREM}</p>",
#       source_url:   "https://example.com/articles/#{i + 1}",
#       article_image: ARTICLE_IMG_URL,
#       tags:         (tags.presence),
#       author:       author
#     )
#   end
# end

# puts "✅ Seeded #{Author.count} authors and #{Article.count} articles."
