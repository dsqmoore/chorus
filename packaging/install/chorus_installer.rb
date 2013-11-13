require 'fileutils'
require 'securerandom'
require 'yaml'
require_relative 'installer_errors'
require_relative 'old_release_cleaner'
require 'base64'
require 'openssl'
require 'pathname'
require 'java'
require_relative '../../lib/shared/properties'

java_import "java.lang.System"

class ChorusInstaller
  attr_accessor :destination_path, :data_path, :database_password, :database_user, :install_mode, :log_stack

  INSTALL_MODES = [:upgrade_existing, :fresh]

  INSTALL_MODES.each do |mode|
    define_method :"#{mode}?" do
      install_mode == mode
    end
  end

  DEFAULT_PATH = "/usr/local/chorus"
  DEFAULT_DATA_PATH = "/data/chorus"

  def alpine_source_path
    File.join(release_path, 'vendor', 'alpine')
  end

  def initialize(options={})
    @installer_home = options[:installer_home]
    @version_detector = options[:version_detector]
    @logger = options[:logger]
    @old_release_cleaner = options[:old_release_cleaner]
    @io = options[:io]
    @log_stack = []
    @log_buffer = []
    @install_mode = :fresh
    @executor = options[:executor]
  end

  def log(message, &block)
    message = "  " * log_stack.count + message
    @io.log message
    @logger.log message
    if block_given?
      log_stack.push(nil).tap { yield block }.pop
      log "...done."
    end
  end

  def log_at_end(message)
    @log_buffer << message
  end

  def flush_logs
    @log_buffer.each do |message|
      log message
    end
  end

  def validate_localhost
    unless system("ping -c 1 localhost > /dev/null")
      raise InstallerErrors::InstallAborted, "Could not connect to 'localhost', please set in /etc/hosts"
    end
  end

  def chorus_installation_path
    File.join(@installer_home, 'chorus_installation')
  end

  def determine_postgres_installer
    @postgres_package = get_postgres_build
  end

  def get_destination_path
    default_path = ENV['CHORUS_HOME'] || DEFAULT_PATH
    default_path = default_path.sub(/\/current$/, '')

    relative_path = @io.prompt_or_default(:destination_path, default_path)

    @destination_path = File.expand_path(relative_path)
    @version_detector.destination_path = @destination_path
    prompt_for_upgrade if @version_detector.can_upgrade?(version)
    @version_detector.check_for_legacy!

    @logger.logfile = File.join(@destination_path, 'install.log')
    validate_path(destination_path)

    @executor.destination_path = @destination_path
    @executor.version = version
  end

  def get_data_path
    if !@version_detector.can_upgrade?(version)
      relative_path = @io.prompt_or_default(:data_path, DEFAULT_DATA_PATH)
      self.data_path = File.expand_path(relative_path)
      log "Data path = #{@data_path}"
      validate_path(data_path)
    end
  end

  def validate_path(path)
    FileUtils.mkdir_p(path)

    unless File.writable?(path)
      raise Errno::EACCES
    end

    true
  rescue Errno::EACCES
    raise InstallerErrors::InstallAborted, "You do not have write permission to #{path}"
  end

  def prompt_for_passphrase
    @io.prompt_or_default(:passphrase, "")
  end

  def prompt_for_upgrade
    @io.require_confirmation :confirm_upgrade
    self.install_mode = :upgrade_existing
  end

  def get_postgres_build
    input = nil
    input = 3 if is_supported_suse?
    input = 5 if is_supported_mac?

    redhat_version = supported_redhat_version
    if redhat_version
      input = 1 if redhat_version.start_with?('5.')
      input = 2 if redhat_version.start_with?('6.')
    end

    if @io.silent? && input.nil?
      raise InstallerErrors::InstallAborted, "Cannot detect OS version automatically. Unable to run in silent mode."
    end

    if input.nil?
      input = @io.prompt_until(:select_os) { |input| (1..4).include?(input.to_i) }.to_i
    end

    case input
      when 1
        @logger.log "Selected RedHat version 5."
        "postgres-redhat5.5-9.2.4.tar.gz"
      when 2
        @logger.log "Selected RedHat version 6."
        "postgres-redhat6.2-9.2.4.tar.gz"
      when 3
        @logger.log "Selected SuSE version 11."
        "postgres-suse11-9.2.4.tar.gz"
      when 5
        @logger.log "Selected OS X."
        "postgres-osx-9.2.4.tar.gz"
      else
        raise InstallerErrors::InstallAborted, "OS version not supported."
    end
  end

  def supported_redhat_version
    return nil unless File.exists?('/etc/redhat-release')

    version_string = File.read('/etc/redhat-release')
    $1 if version_string =~ /release (\d\.\d)/
  end

  def is_supported_suse?
    return false unless File.exists?('/etc/SuSE-release')

    File.open('/etc/SuSE-release').readlines.any? do |release|
      release.match(/^VERSION = 11$/)
    end
  end

  def is_supported_mac?
    `uname`.strip == "Darwin"
  end

  def copy_chorus_to_destination
    FileUtils.mkdir_p(release_path)
    FileUtils.cp_r File.join(chorus_installation_path, '.'), release_path, :preserve => true
  end

  def create_shared_structure
    FileUtils.mkdir_p("#{destination_path}/shared")

    if install_mode == :fresh && !(Dir.entries("#{destination_path}/shared") - ['.', '..']).empty?
      raise InstallerErrors::InstallAborted, "#{destination_path}/shared must be empty"
    end

    FileUtils.mkdir_p("#{destination_path}/shared/tmp/pids")
    FileUtils.mkdir_p("#{destination_path}/shared/solr/data")
    FileUtils.mkdir_p("#{destination_path}/shared/log")
    FileUtils.mkdir_p("#{destination_path}/shared/system")
    FileUtils.mkdir_p("#{destination_path}/shared/demo_data")
    FileUtils.mkdir_p("#{destination_path}/shared/libraries")
  end

  def copy_config_files
    FileUtils.mkdir_p("#{destination_path}/shared")
    copy_if_not_exist("#{chorus_installation_path}/packaging/database.yml.example", "#{destination_path}/shared/database.yml")
    copy_if_not_exist("#{chorus_installation_path}/packaging/sunspot.yml.example", "#{destination_path}/shared/sunspot.yml")
    FileUtils.cp("#{chorus_installation_path}/config/chorus.properties.example", "#{destination_path}/shared/chorus.properties.example")
    copy_if_not_exist("#{chorus_installation_path}/config/chorus.defaults.properties", "#{destination_path}/shared/chorus.properties")
  end

  def copy_if_not_exist(source, destination)
    unless File.exists? destination
      @logger.debug("Copying #{source} to #{destination}")
      FileUtils.cp(source, destination)
    end
  end

  def generate_paths_file
    file_path = "#{destination_path}/chorus_path.sh"
    @logger.debug("Generating paths file: #{file_path}")
    File.open(file_path, 'w') do |file|
      file.puts "export CHORUS_HOME=#{destination_path}"
      file.puts "export PATH=$PATH:$CHORUS_HOME"
      file.puts "export PGPASSFILE=$CHORUS_HOME/.pgpass"
    end
  end

  def generate_chorus_psql_files
    return if upgrade_existing?
    @logger.debug("generating chorus_psql files")
    File.open("#{destination_path}/.pgpass", 'w') do |file|
      file.puts "*:*:*:#{database_user}:#{database_password}"
    end
    FileUtils.chmod(0400, "#{destination_path}/.pgpass")

    File.open("#{destination_path}/chorus_psql.sh", 'w') do |file|
      file.puts CHORUS_PSQL
    end
    FileUtils.chmod(0500, "#{destination_path}/chorus_psql.sh")
  end

  def generate_chorus_rails_console_file
    @logger.debug("generating chorus_rails_console file")
    File.open("#{destination_path}/chorus_rails_console.sh", 'w') do |file|
      file.puts CHORUS_RAILS_CONSOLE
    end
    FileUtils.chmod(0700, "#{destination_path}/chorus_rails_console.sh")
  end

  def link_shared_files
    @logger.debug("Linking shared configuration files")
    FileUtils.ln_sf("#{destination_path}/shared/chorus.properties", "#{release_path}/config/chorus.properties")
    FileUtils.ln_sf("#{destination_path}/shared/database.yml", "#{release_path}/config/database.yml")
    FileUtils.ln_sf("#{destination_path}/shared/sunspot.yml", "#{release_path}/config/sunspot.yml")
    FileUtils.ln_sf("#{destination_path}/shared/secret.key", "#{release_path}/config/secret.key")
    FileUtils.ln_sf("#{destination_path}/shared/secret.token", "#{release_path}/config/secret.token")
    FileUtils.ln_sf("#{destination_path}/shared/demo_data", "#{release_path}/demo_data")

    #Symlink the data paths under shared to the actual data_path directory.  So the app actually
    #goes through two symlinks
    if data_path && File.expand_path("#{data_path}") != File.expand_path("#{destination_path}/shared")
      ['db', 'system', 'solr/data', 'log'].each do |path|
        destination = Pathname.new("#{destination_path}/shared/#{path}")
        source = Pathname.new("#{data_path}/#{path}")
        if (destination.exist? && !destination.symlink?)
          destination.rmdir
        end
        unless (source.exist?)
          source.mkpath
        end
        FileUtils.ln_sf(source.to_s, destination.to_s)
      end
    end

    @logger.debug("Linking shared data folders")
    FileUtils.ln_sf("#{destination_path}/shared/db", "#{release_path}/postgres-db")
    FileUtils.ln_sf("#{destination_path}/shared/tmp", "#{release_path}/tmp")
    FileUtils.ln_sf("#{destination_path}/shared/solr/data", "#{release_path}/solr/data")
    FileUtils.ln_sf("#{destination_path}/shared/log", "#{release_path}/log")

    @logger.debug("Linking nginx logs")
    FileUtils.mkdir_p("#{destination_path}/shared/log/nginx")
    FileUtils.rm_rf("#{release_path}/vendor/nginx/nginx_dist/nginx_data/logs")
    FileUtils.ln_sf("#{destination_path}/shared/log/nginx", "#{release_path}/vendor/nginx/nginx_dist/nginx_data/logs")
    FileUtils.ln_sf("#{destination_path}/shared/system", "#{release_path}/system")

    @logger.debug("Linking libraries")
    FileUtils.ln_sf("#{destination_path}/shared/libraries", "#{release_path}/lib/libraries")

  end

  def create_database_config
    return if upgrade_existing?

    database_config_path = "#{destination_path}/shared/database.yml"
    database_config = YAML.load_file(database_config_path)

    self.database_password = SecureRandom.hex
    self.database_user = database_config['production']['username']

    database_config['production']['password'] = database_password

    @logger.debug("Writing new database configuration")
    File.open(database_config_path, 'w') do |file|
      YAML.dump(database_config, file)
    end
  end

  def validate_data_sources
    @executor.start_postgres
    raise InstallerErrors::InstallAborted, "Duplicate names found in data sources.  Please change data source names so that they are all unique before upgrading." unless @executor.rake "validations:data_source"
  end

  def setup_database
    if upgrade_existing?
      @executor.start_postgres
      log "Running database migrations..." do
        db_commands = "db:migrate"
        db_commands += " enqueue:refresh_and_reindex"
        log "Running rake #{db_commands}"
        @executor.rake db_commands
        @executor.stop_postgres
      end
    else
      log "Initializing database..." do
        File.open("#{release_path}/postgres/pwfile", 'w') do |f|
          f.puts database_password
        end
        FileUtils.chmod(0400, "#{release_path}/postgres/pwfile")
        @executor.initdb data_path, database_user
        @executor.start_postgres
        db_commands = "db:create db:migrate"
        db_commands += " db:seed"
        db_commands += " enqueue:refresh_and_reindex"
        log "Running rake #{db_commands}"
        @executor.rake db_commands
        @executor.stop_postgres
      end
    end
  end

  def link_current_to_release
    link_to_current 'current', release_path
    FileUtils.ln_sf("#{release_path}/packaging/chorus_control.sh", "#{destination_path}/chorus_control.sh")
  end

  def link_to_current_alpine_release
    link_to_current 'alpine-current', alpine_release_path
  end

  def extract_postgres
    @executor.extract_postgres @postgres_package
  end

  def stop_previous_release
    return unless upgrade_existing?
    log "Stopping Chorus..." do
      @executor.stop_previous_release
    end
  end

  def startup
    return unless upgrade_existing?

    log "Starting up Chorus..." do
      @executor.start_chorus
    end
  end

  def prompt_for_eula
    @io.log eula
    @io.require_confirmation :accept_terms
  end

  def install
    prompt_for_eula
    validate_localhost
    get_destination_path
    get_data_path

    dump_environment

    determine_postgres_installer

    log "Installing Chorus version #{version} to #{destination_path}"
    log "Copying files into #{destination_path}..." do
      copy_chorus_to_destination
      create_shared_structure
      copy_config_files
      create_database_config

      log "Configuring secret key..."
      configure_secret_key

      log "Configuring secret token..."
      configure_secret_token

      link_shared_files

      secure_sensitive_files
      secure_public_directory
    end

    log "Extracting postgres..." do
      extract_postgres
    end

    if is_supported_mac?
      warn_and_change_osx_properties
    end

    if upgrade_existing?
      validate_data_sources

      log "Shutting down previous Chorus install..." do
        stop_previous_release
      end
    end

    log "#{upgrade_existing? ? "Updating" : "Creating"} database..." do
      generate_paths_file
      generate_chorus_psql_files
      generate_chorus_rails_console_file
      setup_database do
        enqueue_solr_reindex
      end
    end

    if alpine_exists?
      log "Setting up alpine..." do
        configure_alpine
      end
    end

    link_current_to_release

    flush_logs

  rescue InstallerErrors::InstallAborted => e
    puts e.message
    exit 1
  rescue InstallerErrors::AlreadyInstalled => e
    puts e.message
    exit 0
  rescue InstallerErrors::InstallationFailed => e
    log "#{e.class}: #{e.message}"
    raise
  rescue => e
    log "#{e.class}: #{e.message}"
    raise InstallerErrors::InstallationFailed, e.message
  end

  def warn_and_change_osx_properties
    log_at_end "OS X Users:"
    log_at_end "The properties file 'shared/chorus.properties' has had the number of worker_threads and webserver_threads reduced to 5 and the number of database_threads reduced to 15."

    set_properties({"worker_threads" => 5, "webserver_threads" => 5, "database_threads" => 15})
  end

  def remove_and_restart_previous!
    if upgrade_existing?
      log "Restarting server..."
      @executor.start_previous_release
    else
      @executor.stop_postgres
    end
    log "For Postgres errors check #{destination_path}/shared/db/server.log"
    FileUtils.chmod_R(0755, "#{release_path}/public")
    FileUtils.rm_rf release_path
  end

  def secure_sensitive_files
    files = %W{
    #{destination_path}/shared/secret.token
      #{destination_path}/shared/secret.key
      #{destination_path}/shared/chorus.properties
    }

    files.each do |file|
      File.chmod(0600, file)
    end
  end

  def secure_public_directory
    FileUtils.chmod_R(0555, "#{release_path}/public")
  end

  def configure_secret_key
    key_file = "#{destination_path}/shared/secret.key"
    return if File.exists?(key_file)

    passphrase = prompt_for_passphrase
    if passphrase.nil? || passphrase.strip.empty?
      passphrase = Random.new.bytes(32)
    end
    # only a subset of openssl is available built-in to jruby, so this is the best we could do without including the full jruby-openssl gem
    secret_key = Base64.strict_encode64(OpenSSL::Digest.new("SHA-256", passphrase).digest)
    File.open(key_file, 'w') do |f|
      f.puts secret_key
    end
  end

  def configure_secret_token
    token_file = "#{destination_path}/shared/secret.token"
    return if File.exists?(token_file)

    File.open(token_file, 'w') do |f|
      f << SecureRandom.hex(64)
    end
  end

  def release_path
    "#{destination_path}/releases/#{version}"
  end

  def alpine_release_path
    "#{destination_path}/alpine-releases/#{alpine_version}"
  end

  def eula
    eula_by_brand
  end

  def dump_environment
    @logger.log("=== ENVIRONMENT INFO BEGIN")
    @logger.log("== JAVA ENVIRONMENT")
    System.get_properties.entry_set.each do |e|
      @logger.log(e)
    end

    @logger.log("== OPERATING SYSTEM RELEASE")
    Dir["/etc/*-release"].each do |file|
      @logger.log("#{file}: #{File.open(file).readlines.first}".chomp)
    end

    dca_files_exist = false
    ['/opt/greenplum/conf/build-version.txt',
     '/opt/greenplum/conf/productid',
     '/opt/greenplum/serialnumber'].each do |path|
      next unless File.readable?(path)
      @logger.log("== DCA SPECIFIC FILES") unless dca_files_exist
      dca_files_exist = true
      @logger.log("#{path}: #{File.open(path).readlines.first}".chomp)
    end
    @logger.log("=== ENVIRONMENT INFO END")
  end

  def alpine_exists?
    File.exist? alpine_source_path
  end

  def configure_alpine
    log "Extracting #{alpine_installer} to #{alpine_release_path}"
    extract_alpine(alpine_installer)

    log 'Configuring alpine' do
      @logger.debug('Preparing Alpine Data Repository')
      unless File.exists?("#{destination_path}/shared/ALPINE_DATA_REPOSITORY") then
        log 'No Alpine Data Repository detected, creating...'
        FileUtils.cp_r("#{alpine_release_path}/ALPINE_DATA_REPOSITORY", "#{destination_path}/shared")
        set_alpine_properties
      end
      set_properties( { 'workflow.enabled' => true, 'workflow.url' => 'http://localhost:9090'} )
    end

    link_to_current_alpine_release
  end

  def extract_alpine(alpine_installer)
    @executor.exec("sh #{alpine_installer} --target #{alpine_release_path} --noexec")
  end

  def set_properties(new_properties)
    properties_file = File.join(destination_path, "shared", "chorus.properties")
    properties = Properties.load_file(properties_file)
    properties.merge!(new_properties)
    Properties.dump_file(properties, properties_file)
  end

  def set_alpine_properties
    alpine_config = <<-CONFIG
