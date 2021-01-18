#!/usr/bin/env ruby

require 'amazing_print'
require 'set'
require 'shellwords'
require 'yaml'

raise "This script requires Ruby version 3 or later." unless RUBY_VERSION.split('.').first.to_i >= 3


# An instance of this parser class is created for each ractor.
class RactorParser

  attr_reader :found_words

  def parse(filespecs)
    filespecs.inject(Set.new) do |found_words, filespec|
      found_words | process_one_file(filespec)
    end
  end

  private def word?(string)
    @words ||= File.readlines('/usr/share/dict/words').map(&:chomp).map(&:downcase).sort
    @words.include?(string)
  end

  private def strip_punctuation(string)
    string.gsub(/[.,!@#$%^&*()"?:;]/, ' ')
  end

  private def file_lines(filespec)
    command = "strings #{Shellwords.escape(filespec)}"
    text = `#{command} 2>&1`
    strip_punctuation(text).split("\n")
  end

  private def line_words(line)
    line.split.map(&:downcase).select { |text| word?(text) }
  end

  private def process_one_file(filespec)
    print "Processing #{filespec}..."
    file_words = Set.new
    file_lines(filespec).each do |line|
      line_words(line).each { |word| file_words << word }
    end

    puts "found #{file_words.count} words."
    file_words
  end
end


class Main

  BASEDIR =  ARGV[0] || '.'
  FILEMASK = ARGV[1]

  def call
    found_words = run_ractor
    yaml = found_words.to_a.sort.to_yaml
    File.write('ractor-words.yaml', yaml)
    puts "Words are in ruby-words.yaml."
  end

  private def find_all_filespecs
    filemask = FILEMASK ? %Q{-name '#{FILEMASK}'} : ''
    command = "find -L #{BASEDIR} -type f #{filemask} -print"
    puts "Running the following command to find all filespecs to process: #{command}"
    `#{command}`.split("\n")
  end

  private def create_ractor
    Ractor.new do
      filespecs = Ractor.receive
      RactorParser.new.parse(filespecs)
    end
  end

  private def run_ractor
    ractor = create_ractor
    ractor.send(find_all_filespecs)
    ractor.take
  end
end

Main.new.call