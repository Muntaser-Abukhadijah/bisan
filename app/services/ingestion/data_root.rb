# app/services/ingestion/data_root.rb
module Ingestion
  module DataRoot
    module_function

    def path
      Rails.application.config.x.data_root
    end

    def source_path(source)
      path.join(source) # e.g., /.../our-data-export/metras
    end

    def ndjson_path(source, filename: "parsed.ndjson")
      source_path(source).join(filename)
    end
  end
end
