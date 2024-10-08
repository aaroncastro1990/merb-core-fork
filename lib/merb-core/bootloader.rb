# encoding: UTF-8

module Merb

  class BootLoader

    # def self.subclasses
    #
    # @api plugin
    cattr_accessor :subclasses, :after_load_callbacks, :before_load_callbacks,
    :finished, :before_worker_shutdown_callbacks, :before_master_shutdown_callbacks

    self.subclasses, self.after_load_callbacks,
      self.before_load_callbacks, self.finished, self.before_master_shutdown_callbacks,
      self.before_worker_shutdown_callbacks = [], [], [], [], [], []

    class << self

      # Adds the inheriting class to the list of subclasses in a position
      # specified by the before and after methods.
      #
      # @param [Class] klass The class inheriting from Merb::BootLoader.
      #
      # @return [nil]
      #
      # @api plugin
      def inherited(klass)
        subclasses << klass.to_s
        super
      end

      # Execute this boot loader after the specified boot loader.
      #
      # @param [#to_s] klass The boot loader class after which this boot loader
      #   should be run.
      #
      # @return [nil]
      #
      # @api plugin
      def after(klass)
        move_klass(klass, 1)
        nil
      end

      # Execute this boot loader before the specified boot loader.
      #
      # @param [#to_s] klass The boot loader class before which this boot
      #   loader should be run.
      #
      # @return [nil]
      #
      # @api plugin
      def before(klass)
        move_klass(klass, 0)
        nil
      end

      # Move a class that is inside the bootloader to some place in the Array,
      # relative to another class.
      #
      # @param [#to_s] klass The class to move the bootloader relative to
      # @param [Integer] where 0 means insert it before; 1 means insert it after
      #
      # @return [nil]
      #
      # @api private
      def move_klass(klass, where)
        index = Merb::BootLoader.subclasses.index(klass.to_s)
        if index
          Merb::BootLoader.subclasses.delete(self.to_s)
          Merb::BootLoader.subclasses.insert(index + where, self.to_s)
        end
        nil
      end

      # Runs all boot loader classes by calling their run methods.
      #
      # @return [nil]
      #
      # @api plugin
      def run
        Merb.started = true
        subklasses = subclasses.dup
        until subclasses.empty?
          time = Time.now.to_i
          bootloader = subclasses.shift
          Merb.logger.debug!("Loading: #{bootloader}") if Merb.verbose_logging?
          bootloader.constantize.run
          Merb.logger.debug!("It took: #{Time.now.to_i - time}") if Merb.verbose_logging?
          self.finished << bootloader
        end
        self.subclasses = subklasses
        nil
      end

      # Determines whether or not a specific bootloader has finished yet.
      #
      # @param [String, Class] bootloader The name of the bootloader to check.
      #
      # @return [Boolean] Whether or not the bootloader has finished.
      #
      # @api private
      def finished?(bootloader)
        self.finished.include?(bootloader.to_s)
      end

      # Set up the default framework
      #
      # @return [nil]
      #
      # @api plugin
      # @overridable
      def default_framework
        %w[view model helper controller mailer part].each do |component|
          Merb.push_path(component.to_sym, Merb.root("app", component.pluralize))
        end
        Merb.push_path :application,  Merb.root("app", "controllers"), "application.rb"
        Merb.push_path :config,       Merb.root("config"), nil
        Merb.push_path :router,       Merb.dir_for(:config), (Merb::Config[:router_file] || "router.rb")
        Merb.push_path :lib,          Merb.root("lib"), nil
        Merb.push_path :merb_session, Merb.root("merb" / "session")
        Merb.push_path :log,          Merb.log_path, nil
        Merb.push_path :public,       Merb.root("public"), nil
        Merb.push_path :stylesheet,   Merb.dir_for(:public) / "stylesheets", nil
        Merb.push_path :javascript,   Merb.dir_for(:public) / "javascripts", nil
        Merb.push_path :image,        Merb.dir_for(:public) / "images", nil
        nil
      end

      # Execute a block of code after the app loads.
      #
      # @param &block A block to be added to the callbacks that will be
      #   executed after the app loads.
      #
      # @api public
      def after_app_loads(&block)
        after_load_callbacks << block
      end

      # Execute a block of code before the app loads but after dependencies load.
      #
      # @param &block A block to be added to the callbacks that will be
      #   executed before the app loads.
      #
      # @api public
      def before_app_loads(&block)
        before_load_callbacks << block
      end

      # Execute a block of code before master process is shut down.
      # Only makes sense on platforms where Merb server can use forking.
      #
      # @param &block A block to be added to the callbacks that will be
      #   executed before master process is shut down.
      #
      # @api public
      def before_master_shutdown(&block)
        before_master_shutdown_callbacks << block
      end

      # Execute a block of code before worker process is shut down.
      # Only makes sense on platforms where Merb server can use forking.
      #
      # @param &block A block to be added to the callbacks that will be
      #   executed before worker process is shut down.
      #
      # @api public
      def before_worker_shutdown(&block)
        before_worker_shutdown_callbacks << block
      end
    end

  end

end

