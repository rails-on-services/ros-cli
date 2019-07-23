# frozen_string_literal: true

require 'ros/cli/be/common'

# TODO: move new, generate and destroy to ros/generators
# NOTE: it should be possible to invoke any operation from any of rake task, cli or console

module Ros
  module Be
    class Cli < Thor
      def self.exit_on_failure?; true end

      # def initialize(args) #, opts) # , a, b)
      #   binding.pry
      #   super
      # end

      check_unknown_options!
      class_option :v, type: :boolean, default: false, desc: 'verbose output'
      class_option :n, type: :boolean, default: false, desc: "run but don't execute action"

      desc 'version', 'Display version'
      def version; say "Ros #{VERSION}" end

      class Generate < Thor
        desc 'service', 'Generates a new service'
        def service(name)
          test_for_project
          Ros.generate_service(args, options, current_command_chain[1].eql?(:destroy) ? :revoke : :invoke)
        end

        desc 'env', 'Generates a new environment'
        def env(*args)
          test_for_project
          Ros.generate_env(args, options, current_command_chain[1].eql?(:destroy) ? :revoke : :invoke)
        end

        desc 'infra', 'Run terraform to create/destroy infrastructure'
        option :apply, type: :boolean, default: false, aliases: '-a'
        def infra(*args)
          require 'ros/cli/be/infra'
          # binding.pry
          Ros::Ops::Infra::Cli.new(options).send(current_command_chain[1])
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

      desc 'init', 'Initialize the cluster'
      option :long, type: :boolean, aliases: '-l', desc: 'Run the long form of the command'
      def init
        context(options).init
      end

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
      option :shell, type: :boolean, aliases: '--sh', desc: 'Connect to service shell after starting'
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
      def console(service)
        context(options).console(service)
      end

      desc 'exec SERVICE COMMAND', 'execute an interactive command on a service (short-cut alias: "e")'
      map %w(e) => :exec
      def exec(service, command)
        context(options).exec(service, command)
      end

      # TODO: refactor to a rails specifc set of commands in a dedicated file
      desc 'rails SERVICE COMMAND', 'execute a rails command on a service (short-cut alias: "r")'
      map %w(r) => :rails
      def rails(service, command)
        context(options).exec(service, "rails #{command}")
      end

      desc 'sh SERVICE', 'execute an interactive shell on a service (short-cut alias: "sh")'
      # NOTE: shell is a reserved word
      def sh(service)
        context(options).exec(service, 'bash')
      end

      desc 'logs', 'Tail logs of a running service'
      option :tail, type: :boolean, aliases: '-f'
      def logs(service)
        context(options).logs(service)
      end

      desc 'restart SERVICE', 'Start and stop one or more services'
      option :console, type: :boolean, aliases: '-c', desc: 'Connect to service console after starting'
      option :shell, type: :boolean, aliases: '--sh', desc: 'Connect to service shell after starting'
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

      desc 'list', 'List backend application configuration objects'
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
        require "ros/cli/be/#{infra_type}"
        @context = Object.const_get("Ros::Ops::#{infra_type.capitalize}::#{type.to_s.capitalize}").new(options)
        @context
      end
    end
  end
end
