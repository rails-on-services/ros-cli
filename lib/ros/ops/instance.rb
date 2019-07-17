# frozen_string_literal: true
require 'ros/generators/stack'
require 'ros/generators/be/application/services/services_generator'
require 'ros/generators/be/application/platform/platform_generator'

module Ros
  module Ops
    module Instance
      class Cli
        attr_accessor :options

        def initialize(options = {})
          @options = options
        end

        def build(services)
          generate_config if stale_config
          compose("build #{services.join(' ')}")
        end

        def up(services)
          generate_config if stale_config
          compose_options = options.daemon ? '-d' : ''
          services.each do |service|
            next unless ref = Settings.components.be.components.application.components.platform.components.dig(service)
            config = ref.dig(:config) || Config::Options.new
            if database_check(service, config)
              compose("up #{compose_options} #{service}")
            else
              compose("up #{compose_options} #{service}")
            end
          end
          reload_nginx
        end

        def ps
          generate_config if stale_config
          compose(:ps)
        end

        def console(service)
          generate_config if stale_config
          exec(service, 'rails console')
        end

        def exec(service, command)
          generate_config if stale_config
          run_string = services.include?(service) ? 'exec' : 'run --rm'
          # run_string = %x(docker-compose ps #{service} | grep #{service}).length.positive? ? 'exec' : 'run --rm'
          # binding.pry
          system("docker-compose #{run_string} #{service} #{command}")
        end

        def logs(service)
          generate_config if stale_config
          compose_options = options.tail ? '-f' : ''
          trap("SIGINT") { throw StandardError } if options.tail
          compose("logs #{compose_options} #{service}")
        rescue StandardError
        end

        def restart(services)
          compose("stop #{services.join(' ')}")
          compose("up -d #{services.join(' ')}")
          sleep 3
          reload_nginx
        end

        def stop(services)
          compose("stop #{services.join(' ')}")
          reload_nginx
        end

        def down; compose(:down) end

        # Supporting methods
        def stale_config
          return true unless File.exists?(Ros::Generators::Stack.compose_file)
          mtime = File.mtime(Ros::Generators::Stack.compose_file)
          # Check config files
          Dir["#{Ros.root}/config/**/*.yml"].each { |f| return true if mtime < File.mtime(f) }
          # Check template files
          # TODO: Add path to custom templates
          Dir["#{Pathname.new(File.dirname(__FILE__)).join('../generators')}/be/{application,cluster}/**/templates/**/*"].each { |f| return true if mtime < File.mtime(f) }
          false
        end

        def generate_config
          rs = $stdout
          $stdout = StringIO.new
          Ros::Generators::Be::Application::Services::ServicesGenerator.new([], {}, {behavior: :revoke}).invoke_all
          Ros::Generators::Be::Application::Services::ServicesGenerator.new.invoke_all
          Ros::Generators::Be::Application::Platform::PlatformGenerator.new([], {}, {behavior: :revoke}).invoke_all
          Ros::Generators::Be::Application::Platform::PlatformGenerator.new.invoke_all
          $stdout = rs
        end

        def reload_nginx
          running_services = services(application_component: 'platform')
          rs = $stdout
          $stdout = StringIO.new
          Ros::Generators::Be::Application::Services::ServicesGenerator.new.invoke(:write_nginx, [running_services])
          $stdout = rs
          compose('stop nginx')
          compose('up -d nginx')
          # compose('up -d nginx') unless system("docker container exec #{namespace}_nginx_1 nginx -s reload")
        end

        # stack.name: <%= @service.stack_name %>
        # stack.component: be
        # be.component: application
        # application.component: platform
        # platform.feature_set: <%= @service.current_feature_set %>
        # service.type: <%= profile %>
        def services(status: nil, application_component: nil)
          status ||= 'running'
          filters = []
          filters.append("--filter 'status=#{status}'")
          filters.append("--filter 'label=stack.name=#{Settings.config.name}'")
          filters.append("--filter 'label=application.component=#{application_component}'") if application_component
          filters.append("--filter 'label=platform.feature_set=#{Ros::Generators::Stack.current_feature_set}'")
          filters.append("--format '{{.Names}}'")
          cmd = "docker ps #{filters.join(' ')}"
          ar = %x(#{cmd})
          # TODO: _server is only one profile; fix
          # TODO: _1 is assumed; there could be > 1
          ar.split("\n").map{ |a| a.gsub("#{Ros::Generators::Stack.compose_project_name}_", '').chomp('_1') }
        end

        def database_check(name, config)
          prefix = config.ros ? 'app:' : ''
          migration_file = "#{Ros::Generators::Stack.compose_dir}/#{name}-migrated"
          return true if File.exists?(migration_file) unless options.seed
          FileUtils.rm(migration_file) if File.exists?(migration_file)
          success = compose("run --rm #{name} rails #{prefix}ros:db:reset:seed")
          FileUtils.touch(migration_file) if success
          success
        end

        def compose(cmd); switch!; system_cmd({}, "docker-compose #{cmd}") end

        def switch!
          FileUtils.rm_f('.env')
          FileUtils.ln_s(Ros::Generators::Stack.compose_file, '.env')
        end

        def namespace; @namespace ||= (ENV['ROS_PROFILE'] ? "#{ENV['ROS_PROFILE']}-" : '') + Ros::Generators::Stack.compose_project_name end

def system_cmd(env, cmd)
  options = Config::Options.new
  puts cmd if options.v
  system(env, cmd) unless options.n
end

        # TODO: implement rake method
        # def credentials_show
        #   %x(cat ros/services/iam/tmp/#{Settings.platform.environment.partition_name}/postman/222_222_222-Admin_2.json)
        # end

        # def provision_with_ansible
        #   puts "Deploy '#{config.name_to_s}' of type #{deploy_config.type} in #{Ros.env} environment"
        #   puts "Work dir: #{Ros.ansible_root}"
        #   Dir.chdir(Ros.ansible_root) do
        #     cmd = "ansible-playbook ./#{deploy_config.type}.yml"
        #     puts cmd
        #     # system(cmd)
        #     puts 'TODO: ansible code to invoke compose to spin up images'
        #   end
        # end
        # # TODO: this probably needs a tf var that is set to the name of the file for TF to write code into
        # def after_provision
        #   puts "TODO: After terraform apply, write instance IP to devops/ansible/inventory/#{infra.type}"
        # end
      end
    end
  end
end