# Set up the logger.
#
# Place the logger inside of the Merb log directory (set up in
# Merb::BootLoader::BuildFramework)
class Merb::BootLoader::Logger < Merb::BootLoader

  # Sets Merb.logger to a new logger created based on the config settings.
  #
  # @return [nil]
  #
  # @api plugin
  def self.run
    Merb::Config[:log_level] ||= begin
      if Merb.environment == "production"
        Merb::Logger::Levels[:warn]
      else
        Merb::Logger::Levels[:debug]
      end
    end

    Merb::Config[:log_stream] = 
      Merb::Config[:original_log_stream] || Merb.log_stream
    nil
  end
end

# Stores pid file.
#
# Only run if daemonization or clustering options specified on start.
# Port is taken from Merb::Config and must be already set at this point.
class Merb::BootLoader::DropPidFile < Merb::BootLoader
  class << self

    # Stores a PID file if Merb is running daemonized or clustered.
    #
    # @return [nil]
    #
    # @api plugin
    def run
      Merb::Server.store_pid("main") if Merb::Config[:daemonize] || Merb::Config[:cluster]
      nil
    end
  end
end

# Setup some useful defaults
class Merb::BootLoader::Defaults < Merb::BootLoader
  # Sets up the defaults
  #
  # @return [nil]
  #
  # @api plugin
  def self.run
    Merb::Request.http_method_overrides.concat([
      proc { |c| c.params[:_method] },
      proc { |c| c.env['HTTP_X_HTTP_METHOD_OVERRIDE'] }
    ])
    nil
  end
end


# Build the framework paths.
#
# By default, the following paths will be used:
#
# * **application:** `Merb.root/app/controller/application.rb`
# * **config:** `Merb.root/config`
# * **lib:** `Merb.root/lib`
# * **log:** `Merb.root/log`
# * **view:** `Merb.root/app/views`
# * **model:** `Merb.root/app/models`
# * **controller:** `Merb.root/app/controllers`
# * **helper:** `Merb.root/app/helpers`
# * **mailer:** `Merb.root/app/mailers`
# * **part:** `Merb.root/app/parts`
#
# To override the default, set `Merb::Config[:framework]` in your initialization
# file. `Merb::Config[:framework]` takes a Hash whose key is the name of the
# path, and whose values can be passed into {Merb.push_path}.
#
# All paths will default to `Merb.root`, so if you want a flat-file structure
# simply by doing:
#     Merb::Config[:framework] = {}.
#
# The following code sets up a flat directory structure with the config files and
# controller files under `Merb.root`, but with models, views, and lib with their
# own folders off of `Merb.root`:
#     Merb::Config[:framework] = {
#       :view   => Merb.root / "views",
#       :model  => Merb.root / "models",
#       :lib    => Merb.root / "lib",
#       :public => [Merb.root / "public", nil]
#       :router => [Merb.root / "config", "router.rb"]
#     }
class Merb::BootLoader::BuildFramework < Merb::BootLoader
  class << self

    # Builds the framework directory structure.
    #
    # @return [nil]
    #
    # @api plugin
    def run
      $:.push Merb.root unless Merb.root == File.expand_path(Dir.pwd)
      build_framework
      nil
    end

    # Sets up merb paths to support the app's file layout.
    #
    # First, config/framework.rb is checked, next we look for
    # `Merb.root/framework.rb`, finally we use the default merb layout
    # ({Merb::BootLoader.default_framework})
    #
    # This method can be overriden to support other application layouts.
    #
    # @return [nil]
    #
    # @api plugin
    # @overridable
    def build_framework
      if File.exists?(Merb.root / "config" / "framework.rb")
        require Merb.root / "config" / "framework"
      elsif File.exists?(Merb.root / "framework.rb")
        require Merb.root / "framework"
      else
        Merb::BootLoader.default_framework
      end
      (Merb::Config[:framework] || {}).each do |name, path|
        path = Array(path)
        Merb.push_path(name, path.first, path.length == 2 ? path[1] : "**/*.rb")
      end
      nil
    end
  end
end

