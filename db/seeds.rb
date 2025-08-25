image_url = "https://metras.co/wp-content/uploads/2025/08/Screen-Shot-2025-08-15-at-7.08.12-PM.png"

50.times do |i|
  Article.create!(
    title: "Sample Article #{i + 1}",
    image: image_url,
    excerpt: "This is a sample excerpt for article #{i + 1}.",
    author: "Author #{(i % 5) + 1}", # cycles authors 1–5
    category: [ "News", "Sports", "Tech", "Culture", "Health" ].sample,
    publish_date: Date.today - rand(1..100)
  )
end
