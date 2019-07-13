# frozen_string_literal: true
require 'ros/deployment'
require 'ros/ops/infra'
require 'ros/ops/core'
require 'ros/ops/platform'

module Ros
  module Ops
    module Instance
      class Infra < Deployment
        include Ros::Ops::Infra
        include Ros::Ops::Instance

        # TODO: Here would be the array of host/port maps; test it
        def host_port_map
          Dir[Ros.deployments_dir].each_with_object([]) do |file, ary|
            name = File.basename(file).gsub('.yml', '')
            Ros.load_env(name)
            infra_type = Settings.meta.components.provider.split('/').last
            if infra_type.eql? 'instance'
              ary.append({ host: Settings.infra.endpoint.host, port: Settings.platform.nginx_host_port })
            end
          end
        end

        # TODO: Write out the host_port_map into tf_vars
        def tf_vars_aws
          {
            aws_region: provider.config.region,
            route53_zone_main_name: infra.config.dns&.domain,
            route53_zone_this_name: infra.config.dns&.subdomain,
            ec2_instance_type: provider.config.instance.type,
            ec2_key_pair: provider.config.instance.key_pair,
            ec2_tags: provider.config.instance.tags,
            ec2_ami_distro: provider.config.instance.ami_distro
            # lambda_filename: infra.lambda_filename
          }
        end

        # TODO: this probably needs a tf var that is set to the name of the file for TF to write code into
        def after_provision
          puts "TODO: After terraform apply, write instance IP to devops/ansible/inventory/#{infra.type}"
        end
      end

      class Core < Deployment
        include Ros::Ops::Core
        include Ros::Ops::Instance

        def template_vars(name, profile_name)
          {
            name: name,
            service_names: platform.services.reject{|s| s.last.enabled.eql? false }.map{|s| s.first},
            basic_service_names: core.services.reject{|s| s.last&.enabled.eql? false }.map{|s| s.first},
            relative_path_from_root: relative_path_from_root
          }
        end

        # TODO: this should probably be platform agnostic code rather than instance
        # def write_sftp
        #   content_dir = "#{core_root}/sftp"
        #   FileUtils.mkdir_p("#{content_dir}/host-config/authorized-keys")
        #   Dir.chdir("#{content_dir}/host-config") do
        #     %x(ssh-keygen -P '' -t ed25519 -f ssh_host_ed25519_key < /dev/null)
        #     %x(ssh-keygen -P '' -t rsa -b 4096 -f ssh_host_rsa_key < /dev/null)
        #   end
        #   Dir.chdir(content_dir) { FileUtils.touch('users.conf') }
        # end

        # def apply; puts "provision: Nothing to do" end
        def apply
          write_compose_envs
          compose_options = options.daemon ? '-d' : ''
          compose("up #{compose_options}")
        end

        def rollback; puts "rollback: Nothing to do" end
      end

      class Platform < Deployment
        include Ros::Ops::Platform
        include Ros::Ops::Instance

        def template_vars(name, profile_name)
          image_type = platform.services.dig(name, :type) || 'rails'
          image = platform.config.images[image_type]
          has_envs = !platform.services.dig(name, :environment).nil?
          use_ros_context_dir = (not Ros.is_ros? and platform.services.dig(name, :ros))
          mount_ros = (not Ros.is_ros? and not platform.services.dig(name, :ros))
          {
            context_dir: use_ros_context_dir ? 'ROS_CONTEXT_DIR' : 'CONTEXT_DIR',
            has_envs: has_envs,
            image: image,
            mount: platform.services.dig(name, :mount),
            mount_ros: mount_ros,
            name: name,
            relative_path: relative_path,
            storage_name: "storage#{base_hostname.gsub('.', '-')}"
          }
        end

        def after_setup
          write_compose_envs
        end

        # TODO: stop and rm are passed directly to compose and exits
        # TODO: should be possible to run defaults on port 3000 and another version on 3001
        # by changing the project name in config/app
        def apply
          # binding.pry
          # return unless gem_version_check
          # TODO: make build its own rake task and method
          if options.build
            platform.services.each_pair do |name, config|
              next if config&.enabled.eql? false
              compose("build #{name}")
            end
            return
          end
          # if options.initialize
            # compose("up wait")
            platform.services.each do |name, config|
              next if config&.enabled.eql? false
              prefix = config.ros ? 'app:' : ''
              migration_file = "#{compose_dir}/#{current_feature_set}-#{name}-migrated"
              unless File.exists?(migration_file)
                compose("run --rm #{name} rails #{prefix}ros:db:reset:seed")
                FileUtils.touch(migration_file)
              end
            end
          # end
          compose_options = options.daemon ? '-d' : ''
          compose("up #{compose_options}")
          # if options.initialize
          #   %x(cat ros/services/iam/tmp/#{Settings.platform.environment.partition_name}/postman/222_222_222-Admin_2.json)
          # end
        end

        # Common commands for compose/kubectl
        def psxj; compose(:ps) end
        def ps
          puts services
          st = services
          # puts st
          binding.pry
          nil
        end

        def services(status: nil, tier: nil)
          status ||= 'running'
          filters = []
          filters.append("--filter 'status=#{status}'")
          filters.append("--filter 'label=stack.name=#{core.config.name}'")
          filters.append("--filter 'label=service.tier=#{tier}'") if tier
          filters.append("--filter 'label=platform.feature_set=#{current_feature_set}'")
          filters.append("--format '{{.Names}}'")
          cmd = "docker ps #{filters.join(' ')}"
          ar = %x(#{cmd})
          ar.split("\n").map{|a| a.gsub("#{current_feature_set}_", '').chomp("_1") }
        end

        # def xrunning_services
        #   @running_services ||= compose_x('ps --filter "status=running" --services').split("\n")
        #   # @running_services ||= (
        #   #   raw = compose_x(:ps)
        #   #   raw.split("\n").each_with_object([]) do |a, o|
        #   #     o.append(a.split()[0].split('_')[1].to_sym) unless a.start_with?(' ') or a.start_with?('-')
        #   #   end.uniq
        #   # )
        # end

        def console(service)
          exec(service, 'rails console')
        end

        def exec(service, command)
          run_string = %x(docker-compose ps #{service} | grep #{service}).length.positive? ? 'exec' : 'run --rm'
          system("docker-compose #{run_string} #{service} #{command}")
        end

        def logs(service)
          compose_options = options.tail ? '-f' : ''
          compose("logs #{compose_options} #{service}")
        end

        # Compose specific commands
        def build(services)
          compose_services(:build, services)
        end

        def up(services)
          services = (services.nil? ? Ros.service_names_enabled.append('nginx') : [services]).join(' ')
          compose_services(:up, services)
          write_nginx(platform_services(:running))
          reload_nginx
        end

        # def down; compose(:down) end
        def down(services)
          services = (services.nil? ? Ros.service_names_enabled.append('nginx') : [services]).join(' ')
          compose_services(:stop, services)
          write_nginx(platform_services(:running))
          reload_nginx
        end

        def reload(services)
          compose_services(:stop, services)
          compose_services('up -d', services)
          sleep 3
          reload_nginx
        end

        def reload_nginx
          %x(docker container exec #{namespace}_nginx_1 nginx -s reload)
        end

        def compose_services(command, services = nil)
          switch!
          services = (services.nil? ? Ros.service_names_enabled : [services]).join(' ')
          # TODO: needs to get the correct name of the worker, etc
          # Settings.services.each_with_object([]) do |service, ary|
          #   ary.concat service.profiles
          # end
          compose_options = options.daemon ? '-d' : ''
          cmd_string = "docker-compose #{command} #{compose_options} #{services}"
          puts "Running #{cmd_string}"
          system(cmd_string)
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

        def rollback; compose(:down) end
      end

        def write_nginx(keys = platform.services.reject{|s| s.last.enabled.eql? false }.map{|s| s.first})
          content = File.read("#{template_services_root}/nginx/nginx.conf.erb")
          # keys = platform.services.reject{|s| s.last.enabled.eql? false }.map{|s| s.first}
          content = ERB.new(content).result_with_hash({ service_names: keys })
          binding.pry
          content_dir = "#{core_root}/nginx"
          FileUtils.mkdir_p(content_dir)
          File.write("#{content_dir}/nginx.conf", content)
        end
      def core_root; "#{deploy_root}/core" end

        def compose(cmd); switch!; system_cmd(compose_env, "docker-compose #{cmd}") end
        def compose_x(cmd); switch!; %x(docker-compose #{cmd}) end

        def compose_env; @compose_env ||= {} end

        def write_compose_envs
          content = compose_environment.each_with_object([]) do |kv, ary|
            ary << "#{kv[0].upcase}=#{kv[1]}"
          end.join("\n")
          content = "# This file was auto generated\n# The values are used by docker-compose\n# #{Ros.env}\n#{content}"
          FileUtils.mkdir_p(compose_dir)
          File.write(compose_file, "#{content}\n")
        end

        def compose_environment
          {
            compose_file: Dir["#{deploy_root}/**/*.yml"].map{ |p| p.gsub("#{Ros.root}/", '') }.sort.join(':'),
            compose_project_name: current_feature_set, # "#{current_feature_set}-#{core.config.name}", # namespace,
            context_dir: "#{relative_path}/..",
            ros_context_dir: "#{relative_path}/../ros",
            image_repository: platform.config.image_registry,
            image_tag: image_tag
          }.merge(infra.environment.to_h)
        end

      def switch!
        FileUtils.rm_f('.env')
        FileUtils.ln_s(compose_file, '.env')
      end

      def compose_file; @compose_file ||= "#{compose_dir}/#{current_feature_set}.env" end
      def compose_dir; "#{Ros.root}/tmp/compose/#{Ros.env}" end

      def template_prefix; 'compose' end

      def deploy_path; "#{Ros.env}/#{current_feature_set}" end

      def namespace; @namespace ||= (ENV['ROS_PROFILE'] ? "#{ENV['ROS_PROFILE']}-" : '') + current_feature_set end
    end
  end
end