class Merb::BootLoader::Dependencies < Merb::BootLoader
  # @return [Array(Gem::Dependency)] The dependencies registered in init.rb.
  #
  # As of Merb.1.1 these dependencies only get loaded when
  # Merb::Config[:kernel_dependencies] is set to true. 
  #
  # This will be removed as of Merb 2.0
  #
  # @api plugin
  # @deprecated
  cattr_accessor :dependencies
  self.dependencies = []

  # Load the init_file specified in Merb::Config or if not specified, the
  # init.rb file from the Merb configuration directory, and any environment
  # files and any after_app_loads hooks.
  #
  # Dependencies are loaded via Bunlder and managed in the Gemfile manifest.
  # By default manifest for Bundler is in the root directory of the app and
  # is called Gemfile. All dependencies MUST be definied there because all
  # dependency hangling was removed from Merb.
  #
  # #### Deprecated (1.0.x)
  # Dependencies can hook into the bootloader process itself by using
  # before or after insertion methods. Since these are loaded from this
  # bootloader (Dependencies), they can only adapt the bootloaders that
  # haven't been loaded up until this point.
  #
  # @return [nil]
  #
  # @api plugin
  # @deprecated
  def self.run
    set_encoding
    load_dependencies
    unless Merb::disabled?(:initfile)
      load_initfile
      load_env_config
    end
    expand_ruby_path
    enable_json_gem unless Merb::disabled?(:json)
    update_logger
    nil
  end
  
  # Try to load the gem environment file (set via Merb::Config[:gemenv])
  # defaults to ./gems/environment
  #
  # Load each the dependencies defined in the Merb::Config[:gemfile] 
  # using the bundler gem's Bundler::require_env
  # 
  # Falls back to rubygems if no bundler environment exists
  # 
  # ==== Returns
  # nil
  #
  # :api: private
  def self.load_dependencies
    begin
      Bundler.require(:default, Merb.environment.to_sym)
    rescue Bundler::GemfileNotFound
      Merb.logger.error! "No Gemfile found! If you're generating new app with merb-gen " \
                         "this is fine, otherwise run: bundle init to create Gemfile"
    end
    nil
  end
  
  # Requires json or json_pure.
  #
  # @return [nil]
  #
  # @api private
  def self.enable_json_gem
    require "json"
    rescue LoadError
        Merb.logger.error! "You have enabled JSON but don't have json " \
                           "installed or don't have dependency in the Gemfile. " \
                           "Add \"gem 'json', '>= 1.1.7'\" or " \
                           "\"gem 'json_pure', '>= 1.1.7'\" to your Gemfile."
  end

  # Resets the logger and sets the log_stream to Merb::Config[:log_file]
  # if one is specified, falling back to STDOUT.
  #
  # @return [nil]
  #
  # @api private
  def self.update_logger
    Merb.reset_logger!

    # If log file is given, use it and not log stream we have.
    if Merb::Config[:log_file]
      log_file = Merb::Config[:log_file]
      raise "log file should be a string, got: #{log_file.inspect}" unless log_file.is_a?(String)
      STDOUT.puts "Logging to file at #{log_file}" unless Merb.testing?
      
      # try to create log directory (if it doesnt exist)
      log_directory = File.dirname(log_file)
      FileUtils.mkdir_p(log_directory) unless File.exists?(log_directory)

      Merb::Config[:log_stream] = File.open(log_file, "a")
    # but if it's not given, fallback to log stream or stdout
    else
      Merb::Config[:log_stream] ||= STDOUT
    end

    nil
  end

  # Default encoding to UTF8 if it has not already been set to something else.
  #
  # @return [nil]
  #
  # @api private
  def self.set_encoding
    unless RUBY_VERSION >= '1.9'
      $KCODE = 'UTF8' if $KCODE == 'NONE' || $KCODE.blank?
    end
    
    nil
  end

  private

    # Determines the path for the environment configuration file
    #
    # @return [String] The path to the config file for the environment
    #
    # @api private
    def self.env_config
      Merb.dir_for(:config) / "environments" / (Merb.environment + ".rb")
    end

    # Checks to see whether or not an environment configuration exists
    #
    # @return [Boolean] Whether or not the environment configuration file exists.
    #
    # @api private
    def self.env_config?
      Merb.environment && File.exist?(env_config)
    end

    # Loads the environment configuration file, if it is present
    #
    # @return [nil]
    #
    # @api private
    def self.load_env_config
      if env_config?
        env_config_path = relative_to_merb_path(env_config)
        STDOUT.puts "Loading #{env_config_path}" unless Merb.testing?
        load(env_config)
      end
      nil
    end

    # Determines the init file to use, if any.
    # By default Merb uses init.rb from application config directory.
    #
    # @return [nil]
    #
    # @api private
    def self.initfile
      if Merb::Config[:init_file]
        Merb::Config[:init_file].chomp(".rb") + ".rb"
      else
        Merb.dir_for(:config) / "init.rb"
      end
    end

    # Loads the init file, should one exist
    #
    # @return [nil]
    #
    # @api private
    def self.load_initfile
      return nil if Merb.const_defined?("INIT_RB_LOADED")
      if File.exists?(initfile)
        initfile_path = relative_to_merb_path(initfile)
        STDOUT.puts "Loading init file from #{initfile_path}" unless Merb.testing?
        load(initfile)
        Merb.const_set("INIT_RB_LOADED", true)
      elsif !Merb.testing?
        Merb.fatal! "You are not in a Merb application, or you are in " \
          "a flat application and have not specified the init file. If you " \
          "are trying to create a new merb application, use merb-gen app."
      end
      nil
    end

    # Expands Ruby path with framework directories (for models, lib, etc). Only run once.
    #
    # @return [nil]
    #
    # @api private
    def self.expand_ruby_path
      # Add models, controllers, helpers and lib to the load path
      unless @ran
        Merb.logger.info "Expanding RUBY_PATH..." if Merb::Config[:verbose]

        $LOAD_PATH.unshift Merb.dir_for(:model)
        $LOAD_PATH.unshift Merb.dir_for(:controller)
        $LOAD_PATH.unshift Merb.dir_for(:lib)
        $LOAD_PATH.unshift Merb.dir_for(:helper)
      end

      @ran = true
      nil
    end

    # Converts an absolute path to an path relative to Merbs root, if
    # the path is in the Merb root dir. Otherwise it will return the
    # absolute path.
    #
    # @return [String] Relative path or absolute
    #
    # @api private
    def self.relative_to_merb_path(path)
      absolute_path = File.expand_path(path)
      merb_root = File.expand_path(Merb.root)
      if absolute_path.slice(0, merb_root.length) == merb_root
        '.' + absolute_path.slice(merb_root.length..-1)
      else
        absolute_path
      end
    end

