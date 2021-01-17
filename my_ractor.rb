#!/usr/bin/env ruby

require 'amazing_print'
require 'set'
require 'shellwords'
require 'yaml'

WORDS = File.readlines('/usr/share/dict/words').map(&:chomp).map(&:downcase).sort
puts "Read #{WORDS.size} words from system dictionary."

BASEDIR =  ARGV[0] || '.'
FILEMASK = ARGV[1]

def strip_punctuation(string)
    string.gsub(/[.,!@#$%^&*()"?:;]/, ' ')    
end

def file_lines(filespec)
    command = "strings #{Shellwords.escape(filespec)}"
    text = `#{command} 2>&1`
    strip_punctuation(text).split("\n")
end

def line_words(line)
    line.split.map(&:downcase).select { |word| WORDS.include?(word) }
end

def process_one_file(filespec)
    print "Processing #{filespec}..."
    file_words = Set.new
    file_lines(filespec).each do |line| 
        line_words(line).each { |word| file_words << word }
    end

    puts "found #{file_words.count} words."
    file_words
end

def build_find_command
    filemask = FILEMASK ? %Q{-name '#{FILEMASK}'} : ''
    command = "find -L #{BASEDIR} -type f #{filemask} -print"
    puts command
    command
end

def main
    words = Set.new
    filespecs = `#{build_find_command}`.split("\n")
    puts "Processing #{filespecs.size} files."
    filespecs.each do |filespec|
        words = words | process_one_file(filespec)
    end
    yaml = words.to_a.sort.to_yaml
    File.write('ruby-words.yaml', yaml)
    puts "Words are in ruby-words.yaml."
end

main
