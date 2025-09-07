# frozen_string_literal: true

module Ingestion
  class LineReader
    Line = Struct.new(:num, :raw, :json, keyword_init: true)

    def initialize(pathname)
      @path = pathname
    end

    def each
      return enum_for(:each) unless block_given?
      unless @path.file?
        yield Line.new(num: 0, raw: nil, json: nil)
        return
      end

      num = 0
      File.foreach(@path, encoding: "UTF-8") do |raw|
        num += 1
        next if raw.strip.empty?
        begin
          json = JSON.parse(raw, symbolize_names: true)
          yield Line.new(num:, raw:, json:)
        rescue JSON::ParserError => e
          yield Line.new(num:, raw:, json: { __error__: "json_parse_error", message: e.message })
        end
      end
    end
  end
end
