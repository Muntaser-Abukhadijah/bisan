50.times do |i|
  Article.create!(
    title: "Sample Article #{i + 1}",
    image: "image#{i + 1}.jpg",
    excerpt: "This is a sample excerpt for article #{i + 1}.",
    author: "Author #{(i % 5) + 1}", # cycle through 5 authors
    category: [ "News", "Sports", "Tech", "Culture", "Health" ].sample,
    publish_date: Date.today - rand(1..100)
  )
end