end

class Merb::BootLoader::MixinSession < Merb::BootLoader

  # Mixin the session functionality; this is done before BeforeAppLoads
  # so that SessionContainer and SessionStoreContainer can be subclassed by
  # plugin session stores for example - these need to be loaded in a
  # before_app_loads block or a BootLoader that runs after MixinSession.
  #
  # #### Note
  # Access to Merb::Config is needed, so it needs to run after
  # {Merb::BootLoader::Dependencies} is done.
  #
  # @return [nil]
  #
  # @api plugin
  def self.run
    require 'merb-core/dispatch/session'
    Merb::Controller.send(:include, ::Merb::SessionMixin)
    Merb::Request.send(:include, ::Merb::SessionMixin::RequestMixin)
  end

end

class Merb::BootLoader::BeforeAppLoads < Merb::BootLoader

  # Call any {before_app_loads} hooks that were registered via before_app_loads
  # in any plugins.
  #
  # @return [nil]
  #
  # @api plugin
  def self.run
    orm_module_name = "merb_#{Merb.orm}"
    begin
      require orm_module_name
    rescue LoadError => e
      Merb.logger.warn "Could not load ORM module, model loading will probably fail. #{orm_module_name}: #{e} (#{e.class})"
    end

    Merb::BootLoader.before_load_callbacks.each { |x| x.call }
    nil
  end
end

