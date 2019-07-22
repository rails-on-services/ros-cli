# frozen_string_literal: true
# https://nandovieira.com/creating-generators-and-executables-with-thor
require 'thor'

# TODO: move new, generate and destroy to ros/generators
# NOTE: it should be possible to invoke any operation from any of rake task, cli or console

module Ros
  class Cli < Thor
    def self.exit_on_failure?; true end

    check_unknown_options!
    class_option :v, type: :boolean, default: false, desc: 'verbose output'
    class_option :n, type: :boolean, default: false, desc: "run but don't execute action"

    desc 'version', 'Display version'
    def version; say "Ros #{VERSION}" end

    desc 'new NAME', "Create a new Ros platform project. \"ros new my_project\" creates a\n" \
      'new project called MyProject in "./my_project"'
    option :force, type: :boolean, default: false, aliases: '-f'
    def new(*args)
      name = args[0]
      FileUtils.rm_rf(name) if Dir.exists?(name) and options.force
      raise Error, set_color("ERROR: #{name} already exists. Use -f to force", :red) if Dir.exists?(name)
      Ros.generate_project(args)
    end

    class Generate < Thor
      desc 'service', 'Generates a new service'
      def service(name)
        test_for_project
        Ros.generate_service(args, options, current_command_chain.first)
        Ros.generate_env(args, options, current_command_chain.first.eql?(:destroy) ? :revoke : :invoke)
      end

      desc 'env', 'Generates a new environment'
      def env(*args)
        test_for_project
        Ros.generate_env(args, options, current_command_chain.first.eql?(:destroy) ? :revoke : :invoke)
      end

      private
      def test_for_project
        raise Error, set_color("ERROR: Not a Ros project", :red) if Ros.root.nil?
      end
    end

    desc 'generate TYPE', 'Generate a new asset of type TYPE (short-cut alias: "g")'
    map %w(g) => :generate
    option :force, type: :boolean, default: false, aliases: '-f'
    subcommand 'generate', Generate

    # TODO: refactor setting action to :destroy
    desc 'destroy TYPE', 'Destroy an asset (environment or service)'
    map %w(d) => :destroy
    subcommand 'destroy', Generate

    desc 'preflight', 'Prepare a project'
    def preflight
      Ros.preflight_check(fix: true)
      Ros.preflight_check
    end

    # TODO: Get this working again
    class Lpass < Thor
      desc 'add', "Add #{Ros.env} environment to Lastpass"
      def add
        test_for_project
        lpass_name = "#{Ros.root}/config/environments/#{Ros.env}.yml"
        %x(lpass login #{options.username}) if options.username
        binding.pry
        %x(lpass add --non-interactive --notes #{Ros.env} < #{lpass_name})
      end

      desc 'show', "Displays #{Ros.env} environment from Lastpass"
      def show
        test_for_project
        %x(lpass show --notes #{Ros.env})
      end

      desc 'update', "Updates #{Ros.env} environment in Lastpass"
      def update
        test_for_project
      end

      private
      def test_for_project
        raise Error, set_color("ERROR: Not a Ros project", :red) if Ros.root.nil?
      end
    end

    desc 'lpass ACTION', "Transfer the contents of #{Ros.env} to/from a Lastpass account"
    option :username, aliases: '-u'
    subcommand 'lpass', Lpass

    desc 'build IMAGE', 'build one or all images'
    map %w(b) => :build
    def build(*services)
      context(options).build(services)
    end

    desc 'up SERVICE', 'bring up service(s)'
    option :build, type: :boolean, aliases: '-b', desc: 'Build image before run'
    option :console, type: :boolean, aliases: '-c', desc: 'Connect to service console after starting'
    option :daemon, type: :boolean, aliases: '-d', desc: 'Run in the background'
    option :force, type: :boolean, default: false, aliases: '-f', desc: 'Force cluster creation'
    option :seed, type: :boolean, aliases: '--seed', desc: 'Seed the database before starting the service'
    option :shell, type: :boolean, aliases: '-s', desc: 'Connect to service shell after starting'
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

    option :console, type: :boolean, aliases: '-c', desc: 'Connect to service console after starting'
    option :shell, type: :boolean, aliases: '-s', desc: 'Connect to service shell after starting'
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
      raise Error, set_color("ERROR: Not a Ros project", :red) if Ros.root.nil?
      infra_type = 'instance'
      infra_type = Settings.components.be.components.cluster.config.type
      type = :cli
      require "ros/ops/#{infra_type}"
      @context = Object.const_get("Ros::Ops::#{infra_type.capitalize}::#{type.to_s.capitalize}").new(options)
      @context
    end
  end
end
