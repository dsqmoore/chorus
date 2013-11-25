require_relative 'installer_errors'

class ChorusExecutor
  attr_writer :destination_path, :version

  def initialize(options = {})
    @logger = options[:logger]
    @debug = options[:debug] == true

    raise InstallerErrors::InstallationFailed.new("Logger must be set") unless @logger
  end

  def exec(command, postgres_bin_path = release_path)
    full_command = "PATH=#{postgres_bin_path}/postgres/bin:$PATH && #{command}"
    @logger.debug(full_command)
    @logger.capture_output(full_command) || raise(InstallerErrors::CommandFailed, command)
  end

  def rake(command)
    exec "cd #{release_path} && RAILS_ENV=production bin/rake #{command}#{if_debug(' --trace')}"
  end

  def start_chorus
    chorus_control "start"
  end

  def start_postgres
    @logger.log "starting postgres..."
    chorus_control "start postgres"
  end

  def stop_postgres
    if File.directory? "#{release_path}/postgres"
      @logger.log "stopping postgres..."
      chorus_control "stop postgres"
    end
  end

  def initdb(data_path, database_user)
    exec "initdb --locale=en_US.UTF-8 -D #{data_path}/db --auth=md5 --pwfile=#{release_path}/postgres/pwfile --username=#{database_user}"
  end

  def extract_postgres(package_name)
    exec "tar xzf#{if_debug("v")} #{release_path}/packaging/postgres/#{package_name} -C #{release_path}"
  end

  def start_previous_release
    previous_chorus_control "start"
  end

  def stop_previous_release
    previous_chorus_control "stop"
  end

  private

  def release_path
    "#{@destination_path}/releases/#{@version}"
  end

  def chorus_control(command)
    exec "CHORUS_HOME=#{release_path} #{alpine_env} #{release_path}/packaging/chorus_control.sh #{command}"
  end

  def previous_chorus_control(command)
    exec "CHORUS_HOME=#{@destination_path}/current #{alpine_env} #{@destination_path}/chorus_control.sh #{command}", "#{@destination_path}/current"
  end

  def alpine_env
    "ALPINE_HOME=#{@destination_path}/alpine-current ALPINE_DATA_REPOSITORY=#{@destination_path}/shared/ALPINE_DATA_REPOSITORY"
  end

  def if_debug(arg)
    if @debug
      arg
    else
      ""
    end
  end
end