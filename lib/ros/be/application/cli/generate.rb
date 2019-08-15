# frozen_string_literal: true
require 'ros/be/application/cli_base'

module Ros
  module Be
    module Application
      class GenerateCli < Thor
        include CliBase

        check_unknown_options!
        class_option :v, type: :boolean, default: false, desc: 'verbose output'
        class_option :n, type: :boolean, default: false, desc: "run but don't execute action"

        def initialize(*args)
          super
          self.options = args.empty? ? {} : args[2][:class_options]
        end

        desc 'service', 'Generates a new service'
        def service(name)
          generate_service(args, options, current_command_chain[1].eql?(:destroy) ? :revoke : :invoke)
        end

        private
        def generate_service(args, options = {}, behavior = nil)
          test_for_project
          require 'ros/be/application/platform/rails/service/service_generator'
          args.push(File.basename(Ros.root)) unless args[1]
          generator = Ros::Be::Application::Platform::Rails::Service::Generator.new(args, options)
          generator.options = options
          generator.behavior = behavior if behavior
          # NOTE: This is necessary b/c currently the generator is called from a subcommand whihc doesn't pass options
          generator.behavior = :revoke if options&.behavior&.eql?('revoke')
          generator.destination_root = Ros.root
          generator.invoke_all
        end
      end
    end
  end
end
