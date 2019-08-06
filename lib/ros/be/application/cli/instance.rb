# frozen_string_literal: true

module Ros
  module Be
    module Application
      class Instance
        include CliBase

        def initialize(options = {})
          @options = options
        end

        def build(services)
          generate_config if stale_config
          compose("build #{services.join(' ')}")
        end

        def push(services)
          services = enabled_services if services.empty?
          generate_config if stale_config
          compose("push #{services.join(' ')}")
        end

        def up(services)
          services = enabled_services if services.empty?
          generate_config if stale_config
          STDOUT.puts 'NOT regenerating config' if options.v and not stale_config
          compose_options = ''
          if options.daemon or options.console or options.shell
            compose_options = '-d'
          end
          services.each do |service|
            # if the service name is without a profile extension, e.g. 'iam' then load config and check db migration
            # If the database check is ok then bring up the service and trigger a reload of nginx
            if ref = svc_config(service)
              config = ref.dig(:config) || Config::Options.new
              next unless database_check(service, config)
            end
            compose("build #{service}") if options.build
            service = "#{service} 'tail -f log/development.log'" unless options.process
            compose("up #{compose_options} #{service}")
          end
          reload_nginx(services)
          status
          console(services.last) if options.console
          exec(services.last, 'bash') if options.shell
        end

        def ps
          generate_config if stale_config
          compose(:ps)
        end

        def get_credentials
          file = "#{Ros.is_ros? ? '' : 'ros/'}services/iam/tmp/#{application.current_feature_set}/credentials.json"
          FileUtils.mkdir_p("#{runtime_dir}/platform")
          # TODO: This coule be mv
          # and the tmp file on iam should probably be ROS_ENV (as passed to image vi ENV var) / feature_set
          FileUtils.cp(file, creds_file)
        end

        def console(service)
          exec(service, 'rails console')
        end

        def exec(service, command)
          generate_config if stale_config
          run_string = services.include?(service) ? 'exec' : 'run --rm'
          compose("#{run_string} #{service} #{command}")
        end

        def logs(service)
          generate_config if stale_config
          compose_options = options.tail ? '-f' : ''
          trap("SIGINT") { throw StandardError } if options.tail
          compose("logs #{compose_options} #{service}")
        rescue StandardError
        end

        def running_services; @running_services ||= services end

        def restart(services)
          generate_config if stale_config
          compose("stop #{services.join(' ')}")
          compose("up -d #{services.join(' ')}")
          services.each do |service|
            if ref = Settings.components.be.components.application.components.platform.components.dig(service)
              config = ref.dig(:config) || Config::Options.new
              next unless database_check(service, config)
            end
          end
          reload_nginx(services)
          status
          return unless services.size.eql? 1
          console(services[0]) if options.console
          exec(services[0], 'bash') if options.shell
        end

        def stop(services)
          generate_config if stale_config
          compose("stop #{services.join(' ')}")
          reload_nginx(services)
        end

        def down(services); compose(:down) end

        # Supporting methods
        def reload_nginx(services)
          nginx_reload = false
          services.each do |service|
            nginx_reload = true if Settings.components.be.components.application.components.platform.components.dig(service)
          end
          return unless nginx_reload
          running_services = services(application_component: 'platform')
          silence_output do
            Ros::Be::Application::Services::Generator.new.invoke(:nginx_conf, [running_services])
          end
          compose('stop nginx')
          compose('up -d nginx')
          # NOTE: nginx seems not to notice changes in the mounted file (at least on NFS share) so can't just reload
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
          filters.append("--filter 'label=platform.feature_set=#{application.current_feature_set}'")
          filters.append("--format '{{.Names}}'")
          cmd = "docker ps #{filters.join(' ')}"
          ar = %x(#{cmd})
          # TODO: _server is only one profile; fix
          # TODO: _1 is assumed; there could be > 1
          ar.split("\n").map{ |a| a.gsub("#{application.compose_project_name}_", '').chomp('_1') }
        end

        def database_check(name, config)
          prefix = config.ros ? 'app:' : ''
          migration_file = "#{application.compose_dir}/#{name}-migrated"
          return true if File.exists?(migration_file) unless options.seed
          FileUtils.rm(migration_file) if File.exists?(migration_file)
          if success = compose("run --rm #{name} rails #{prefix}ros:db:reset:seed")
            FileUtils.touch(migration_file)
            if name.eql?('iam')
              publish_env_credentials
              credentials
            end
          end
          success
        end

        def compose(cmd); switch!; system_cmd({}, "docker-compose #{cmd}") end

        def switch!
          FileUtils.rm_f('.env')
          FileUtils.ln_s(application.compose_file, '.env')
        end

        def namespace; @namespace ||= (ENV['ROS_PROFILE'] ? "#{ENV['ROS_PROFILE']}-" : '') + Ros::Generators::Stack.compose_project_name end

        def config_files
          Dir[application.compose_file]
        end
      end
    end
  end
end
