task :console do
  require 'irb'
  require 'pry'
  require 'pry-debugger'
  require_relative 'lib/molen'
  include Molen
  ARGV.clear
  IRB.start
end

task :run do
    require_relative 'lib/molen'
    include Molen

    Molen.run open(ENV['file']).read, ENV['file']
end
