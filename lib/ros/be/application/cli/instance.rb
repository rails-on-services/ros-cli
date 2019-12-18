# frozen_string_literal: true

module Ros
  module Be
    module Application
      class Instance
        include CliBase

        def initialize(options = {})
          @options = options
          @errors = Ros::Errors.new
        end

        def cmd(_services)
          # binding.pry
          # TODO: update service labels so can check for them rather than deploying each time
          STDOUT.puts 'Not implemented on cli/instance' if options.v
        end

        def build(services)
          generate_config if stale_config
          compose("build --parallel #{services.join(' ')}")
          errors.add(:build, 'see terminal output') unless exit_code.zero?
          exec(services.last, 'bash') if options.shell
        end

        def pull(services)
          generate_config if stale_config
          compose("pull #{services.join(' ')}")
          errors.add(:pull, 'see terminal output') unless exit_code.zero?
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
          STDOUT.puts 'NOT regenerating config' if options.v && !stale_config
          compose_options = ''
          compose_options = '-d' if options.daemon || options.console || options.shell || options.attach
          services.each do |service|
            # if the service name is without a profile extension, e.g. 'iam' then load config and check db migration
            # If the database check is ok then bring up the service and trigger a reload of nginx
            if options.build
              compose("build --parallel #{service}")
              if exit_code.positive?
                errors.add(:build, 'see terminal output')
                next
              end
            end
            if ref = svc_config(service)
              config = ref.dig(:config) || Config::Options.new
              next unless config.type&.eql?('basic') || database_check(service, config)
            end
            compose("up #{compose_options} #{service}")
            errors.add(:up, 'see terminal output') if exit_code.positive?
          end
          # reload_nginx(services)
          status
          # TODO: only one of console, shell or attach can be passed
          console(services.last) if options.console
          exec(services.last, 'bash') if options.shell
          attach(services.last) if options.attach
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
          copy_service_file('iam', file, creds_file)
          errors.add(:get_credentials, "file not found: #{file}") if exit_code.positive?
        end

        def copy_service_file(service_name, src, dest)
          capture_cmd("docker-compose ps -q #{service_name}")
          container_id = stdout.chomp
          system_cmd("docker cp #{container_id}:#{src} #{dest}")
        end

        def console(service)
          exec(service, 'rails console')
        end

        def exec(service, command)
          generate_config if stale_config
          build([service]) if command.eql?('bash') && options.build
          run_string = services.include?(service) ? 'exec' : 'run --rm'
          compose("#{run_string} #{service} #{command}", true)
        end

        def logs(service)
          generate_config if stale_config
          compose_options = options.tail ? '-f' : ''
          trap('SIGINT') { throw StandardError } if options.tail
          project_name = Ros::Be::Application::Model.compose_project_name
          system_cmd("docker logs #{compose_options} #{project_name}_#{service}_1", {}, true)
          # compose("logs #{compose_options} #{services.join(' ')}", true)
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
          if options.attach
            attach(services.last)
          elsif options.shell
            exec(services.last, 'bash')
          elsif options.console
            console(services.last)
          else
            status
          end
        end

        def stop(services)
          generate_config if stale_config
          compose("stop #{services.join(' ')}")
          # reload_nginx(services)
        end

        def down(services)
          if services.any?
            compose("stop #{services.join(' ')}")
            compose("rm -f #{services.join(' ')}")
            remove_cache('iam') if services.include?('iam')
          else
            compose(:down)
            remove_cache
          end
        end

        def attach(service)
          project_name = Ros::Be::Application::Model.compose_project_name
          system_cmd("docker attach #{project_name}_#{service}_1 --detach-keys='ctrl-f'", {}, true)
        end

        # Supporting methods
        def reload_nginx(services)
          nginx_reload = false
          services.each do |service|
            next unless Settings.components.be.components.application.components.platform.components.dig(service)

            nginx_reload = true
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
          stdout.split("\n").map { |a| a.gsub("#{application.compose_project_name}_", '').chomp('_1') }
        end

        def database_check(name, config)
          prefix = config.ros ? 'app:' : ''
          migration_file = "#{application.compose_dir}/#{name}-migrated"
          return true unless options.seed || !File.exist?(migration_file)

          FileUtils.rm(migration_file) if File.exist?(migration_file)
          if success = compose("run --rm #{name} rails #{prefix}ros:db:reset:seed")
            FileUtils.touch(migration_file)
            remove_cache('iam') if name.eql?('iam')
          else
            errors.add(:database_check, stderr)
          end
          success
        end

        def compose(cmd, never_capture = false)
          switch!
          hash = {}
          if gem_cache = gem_cache_server
            hash = { 'GEM_SERVER' => "http://#{gem_cache}:9292" }
          end
          system_cmd("docker-compose #{cmd}", hash, never_capture)
        end

        def gem_cache_server
          return unless `docker ps`.index('gem_server')

          host = RbConfig::CONFIG['host_os']
          return `ifconfig vboxnet1`.split[7] if host =~ /darwin/

          `ip -o -4 addr show dev docker0`.split[3].split('/')[0]
        end

        def switch!
          FileUtils.rm_f('.env')
          FileUtils.ln_s(application.compose_file, '.env')
          Dir.chdir("#{Ros.root}/services") do
            FileUtils.rm_f('.env')
            FileUtils.ln_s("../#{application.deploy_path}/platform", '.env')
          end
          unless Ros.is_ros?
            Dir.chdir("#{Ros.root}/ros/services") do
              FileUtils.rm_f('.env')
              FileUtils.ln_s("../../#{application.deploy_path}/platform", '.env')
            end
          end
        end

        def namespace
          @namespace ||= (ENV['ROS_PROFILE'] ? "#{ENV['ROS_PROFILE']}-" : '') +
                         Ros::Generators::Stack.compose_project_name
        end

        def config_files
          Dir[application.compose_file]
        end
      end
    end
  end
end
