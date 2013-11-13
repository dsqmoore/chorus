require 'minimal_spec_helper'
require_relative "../../packaging/install/chorus_installer"
require_relative "stub_executor"
require 'fakefs/spec_helpers'

describe ChorusInstaller do
  include FakeFS::SpecHelpers

  def create_test_database_yml
    FileUtils.mkdir_p '/usr/local/chorus/shared/'
    File.open('/usr/local/chorus/shared/database.yml', 'w') do |f|
      f.puts({'production' => {'password' => 'something', 'username' => 'the_user'}}.to_yaml)
    end
  end

  let(:installer) { described_class.new(options) }
  let(:options) do
    {
      installer_home: '.',
      version_detector: version_detector,
      logger: logger,
      old_release_cleaner: old_release_cleaner,
      io: io,
      executor: executor
    }
  end

  let(:version_detector) { Object.new }
  let(:logger) { Object.new }
  let(:old_release_cleaner) { Object.new }
  let(:io) { Object.new }
  let(:executor) { StubExecutor.new }

  before do
    ENV['CHORUS_HOME'] = nil
    stub(logger).log(anything)
    stub(logger).debug(anything)
    stub(io).log(anything)
    stub(io).silent? { false }
  end

  describe "#get_destination_path" do
    before do
      stub(installer).version { "2.2.0.1-8840ae71c" }
      stub(logger).logfile=(anything)
      stub(version_detector).destination_path=(anything)
      stub(version_detector).can_upgrade?(anything) { upgrade }
      stub(version_detector).check_for_legacy! { true }
      mock(io).prompt_or_default(:destination_path, default_path) { destination_path }
    end

    let(:upgrade) { false }
    let(:default_path) { '/usr/local/chorus' }
    let(:destination_path) { '/somewhere/chorus' }

    it "should set relevant settings" do
      mock(version_detector).destination_path=('/somewhere/chorus')
      mock(logger).logfile=('/somewhere/chorus/install.log')
      mock(executor).destination_path=('/somewhere/chorus')
      mock(executor).version=("2.2.0.1-8840ae71c")
      installer.get_destination_path
      installer.destination_path.should == '/somewhere/chorus'
    end

    it "checks for legacy versions" do
      mock(version_detector).check_for_legacy!
      installer.get_destination_path
    end

    describe "when the user types a relative path" do
      let(:destination_path) { "~/chorus" }

      it "returns the expanded path" do
        mock(version_detector).destination_path=("#{ENV['HOME']}/chorus")
        mock(logger).logfile=("#{ENV['HOME']}/chorus/install.log")
        installer.get_destination_path
        installer.destination_path.should == "#{ENV['HOME']}/chorus"
      end
    end

    describe "when there is a CHORUS_HOME set" do
      before do
        ENV["CHORUS_HOME"] = default_path + "/current"
      end
      let(:default_path) { "/not/standard/dir" }

      it "should set that as the default" do
        installer.get_destination_path
      end
    end

    context "when not upgrading" do
      it "should do a non-upgrade install" do
        dont_allow(installer).prompt("Existing version of Chorus detected. Upgrading will restart services.  Continue now? [y]:")
        installer.get_destination_path
        installer.upgrade_existing?.should be_false
      end
    end
  end

  describe "#get_data_path" do
    before do
      stub(installer).version { "2.2.0.1-8840ae71c" }
      installer.destination_path = destination_path
      stub(version_detector).can_upgrade?(anything) { upgrade }
    end
    let(:default_path) { '/data/chorus' }
    let(:data_path) { '/large_disk/data/' }
    let(:destination_path) { '/destination' }
    let(:upgrade) { false }

    context "for a fresh install" do
      before do
        mock(io).prompt_or_default(:data_path, default_path) { data_path }
      end

      it "should set the data path when the user enters one" do
        installer.get_data_path
        installer.data_path.should == '/large_disk/data'
      end

      describe "when the user types a relative path" do
        let(:data_path) { "~/data" }
        it "returns the expanded path" do
          installer.get_data_path
          installer.data_path.should == "#{ENV['HOME']}/data"
        end
      end
    end

    context "When doing an upgrade" do
      let(:upgrade) { true }

      it "should not prompt data directory" do
        installer.get_data_path
        installer.data_path.should == nil
      end
    end
  end

  describe "#validate_path" do
    let(:path) { '/user/example/path' }

    context "when the user has write permissions" do
      it "creates the path and returns true" do
        installer.validate_path(path).should == true
        File.exist?(path).should == true

        installer.validate_path(path).should == true
      end
    end

    context "when the path does not exist the user does not have permission to create it" do
      before do
        mock(FileUtils).mkdir_p(path) { raise Errno::EACCES }
      end

      it "raises an exception" do
        expect {
          installer.validate_path(path)
        }.to raise_error(InstallerErrors::InstallAborted)
      end
    end

    context "when the path exists, but the user does not have write access" do
      before do
        FileUtils.mkdir_p(path)
        stub(File).writable?(path) { false }
      end

      it "raises an exception" do
        expect {
          installer.validate_path(path)
        }.to raise_error(InstallerErrors::InstallAborted)
      end
    end
  end

  describe "#get_postgres_build" do
    context "when Linux" do
      before do
        stub(installer).is_supported_mac? { false }
      end

      [5.5, 5.6, 5.7].each do |version|
        context "when Linux is CentOS/RHEL #{version}" do
          before do
            FileUtils.mkdir_p("/etc/")
            File.open("/etc/redhat-release", "w") { |f| f.puts "XXXXXXXXX release #{version} (Final)" }
          end

          it "returns the RedHat 5.5 build" do
            installer.get_postgres_build.should == 'postgres-redhat5.5-9.2.4.tar.gz'
          end

          it "logs the users choice" do
            mock(logger).log("Selected RedHat version 5.")
            installer.get_postgres_build
          end
        end
      end

      [6.2, 6.4].each do |version|
        context "when Linux is CentOS/RHEL #{version}" do
          before do
            FileUtils.mkdir_p("/etc/")
            File.open("/etc/redhat-release", "w") { |f| f.puts "XXXXXXXXX release #{version} (Final)" }
          end

          it "returns the RedHat 6.2 build" do
            installer.get_postgres_build.should == 'postgres-redhat6.2-9.2.4.tar.gz'
          end

          it "logs the users choice" do
            mock(logger).log("Selected RedHat version 6.")
            installer.get_postgres_build
          end
        end
      end

      context "when Linux is SLES 11" do
        before do
          FileUtils.mkdir_p("/etc/")
          File.open("/etc/SuSE-release", "w") do |f|
            f.puts "SuSE"
            f.puts "VERSION = 11"
            f.puts "PATCHLEVEL = 1"
          end
        end

        it "returns the suse11 build" do
          installer.get_postgres_build.should == 'postgres-suse11-9.2.4.tar.gz'
        end

        it "logs the users choice" do
          mock(logger).log("Selected SuSE version 11.")
          installer.get_postgres_build
        end
      end
    end

    context "when OSX" do
      before do
        stub(installer).is_supported_mac? { true }
      end

      it "should return the OSX build" do
        installer.get_postgres_build.should == 'postgres-osx-9.2.4.tar.gz'
      end

      it "logs the users choice" do
        mock(logger).log("Selected OS X.")
        installer.get_postgres_build
      end
    end

    context "when couldn't guess version/distribution" do
      before do
        stub(installer).is_supported_mac? { false }
        mock(io).prompt_until(:select_os).times(prompt_times) do |symbol, proc|
          proc.call(nil).should be_false
          proc.call('1').should be_true
          proc.call('2').should be_true
          proc.call('3').should be_true
          proc.call('4').should be_true
          proc.call('a').should be_false
          result
        end
      end
      let(:prompt_times) { 1 }

      context "in silent mode" do
        let(:prompt_times) { 0 }

        before do
          stub(io).silent? { true }
        end

        it "should fail" do
          expect { installer.get_postgres_build }.to raise_error(InstallerErrors::InstallAborted, /Cannot detect OS version automatically\. Unable to run in silent mode/)
        end
      end

      context "when the user selects redhat 5.5" do
        let(:result) { "1" }

        it "returns the RedHat 5.5 build" do
          installer.get_postgres_build.should == 'postgres-redhat5.5-9.2.4.tar.gz'
        end
      end

      context "when the user selects redhat 6.2" do
        let(:result) { "2" }

        it "returns the RedHat 6.2 build" do
          installer.get_postgres_build.should == 'postgres-redhat6.2-9.2.4.tar.gz'
        end
      end

      context "when the user selects suse" do
        let(:result) { "3" }

        it "returns the Suse 11 build" do
          installer.get_postgres_build.should == 'postgres-suse11-9.2.4.tar.gz'
        end
      end

      context "when the user selects abort" do
        let(:result) { "4" }

        it "should fail" do
          expect { installer.get_postgres_build }.to raise_error(InstallerErrors::InstallAborted, /OS version not supported/)
        end
      end
    end
  end

  describe "#copy_chorus_to_destination" do
    before do
      installer.destination_path = "/usr/local/chorus"

      FileUtils.mkpath './chorus_installation/'
      FileUtils.touch './chorus_installation/source_file_of_some_kind'
      stub_version
      mock(FileUtils).cp_r('./chorus_installation/.', '/usr/local/chorus/releases/2.2.0.0', :preserve => true)
    end

    it "creates the correct release path" do
      installer.copy_chorus_to_destination
      File.directory?('/usr/local/chorus/releases/2.2.0.0').should be_true
    end
  end

  describe "#create_shared_structure" do
    before do
      installer.destination_path = "/usr/local/chorus"
    end

    it "creates the temporary folders" do
      installer.create_shared_structure

      File.directory?('/usr/local/chorus/shared/tmp/pids').should be_true
    end

    it "creates the solr index data path" do
      installer.create_shared_structure

      File.directory?('/usr/local/chorus/shared/solr/data').should be_true
    end

    it "creates the logs path" do
      installer.create_shared_structure

      File.directory?('/usr/local/chorus/shared/log').should be_true
    end

    it "creates the demo data folder" do
      installer.create_shared_structure

      File.directory?('/usr/local/chorus/shared/demo_data').should be_true
    end

    it "creates the system file uploads path" do
      installer.create_shared_structure

      File.directory?('/usr/local/chorus/shared/system').should be_true
    end

    it "creates the libraries folder" do
      installer.create_shared_structure

      File.directory?('/usr/local/chorus/shared/libraries').should be_true
    end

    context "when shared directory is not empty" do
      before do
        FileUtils.mkdir_p("/usr/local/chorus/shared/bad_folder")
        installer.install_mode = install_mode
      end

      context "when doing a fresh install" do
        let(:install_mode) { :fresh }
        it "throws an error" do
          expect {
            installer.create_shared_structure
          }.to raise_error(InstallerErrors::InstallAborted)
        end
      end

      context "when doing a 2.2 upgrade" do
        let(:install_mode) { :upgrade_existing }
        it "doesn't raise" do
          expect {
            installer.create_shared_structure
          }.to_not raise_error
        end
      end
    end

    context "when shared directory is empty" do
      before do
        installer.install_mode = :fresh
      end
      it "doesn't raise" do
        expect {
          installer.create_shared_structure
        }.to_not raise_error
      end
    end
  end

  describe "#copy_config_files" do
    before do
      installer.destination_path = "/usr/local/chorus"

      FileUtils.mkdir_p './chorus_installation/config'
      FileUtils.mkdir_p './chorus_installation/packaging'
      FileUtils.touch './chorus_installation/packaging/database.yml.example'
      FileUtils.touch './chorus_installation/packaging/sunspot.yml.example'
      FileUtils.touch './chorus_installation/config/chorus.properties.example'
      FileUtils.touch './chorus_installation/config/chorus.defaults.properties'
    end

    it "should create chorus.properties.example in shared path" do
      File.exists?('/usr/local/chorus/shared/chorus.properties.example').should be_false
      installer.copy_config_files

      File.exists?('/usr/local/chorus/shared/chorus.properties.example').should be_true
    end

    context "chorus.properties" do
      context "when chorus.properties doesn't exist in shared path" do
        it "creates chorus.properties file in shared path" do
          File.exists?('/usr/local/chorus/shared/chorus.properties').should be_false
          installer.copy_config_files

          File.exists?('/usr/local/chorus/shared/chorus.properties').should be_true
        end
      end

      context "when chorus.properties file already exists in the shared path" do
        before do
          FileUtils.mkdir_p('/usr/local/chorus/shared')
          File.open('/usr/local/chorus/shared/chorus.properties', 'w') { |f| f.puts "some yaml stuff" }
        end

        it "should not overwrite existing chorus.properties" do
          installer.copy_config_files
          File.read('/usr/local/chorus/shared/chorus.properties').strip.should == "some yaml stuff"
        end
      end
    end

    context "when database.yml doesn't exist in shared path" do
      it "creates database.yml file in shared path" do
        File.exists?('/usr/local/chorus/shared/database.yml').should be_false
        installer.copy_config_files

        File.exists?('/usr/local/chorus/shared/database.yml').should be_true
      end
    end

    context "when database.yml exists in the shared path" do
      before do
        FileUtils.mkdir_p('/usr/local/chorus/shared')
        File.open('/usr/local/chorus/shared/database.yml', 'w') { |f| f.puts "some yaml stuff" }
      end

      it "should not overwrite existing database.yml" do
        installer.copy_config_files
        File.read('/usr/local/chorus/shared/database.yml').strip.should == "some yaml stuff"
      end
    end

    context "when sunspot.yml doesn't exist in shared path" do
      it "creates sunspot.yml file in shared path" do
        File.exists?('/usr/local/chorus/shared/sunspot.yml').should be_false
        installer.copy_config_files

        File.exists?('/usr/local/chorus/shared/sunspot.yml').should be_true
      end
    end

    context "when sunspot.yml exists in the shared path" do
      before do
        FileUtils.mkdir_p('/usr/local/chorus/shared')
        File.open('/usr/local/chorus/shared/sunspot.yml', 'w') { |f| f.puts "some yaml stuff" }
      end

      it "should not overwrite existing sunspot.yml" do
        installer.copy_config_files
        File.read('/usr/local/chorus/shared/sunspot.yml').strip.should == "some yaml stuff"
      end
    end
  end

  describe "#configure_secret_key" do
    before do
      installer.destination_path = "/usr/local/chorus"

      FileUtils.mkdir_p './chorus_installation/config'
      FileUtils.mkdir_p './chorus_installation/packaging'
      FileUtils.touch './chorus_installation/packaging/database.yml.example'
      FileUtils.touch './chorus_installation/packaging/sunspot.yml.example'
      FileUtils.touch './chorus_installation/config/chorus.properties.example'
      FileUtils.touch './chorus_installation/config/chorus.defaults.properties'
      installer.copy_config_files
    end

    context "when key is not already present in shared" do
      let(:passphrase) { 'secret_key' }
      before do
        mock(installer).prompt_for_passphrase { passphrase }
      end
      it "generates the key from a passphrase and stores it in shared/secret.key" do
        installer.configure_secret_key
        File.read('/usr/local/chorus/shared/secret.key').strip.should_not be_nil
      end
    end

    context "when key is already present" do
      let(:secret_key) { "its secret" }
      before do
        File.open('/usr/local/chorus/shared/secret.key', 'w') { |f| f.puts secret_key }
      end

      it "does not change the existing key" do
        installer.configure_secret_key
        File.read('/usr/local/chorus/shared/secret.key').strip.should == secret_key
      end
    end

    context "when the default key is used" do
      let(:passphrase) { 'secret_key' }
      before do
        mock(installer).prompt_for_passphrase.times(2) { "" }
      end

      it "generates a different random key on each run" do
        installer.configure_secret_key
        key1 = File.read('/usr/local/chorus/shared/secret.key').strip
        File.delete('/usr/local/chorus/shared/secret.key')
        installer.configure_secret_key
        key2 = File.read('/usr/local/chorus/shared/secret.key').strip
        key1.should_not == key2
      end
    end
  end

  describe "#configure_secret_token" do
    before do
      installer.destination_path = "/usr/local/chorus"

      FileUtils.mkdir_p './chorus_installation/config'
      FileUtils.mkdir_p './chorus_installation/packaging'
      FileUtils.touch './chorus_installation/packaging/database.yml.example'
      FileUtils.touch './chorus_installation/packaging/sunspot.yml.example'
      FileUtils.touch './chorus_installation/config/chorus.properties.example'
      FileUtils.touch './chorus_installation/config/chorus.defaults.properties'
      installer.copy_config_files
    end

    context "when token is not already present in shared" do
      it "generates the token and stores it in shared/secret.token" do
        installer.configure_secret_token
        File.read('/usr/local/chorus/shared/secret.token').strip.should_not be_nil
      end
    end

    context "when token is already present" do
      let(:secret_token) { "its secret" }
      before do
        File.open('/usr/local/chorus/shared/secret.token', 'w') { |f| f << secret_token }
      end

      it "does not change the existing token" do
        installer.configure_secret_token
        File.read('/usr/local/chorus/shared/secret.token').strip.should == secret_token
      end
    end
  end

  describe "#secure_sensitive_files" do
    let(:files) {
      %w{
        /usr/local/chorus/shared/secret.token
        /usr/local/chorus/shared/secret.key
        /usr/local/chorus/shared/chorus.properties
      }
    }
    before do
      installer.destination_path = "/usr/local/chorus"
      FileUtils.mkdir_p '/usr/local/chorus/shared'
      files.each do |file|
        FileUtils.touch file
      end
      installer.secure_sensitive_files
    end

    it "changes permissions to 600" do
      files.each do |file|
        File.stat(file).mode.should == 0100600
      end
    end
  end

  describe "#secure_public_directory" do
    let(:public_directory) { "/usr/local/chorus/releases/2.2.0.0/public" }
    before do
      stub(installer).version { "2.2.0.0" }
      FileUtils.mkdir_p "#{public_directory}/assets"
      installer.destination_path = "/usr/local/chorus"
      installer.secure_public_directory
    end

    it "changes permissions to 555" do
      File.stat(public_directory).mode.should == 0100555
      File.stat("#{public_directory}/assets").mode.should == 0100555
    end
  end

  describe "#generate_paths_file" do
    before do
      installer.destination_path = "/usr/local/chorus"
      FileUtils.mkdir_p installer.destination_path
    end

    it "generates a file with the CHORUS_HOME and PATH set" do
      installer.generate_paths_file
      lines = File.read("/usr/local/chorus/chorus_path.sh").lines.to_a
      lines[0].chomp.should == "export CHORUS_HOME=#{installer.destination_path}"
      lines[1].chomp.should == "export PATH=$PATH:$CHORUS_HOME"
      lines[2].chomp.should == "export PGPASSFILE=$CHORUS_HOME/.pgpass"
    end
  end

  describe "#generate_chorus_psql_file and .pgpass file" do
    before do
      installer.destination_path = "/usr/local/chorus"

      create_test_database_yml

      FileUtils.mkdir_p installer.destination_path
      installer.create_database_config
    end

    context "when new install" do
      before do
        installer.generate_chorus_psql_files
      end

      it "generates a .pgpass file" do
        lines = File.read("/usr/local/chorus/.pgpass").lines.to_a
        lines[0].strip.should =~ /\*:\*:\*:the_user:[a-z0-9]{32}/
        stats = File.stat("/usr/local/chorus/.pgpass").mode
        sprintf("%o", stats).should == "100400"
      end

      it "generates a file for connecting to psql with password" do
        lines = File.read("/usr/local/chorus/chorus_psql.sh").lines.to_a
        lines[3].strip.should == "$CHORUS_HOME/current/postgres/bin/psql -U postgres_chorus -p 8543 chorus;"
        stats = File.stat("/usr/local/chorus/chorus_psql.sh").mode
        sprintf("%o", stats).should == "100500"
      end
    end

    context "when upgrade" do
      before do
        installer.install_mode = :upgrade_existing
        installer.generate_chorus_psql_files
      end

      it "does not generate .pgpass file" do
        File.exists?("/usr/local/chorus/.pgpass").should be_false
      end
    end
  end

  describe "#generate_chorus_rails_console_file" do
    before do
      installer.destination_path = "/usr/local/chorus"

      FileUtils.mkdir_p installer.destination_path
      installer.generate_chorus_rails_console_file
    end

    it "generates a file for starting a rails console" do
      lines = File.read("/usr/local/chorus/chorus_rails_console.sh").lines.to_a
      lines[3].strip.should == "RAILS_ENV=production $CHORUS_HOME/current/bin/ruby $CHORUS_HOME/current/script/rails console"
      stats = File.stat("/usr/local/chorus/chorus_rails_console.sh").mode
      sprintf("%o", stats).should == "100700"
    end
  end

  describe "#link_shared_files" do
    before do
      installer.destination_path = destination_path
      installer.data_path = data_path
      stub_version

      FileUtils.mkdir_p "#{installer.release_path}/vendor/nginx/nginx_dist/nginx_data/logs"

      installer.link_shared_files
    end

    let(:data_path) { "/data/chorus" }
    let(:destination_path) { "/usr/local/chorus" }

    it "links the chorus.properties file" do
      File.readlink('/usr/local/chorus/releases/2.2.0.0/config/chorus.properties').should == '/usr/local/chorus/shared/chorus.properties'
    end

    it "links the demo data" do
      File.readlink('/usr/local/chorus/releases/2.2.0.0/demo_data').should == '/usr/local/chorus/shared/demo_data'
    end

    it "links the database.yml file" do
      File.readlink('/usr/local/chorus/releases/2.2.0.0/config/database.yml').should == '/usr/local/chorus/shared/database.yml'
    end

    it "links the sunspot.yml file" do
      File.readlink('/usr/local/chorus/releases/2.2.0.0/config/sunspot.yml').should == '/usr/local/chorus/shared/sunspot.yml'
    end

    it "links the secret.key file" do
      File.readlink('/usr/local/chorus/releases/2.2.0.0/config/secret.key').should == '/usr/local/chorus/shared/secret.key'
    end

    it "links the secret.token file" do
      File.readlink('/usr/local/chorus/releases/2.2.0.0/config/secret.token').should == '/usr/local/chorus/shared/secret.token'
    end

    it "links tmp" do
      File.readlink('/usr/local/chorus/releases/2.2.0.0/tmp').should == '/usr/local/chorus/shared/tmp'
    end

    it "creates data_path" do
      FileTest.exist?('/data/chorus/system').should be_true
    end

    it "links system" do
      File.readlink('/usr/local/chorus/releases/2.2.0.0/system').should == '/usr/local/chorus/shared/system'
      File.readlink('/usr/local/chorus/shared/system').should == '/data/chorus/system'
    end

    it "links db" do
      File.readlink('/usr/local/chorus/releases/2.2.0.0/postgres-db').should == '/usr/local/chorus/shared/db'
      File.readlink('/usr/local/chorus/shared/db').should == '/data/chorus/db'
    end

    it "links solr" do
      File.readlink('/usr/local/chorus/releases/2.2.0.0/solr/data').should == '/usr/local/chorus/shared/solr/data'
      File.readlink('/usr/local/chorus/shared/solr/data').should == '/data/chorus/solr/data'
    end

    it "links log" do
      File.readlink('/usr/local/chorus/releases/2.2.0.0/log').should == '/usr/local/chorus/shared/log'
      File.readlink('/usr/local/chorus/shared/log').should == '/data/chorus/log'
    end

    it "links the nginx logs" do
      File.readlink('/usr/local/chorus/releases/2.2.0.0/vendor/nginx/nginx_dist/nginx_data/logs').should == '/usr/local/chorus/shared/log/nginx'
    end

    it "links the libraries directory" do
      File.readlink('/usr/local/chorus/releases/2.2.0.0/lib/libraries').should == '/usr/local/chorus/shared/libraries'
    end

    shared_examples "not link the data paths" do
      it "doesn't link system" do
        File.readlink('/usr/local/chorus/releases/2.2.0.0/system').should == '/usr/local/chorus/shared/system'
        File.symlink?('/usr/local/chorus/shared/system').should be_false
      end

      it "doesn't link db" do
        File.readlink('/usr/local/chorus/releases/2.2.0.0/postgres-db').should == '/usr/local/chorus/shared/db'
        File.symlink?('/usr/local/chorus/shared/db').should be_false
      end

      it "doesn't link solr" do
        File.readlink('/usr/local/chorus/releases/2.2.0.0/solr/data').should == '/usr/local/chorus/shared/solr/data'
        File.symlink?('/usr/local/chorus/shared/solr/data').should be_false
      end

      it "doesn't link log" do
        File.readlink('/usr/local/chorus/releases/2.2.0.0/log').should == '/usr/local/chorus/shared/log'
        File.symlink?('/usr/local/chorus/shared/log').should be_false
      end

      it "creates the nginx folder" do
        File.exists?('/usr/local/chorus/shared/log/nginx').should be_true
      end
    end

    context "when data_path is not set" do
      let(:data_path) { nil }
      it_should_behave_like "not link the data paths"
    end

    context "when data_path is set to the shared directory" do
      let(:data_path) { destination_path + "/shared" }
      it_should_behave_like "not link the data paths"
    end
  end

  describe "#create_database_config" do
    before do
      installer.destination_path = "/usr/local/chorus"
      create_test_database_yml
    end

    it "writes a new random password to the database.yml" do
      installer.create_database_config
      installer.database_password.should_not == 'something'
      installer.database_password.length >= 10
      installer.database_user.should == 'the_user'

      YAML.load_file('/usr/local/chorus/shared/database.yml')['production']['password'].should == installer.database_password
    end

    it "does not update database.yml if upgrading" do
      installer.install_mode = :upgrade_existing
      installer.create_database_config

      YAML.load_file('/usr/local/chorus/shared/database.yml')['production']['password'].should == 'something'
    end
  end

  describe "#validate_data_sources" do
    before do
      stub(installer).version { "2.2.0.0" }
      installer.destination_path = destination_path
      FileUtils.mkdir_p "#{destination_path}/shared"
    end

    let(:destination_path) { "/usr/local/chorus" }

    context "when the data sources are invalid" do
      before do
        mock(executor).rake("validations:data_source") { false }
        mock(executor).start_postgres
      end

      it "raises an installer error" do
        expect { installer.validate_data_sources }.to raise_error(InstallerErrors::InstallAborted, /Duplicate names found in data sources\.  Please change data source names so that they are all unique before upgrading/)
      end
    end

    context "when the data sources are valid" do
      before do
        mock(executor).rake("validations:data_source") { true }
        mock(executor).start_postgres
      end

      it "runs without incident" do
        expect { installer.validate_data_sources }.to_not raise_error
      end
    end
  end

  describe "#setup_database" do
    before do
      stub(installer).version { "2.2.0.0" }
      installer.destination_path = destination_path
      FileUtils.mkdir_p "#{destination_path}/shared"

      installer.database_user = 'the_user'
      installer.database_password = 'secret'
      installer.data_path = "/data/chorus"
      FileUtils.mkdir_p "#{installer.release_path}/postgres"
    end

    let(:destination_path) { "/usr/local/chorus" }

    context "when installing fresh" do
      it "creates the database structure" do
        installer.setup_database
        executor.call_order.should == [:initdb, :start_postgres, :rake, :stop_postgres]
        executor.calls[:initdb].should == [installer.data_path, installer.database_user]
        executor.calls[:rake].should == ["db:create db:migrate db:seed enqueue:refresh_and_reindex"]

        stats = File.stat("/usr/local/chorus/releases/2.2.0.0/postgres/pwfile").mode
        sprintf("%o", stats).should == "100400"
      end
    end

    context "#when upgrading" do
      before do
        installer.install_mode = :upgrade_existing
      end

      it "migrates the existing database" do
        installer.setup_database
        executor.call_order.should == [:start_postgres, :rake, :stop_postgres]
        executor.calls[:rake].should == ["db:migrate enqueue:refresh_and_reindex"]
      end
    end
  end

  describe "#stop_previous_release" do
    context "when installing fresh" do
      before do
        dont_allow(installer).system
      end

      it "should do nothing" do
        installer.stop_previous_release
      end
    end

    context "when upgrading" do
      before do
        stub(installer).version { '2.2.0.0' }
        installer.install_mode = :upgrade_existing
        installer.destination_path = '/usr/local/chorus'
        mock(executor).stop_previous_release
      end

      it "should stop the previous version" do
        installer.stop_previous_release
      end
    end
  end

  describe "#startup" do
    context "when installing fresh" do
      before do
        dont_allow(installer).system
      end

      it "should do nothing" do
        installer.startup
      end
    end

    context "when upgrading" do
      before do
        stub(installer).version { '2.2.0.0' }
        installer.install_mode = :upgrade_existing
        installer.destination_path = '/usr/local/chorus'
        mock(executor).start_chorus
      end

      it "should stop the previous version" do
        installer.startup
      end
    end
  end

  describe "#link_current_to_release" do
    let(:previous_version) { '/usr/local/chorus/releases/1.2.2.2' }
    let(:new_version) { '/usr/local/chorus/releases/2.2.0.0' }
    before do
      installer.destination_path = "/usr/local/chorus"
      stub(installer).version { '2.2.0.0' }
      FileUtils.mkdir_p previous_version
    end

    it "creates a symlink to the new release from current" do
      installer.link_current_to_release

      File.readlink('/usr/local/chorus/current').should == new_version
    end

    context "when there is an existing link to current" do
      before do
        mock(old_release_cleaner).remove_except(new_version, previous_version)
      end

      it "should overwrite the existing link to current" do
        FileUtils.ln_s(previous_version, "/usr/local/chorus/current")
        mock(File).delete("/usr/local/chorus/current") # FakeFS workaround
        installer.link_current_to_release

        File.readlink('/usr/local/chorus/current').should == '/usr/local/chorus/releases/2.2.0.0'
      end
    end

    context "when there is no existing link to current" do
      it "should not try to remove directories, because this is probably a fresh install" do
        do_not_allow(old_release_cleaner).remove_except
        installer.link_current_to_release
      end
    end

    it "should create a symlink for chorus_control" do
      installer.link_current_to_release

      File.readlink('/usr/local/chorus/chorus_control.sh').should == '/usr/local/chorus/releases/2.2.0.0/packaging/chorus_control.sh'
    end

    it "should replace an existing link to chorus_control" do
      FileUtils.ln_s("/usr/local/chorus/releases/1.2.2.2", "/usr/local/chorus/chorus_control.sh")
      installer.link_current_to_release

      File.readlink('/usr/local/chorus/chorus_control.sh').should == '/usr/local/chorus/releases/2.2.0.0/packaging/chorus_control.sh'
    end
  end

  describe "#extract_postgres" do
    before do
      stub_version
      installer.destination_path = "/usr/local/chorus"
    end

    it "calls tar to unpack postgres" do
      installer.instance_variable_set(:@postgres_package, 'postgres-blahblah.tar.gz')
      mock(executor).extract_postgres('postgres-blahblah.tar.gz')
      installer.extract_postgres
    end
  end

  describe "#validate_localhost" do
    context "when localhost is undefined"
    it "raises an exception" do
      mock(installer).system("ping -c 1 localhost > /dev/null") { false }
      expect { installer.validate_localhost }.to raise_error(InstallerErrors::InstallAborted, /Could not connect to 'localhost', please set in \/etc\/hosts/)
    end

    context "when localhost is defined" do
      it "does not raise an exception" do
        expect { installer.validate_localhost }.to_not raise_error()
      end
    end
  end

  describe "#remove_and_restart_previous!" do
    let(:public_dir) { "/usr/local/chorus/releases/2.2.0.0/public" }
    before do
      stub(installer).version { "2.2.0.0" }
      installer.destination_path = "/usr/local/chorus"
      FileUtils.mkdir_p public_dir
      FileUtils.touch "#{public_dir}/foo"
      installer.secure_public_directory
    end

    context "when upgrading an existing 2.2 installation" do
      before do
        installer.install_mode = :upgrade_existing
        mock(executor).start_previous_release
      end

      it "starts up the previous installation" do
        installer.remove_and_restart_previous!
      end

      it "removes the release folder" do
        mock(FileUtils).chmod_R(0755, public_dir)
        installer.remove_and_restart_previous!
        File.exists?("/usr/local/chorus/releases/2.2.0.0").should == false
      end
    end

    context "when doing a fresh install" do
      before do
        installer.install_mode = :fresh
      end

      it "stops postgres and removes the release folder" do
        FileUtils.mkdir_p "#{installer.release_path}/postgres"
        mock(executor).stop_postgres
        installer.remove_and_restart_previous!
        File.exists?("/usr/local/chorus/releases/2.2.0.0").should == false
      end
    end
  end

  describe "#warn_and_change_osx_properties" do
    before do
      installer.destination_path = '/usr/local/chorus'
    end
    let(:chorus_config_path) { File.join(installer.destination_path, 'shared', 'chorus.properties') }

    it "modifies the properties to be OS X specific" do
      mock(Properties).load_file(chorus_config_path) { {} }
      stub(Properties).dump_file(hash_including({
                                                  'worker_threads' => 5,
                                                  'webserver_threads' => 5,
                                                  'database_threads' => 15}), chorus_config_path)
      installer.warn_and_change_osx_properties
    end
  end

  describe "#prompt_for_eula" do
    subject { installer.prompt_for_eula }
    before do
      mock(io).log(installer.eula)
      mock(io).require_confirmation(:accept_terms)
    end

    it "should require confirmation" do
      subject
    end
  end

  describe "#eula" do
    describe "a pivotal build" do
      before do
        ENV['PIVOTALLABEL'] = 'true'
      end

      it "contains the emc eula" do
        installer.eula.should match(/EMC Corporation/)
      end
    end

    describe "a standard build" do
      before do
        ENV['PIVOTALLABEL'] = nil
      end

      it "contains the alpine eula" do
        installer.eula.should match(/ALPINE ANALYTICS/)
      end
    end
  end

  describe "#dump_environment" do
    DCA_FILES = ['/opt/greenplum/conf/build-version.txt',
                 '/opt/greenplum/conf/productid',
                 '/opt/greenplum/serialnumber']

    describe "detecting the installation OS" do
      before do
        Java::JavaUtil::Properties.__persistent__ = true
        stub(System.get_properties).entry_set { ["os.name=TestOS", "os.version=1.2.3"] }
      end

      it "prints out the java system properties" do
        mock(logger).log("os.name=TestOS")
        mock(logger).log("os.version=1.2.3")
        installer.dump_environment
      end

      it "prints out the /etc/*-release files" do
        mock(logger).log("/etc/test-release: a test os 1.0")
        FileUtils.mkdir_p('/etc')
        File.open('/etc/test-release', 'w') { |f| f.puts "a test os 1.0" }
        installer.dump_environment
      end

      describe "prints out section headers" do
        it "outputs section headers" do
          mock(logger).log("=== ENVIRONMENT INFO BEGIN")
          mock(logger).log("== JAVA ENVIRONMENT")
          mock(logger).log("== OPERATING SYSTEM RELEASE")
          mock(logger).log("=== ENVIRONMENT INFO END")
          installer.dump_environment
        end

        context "when there are DCA files present" do
          before do
            FileUtils.mkdir_p('/opt/greenplum/conf')
            DCA_FILES.each do |path|
              File.open(path, 'w') { |f| f.puts "#{path} content" }
            end
          end

          it "outputs the section header" do
            mock(logger).log("== DCA SPECIFIC FILES")
            installer.dump_environment
          end

          context "when the current user does not have permission to access the DCA files" do
            before do
              DCA_FILES.each do |path|
                mock(File).readable?(path) { false }
              end

              stub(File).open('/opt/greenplum/conf/build-version.txt') { raise Errno::EACCES.new("permission denied") }
            end

            it "does not explode" do
              expect { installer.dump_environment }.not_to raise_error
            end
          end
        end

        context "when there are not DCA files present" do
          it "doesn't output the section header" do
            dont_allow(logger).log("== DCA SPECIFIC FILES")
            installer.dump_environment
          end
        end
      end
    end

    describe "DCA specific files" do
      it "prints out the file names and contents if files exist" do
        FileUtils.mkdir_p('/opt/greenplum/conf')
        DCA_FILES.each do |path|
          mock(logger).log("#{path}: #{path} content")
          File.open(path, 'w') { |f| f.puts "#{path} content" }
        end
        installer.dump_environment
      end
    end
  end

  describe "#log_at_end" do
    it "does not output immediately" do
      dont_allow(installer).log
      installer.log_at_end("HI!")
    end

    it "outputs when flush_logs is called" do
      installer.log_at_end("HI!")
      installer.log_at_end("BYE!")
      mock(installer).log("HI!")
      mock(installer).log("BYE!")
      installer.flush_logs
    end
  end

  describe "#alpine_exists?" do
    before do
      stub_version
    end

    context 'if alpine package exists' do
      let(:alpine_version_new) { '3.0-asdfsdf' }

      before do
        FileUtils.mkdir_p(installer.alpine_source_path)
        File.open("#{installer.alpine_source_path}/alpine-3.0.0.0.38-e970d467.sh", 'w') do |f|
          f.puts "i am alpine"
        end
        stub(installer).alpine_version { alpine_version_new }
      end

      it 'returns true' do
        installer.alpine_exists?.should be_true
      end

      describe '#link_current_to_release' do
        let(:previous_version) { '/usr/local/chorus/alpine-releases/3-old' }
        let(:new_version) { '/usr/local/chorus/alpine-releases/' + alpine_version_new }
        before do
          installer.destination_path = '/usr/local/chorus'
          stub(installer).version { '2.2.0.0' }
          FileUtils.mkdir_p previous_version
        end

        it 'creates a symlink to the new release from alpine-current' do
          installer.link_to_current_alpine_release

          File.readlink('/usr/local/chorus/alpine-current').should == new_version
        end

        context 'when there is an existing link to current' do
          before do
            mock(old_release_cleaner).remove_except(new_version, previous_version)
          end

          it 'should overwrite the existing link to current' do
            FileUtils.ln_s(previous_version, '/usr/local/chorus/alpine-current')
            mock(File).delete('/usr/local/chorus/alpine-current') # FakeFS workaround
            installer.link_to_current_alpine_release

            File.readlink('/usr/local/chorus/alpine-current').should == new_version
          end
        end

        context 'when there is no existing link to current' do
          it 'should not try to remove directories, because this is probably a fresh install' do
            do_not_allow(old_release_cleaner).remove_except
            installer.link_to_current_alpine_release
          end
        end
      end
    end

    context 'if alpine package does not exist' do
      it 'returns false' do
        installer.alpine_exists?.should be_false
      end
    end
  end

  describe "#set_properties" do
    before do
      installer.destination_path = '/usr/local/chorus'
    end
    let(:chorus_config_path) { File.join(installer.destination_path, 'shared', 'chorus.properties') }

    it "changes the chorus_properties with some cool new props" do
      mock(Properties).load_file(chorus_config_path) { {} }
      stub(Properties).dump_file(hash_including({
                                                  'sandwich' => 'board'
                                                }), chorus_config_path)
      installer.set_properties({'sandwich' => 'board'})
    end
  end

  def stub_version
    FileUtils.mkdir_p('./chorus_installation')
    File.open('./chorus_installation/version_build', 'w') { |f| f.puts "2.2.0.0" }
  end
end
