require 'optparse'

module Merb
  class Config
    class << self
      # Returns the hash of default config values for Merb.
      #
      # @return [Hash] The defaults for the config.
      #
      # @api private
      def defaults
        @defaults ||= {
          host: '0.0.0.0',
          port: '4000',
          adapter: 'runner',
          reload_classes: true,
          fork_for_class_load: Merb.forking_environment?,
          environment: 'development',
          merb_root: Dir.pwd,
          use_mutex: true,
          log_delimiter: ' ~ ',
          log_auto_flush: false,
          log_level: :info,
          log_stream: STDOUT,
          disabled_components: Merb.on_windows? ? [:signals] : [],
          deferred_actions: [],
          verbose: false,
          name: 'merb',
          kernel_dependencies: true,
          gemfile: nil,
          gemenv: nil
        }
      end

      # Yields the configuration.
      #
      # @yieldparam [Hash] config The configuration
      #
      # @example Use like:
      #     Merb::Config.use do |config|
      #       config[:exception_details] = false
      #       config[:log_stream]        = STDOUT
      #     end
      #
      # @return [nil]
      #
      # @api public
      def use
        @configuration ||= {}
        yield @configuration
        nil
      end

      # Detects whether the provided key is in the config.
      #
      # @param [Object] key The key to check.
      #
      # @return [Boolean] True if the key exists in the config.
      #
      # @api public
      def key?(key)
        @configuration.key?(key)
      end

      # Retrieve the value of a config entry.
      #
      # @param [Object] key The key to retrieve the parameter for.
      #
      # @return [Object] The value of the configuration parameter.
      #
      # @api public
      def [](key)
        (@configuration ||= setup)[key]
      end

      # Set the value of a config entry.
      #
      # @param [Object] key The key to set the parameter for.
      # @param [Object] val The value of the parameter.
      #
      # @api public
      def []=(key, val)
        (@configuration ||= setup)[key] = val
      end

      # Remove the value of a config entry.
      #
      # @param [Object] key The key of the parameter to delete.
      #
      # @return [Object] The value of the removed entry.
      #
      # @api public
      def delete(key)
        @configuration.delete(key)
      end

      # Retrieve the value of a config entry, returning the provided default
      #   if the key is not present.
      #
      # @param [Object] key The key to retrieve the parameter for.
      # @param [Object] default The default value to return if the parameter
      #   is not set.
      #
      # ==== Returns
      # Object:: The value of the configuration parameter or the default.
      #
      # @api public
      def fetch(key, default)
        @configuration.fetch(key, default)
      end

      # Returns the configuration as a hash.
      #
      # @return [Hash] The config as a hash.
      #
      # @api public
      def to_hash
        @configuration
      end

      # Returns the config as YAML.
      #
      # @return [String] The config as YAML.
      #
      # @api public
      def to_yaml
        require 'yaml'
        @configuration.to_yaml
      end

      # Sets up the configuration by storing the given settings.
      #
      # @param [Hash] settings Configuration settings to use. These are
      #   merged with the defaults.
      #
      # @return [Hash] The configuration as a hash.
      #
      # @api private
      def setup(settings = {})
        # Merge new settings with any existing configuration settings
        settings = @configuration.merge(settings) unless @configuration.nil?

        # Merge new settings with default settings
        config = defaults.merge(settings)

        config[:fork_for_class_load] = false unless config[:reload_classes]

        dev_mode = config[:environment] == 'development'
        config[:reap_workers_quickly] = dev_mode & !config[:cluster] unless config.key?(:reap_workers_quickly)

        config[:bind_fail_fatal] = dev_mode unless config.key?(:bind_fail_fatal)

        # Set mutex to dispatcher
        ::Merb::Dispatcher.use_mutex = config[:use_mutex]

        @configuration = config
      end

      # Parses the command line arguments and stores them in the config.
      #
      # @param [Array<String>] argv The command line arguments.
      #
      # @return [Hash] The configuration as a hash.
      #
      # @api private
      def parse_args(argv = ARGV)
        @configuration ||= {}
        # Our primary configuration hash for the length of this method
        options = {}

        # Environment variables always win
        options[:environment] = ENV['MERB_ENV'] if ENV['MERB_ENV']

        # Build a parser for the command line arguments
        opts = OptionParser.new do |parser|
          parser.version = Merb::VERSION

          parser.banner = 'Usage: merb [uGdcIpPhmailLerkKX] [argument]'
          parser.define_head 'Merb. Pocket rocket web framework'
          parser.separator '*' * 80
          parser.separator 'If no flags are given, Merb starts in the ' \
            'foreground on port 4000.'
          parser.separator '*' * 80

          parser.on('-u', '--user USER', 'This flag is for having merb run ' \
                  'as a user other than the one currently logged in. Note: ' \
                  'if you set this you must also provide a --group option ' \
                  'for it to take effect.') do |user|
            options[:user] = user
          end

          parser.on('-G', '--group GROUP', 'This flag is for having merb run ' \
                  'as a group other than the one currently logged in. Note: ' \
                  'if you set this you must also provide a --user option ' \
                  'for it to take effect.') do |group|
            options[:group] = group
          end

          parser.on('-d', '--daemonize', 'This will run a single merb in the ' \
                  'background.') do |_daemon|
            options[:daemonize] = true
          end

          parser.on('-N', '--no-daemonize', 'This will allow you to run a ' \
                  'cluster in console mode') do |_no_daemon|
            options[:daemonize] = false
          end

          parser.on('-c', '--cluster-nodes NUM_MERBS', Integer,
                    'Number of merb daemons to run.') do |nodes|
            options[:daemonize] = true unless options.key?(:daemonize)
            options[:cluster] = nodes
          end

          parser.on('-I', '--init-file FILE', 'File to use for initialization ' \
                  'on load, defaults to config/init.rb') do |init_file|
            options[:init_file] = init_file
          end

          parser.on('-p', '--port PORTNUM', Integer, 'Port to run merb on, ' \
                  'defaults to 4000.') do |port|
            options[:port] = port
          end

          parser.on('-o', '--socket-file FILE', 'Socket file to run merb on, ' \
                  'defaults to [Merb.root]/log/merb.sock. This is for ' \
                  'web servers, like thin, that use sockets.' \
                  'Specify this *only* if you *must*.') do |port|
            options[:socket_file] = port
          end

          parser.on('-s', '--socket SOCKNUM', Integer, 'Socket number to run ' \
                  'merb on, defaults to 0.') do |port|
            options[:socket] = port
          end

          parser.on('-n', '--name NAME', String, 'Set the name of the application. '\
                  'This is used in the process title and log file names.') do |name|
            options[:name] = name
          end

          parser.on('-P', '--pid PIDFILE', 'PID file, defaults to ' \
                  '[Merb.root]/log/merb.main.pid for the master process and' \
                  '[Merb.root]/log/merb.[port number].pid for worker ' \
                  'processes. For clusters, use %s to specify where ' \
                  'in the file merb should place the port number. For ' \
                  'instance: -P myapp.%s.pid') do |pid_file|
            options[:pid_file] = pid_file
          end

          parser.on('-h', '--host HOSTNAME', 'Host to bind to ' \
                  '(default is 0.0.0.0).') do |host|
            options[:host] = host
          end

          parser.on('-m', '--merb-root /path/to/approot', 'The path to the ' \
                  'Merb.root for the app you want to run ' \
                  '(default is current working directory).') do |root|
            options[:merb_root] = File.expand_path(root)
          end

          adapters = %i[mongrel emongrel thin ebb fastcgi webrick]

          parser.on('-a', '--adapter ADAPTER',
                    'The rack adapter to use to run merb (default is thin)' \
                    "[#{adapters.join(', ')}]") do |adapter|
            options[:adapter] ||= adapter
          end

          parser.on('-R', '--rackup FILE', 'Load an alternate Rack config ' \
                  'file (default is config/rack.rb)') do |rackup|
            options[:rackup] = rackup
          end

          parser.on('-i', '--irb-console', 'This flag will start merb in ' \
                  'irb console mode. All your models and other classes will ' \
                  'be available for you in an irb session.') do |_console|
            options[:adapter] = 'irb'
          end

          parser.on('-S', '--sandbox', 'This flag will enable a sandboxed irb ' \
                  'console. If your ORM supports transactions, all edits will ' \
                  'be rolled back on exit.') do |_sandbox|
            options[:sandbox] = true
          end

          parser.on('-l', '--log-level LEVEL', 'Log levels can be set to any of ' \
                  'these options: debug < info < warn < error < ' \
                  'fatal (default is info)') do |log_level|
            options[:log_level] = log_level.to_sym
            options[:force_logging] = true
          end

          parser.on('-L', '--log LOGFILE', 'A string representing the logfile to ' \
                  'use. Defaults to [Merb.root]/log/merb.[main].log for the ' \
                  'master process and [Merb.root]/log/merb[port number].log' \
                  'for worker processes') do |log_file|
            options[:log_file] = log_file
            options[:force_logging] = true
          end

          parser.on('-e', '--environment STRING', 'Environment to run Merb ' \
                  'under [development, production, testing] ' \
                  '(default is development)') do |env|
            options[:environment] = env
          end

          parser.on('-r', "--script-runner ['RUBY CODE'| FULL_SCRIPT_PATH]",
                    'Command-line option to run scripts and/or code in the ' \
                    'merb app.') do |code_or_file|
            options[:runner_code] = code_or_file
            options[:adapter] = 'runner'
          end

          parser.on('-K', '--graceful PORT or all', 'Gracefully kill one ' \
                  'merb proceses by port number.  Use merb -K all to ' \
                  'gracefully kill all merbs.') do |ports|
            options[:action] = :kill
            ports = 'main' if ports == 'all'
            options[:port] = ports
          end

          parser.on('-k', '--kill PORT', 'Force kill one merb worker ' \
                  'by port number. This will cause the worker to' \
                  'be respawned.') do |port|
            options[:action] = :kill_9
            port = 'main' if port == 'all'
            options[:port] = port
          end

          parser.on('--fast-deploy', 'Reload the code, but not your' \
            'init.rb or gems') do
            options[:action] = :fast_deploy
          end

          # @todo Do we really need this flag? It seems unlikely to want to
          #   change the mutex from the command-line.
          parser.on('-X', '--mutex on/off', 'This flag is for turning the ' \
                  'mutex lock on and off.') do |mutex|
            options[:use_mutex] = !(mutex == 'off')
          end

          parser.on('-D', '--debugger', 'Run merb using rDebug.') do
            require 'ruby-debug'
            Debugger.start

            # Load up any .rdebugrc files we find
            ['.', ENV['HOME'], ENV['HOMEPATH']].each do |script_dir|
              script_file = "#{script_dir}/.rdebugrc"
              Debugger.run_script script_file, StringIO.new if File.exist?(script_file)
            end

            Debugger.settings[:autoeval] = true if Debugger.respond_to?(:settings)
            puts 'Debugger enabled'
          rescue LoadError
            puts 'You need to install ruby-debug to run the server in ' \
              "debugging mode. With gems, use `gem install ruby-debug'"
            exit
          end

          parser.on('-V', '--verbose', 'Print extra information') do
            options[:verbose] = true
          end

          parser.on('-C', '--console-trap', 'Enter an irb console on ^C') do
            options[:console_trap] = true
          end

          parser.on('-?', '-H', '--help', 'Show this help message') do
            puts opts
            exit
          end
        end

        # Parse what we have on the command line
        begin
          opts.parse!(argv, into: nil)
        rescue OptionParser::InvalidOption => e
          Merb.fatal! e.message, e
        end
        Merb::Config.setup(options)
      end

      # @api private
      attr_accessor :configuration

      # Set configuration parameters from a code block, where each method
      # evaluates to a config parameter.
      #
      # @param &block Configuration parameter block.
      #
      # @example Use like:
      #     # Set environment and log level.
      #     Merb::Config.configure do
      #       environment "development"
      #       log_level   "debug"
      #       log_file    Merb.root / "log" / "special.log"
      #     end
      #
      # @return [nil]
      #
      # @api public
      def configure(&block)
        ConfigBlock.new(self, &block) if block_given?
        nil
      end

      # Allows retrieval of single key config values via `Merb.config.<key>`
      # Allows single key assignment via `Merb.config.<key> = ...`
      #
      # @param [#to_s] method Method name as hash key value.
      # @param *args Value to set the configuration parameter to.
      #
      # @return [Object] The value of the entry fetched or assigned to.
      #
      # @api public
      def method_missing(method, *args)
        if method.to_s[-1, 1] == '='
          @configuration[method.to_s.tr('=', '').to_sym] = *args
        else
          @configuration[method]
        end
      end
    end # class << self

    class ConfigBlock
      # Evaluates the provided block, where any call to a method causes
      # \#[]= to be called on klass with the method name as the key and
      # the arguments as the value.
      #
      # @param [#[]=] klass The object on which to assign values.
      # @param &block The block which specifies the config values to set.
      #
      # @return [nil]
      #
      # @api private
      def initialize(klass, &block)
        @klass = klass
        instance_eval(&block)
      end

      # Assign args as the value of the entry keyed by method.
      #
      # @api private
      def method_missing(method, *args)
        @klass[method] = *args
      end
    end # class Configurator
  end # Config
end # Merb
