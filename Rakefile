task :console do
  require 'pry'
  require_relative 'lib/molen'
  include Molen

  ARGV.clear
  Pry::CLI.parse_options
end

task :run do
    require_relative 'lib/molen'
    include Molen

    unless ENV['file']
        puts "ERROR: No file or directory given!"
        exit 1
    end

    if File.directory?(ENV['file']) then
        Dir[ENV['file'] + "**/*.en"].each do |file|
            puts "# FILE #{file}"
            begin
                Molen.run open(file).read, file
            rescue StandardError => ex
                puts "# Error executing file #{file}: #{ex.to_s}"
            end
            puts ""
        end
    else
        Molen.run open(ENV['file']).read, ENV['file']
    end
end