# Load all classes inside the load paths.
#
# This is used in conjunction with {Merb::BootLoader::ReloadClasses} to track
# files that need to be reloaded, and which constants need to be removed in
# order to reload a file.
#
# This also adds the model, controller, and lib directories to the load path,
# so they can be required in order to avoid load-order issues.
class Merb::BootLoader::LoadClasses < Merb::BootLoader
  LOADED_CLASSES = {}
  MTIMES = {}
  FILES_LOADED = {}

  class << self

    # Load all classes from Merb's native load paths.
    #
    # If fork-based loading is used, every time classes are loaded this will return in a new spawner process
    # and boot loading will continue from this point in the boot loading process.
    #
    # If fork-based loading is not in use, this only returns once and does not fork a new
    # process.
    #
    # @return [nil] At least once
    #
    # @api plugin
    def run
      # process name you see in ps output
      $0 = "merb#{" : " + Merb::Config[:name] if Merb::Config[:name]} : master"

      # Log the process configuration user defined signal 1 (SIGUSR1) is received.
      Merb.trap("USR1") do
        require "yaml"
        Merb.logger.fatal! "Configuration:\n#{Merb::Config.to_hash.merge(:pid => $$).to_yaml}\n\n"
      end

      if Merb::Config[:fork_for_class_load] && !Merb.testing?
        start_transaction
      else
        Merb.trap('INT') do
          Merb.logger.warn! "Reaping Workers"
          reap_workers
        end
      end

      # Load application file if it exists - for flat applications
      load_file Merb.dir_for(:application) if File.file?(Merb.dir_for(:application))

      # Load classes and their requirements
      Merb.load_paths.each do |component, path|
        next if path.last.blank? || component == :application || component == :router
        load_classes(path.first / path.last)
      end

      Merb::Controller.send :include, Merb::GlobalHelpers

      nil
    end

    # Wait for any children to exit, remove the "main" PID, and
    # exit.
    #
    # @return [] (Does not return.)
    #
    # @api private
    def exit_gracefully
      # wait all workers to exit
      Process.waitall
      # remove master process pid
      Merb::Server.remove_pid("main")
      # terminate, workers remove their own pids
      # in on exit hook

      Merb::BootLoader.before_master_shutdown_callbacks.each do |cb|
        begin
          cb.call
        rescue Exception => e
          Merb.logger.fatal "before_master_shutdown callback crashed: #{e.message}"
        end
      end
      exit
    end

    # Set up the BEGIN point for fork-based loading and sets up
    # any signals in the parent and child.
    #
    # This is done by forking the app. The child process continues on to run
    # the app. The parent process waits for the child process to finish and
    # either forks again or exits by calling {exit_gracefully}. (See TODO
    # note.)
    # @todo Docs: "either forks again" or what?
    #
    # @return [nil] Child process(es) return at least once, the parent
    #   process does not return.
    #
    # @api private
    def start_transaction
      Merb.logger.warn! "Parent pid: #{Process.pid}"
      reader, writer = nil, nil

      # Enable REE garbage collection
      if GC.respond_to?(:copy_on_write_friendly=)
        GC.copy_on_write_friendly = true
      end

      loop do
        # create two connected endpoints
        # we use them for master/workers communication
        reader, @writer = IO.pipe
        pid = Kernel.fork

        # pid means we're in the parent; only stay in the loop if that is case
        break unless pid
        # writer must be closed so reader can generate EOF condition
        @writer.close

        # master process stores pid to merb.main.pid
        Merb::Server.store_pid("main") if Merb::Config[:daemonize] || Merb::Config[:cluster]

        if Merb::Config[:console_trap]
          Merb.trap("INT") {}
        else
          # send ABRT to worker on INT
          Merb.trap("INT") do
            Merb.logger.warn! "Reaping Workers"
            begin
              Process.kill(reap_workers_signal, pid)
            rescue SystemCallError
            end
            exit_gracefully
          end
        end

        Merb.trap("HUP") do
          Merb.logger.warn! "Doing a fast deploy\n"
          Process.kill("HUP", pid)
        end

        reader_ary = [reader]
        loop do
          # wait for worker to exit and capture exit status
          #
          #
          # WNOHANG specifies that wait2 exists without waiting
          # if no worker processes are ready to be noticed.
          if exit_status = Process.wait2(pid, Process::WNOHANG)
            # wait2 returns a 2-tuple of process id and exit
            # status.
            #
            # We do not care about specific pid here.
            exit_status[1] && exit_status[1].exitstatus == 128 ? break : exit
          end
          # wait for data to become available, timeout in 0.5 of a second
          if select(reader_ary, nil, nil, 0.5)
            begin
              # no open writers
              next if reader.eof?
              msg = reader.readline
              reader.close
              if msg.to_i == 128
                Process.waitpid(pid, Process::WNOHANG)
                break
              else
                exit_gracefully
              end
            rescue SystemCallError
              exit_gracefully
            end
          end
        end
      end

      reader.close

      # add traps to the worker
      if Merb::Config[:console_trap]
        Merb::Server.add_irb_trap
        at_exit { reap_workers }
      else
        Merb.trap('INT') do
          Merb::BootLoader.before_worker_shutdown_callbacks.each { |cb| cb.call }
        end
        Merb.trap('ABRT') { reap_workers }
        Merb.trap('HUP') { reap_workers(128, "ABRT") }
      end
    end

    # @return [String] Name of the signal with which child processes are
    #   terminated.
    #
    # @api private
    def reap_workers_signal
      Merb::Config[:reap_workers_quickly] ? "KILL" : "ABRT"
    end

    # Reap any workers of the spawner process and
    # exit with an appropriate status code.
    #
    # Note that exiting the spawner process with a status code
    # of 128 when a master process exists will cause the
    # spawner process to be recreated, and the app code reloaded.
    #
    # @param [Integer] status The status code to exit with.
    # @param [String] sig The signal to send to workers
    #
    # @return [] (Does not return)
    #
    # @api private    
    def reap_workers(status = 0, sig = reap_workers_signal)
      
      Merb.logger.info "Executed all before worker shutdown callbacks..."
      Merb::BootLoader.before_worker_shutdown_callbacks.each do |cb|
        begin
          cb.call
        rescue Exception => e
          Merb.logger.fatal "before worker shutdown callback crashed: #{e.message}"
        end

      end

      Merb.exiting = true unless status == 128

      begin
        if @writer
          @writer.puts(status.to_s)
          @writer.close
        end
      rescue SystemCallError
      end

      threads = []

      ($WORKERS || []).each do |p|
        threads << Thread.new do
          begin
            Process.kill(sig, p)
            Process.wait2(p)
          rescue SystemCallError
          end
        end
      end
      threads.each {|t| t.join }
      exit(status)
    end

    # Loads a file, tracking its modified time and, if necessary, the classes it declared.
    #
    # @param [String] file The file to load.
    # @param [Boolean] reload Indicates if this is a reload call.
    #
    # @return [nil]
    #
    # @api private
    def load_file(file, reload = false)
      Merb.logger.verbose! "#{reload ? "re" : ""}loading #{file}"
      
      # If we're going to be reloading via constant remove,
      # keep track of what constants were loaded and what files
      # have been added, so that the constants can be removed
      # and the files can be removed from $LOADED_FEAUTRES
      if !Merb::Config[:fork_for_class_load]
        if FILES_LOADED[file]
          FILES_LOADED[file].each {|lf| $LOADED_FEATURES.delete(lf)}
        end
        
        klasses = ObjectSpace.classes.dup
        files_loaded = $LOADED_FEATURES.dup
      end

      # If we're in the midst of a reload, remove the file
      # itself from $LOADED_FEATURES so it will get reloaded
      if reload
        $LOADED_FEATURES.delete(file) if reload
      end

      # Ignore the file for syntax errors. The next time
      # the file is changed, it'll be reloaded again
      begin
        require file
      rescue SyntaxError => e
        Merb.logger.error "Cannot load #{file} because of syntax error: #{e.message}"
      ensure
        if Merb::Config[:reload_classes]
          MTIMES[file] = File.mtime(file)
        end
      end

      # If we're reloading via constant remove, store off the details
      # after the file has been loaded
      unless Merb::Config[:fork_for_class_load]
        LOADED_CLASSES[file] = ObjectSpace.classes - klasses
        FILES_LOADED[file] = $LOADED_FEATURES - files_loaded
      end

      nil
    end

    # Load classes from given paths using path/glob pattern.
    #
    # @param [Array] *paths Array of paths to load classes from. May
    #   contain glob pattern
    #
    # @return [nil]
    #
    # @api private
    def load_classes(*paths)
      orphaned_classes = []
      paths.flatten.each do |path|
        Dir[path].sort.each do |file|
          begin
            load_file file
          rescue NameError => ne
            Merb.logger.verbose! "Stashed file with missing requirements for later reloading: #{file}"
            ne.backtrace.each_with_index { |line, idx| Merb.logger.verbose! "[#{idx}]: #{line}" }
            orphaned_classes.unshift(file)
          end
        end
      end
      load_classes_with_requirements(orphaned_classes)
    end

    # Reloads the classes in the specified file.
    #
    # If fork-based loading is used, this causes the current processes
    # to be killed and and all classes to be reloaded. If class-based
    # loading is not in use, the classes declared in that file are removed
    # and the file is reloaded.
    #
    # @param [String] file The file to reload.
    #
    # @return [nil] Does not return if fork-based loading is used.
    #
    # @api private
    def reload(file)
      if Merb::Config[:fork_for_class_load]
        reap_workers(128)
      else
        remove_classes_in_file(file) { |f| load_file(f, true) }
      end
    end

    # Removes all classes declared in the specified file.
    #
    # Any hashes which use classes as keys will be protected provided they
    # have been added to {Merb.klass_hashes}. These hashes have their keys
    # substituted with placeholders before the file's classes are unloaded.
    # If a block is provided, it is called before the substituted keys are
    # reconstituted.
    #
    # @param [String] file<String> The file to remove classes for.
    # @param &block A block to call with the file that has been removed
    #   before klass_hashes are updated to use the current values of the
    #   constants they used as keys.
    #
    # @return [nil]
    #
    # @api private
    def remove_classes_in_file(file, &block)
      Merb.klass_hashes.each { |x| x.protect_keys! }
      if klasses = LOADED_CLASSES.delete(file)
        klasses.each { |klass| remove_constant(klass) unless klass.to_s =~ /Router/ }
      end
      yield file if block_given?
      Merb.klass_hashes.each {|x| x.constantize_keys!}
      nil
    end

    # Removes the specified class.
    #
    # Additionally, removes the specified class from the subclass list of every superclass that
    # tracks its subclasses in an array returned by {_subclasses_list}. Classes that wish to use this
    # functionality are required to alias the reader for their list of subclasses
    # to _subclasses_list. Plugins for ORMs and other libraries should keep this in mind.
    #
    # @param [Class] const The class to remove.
    #
    # @return [nil]
    #
    # @api private
    def remove_constant(const)
      # This is to support superclasses (like AbstractController) that track
      # their subclasses in a class variable.
      superklass = const
      until (superklass = superklass.superclass).nil?
        if superklass.respond_to?(:_subclasses_list)
          superklass.send(:_subclasses_list).delete(klass)
          superklass.send(:_subclasses_list).delete(klass.to_s)
        end
      end

      parts = const.to_s.split("::")
      base = parts.size == 1 ? Object : parts[0..-2].join("::").constantize
      object = parts[-1].to_s
      begin
        base.send(:remove_const, object)
        Merb.logger.debug("Removed constant #{object} from #{base}")
      rescue NameError
        Merb.logger.debug("Failed to remove constant #{object} from #{base}")
      end
      nil
    end

    private

    # "Better loading" of classes.
    #
    # If a file fails to load due to a NameError it will be added to the
    # failed_classes and load cycle will be repeated unless no classes load.
    #
    # @param [Array<Class>] klasses Classes to load.
    #
    # @return [nil]
    #
    # @api private
    def load_classes_with_requirements(klasses)
      klasses.uniq!

      while klasses.size > 0
        # Note size to make sure things are loading
        size_at_start = klasses.size

        # List of failed classes
        failed_classes = []
        # Map classes to exceptions
        error_map = {}

        klasses.each do |klass|
          begin
            load_file klass
          rescue NameError => ne
            error_map[klass] = ne
            failed_classes.push(klass)
          end
        end
        klasses.clear

        # Keep list of classes unique
        failed_classes.each { |k| klasses.push(k) unless klasses.include?(k) }

        # Stop processing if nothing loads or if everything has loaded
        if klasses.size == size_at_start && klasses.size != 0
          # Write all remaining failed classes and their exceptions to the log
          messages = error_map.slice(*failed_classes).map do |klass, e|
            ["Could not load #{klass}:\n\n#{e.message} - (#{e.class})",
              "#{(e.backtrace || []).join("\n")}"]
          end
          messages.each { |msg, trace| Merb.logger.fatal!("#{msg}\n\n#{trace}") }
          Merb.fatal! "#{failed_classes.join(", ")} failed to load."
        end
        break if(klasses.size == size_at_start || klasses.size == 0)
      end

      nil
    end

  end

