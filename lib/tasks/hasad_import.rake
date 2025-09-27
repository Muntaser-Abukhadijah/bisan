# lib/tasks/hasad_import.rake
namespace :hasad do
  desc "Import NDJSON from hasad recursively (debug)"
  task import: :environment do
    root = ENV["HASAD_ROOT"].presence || Rails.root.join("hasad").to_s
    abort "[hasad:import] Root not found: #{root}" unless Dir.exist?(root)

    all_ndjson = Dir.glob(File.join(root, "**", "*.ndjson")).sort
    puts "[hasad:import] Using HASAD_ROOT=#{root}"
    puts "[hasad:import] All *.ndjson found: #{all_ndjson.size}"
    all_ndjson.first(10).each { |p| puts "  • #{p}" }

    before_auth = Author.count
    before_art  = Article.count

    HasadImportJob.perform_now

    puts "[hasad:import] Counts before  => authors=#{before_auth}, articles=#{before_art}"
    puts "[hasad:import] Counts after   => authors=#{Author.count}, articles=#{Article.count}"
  end
end
