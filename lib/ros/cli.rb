# frozen_string_literal: true
# https://nandovieira.com/creating-generators-and-executables-with-thor
require 'thor'

# TODO: move new, generate and destroy to ros/generators
# NOTE: it should be possible to invoke any operation from any of rake task, cli or console

module Ros
  class Cli < Thor
    def self.exit_on_failure?; true end

    check_unknown_options!
    # class_option :verbose, type: :boolean, default: false, alias: '-v'
    class_option :v, type: :boolean, default: false
    class_option :n, type: :boolean, default: false

    desc 'version', 'Display version'
    # map %w(--version) => :version
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
        generator = Ros::Generators::EnvGenerator.new([env, host, name, :nil])
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

    class Generate < Thor
      desc 'service', 'Generates a new service'
      def service(name)
        test_for_project
        Ros.generate_service(args, options)
      end

      desc 'env', 'Generates a new environment'
      def env(*args)
        test_for_project
        Ros.generate_env(args, options)
      end

      private
      def test_for_project
        raise Error, set_color("ERROR: Not a Ros project", :red) if Ros.root.nil?
      end
    end

    desc 'generate SUBCOMMAND', 'Some Parent Command'
    map %w(g) => :generate
    option :force, type: :boolean, default: false, aliases: '-f'
    subcommand 'generate', Generate

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

    desc 'build IMAGE', 'build one or all images'
    map %w(b) => :build
    def build(*services)
      context(options).build(services)
    end

    desc 'up SERVICE', 'bring up service(s)'
    option :daemon, type: :boolean, aliases: '-d', desc: 'Run in the background'
    option :seed, type: :boolean, aliases: '--seed', desc: 'Seed the database before starting the service'
    def up(*services)
      context(options).up(services)
    end

    desc 'server PROFILE', 'Start all services (short-cut alias: "s")'
    option :daemon, type: :boolean, aliases: '-d'
    option :environment, type: :string, aliases: '-e', default: 'development'
    map %w(s) => :server
    def server
      # TODO: Test this
      Ros.load_env(options.environment) if options.environment != Ros.default_env
      context(options).up
      # Ros.ops_action(:platform, :apply, options)
    end

    desc 'ps', 'List running services'
    def ps
      context(options).ps
    end

    desc 'console', 'Start the Ros console (short-cut alias: "c")'
    map %w(c) => :console
    def console(service = nil)
      if service
        context(options).console(service)
      else
        context(options).switch!
        Pry.start
      end
    end

    desc 'exec SERVICE COMMAND', 'execute an interactive command on a service (short-cut alias: "e")'
    map %w(e) => :exec
    def exec(service, command)
      context(options).exec(service, command)
    end

    desc 'rails SERVICE COMMAND', 'execute a rails command on a service (short-cut alias: "r")'
    map %w(r) => :rails
    def rails(service, command)
      context(options).exec(service, "rails #{command}")
    end

    desc 'shell SERVICE', 'execute an interactive shell on a service (short-cut alias: "sh")'
    def sh(service)
      context(options).exec(service, 'bash')
    end

    desc 'logs', 'Tail logs of a running service'
    option :tail, type: :boolean, aliases: '-f'
    def logs(service)
      context(options).logs(service)
    end

    desc 'restart SERVICE', 'Start and stop one or more services'
    def restart(*services)
      context(options).restart(services)
    end

    desc 'stop SERVICE', 'Stop a service'
    def stop(*services)
      context(options).stop(services)
    end

    desc 'down', 'bring down platform'
    def down
      context(options).down
    end

    desc 'list', 'List configuration objects'
    map %w(ls) => :list
    def list(what = nil)
      STDOUT.puts 'Options: infra, services, platform' if what.nil?
      STDOUT.puts "#{Settings.components.be.components.application.components[what].components.keys.join("\n")}" unless what.nil?
    end

    private

    def context(options = {})
      return @context if @context
      infra_type = Settings.components.be.components.cluster.config.type
      type = :cli
      require "ros/ops/#{infra_type}"
      @context = Object.const_get("Ros::Ops::#{infra_type.capitalize}::#{type.to_s.capitalize}").new(options)
      @context
    end
  end
end
