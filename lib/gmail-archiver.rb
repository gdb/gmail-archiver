require 'yaml'

require 'rubygems'
require 'stripe-context'
require 'highline/import'

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
  def self.get_login_info(cache)
    username = File.read('/tmp/username.txt').strip rescue nil
    unless username
      username = ask("Enter your email:  ")
      File.open('/tmp/username.txt', 'w', 0600) {|f| f.write(username)} if cache
    end

    password = File.read('/tmp/password.txt').strip rescue nil
    unless password
      password = ask("Enter your password:  ") { |q| q.echo = "*" }
      File.open('/tmp/password.txt', 'w', 0600) {|f| f.write(password)} if cache
    end

    [username, password]
  end

  module IMAP
    def slice_size
      100
    end

    def login
      if @imap
        begin
          @imap.logout
          @imap.disconnect
        rescue
        end
      end

      log_ann('Connecting to imap.gmail.com')
      @imap = Net::IMAP.new('imap.gmail.com', 993, true)
      log_ann('Authenticating')
      @imap.login(@username, @password)
    end

    def select
      log_ann('Selecting all mail')
      @imap.select('[Gmail]/All Mail')
    end
  end

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

    def benchmark(total, &blk)
      @db['elapsed'] ||= 0
      @db['consumed'] ||= 0

      start = Time.now.to_f
      actual, logical = blk.call
      delta = Time.now.to_f - start
      @db['elapsed'] += delta
      @db['consumed'] += logical

      records_per_second = @db['consumed'] /@db['elapsed']
      records_per_day = records_per_second * 24 * 60 * 60
      estimate = (total - @db['consumed']) / records_per_day

      log_ann("Just processed #{logical} logical records in #{sprintf('%.02f', delta)}s (actual: #{actual}). Total: #{@db['consumed']} in #{@db['elapsed']}s, for a total of #{sprintf('%.02f', records_per_second)} records per second, or #{records_per_day.to_i} records per day. I estimate #{sprintf('%.02f', estimate)} days remaining to process #{total} logical records.")
    end
  end
end
