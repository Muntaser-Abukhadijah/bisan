# config/initializers/data_root.rb
# Sets a single source of truth for where exported scraper data lives.
# Default: ../our-data-export (sibling to the Rails repo)
# Override: set DATA_ROOT=/absolute/or/relative/path

require "pathname"

env_path = ENV["DATA_ROOT"]
default_path = Rails.root.join("..", "our-data-export").expand_path

DATA_ROOT_PATH = if env_path && !env_path.empty?
  Pathname.new(env_path).expand_path
else
  default_path
end

# Prefer putting this on Rails config so any part of the app can use it
Rails.application.config.x.data_root = DATA_ROOT_PATH

# Optional: log at boot so it’s visible in logs
Rails.logger.info("[init] DATA_ROOT => #{Rails.application.config.x.data_root}")
