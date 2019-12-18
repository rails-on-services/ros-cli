# frozen_string_literal: true

# https://nandovieira.com/creating-generators-and-executables-with-thor
require 'thor'
require 'ros/be/application/cli'
# require 'ros/cli/lpass'

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
    def new(name)
      FileUtils.rm_rf(name) if Dir.exist?(name) && options.force
      raise Error, set_color("ERROR: #{name} already exists. Use -f to force", :red) if Dir.exist?(name)

      generate_project(name)
    end

    desc 'console', 'Start the Ros console (short-cut alias: "c")'
    map %w[c] => :console
    def console(service = nil)
      if service.nil?
        Pry.start
        return
      end
      Ros::Be::Application::Cli.new([], v: true).console(service)
    end

    desc 'server', 'Start the Ros console (short-cut alias: "s")'
    map %w[s] => :server
    def server(service)
      Ros::Be::Application::Cli.new([], v: true, daemon: true, attach: true).server(service)
    end

    desc 'be COMMAND', 'Invoke backend commands'
    subcommand 'be', Ros::Be::Application::Cli

    # desc 'lpass COMMAND', "Transfer the contents of #{Ros.env} to/from a Lastpass account"
    # option :username, aliases: '-u'
    # subcommand 'lpass', Ros::Cli::Lpass

    private

    def generate_project(name)
      # host = URI(args[1] || 'http://localhost:3000')
      # args.push(:nil, :nil, :nil)
      require 'ros/main/project/generator.rb'
      generator = Ros::Main::Project::Generator.new(args)
      generator.destination_root = name
      generator.invoke_all
      # require 'ros/main/env/generator.rb'
      # %w(development test production).each do |env|
      #   generator = Ros::Main::Env::Generator.new([env, nil, name, nil])
      #   generator.destination_root = name
      #   generator.invoke_all
      # end
      # require 'ros/generators/be/application/platform/rails/rails_generator.rb'
      # generator = Ros::Generators::Be::RailsGenerator.new(args)
      # generator.destination_root = "#{name}/be"
      # generator.invoke_all
    end
  end
end
