
module TreasureData
module Command


class Runner
  def initialize
    @config_path = nil
    @apikey = nil
    @prog_name = nil
  end

  attr_accessor :apikey, :config_path, :prog_name

  def run(args=ARGV)
    require 'td/version'
    require 'optparse'

    $prog = @prog_name || File.basename($0)

    op = OptionParser.new
    op.version = TreasureData::VERSION
    op.banner = <<EOF
usage: #{$prog} [options] COMMAND [args]

options:
EOF

    op.summary_indent = "  "

    (class<<self;self;end).module_eval do
      define_method(:usage) do |errmsg|
        require 'td/command/list'
        puts op.to_s
        puts ""
        puts "commands:"
        TreasureData::Command::List.show_help(op.summary_indent)
        puts ""
        puts "Type '#{$prog} help COMMAND' for more information on a specific command."
        if errmsg
          puts "error: #{errmsg}"
          exit 1
        else
          exit 0
        end
      end
    end

    config_path = @config_path
    apikey = @apikey
    $verbose = false
    #$debug = false

    op.on('-c', '--config PATH', "path to config file (~/.td/td.conf)") {|s|
      config_path = s
    }

    op.on('-k', '--apikey KEY', "use this API key instead of reading the config file") {|s|
      apikey = s
    }

    op.on('-v', '--verbose', "verbose mode", TrueClass) {|b|
      $verbose = b
    }

    #op.on('-d', '--debug', "debug mode", TrueClass) {|b|
    #	$debug = b
    #}

    begin
      op.order!(args)
      usage nil if args.empty?
      cmd = args.shift

      require 'td/config'
      if config_path
        TreasureData::Config.path = config_path
      end
      if apikey
        TreasureData::Config.apikey = apikey
      end
    rescue
      usage $!.to_s
    end

    require 'td/command/list'

    method = TreasureData::Command::List.get_method(cmd)
    unless method
      $stderr.puts "'#{cmd}' is not a td command. Run '#{$prog}' to show the list."
      TreasureData::Command::List.show_guess(cmd)
      exit 1
    end

    begin
      method.call
    rescue TreasureData::ConfigError
      $stderr.puts "TreasureData account is not configured yet."
      $stderr.puts "Run '#{$prog} account' first."
    rescue
      $stderr.puts "error #{$!.class}: backtrace:"
      $!.backtrace.each {|b|
        $stderr.puts "  #{b}"
      }
      puts ""
      puts $!
    end
  end
end


end
end
