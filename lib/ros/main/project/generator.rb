# frozen_string_literal: true

require 'thor/group'

module Ros
  module Main
    module Project
      class Generator < Thor::Group
        include Thor::Actions
        argument :name

        def self.source_paths; [Pathname(File.dirname(__FILE__)).join('templates').to_s, File.dirname(__FILE__)] end

        def generate
          directory('files', '.')
          # TODO: template Dockerfiles for the various supported languages, e.g. node
          # template 'Dockerfile'
          template 'config/deployment.yml'
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
