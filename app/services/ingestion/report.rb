# frozen_string_literal: true

module Ingestion
  class Report
    attr_reader :source, :file, :started_at, :finished_at, :totals, :errors

    def initialize(source:, file:)
      @source = source
      @file   = file
      @started_at = Time.current
      @finished_at = nil
      @totals = Hash.new(0) # lines, valid, inserted, updated, skipped, errors
      @errors = []          # [{line:, code:, message:}]
    end

    def incr(key, by = 1) = @totals[key] += by

    def add_error(line:, code:, message:)
      @errors << { line:, code:, message: }
      incr(:errors)
    end

    def finish!
      @finished_at = Time.current
      self
    end

    def to_h
      {
        source: source,
        file: file.to_s,
        started_at: started_at,
        finished_at: finished_at,
        duration_s: (finished_at - started_at).round(3),
        totals: totals,
        errors: errors
      }
    end
  end
end