end

# Loads the router file. This needs to happen after everything else is loaded while merb is starting up to ensure
# the router has everything it needs to run.
class Merb::BootLoader::Router < Merb::BootLoader
  class << self

    # Load the router file.
    #
    # @return [nil]
    #
    # @api plugin
    def run
      Merb::BootLoader::LoadClasses.load_file(router_file) if router_file

      nil
    end

    # Tries to find the router file.
    #
    # @return [String, nil] The path to the router file if it exists, nil otherwise.
    #
    # @api private
    def router_file
      @router_file ||= begin
        if File.file?(router = Merb.dir_for(:router) / Merb.glob_for(:router))
          router
        end
      end
    end

  end
end

# Precompiles all non-partial templates.
class Merb::BootLoader::Templates < Merb::BootLoader
  class << self

    # Loads all non-partial templates into the Merb::InlineTemplates module.
    #
    # @return [Array<String>] The list of template files which were loaded.
    #
    # @api plugin
    def run
      template_paths.each do |path|
        Merb::Template.inline_template(File.open(path))
      end
    end

    # Finds a list of templates to load.
    #
    # @return [Array<String>] All found template files whose basename does
    #   not begin with "_".
    #
    # @api private
    def template_paths
      extension_glob = "{#{Merb::Template.template_extensions.join(',')}}"

      # This gets all templates set in the controllers template roots
      # We separate the two maps because most of controllers will have
      # the same _template_root, so it's silly to be globbing the same
      # path over and over.
      controller_view_paths = []
      Merb::AbstractController._abstract_subclasses.each do |klass|
        next if (const = klass.constantize)._template_root.blank?
        controller_view_paths += const._template_roots.map { |pair| pair.first }
      end
      template_paths = controller_view_paths.uniq.compact.map { |path| Dir["#{path}/**/*.#{extension_glob}"] }

      # This gets the templates that might be created outside controllers
      # template roots.  eg app/views/shared/*
      template_paths << Dir["#{Merb.dir_for(:view)}/**/*.#{extension_glob}"] if Merb.dir_for(:view)

      # This ignores templates for partials, which need to be compiled at use time to generate
      # a preamble that assigns local variables
      template_paths.flatten.compact.uniq.grep(%r{^.*/[^_][^/]*$})
    end
  end
