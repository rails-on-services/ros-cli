# frozen_string_literal: true
# https://nandovieira.com/creating-generators-and-executables-with-thor
require 'thor'
require 'ros/cli/be'

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

    desc 'new NAME', 'Create a new Ros project. "ros new my_project" creates a new project in "./my_project"'
    option :force, type: :boolean, default: false, aliases: '-f'
    def new(*args)
      name = args[0]
      FileUtils.rm_rf(name) if Dir.exists?(name) and options.force
      raise Error, set_color("ERROR: #{name} already exists. Use -f to force", :red) if Dir.exists?(name)
      Ros.generate_project(args)
    end

    desc 'console', 'Start the Ros console (short-cut alias: "c")'
    map %w(c) => :console
    def console
      # context(options).switch!
      Pry.start
    end

    # TODO: Get this working again
    class Lpass < Thor
      desc 'add', "Add #{Ros.env} environment to Lastpass"
      def add
        test_for_project
        lpass_name = "#{Ros.root}/config/environments/#{Ros.env}.yml"
        %x(lpass login #{options.username}) if options.username
        binding.pry
        # %x(lpass add --non-interactive --notes #{Ros.env} < #{lpass_name})
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

    desc 'lpass COMMAND', "Transfer the contents of #{Ros.env} to/from a Lastpass account"
    option :username, aliases: '-u'
    subcommand 'lpass', Lpass

    desc 'be COMMAND', 'Invoke backend commands'
    # register(Ros::Be::Cli, 'be', 'generate [something]', 'Type foo generate for more help.')
    subcommand 'be', Ros::Be::Cli
  end
end
