task :console do
    require 'irb'
    require 'bundler/setup'
    require 'llvm/core'
    require 'ruby-graphviz'
    require_relative 'lib/molen'
    include Molen
    ARGV.clear
    IRB.start
end