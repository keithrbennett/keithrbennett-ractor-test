#!/usr/bin/env ruby

require 'amazing_print'
require 'etc'
require 'set'
require 'shellwords'
require 'yaml'

raise "This script requires Ruby version 3 or later." unless RUBY_VERSION.split('.').first.to_i >= 3


# An instance of this parser class is created for each ractor.
class RactorParser

  attr_reader :dictionary_words

  def initialize(dictionary_words)
    @dictionary_words = dictionary_words
  end

  def parse(filespecs)
    filespecs.inject(Set.new) do |found_words, filespec|
      found_words | process_one_file(filespec)
    end
  end

  private def word?(string)
    dictionary_words.include?(string)
  end

  private def strip_punctuation(string)
    punctuation_regex = /[[:punct:]]/
    string.gsub(punctuation_regex, ' ')
  end

  private def file_lines(filespec)
    command = "strings #{Shellwords.escape(filespec)}"
    text = `#{command}`
    strip_punctuation(text).split("\n")
  end

  private def line_words(line)
    line.split.map(&:downcase).select { |text| word?(text) }
  end

  private def process_one_file(filespec)
    file_words = Set.new
    file_lines(filespec).each do |line|
      line_words(line).each { |word| file_words << word }
    end

    # puts "Found #{file_words.count} words in #{filespec}."
    file_words
  end
end


class Main

  BASEDIR =  ARGV[0] || '.'
  FILEMASK = ARGV[1]
  CPU_COUNT = Etc.nprocessors

  def call
    check_arg_count
    slices = get_filespec_slices
    ractors = create_and_populate_ractors(slices)
    all_words = collate_ractor_results(ractors)
    yaml = all_words.to_a.sort.to_yaml
    File.write('ractor-words.yaml', yaml)
    puts "Words are in ractor-words.yaml."
  end

  private def check_arg_count
    if ARGV.length > 2
      puts "Syntax is ractor [base_directory] [filemask], and filemask must be quoted so that the shell does not expand it."
      exit -1
    end
  end

  private def collate_ractor_results(ractors)
    ractors.inject(Set.new) do |all_words, ractor|
      all_words | ractor.take
    end
  end

  private def get_filespec_slices
    all_filespecs = find_all_filespecs
    slice_size = (all_filespecs.size / CPU_COUNT) + 1
    # slice_size = all_filespecs.size # use this line instead of previous to test with 1 ractor
    slices = all_filespecs.each_slice(slice_size).to_a
    puts "Processing #{all_filespecs.size} files in #{slices.size} slices, whose sizes are:\n#{slices.map(&:size).inspect}"
    slices
  end

  private def create_and_populate_ractors(slices)
    words = File.readlines('/usr/share/dict/words').map(&:chomp).map(&:downcase).sort

    slices.map do |slice|
      ractor = Ractor.new do
        filespecs = Ractor.receive
        dictionary_words = Ractor.receive
        RactorParser.new(dictionary_words).parse(filespecs)
      end
      ractor.send(slice)
      ractor.send(words)
      ractor
    end
  end

  private def find_all_filespecs
    filemask = FILEMASK ? %Q{-name '#{FILEMASK}'} : ''
    command = "find -L #{BASEDIR} -type f #{filemask} -print"
    puts "Running the following command to find all filespecs to process: #{command}"
    `#{command}`.split("\n")
  end
end

Main.new.call