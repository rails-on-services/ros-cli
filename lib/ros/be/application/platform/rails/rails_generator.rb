# frozen_string_literal: true

require 'thor/group'

module Ros
  module Generators
    module Be
      class RailsGenerator < Thor::Group
        include Thor::Actions
        argument :name

        def self.source_paths; [Pathname(File.dirname(__FILE__)).join('templates').to_s, File.dirname(__FILE__)] end

        def generate
          in_root do
            `git clone https://github.com/rails-on-services/ros.git`
            FileUtils.cp_r('ros/devops', '.')
          end # if false
          # directory('files', '.')
          # TODO: move to be specific
          # template 'Dockerfile'
          # empty_directory('services')
        end

        def core
          require 'ros/generators/be/rails/core/core_generator.rb'
          generator = Ros::Generators::CoreGenerator.new([name])
          generator.destination_root = "#{name}/be"
          generator.invoke_all
        end

        def sdk
          require 'ros/generators/be/rails/sdk/sdk_generator.rb'
          generator = Ros::Generators::SdkGenerator.new([name])
          generator.destination_root = "#{name}/be"
          generator.invoke_all
        end

        private

        # TODO: Fix these hard coded values to dynamic
        def ruby_version; '2.6.3' end

        def os_version; 'stretch' end

        def static_gems
          ['bundler:2.0.1',
           'nokogiri:1.10.3',
           'ffi:1.10.0',
           'mini_portile2:2.3.0',
           'msgpack:1.2.9',
           'pg:1.1.4',
           'nio4r:2.3.1',
           'puma:3.12.0',
           'eventmachine:1.2.7']
        end

        def create_ros_services
          # TODO: for each ros service gem, generate a rails application in ./services that includes that gem
          # TODO figure out how the ros services are written to a new project. they should be apps that include ros service gems
        end

        def gemfile_content
          ros_gems = ''
          if options.dev
            ros_gems = <<~'EOF'
              git 'git@github.com:rails-on-services/ros.git', glob: '**/*.gemspec', branch: :master do
                gem 'ros', path: 'ros/ros'
                gem 'ros-cognito', path: 'ros/services/cognito'
                gem 'ros-comm', path: 'ros/services/comm'
                gem 'ros-iam', path: 'ros/services/iam'
                gem 'ros-core', path: 'ros/lib/core'
                gem 'ros_sdk', path: 'ros/lib/sdk'
              end
            EOF
          end
        end
      end
    end
  end
end
