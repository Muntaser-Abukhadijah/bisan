# Bisan Project Documentation

## Overview
**Bisan** is a Ruby on Rails–based content aggregation platform.  
It provides a centralized place to collect, manage, and display content from various sources.  

### Purpose
- To enable browsing of content from multiple external websites in one place.
- To serve as a foundation for further experimentation (e.g., search, AI integrations, recommendations).

**Bisan** provides:
* Centrilized place that have all the Articals that talks about Palestine.
* Search engine that enables users to search on top of everything avialble in the website (Articals, books, videos trascripts)

---
## Project Structuer
```
.
├── Dockerfile
├── Gemfile
├── Gemfile.lock
├── Procfile.dev
├── README.md
├── Rakefile
├── app
│   ├── assets
│   │   ├── builds
│   │   │   ├── tailwind
│   │   │   └── tailwind.css
│   │   ├── images
│   │   ├── stylesheets
│   │   │   └── application.tailwind.css
│   │   └── tailwind
│   │       └── application.css
│   ├── controllers
│   │   ├── application_controller.rb
│   │   ├── articles_controller.rb
│   │   ├── authors_controller.rb
│   │   └── concerns
│   │       └── internationalization.rb
│   ├── helpers
│   │   ├── application_helper.rb
│   │   └── articles_helper.rb
│   ├── javascript
│   │   ├── application.js
│   │   └── controllers
│   │       ├── application.js
│   │       ├── hello_controller.js
│   │       └── index.js
│   ├── jobs
│   │   └── application_job.rb
│   ├── mailers
│   │   └── application_mailer.rb
│   ├── models
│   │   ├── application_record.rb
│   │   ├── article.rb
│   │   ├── author.rb
│   │   └── concerns
│   └── views
│       ├── articles
│       │   ├── _card.html.erb
│       │   ├── index.html.erb
│       │   └── show.html.erb
│       ├── author
│       │   ├── _card.html.erb
│       │   ├── index.html.erb
│       │   └── show.html.erb
│       ├── layouts
│       │   ├── application.html.erb
│       │   ├── mailer.html.erb
│       │   └── mailer.text.erb
│       ├── pwa
│       │   ├── manifest.json.erb
│       │   └── service-worker.js
│       └── shared
│           └── _pagination.html.erb
├── bin
│   ├── brakeman
│   ├── bundle
│   ├── dev
│   ├── docker-entrypoint
│   ├── jobs
│   ├── kamal
│   ├── rails
│   ├── rake
│   ├── rubocop
│   ├── setup
│   └── thrust
├── config
│   ├── application.rb
│   ├── boot.rb
│   ├── cable.yml
│   ├── cache.yml
│   ├── credentials.yml.enc
│   ├── database.yml
│   ├── deploy.yml
│   ├── environment.rb
│   ├── environments
│   │   ├── development.rb
│   │   ├── production.rb
│   │   └── test.rb
│   ├── initializers
│   │   ├── assets.rb
│   │   ├── content_security_policy.rb
│   │   ├── filter_parameter_logging.rb
│   │   ├── inflections.rb
│   │   ├── meilisearch.rb
│   │   └── pagy.rb
│   ├── locales
│   │   ├── ar.yml
│   │   └── en.yml
│   ├── master.key
│   ├── puma.rb
│   ├── queue.yml
│   ├── recurring.yml
│   ├── routes.rb
│   └── storage.yml
├── config.ru
├── data.ms
│   ├── VERSION
│   ├── auth
│   │   ├── data.mdb
│   │   └── lock.mdb
│   ├── indexes
│   │   └── 5416ca31-3ba1-4773-9a88-cdd0f4beb562
│   │       ├── data.mdb
│   │       └── lock.mdb
│   ├── instance-uid
│   ├── tasks
│   │   ├── data.mdb
│   │   └── lock.mdb
│   └── update_files
├── db
│   ├── cable_schema.rb
│   ├── cache_schema.rb
│   ├── migrate
│   │   ├── 20250825093327_create_articles.rb
│   │   └── 20250828102639_update_articles_for_show_page.rb
│   ├── queue_schema.rb
│   ├── schema.rb
│   └── seeds.rb
├── dumps
├── lib
│   └── tasks
├── log
│   └── development.log
├── package.json
├── prompt.md
├── public
│   ├── 400.html
│   ├── 404.html
│   ├── 406-unsupported-browser.html
│   ├── 422.html
│   ├── 500.html
│   ├── icon.png
│   ├── icon.svg
│   └── robots.txt
├── script
├── storage
│   ├── development.sqlite3
│   ├── development.sqlite3-shm
│   ├── development.sqlite3-wal
│   └── test.sqlite3
├── tmp
│   ├── cache
│   │   └── bootsnap
│   │       ├── compile-cache-iseq
│   │       ├── compile-cache-yaml
│   │       └── load-path-cache
│   ├── caching-dev.txt
│   ├── pids
│   │   └── server.pid
│   ├── restart.txt
│   ├── sockets
│   └── storage
└── vendor
```

### Schema
```
ActiveRecord::Schema[8.0].define(version: 2025_08_31_105125) do
  create_table "articles", force: :cascade do |t|
    t.string "title"
    t.string "article_image"
    t.text "excerpt"
    t.string "category"
    t.date "publish_date"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "body"
    t.string "source_url"
    t.string "tags"
    t.integer "author_id", null: false
    t.index ["author_id"], name: "index_articles_on_author_id"
  end

  create_table "authors", force: :cascade do |t|
    t.string "name", null: false
    t.text "bio"
    t.string "avatar_url"
    t.json "social_links", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  add_foreign_key "articles", "authors"
end
```