end

# Register the default MIME types:
#
# By default, the mime-types include:
# * **`:all`:** no transform, */*
# * **`:yaml`:** to_yaml, application/x-yaml or text/yaml
# * **`:text`:** to_text, text/plain
# * **`:html`:** to_html, text/html or application/xhtml+xml or application/html
# * **`:xml`:** to_xml, application/xml or text/xml or application/x-xml
# * **`:js`:** to_json, text/javascript ot application/javascript or application/x-javascript
# * **`:json`:** to_json, application/json or text/x-json
class Merb::BootLoader::MimeTypes < Merb::BootLoader

  # Registers the default MIME types.
  #
  # @return [nil]
  #
  # @api plugin
  def self.run
    Merb.add_mime_type(:all,  nil,      %w[*/*])
    Merb.add_mime_type(:yaml, :to_yaml, %w[application/x-yaml text/yaml], :charset => "utf-8")
    Merb.add_mime_type(:text, :to_text, %w[text/plain], :charset => "utf-8")
    Merb.add_mime_type(:html, :to_html, %w[text/html application/xhtml+xml application/html], :charset => "utf-8")
    Merb.add_mime_type(:xml,  :to_xml,  %w[application/xml text/xml application/x-xml], {:charset => "utf-8"}, 0.9998)
    Merb.add_mime_type(:js,   :to_json, %w[text/javascript application/javascript application/x-javascript], :charset => "utf-8")
    Merb.add_mime_type(:json, :to_json, %w[application/json text/x-json], :charset => "utf-8")
    nil
  end
end

# Set up cookies support in Merb::Controller and Merb::Request
class Merb::BootLoader::Cookies < Merb::BootLoader

  # Set up cookies support in Merb::Controller and Merb::Request
  #
  # @return [nil]
  #
  # @api plugin
  def self.run
    require 'merb-core/dispatch/cookies'
    Merb::Controller.send(:include, Merb::CookiesMixin)
    Merb::Request.send(:include, Merb::CookiesMixin::RequestMixin)
    nil
  end

end

class Merb::BootLoader::SetupSession < Merb::BootLoader

  # Enable the configured session container(s); any class that inherits from
  # SessionContainer will be considered by its session_store_type attribute.
  #
  # @return [nil]
  #
  # @api plugin
  def self.run
    # Require all standard session containers.
    Dir[Merb.framework_root / "merb-core" / "dispatch" / "session" / "*.rb"].each do |file|
      base_name = File.basename(file, ".rb")
      require file unless base_name == "container" || base_name == "store_container"
    end

    # Set some defaults.
    Merb::Config[:session_id_key] ||= "_session_id"

    # List of all session_stores from :session_stores and :session_store config options.
    config_stores = Merb::Config.session_stores

    # Register all configured session stores - any loaded session container class
    # (subclassed from Merb::SessionContainer) will be available for registration.
    Merb::SessionContainer.subclasses.each do |class_name|
      if(store = class_name.constantize) &&
        config_stores.include?(store.session_store_type)
          Merb::Request.register_session_type(store.session_store_type, class_name)
      end
    end

    # Mixin the Merb::Session module to add app-level functionality to sessions
    overrides = (Merb::Session.instance_methods & Merb::SessionContainer.instance_methods)
    overrides.each do |m| 
      Merb.logger.warn!("Warning: Merb::Session##{m} overrides existing " \
                        "Merb::SessionContainer##{m}")
    end    
    Merb::SessionContainer.send(:include, Merb::Session)
    nil
  end

end

# In case someone is running a sparse app, the default exceptions require the
# Exceptions class.  This must run prior to the AfterAppLoads BootLoader
# So that plugins may have ensured access in the after_app_loads block
class Merb::BootLoader::SetupStubClasses < Merb::BootLoader
  # Declares empty Application and Exception controllers.
  #
  # @return [nil]
  #
  # @api plugin
  def self.run
    unless defined?(Exceptions)
      Object.class_eval <<-RUBY
        class Application < Merb::Controller
          abstract!
        end

        class Exceptions < Merb::Controller
        end
      RUBY
    end
    nil
  end
end

class Merb::BootLoader::AfterAppLoads < Merb::BootLoader

  # Call any after_app_loads hooks that were registered via after_app_loads in
  # init.rb.
  #
  # @return [nil]
  #
  # @api plugin
  def self.run
    Merb::BootLoader.after_load_callbacks.each {|x| x.call }
    nil
  end
end

class Merb::BootLoader::ChooseAdapter < Merb::BootLoader

  # Choose the Rack adapter/server to use and set Merb.adapter.
  #
  # @return [nil]
  #
  # @api plugin
  def self.run
    # Check if we running in IRB if so run IRB adapter
    Merb::Config[:adapter] = 'irb' if Merb.running_irb?
    Merb.adapter = Merb::Rack::Adapter.get(Merb::Config[:adapter])
  end
end

class Merb::BootLoader::RackUpApplication < Merb::BootLoader
  # Setup the Merb Rack App or read a rackup file located at
  # Merb::Config[:rackup] with the same syntax as the
  # rackup tool that comes with rack. Automatically evals the file in
  # the context of a Rack::Builder.new { } block. Allows for mounting
  # additional apps or middleware.
  #
  # @return [nil]
  #
  # @api plugin
  def self.run
    require 'rack'
    if File.exists?(Merb.dir_for(:config) / "rack.rb")
      Merb::Config[:rackup] ||= Merb.dir_for(:config) / "rack.rb"
    end

    if Merb::Config[:rackup]
      rackup_code = File.read(Merb::Config[:rackup])
      Merb::Config[:app] = eval("::Rack::Builder.new {( #{rackup_code}\n )}.to_app", TOPLEVEL_BINDING, Merb::Config[:rackup])
    else
      Merb::Config[:app] = ::Rack::Builder.new {
         use Merb::Rack::Head # handle head requests
         use Merb::Rack::ContentLength # report content length
         if prefix = ::Merb::Config[:path_prefix]
           use Merb::Rack::PathPrefix, prefix
         end
         use Merb::Rack::Static, Merb.dir_for(:public)
         run Merb::Rack::Application.new
       }.to_app
    end

    nil
  end
end

class Merb::BootLoader::BackgroundServices < Merb::BootLoader
  # Start background services, such as the run_later worker thread.
  #
  # @return [nil]
  #
  # @api plugin
  def self.run
    Merb::Worker.start unless Merb.testing? || Merb::Worker.started?
    nil
  end
end

class Merb::BootLoader::ReloadClasses < Merb::BootLoader

  class TimedExecutor
    # Periodically execute the associated block in a separate thread.
    #
    # @param [Integer] seconds Number of seconds to sleep in between runs of &block.
    # @param &block The block to execute periodically.
    #
    # @return [Thread] The thread executing the block periodically.
    #
    # @api private
    def self.every(seconds, &block)
      Thread.new do
        loop do
          sleep( seconds )
          yield
        end
        Thread.exit
      end
    end
  end

  # Set up the class reloader if class reloading is enabled. This checks periodically
  # for modifications to files loaded by the LoadClasses BootLoader and reloads them
  # when they are modified.
  #
  # @return [nil]
  #
  # @api plugin
  def self.run
    return unless Merb::Config[:reload_classes]

    TimedExecutor.every(Merb::Config[:reload_time] || 0.5) do
      GC.start
      reload!
    end

    nil
  end

  # Reloads all the files on the Merb application path
  #
  # @return [nil]
  #
  # @api private
  def self.reload!
    reload(build_paths)
  end

  # Reloads all files which have been modified since they were last loaded.
  #
  # @return [nil]
  #
  # @api private
  def self.reload(paths = [])
    paths.each do |file|
      next if LoadClasses::MTIMES[file] &&
        LoadClasses::MTIMES[file] == File.mtime(file)

      LoadClasses.reload(file)
    end

    nil
  end

  # Returns a list of the paths on the merb application stack
  #
  # @return [nil]
  #
  # @api private
  def self.build_paths
    paths = []
    Merb.load_paths.each do |path_name, file_info|
      path, glob = file_info
      next unless glob
      paths << Dir[path / glob]
    end

    if Merb.dir_for(:application) && File.file?(Merb.dir_for(:application))
      paths << Merb.dir_for(:application)
    end

    paths.flatten!

    return paths
  end
end
