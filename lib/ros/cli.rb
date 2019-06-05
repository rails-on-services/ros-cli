# frozen_string_literal: true
# https://nandovieira.com/creating-generators-and-executables-with-thor
require 'thor'

# TODO: move new, generate and destroy to ros/generators
# NOTE: it should be possible to invoke any operation from any of rake task, cli or console

module Ros
  class Cli < Thor
    def self.exit_on_failure?; true end

    check_unknown_options!
    class_option :verbose, type: :boolean, default: false

    desc 'version', 'Display version'
    map %w(-v --version) => :version
    def version; say "Ros #{VERSION}" end

    desc 'new NAME HOST', "Create a new Ros platform project. \"ros new my_project\" creates a\n" \
      'new project called MyProject in "./my_project"'
    option :force, type: :boolean, default: false, aliases: '-f'
    def new(*args)
      name = args[0]
      host = URI(args[1] || 'http://localhost:3000')
      args.push(:nil, :nil, :nil)
      FileUtils.rm_rf(name) if Dir.exists?(name) and options.force
      raise Error, set_color("ERROR: #{name} already exists. Use -f to force", :red) if Dir.exists?(name)
      require_relative 'generators/project/project_generator.rb'
      generator = Ros::Generators::ProjectGenerator.new(args)
      generator.destination_root = name
      generator.invoke_all
      require_relative 'generators/env/env_generator.rb'
      %w(console local development production).each do |env|
        generator = Ros::Generators::EnvGenerator.new([env, name, host, :nil])
        generator.destination_root = name
        generator.invoke_all
      end
      require_relative 'generators/core/core_generator.rb'
      generator = Ros::Generators::CoreGenerator.new(args)
      generator.destination_root = name
      generator.invoke_all
      require_relative 'generators/sdk/sdk_generator.rb'
      generator = Ros::Generators::SdkGenerator.new(args)
      generator.destination_root = name
      generator.invoke_all
    end

    desc 'generate TYPE NAME', 'Generate a new environment or service'
    map %w(g) => :generate
    option :force, type: :boolean, default: false, aliases: '-f'
    def generate(artifact, *args)
      raise Error, set_color("ERROR: Not a Ros project", :red) if Ros.root.nil?
      valid_artifacts = %w(service env)
      raise Error, set_color("ERROR: invalid artifact #{artifact}. valid artifacts are: #{valid_artifacts.join(', ')}", :red) unless valid_artifacts.include? artifact
      raise Error, set_color("ERROR: must supply a name for #{artifact}", :red) if %w(service env).include?(artifact) and args[0].nil?
      Ros.send("generate_#{artifact}", args, options)
    end

    # TODO: refactor setting action to :destroy
    desc 'destroy TYPE NAME', 'Destroy an environment or service'
    map %w(d) => :destroy
    def destroy(artifact, *args)
      raise Error, set_color("ERROR: Not a Ros project", :red) if Ros.root.nil?
      valid_artifacts = %w(service env)
      raise Error, set_color("ERROR: invalid artifact #{artifact}. valid artifacts are: #{valid_artifacts.join(', ')}", :red) unless valid_artifacts.include? artifact
      raise Error, set_color("ERROR: must supply a name for #{artifact}", :red) if %w(service env).include?(artifact) and args[0].nil?
      Ros.send("generate_#{artifact}", args, options, :revoke)
    end

    # TODO Handle show and edit as well
    desc 'lpass ACTION', 'Transfer the contents of app.env to/from a Lastpass account'
    option :username, aliases: '-u'
    def lpass(action)
      raise Error, set_color("ERROR: invalid action #{action}. valid actions are: add, show, edit", :red) unless %w(add show edit).include? action
      raise Error, set_color("ERROR: Not a Ros project", :red) unless File.exists?('app.env')
      lpass_name = "#{File.basename(Dir.pwd)}/development"
      %x(lpass login #{options.username}) if options.username
      %x(lpass add --non-interactive --notes #{lpass_name} < app.env)
    end

    desc 'console', 'Start the Ros console (short-cut alias: "c")'
    map %w(c) => :console
    def console(service = nil)
      if service
        # binding.pry
        type = Settings.meta.components.provider.split('/').last
        if type.eql?('instance')
          run_string = %x(docker-compose ps #{service} | grep #{service}).length.positive? ? 'exec' : 'run --rm'
          # Settings.platform.environment.partition_name}_nginx_1 nginx -s reload)
          system("docker-compose #{run_string} #{service} rails console")
        end
        return
      else
        # Ros.load_env(env) if (env and env != Ros.default_env)
        Pry.start
      end
    end

    desc 'server PROFILE', 'Start all services (short-cut alias: "s")'
    option :daemon, type: :boolean, aliases: '-d'
    option :environment, type: :string, aliases: '-e', default: 'local'
    # option :initialize, type: :boolean, aliases: '-i'
    map %w(s) => :server
    def server
      Ros.load_env(options.environment) if options.environment != Ros.default_env
      Ros.ops_action(:service, :provision, options)
    end

    desc 'build IMAGE', 'build one or all images'
    map %w(b) => :build
    def build(services = nil)
      compose(:build, services)
    end

    # wrap docker compose commands
    desc 'up', 'bring up service(s)'
    option :daemon, type: :boolean, aliases: '-d'
    def up(services = nil)
      compose(:up, services)
      %x(docker container exec #{Settings.platform.partition_name}_nginx_1 nginx -s reload)
    end

    desc 'stop', 'stop platform'
    def stop
      compose(:stop, '')
    end

    desc 'down', 'bring down platform'
    def down
      compose(:down, '')
    end

    desc 'restart SERVICE', 'Restart a service'
    def restart(service)
      compose(:stop, service)
      compose(:rm, service)
      compose('up -d', service)
      sleep 3
      %x(docker container exec #{Settings.platform.partition_name}_nginx_1 nginx -s reload)
    end

    desc 'reload all non-platform services', 'Reloads all non-platform services'
    def reload(services = nil)
      compose(:stop, services)
      compose('up -d', services)
      sleep 3
      %x(docker container exec #{Settings.platform.partition_name}_nginx_1 nginx -s reload)
    end

    desc 'logs', 'Tail logs of a running service'
    def logs(service)
      puts system("docker-compose logs -f #{service}")
    end

    desc 'ps', 'List running services'
    def ps
      puts %x(docker-compose ps)
    end

    desc 'list', 'List configuration objects'
    map %w(ls) => :list
    def list(what = nil)
      STDOUT.puts 'Options: services, profiles, images' if what.nil?
      STDOUT.puts "#{Settings.send(what).keys.join("\n")}" unless what.nil?
    end

    private

    def compose(command, services = nil)
      services = (services.nil? ? Ros.service_names_enabled : [services]).join(' ')
      # TODO: needs to get the correct name of the worker, etc
      # Settings.services.each_with_object([]) do |service, ary|
      #   ary.concat service.profiles
      # end
      compose_options = options.daemon ? '-d' : ''
      cmd_string = "docker-compose #{command} #{compose_options} #{services}"
      puts "Running #{cmd_string}"
      FileUtils.rm_f('.env')
      FileUtils.ln_s("#{compose_dir}/#{Ros.env}.env", '.env')
      system(cmd_string)
    end
    def compose_dir; "#{Ros.root}/tmp/compose" end
  end
end
