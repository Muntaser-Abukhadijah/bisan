# frozen_string_literal: true

require "json"

module Ingestion
  class Importer
    def initialize(source:, data_root: nil, logger: Rails.logger)
      @source     = source.to_s
      @data_root  = Pathname(data_root || Rails.application.config.x.data_root)
      @logger     = logger
      @normalizer = Normalizer.new(source_id: @source)
      @upserter   = Upserter.new
    end

    def run(filename: "parsed.ndjson")
      file = @data_root.join(@source, filename)
      report = Report.new(source: @source, file:)

      unless file.file?
        @logger.warn("[ingest] #{@source}: file not found: #{file}")
        return report.finish!
      end

      @logger.info("[ingest] #{@source}: reading #{file}")

      reader = LineReader.new(file)
      reader.each do |line|
        report.incr(:lines)

        if line.json.nil?
          report.add_error(line: line.num, code: "json_parse_error", message: "invalid json")
          next
        end

        if (err = line.json[:__error__])
          report.add_error(line: line.num, code: err, message: line.json[:message])
          next
        end

        norm = @normalizer.call(line.json)
        unless norm.ok?
          report.add_error(line: line.num, code: norm.error, message: "normalization failed")
          next
        end

        report.incr(:valid)

        outcome = @upserter.call(norm.data)
        case outcome.status
        when :inserted then report.incr(:inserted)
        when :updated  then report.incr(:updated)
        when :skipped  then report.incr(:skipped)
        when :error
          report.add_error(line: line.num, code: "upsert_error", message: outcome.message)
        else
          report.add_error(line: line.num, code: "unknown_status", message: outcome.inspect)
        end
      end

      report.finish!
      @logger.info("[ingest] #{@source}: #{report.totals.inspect}")

      # after @logger.info totals
      begin
        dumps = Rails.root.join("dumps")
        dumps.mkpath
        stamp = Time.current.strftime("%Y%m%d-%H%M%S")
        File.write(dumps.join("ingest_#{@source}_#{stamp}.json"), JSON.pretty_generate(report.to_h))
      rescue => e
        @logger.warn("[ingest] failed to write report file: #{e.message}")
      end

      report
    end
  end
end
