# frozen_string_literal: true
require 'ros/cli/be/common'

module Ros
  module Cli
    module Be
      class Generate < Thor
        include Ros::Cli::Be::Common
        check_unknown_options!
        class_option :v, type: :boolean, default: false, desc: 'verbose output'
        class_option :n, type: :boolean, default: false, desc: "run but don't execute action"

        def initialize(*args)
          super
          self.options = args.empty? ? {} : args[2][:class_options]
        end

        desc 'env', 'Generates a new environment'
        def env(*args)
          generate_env(args, options, current_command_chain[1].eql?(:destroy) ? :revoke : :invoke)
        end

        desc 'service', 'Generates a new service'
        def service(name)
          generate_service(args, options, current_command_chain[1].eql?(:destroy) ? :revoke : :invoke)
        end

        private

        def generate_env(args, options = {}, behavior = nil)
          test_for_project
          require 'ros/generators/stack/env/env_generator.rb'
          args.push('http://localhost:3000') unless args[1]
          args.push(File.basename(Ros.root)) unless args[2]
          args.push('')
          generator = Ros::Generators::EnvGenerator.new(args)
          generator.options = options
          generator.behavior = behavior if behavior
          generator.destination_root = Ros.root
          generator.invoke_all
        end

        def generate_service(args, options = {}, behavior = nil)
          test_for_project
          require 'ros/generators/be/service/service_generator'
          args.push(File.basename(Ros.root)) unless args[1]
          generator = Ros::Generators::ServiceGenerator.new(args, options)
          generator.options = options
          generator.behavior = behavior if behavior
          generator.destination_root = Ros.root
          generator.invoke_all
        end
      end
    end
  end
end
