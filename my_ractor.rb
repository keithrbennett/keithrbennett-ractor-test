#!/usr/bin/env ruby

require 'amazing_print'
require 'benchmark'
require 'etc'
require 'prettyprint'
require 'set'
require 'shellwords'
require 'json'
require 'yaml'

raise "This script requires Ruby version 3 or later." unless RUBY_VERSION.split('.').first.to_i >= 3


# An instance of this parser class is created for each ractor.
class RactorFileParser

  attr_reader :dictionary_words, :name

  def initialize(name, dictionary_words)
    @dictionary_words = dictionary_words
    @name = name
  end

  def parse(filespec)
    # e.g.: ractor_9     casa/app/controllers/case_court_reports_controller.rb
    printf("%-12s %s\n", name, filespec)
    file_lines(filespec).each_with_object(Set.new) do |line, file_words|
      line_words(line).each { |word| file_words << word }
    end
  end

  private def word?(string)
    dictionary_words.include?(string)
  end

  private def strip_punctuation(string)
    string.gsub(/[[:punct:]]/, ' ')
  end

  private def file_lines(filespec)
    command = "strings #{Shellwords.escape(filespec)}"
    strip_punctuation(`#{command}`).split("\n")
  end

  private def line_words(line)
    line.split.map(&:downcase).select { |text| word?(text) }
  end
end


class Main

  BASEDIR =  ARGV[0] || '.'
  FILEMASK = ARGV[1]

  def call
    check_arg_count
    ractors = create_and_populate_ractors
    all_words = nil
    benchmark = Benchmark.measure { all_words = collate_ractor_results(ractors) }
    write_results(all_words, benchmark)
  end


  private def ractor_count
    unless @ractor_count
      specified_as_env_var = !!ENV['RACTOR_COUNT']
      @ractor_count = specified_as_env_var ? ENV['RACTOR_COUNT'].to_i : Etc.nprocessors

      raise "Ractor count must > 0." unless @ractor_count > 0

      unless specified_as_env_var
        puts "Using the number of CPU's (#{@ractor_count}) as the number of ractors."
        puts "You can also optionally specify the number of ractors to use with the environment variable RACTOR_COUNT."
      end
    end
    @ractor_count
  end


  private def write_results(all_words, benchmark)
    File.write('ractor-words.txt', all_words.to_a.sort.join("\n"))
    puts "\nFinished. Words are in ractor-words.txt, log files are *.log."
    benchmark_hash = benchmark_to_hash(benchmark)
    ap benchmark_hash
    puts "\nJSON:"
    puts benchmark_hash.to_json
    puts "\nYAML:"
    puts benchmark_hash.to_yaml
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


  private def create_parser_ractor(seq_no)
    Ractor.new(name: "ractor_#{seq_no}") do
      File.open("#{name}.log", 'w') do |log|
        found_words = Set.new
        dictionary_words = Ractor.receive
        yielder = Ractor.receive
        parser = RactorFileParser.new(name, dictionary_words)
        start_time = Time.now

        loop do
          filespec = yielder.take

          # e.g.:      0.00001   Received casa/app/models/followup.rb for processing.
          log.printf("%12.5f  Received %s for processing.\n", (Time.now - start_time).round(5), filespec)

          if filespec.is_a?(Array)
            puts "\n\n\n!!!!\nRactor received a message that contained the list of all filespecs, instead of a single filespec."
            puts "This was not sent via the filespec yielder. Why? Skipping it...\n!!!!\n\n"
            next
          end
          file_start_time = Time.now
          found_words |= parser.parse(filespec)

          # e.g.:    46.33613                                        +45.68088  Completed processing casa/app/documents/templates/report_template_non_transition.docx
          log.printf("%12.5f%12s+%8.5f Completed processing %s\n", (Time.now - start_time).round(5), '', (Time.now - file_start_time).round(5), filespec)
        end

        # e.g.: Ractor ractor_16    duration (secs): 18.76906
        message = sprintf("Ractor %-12s duration (secs): %.5f", name, (Time.now - start_time).round(5))
        puts message
        log.puts message

        found_words
      end
    end
  end


  private def create_filespec_yielding_ractor(all_filespecs)
    ractor = Ractor.new(name: 'FilespecYielder') do
      File.open('filespec_yielder_ractor.log', 'w') do |log|
        filespecs = Ractor.receive
        filespecs.each do |filespec|
          Ractor.yield(filespec)
          log.puts filespec
        end
      end
    end
    ractor.send(all_filespecs)
    ractor
  end


  private def create_and_populate_ractors
    puts "Creating #{ractor_count} ractor(s)."
    filespec_yielder = create_filespec_yielding_ractor(find_all_filespecs)
    dictionary_words = File.readlines('/usr/share/dict/words').map(&:chomp).map(&:downcase).sort
    ractors = (0...ractor_count).map { |n| create_parser_ractor(n) }
    ractors.each do |ractor|
      ractor.send(dictionary_words)
      ractor.send(filespec_yielder)
    end
  end


  private def find_all_filespecs
    filemask = FILEMASK ? %Q{-name '#{FILEMASK}'} : ''
    command = "find -L #{BASEDIR} -type f #{filemask} -print"
    puts "Running the following command to find all filespecs to process: #{command}"
    filespecs = `#{command}`.split("\n").map(&:freeze)
    puts "Found #{filespecs.size} files."
    filespecs
  end


  private def benchmark_to_hash(bm)
    {
      user: bm.utime.round(3),
      system: bm.stime.round(3),
      total: bm.total.round(3),
      real: bm.real.round(3)
    }
  end
end

Main.new.call