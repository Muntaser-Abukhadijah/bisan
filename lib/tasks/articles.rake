namespace :articles do
  desc "Populate missing excerpts from article body"
  task populate_excerpts: :environment do
    count = 0
    Article.where(excerpt: [nil, '']).find_each do |article|
      if article.body.present?
        excerpt = article.body.gsub(/<[^>]*>/, '').strip.truncate(200)
        article.update_column(:excerpt, excerpt)
        count += 1
      end
    end
    puts "Populated #{count} article excerpts"
  end
end
