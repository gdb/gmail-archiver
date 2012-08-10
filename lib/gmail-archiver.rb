require 'yaml'

require 'rubygems'
require 'stripe-context'

#############################

module StripeContext
  module TopLevel
    include StripeContext::Log::Loggable

    def self.assert(statement, msg=nil, hard=false)
      return if statement

      msg = msg ? "Assertion Failure: #{msg}" : "Assertion Failure"
      formatted = "#{msg}\n  #{caller.join("\n  ")}"
      log_error(formatted)
      raise msg if hard
    end
  end
end

def assert(*args)
  StripeContext::TopLevel.assert(*args)
end

StripeContext::Log::Loggable.init('default_level' => 'WARN')

############################

module GmailArchiver
  class AbstractRunner
    include StripeContext::Log::Loggable

    # Override
    def db_file
      raise NotImplementedError
    end

    def do_run
      raise NotImplementedError
    end

    def path(file)
      base = File.expand_path(File.join(File.dirname(__FILE__), '..'))
      File.join(base, file)
    end

    def load_db
      if File.exists?(db_file)
        log_ann("Loaded #{db_file}")
        @db = YAML.load_file(db_file)
      else
        log_ann("#{db_file} does not exist; initializing db")
        @db = {}
      end
    end

    def checkpoint_db
      log_ann('Checkpointing db')
      StripeContext::FileUtils.atomic_write(db_file) do |f|
        f.write(YAML.dump(@db))
      end
    end

    def run
      load_db
      do_run
    end

    def benchmark(&blk)
      @db['elapsed'] ||= 0
      @db['consumed'] ||= 0

      start = Time.now.to_f
      count = blk.call
      delta = Time.now.to_f - start
      @db['elapsed'] += delta
      @db['consumed'] += count

      records_per_second = @db['consumed'] /@db['elapsed']
      records_per_day = records_per_second * 24 * 60 * 60
      estimate = (2000000 - @db['consumed']) / records_per_day

      log_ann("Just fetched #{count} records in #{sprintf('%.02f', delta)}s. Total: #{@db['consumed']} in #{@db['elapsed']}s, for a total of #{sprintf('%.02f', records_per_second)} records per second, or #{records_per_day.to_i} records per day. I estimate #{sprintf('%.02f', estimate)} days remaining to fetch 2M records.")
    end
  end
end
