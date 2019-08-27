# frozen_string_literal: true

module Ros
  module Be
    module Application
      class Instance
        include CliBase
        attr_accessor :services

        def initialize(options = {})
          @options = options
          @errors = Ros::Errors.new
        end

        def cmd(services)
          binding.pry
        end

        def build(services)
          generate_config if stale_config
          compose("build #{services.join(' ')}")
          errors.add(:build, 'see terminal output') unless exit_code.zero?
        end

        def push(services)
          services = enabled_services if services.empty?
          generate_config if stale_config
          compose("push #{services.join(' ')}")
          errors.add(:push, 'see terminal output') unless exit_code.zero?
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
            if options.build
              compose("build #{service}")
              if exit_code.positive?
                errors.add(:build, 'see terminal output')
                next
              end
            end
            if ref = svc_config(service)
              config = ref.dig(:config) || Config::Options.new
              binding.pry
              next unless database_check(service, config) unless config.type&.eql?('basic')
            end
            compose("up #{compose_options} #{service}")
            errors.add(:up, 'see terminal output') if exit_code.positive?
          end
          reload_nginx(services)
          status
          console(services.last) if options.console
          exec(services.last, 'bash') if options.shell
        end

        def ps
          generate_config if stale_config
          compose(:ps, true)
        end

        def get_credentials
          file = "/home/rails/services/app/tmp/#{application.current_feature_set}/credentials.json"
          FileUtils.mkdir_p("#{runtime_dir}/platform")
          #
          # TODO: the tmp file on iam should probably be ROS_ENV (as passed to image vi ENV var) / feature_set
          # TODO: when IAM service is brought down the credentials file should be removed
          capture_cmd("docker-compose ps -q iam")
          errors.add(:get_credentials, "file not found: #{file}") if exit_code.positive?
          copy_service_file(stdout.chomp, file, creds_file) if exit_code.zero?
        end

        def copy_service_file(container_id, src, dest)
          system_cmd("docker cp #{container_id}:#{src} #{dest}")
        end

        def console(service)
          exec(service, 'rails console')
        end

        def exec(service, command)
          generate_config if stale_config
          run_string = services.include?(service) ? 'exec' : 'run --rm'
          compose("#{run_string} #{service} #{command}", true)
        end

        def logs(service)
          generate_config if stale_config
          compose_options = options.tail ? '-f' : ''
          trap("SIGINT") { throw StandardError } if options.tail
          compose("logs #{compose_options} #{service}", true)
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

        def down(services)
          compose(:down)
          remove_cache
        end

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
          capture_cmd("docker ps #{filters.join(' ')}")
          return [] if options.n
          # TODO: _server is only one profile; fix
          # TODO: _1 is assumed; there could be > 1
          stdout.split("\n").map{ |a| a.gsub("#{application.compose_project_name}_", '').chomp('_1') }
        end

        def database_check(name, config)
          prefix = config.ros ? 'app:' : ''
          migration_file = "#{application.compose_dir}/#{name}-migrated"
          return true if File.exist?(migration_file) unless options.seed
          FileUtils.rm(migration_file) if File.exist?(migration_file)
          if success = compose("run --rm #{name} rails #{prefix}ros:db:reset:seed")
            FileUtils.touch(migration_file)
            if name.eql?('iam')
              FileUtils.rm(creds_file) if File.exist?(creds_file)
              # publish_env_credentials
              # credentials
            end
          else
            errors.add(:database_check, stderr)
          end
          success
        end

        def compose(cmd, never_capture = false)
          switch!
          system_cmd("docker-compose #{cmd}", {}, never_capture)
        end

        def switch!
          FileUtils.rm_f('.env')
          FileUtils.ln_s(application.compose_file, '.env')
        end

        def namespace
          @namespace ||= (ENV['ROS_PROFILE'] ? "#{ENV['ROS_PROFILE']}-" : '') + Ros::Generators::Stack.compose_project_name
        end

        def config_files
          Dir[application.compose_file]
        end
      end
    end
  end
end