chorus.active = true
chorus.port = 8080
    CONFIG
    alpine_config_filename = "#{destination_path}/shared/ALPINE_DATA_REPOSITORY/configuration/alpine.config"
    File.open(alpine_config_filename, 'w') {|f| f.write(alpine_config)}
  end

  private

  def version
    @version ||= File.read("#{chorus_installation_path}/version_build").strip
  end

  def alpine_version
    @alpine_version ||= File.basename(alpine_installer, '.sh')
  end

  def alpine_installer
    @alpine_installer ||= Dir.glob(File.join(alpine_source_path, '*.sh')).first
  end

  def chorus_exec(command)
    @logger.capture_output("PATH=#{release_path}/postgres/bin:$PATH && #{command}") || raise(InstallerErrors::CommandFailed, command)
  end

  def chorus_control(args)
    @executor.chorus_control(args)
  end

  def link_to_current(link_name, rel_path)
    if File.exists?("#{destination_path}/#{link_name}")
      previous_version = File.readlink("#{destination_path}/#{link_name}")
      @old_release_cleaner.remove_except(rel_path, previous_version)
      File.delete("#{destination_path}/#{link_name}")
    end
    FileUtils.ln_sf(rel_path, "#{destination_path}/#{link_name}")
  end

  CHORUS_PSQL = <<-CHORUS_PSQL
    if [ "$CHORUS_HOME" = "" ]; then
      echo "CHORUS_HOME is not set.  Exiting..."
    else
      $CHORUS_HOME/current/postgres/bin/psql -U postgres_chorus -p 8543 chorus;
    fi
  CHORUS_PSQL

  CHORUS_RAILS_CONSOLE = <<-CHORUS_RAILS_CONSOLE
      if [ "$CHORUS_HOME" = "" ]; then
        echo "CHORUS_HOME is not set.  Exiting..."
      else
        RAILS_ENV=production $CHORUS_HOME/current/bin/ruby $CHORUS_HOME/current/script/rails console
      fi
  CHORUS_RAILS_CONSOLE

  def eula_by_brand
    file_name = ENV['PIVOTALLABEL'] ? 'emc' : 'alp'
    case file_name
      when 'alp' then ALP_EULA
      when 'emc' then EMC_EULA
      else #nil
    end
  end

  EMC_EULA = File.read(File.join(File.dirname(__FILE__), 'eula_emc.txt'))
  ALP_EULA = File.read(File.join(File.dirname(__FILE__), 'eula_alpine.txt'))
end
