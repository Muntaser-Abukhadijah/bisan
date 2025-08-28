image_url = "https://metras.co/wp-content/uploads/2025/08/Screen-Shot-2025-08-15-at-7.08.12-PM.png"
author_image_url = "https://metras.co/wp-content/uploads/2024/06/ZKlHAQgt_400x400-150x150.jpg"

categories = [ "News", "Sports", "Tech", "Culture", "Health" ]

50.times do |i|
  Article.create!(
    title: "Sample Article #{i + 1}",
    body: "This is the full body of sample article #{i + 1}.
           Here you could write multiple paragraphs of content.",
    article_image: image_url,
    source_url: "https://example.com/sample-article-#{i + 1}",
    excerpt: "This is a sample excerpt for article #{i + 1}.",
    author: "Author #{(i % 5) + 1}", # cycles authors 1–5
    author_image: author_image_url,
    category: categories.sample,
    tags: [ "rails", "ruby", "tailwind", "development", "tutorial" ].sample(2).join(", "),
    publish_date: Date.today - rand(1..100)
  )
end
