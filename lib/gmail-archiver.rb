require 'logger'
require 'yaml'
require 'tempfile'

require 'rubygems'
require 'highline/import'

$log = Logger.new(STDERR)
$log.level = Logger::INFO

def assert(statement, msg=nil, hard=false)
  return if statement

  msg = msg ? "Assertion Failure: #{msg}" : "Assertion Failure"
  formatted = "#{msg}\n  #{caller.join("\n  ")}"
  $log.error(formatted)
  raise msg if hard
end

module GmailArchiver
  module Third
    # From http://api.rubyonrails.org/classes/File.html
    def self.atomic_write(file_name, temp_dir = Dir.tmpdir)
      temp_file = Tempfile.new(File.basename(file_name), temp_dir)
      yield temp_file
      temp_file.close

      begin
        # Get original file permissions
        old_stat = File.stat(file_name)
      rescue Errno::ENOENT
        # No old permissions, write a temp file to determine the defaults
        check_name = File.join(File.dirname(file_name), ".permissions_check.#{Thread.current.object_id}.#{Process.pid}.#{rand(1000000)}")
        File.open(check_name, "w") { }
        old_stat = File.stat(check_name)
        File.unlink(check_name)
      end

      # Overwrite original file with temp file
      ::FileUtils.mv(temp_file.path, file_name)

      # Set correct permissions on new file TODO: there is a secuity
      # race here, where a sensitive tempfile could be momentarily world
      # readable.
      # TODO: don't do this unless root
      File.chown(old_stat.uid, old_stat.gid, file_name)
      File.chmod(old_stat.mode, file_name)
    end
  end

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

      $log.info('Connecting to imap.gmail.com')
      @imap = Net::IMAP.new('imap.gmail.com', 993, true)
      $log.info('Authenticating')
      @imap.login(@username, @password)
    end

    def select
      $log.info('Selecting all mail')
      @imap.select('[Gmail]/All Mail')
    end
  end

  class AbstractRunner
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
        $log.info("Loaded #{db_file}")
        @db = YAML.load_file(db_file)
      else
        $log.info("#{db_file} does not exist; initializing db")
        @db = {}
      end
    end

    def checkpoint_db
      $log.info('Checkpointing db')
      Third.atomic_write(db_file) do |f|
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

      $log.info("Just processed #{logical} logical records in #{sprintf('%.02f', delta)}s (actual: #{actual}). Total: #{@db['consumed']} in #{@db['elapsed']}s, for a total of #{sprintf('%.02f', records_per_second)} records per second, or #{records_per_day.to_i} records per day. I estimate #{sprintf('%.02f', estimate)} days remaining to process #{total} logical records.")
    end
  end
end
