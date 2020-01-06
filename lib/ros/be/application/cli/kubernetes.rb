# frozen_string_literal: true

module Ros
  module Be
    module Application
      class Kubernetes
        include CliBase
        attr_accessor :services

        def clean_kubernetes_name(name)
          name.to_s.gsub(/[^a-zA-Z-]/, '-')
        end
        def initialize(options = {})
          @options = options
          @errors = Ros::Errors.new
        end

        def cmd(services)
          binding.pry
        end

        def build(services)
          generate_config if stale_config
          services.each do |service|
            next true unless platform.components.keys.include?(service.to_sym)

            service_file = "#{platform_root}/#{service}.yml"
            Dir.chdir(platform_root) do
              # TODO: next unless check and gem_version_check
              run_cmd = 'build'
              skaffold("#{run_cmd} -f #{File.basename(service_file)}")
              errors.add(:skaffold, stderr) if exit_code.positive?
            end
          end
        end

        def push(services)
          STDOUT.puts("build command already pushed the image, skipping.")
        end

        # TODO: Add ability for fail fast
        def up(services)
          @platform_services = []
          @infra_services = []

          services.each do |service|
            if enabled_services.include?(service.to_sym)
              @platform_services.push(service)
            elsif enabled_application_services.include?(service.to_sym)
              @infra_services.push(service)
            else
              STDERR.puts "Services specified not found or enabled: #{service}, exit"
              return
            end
          end

          # No services specified - launch whole app stack
          if @platform_services.empty? && @infra_services.empty? && !options.only_infra
            STDOUT.puts "No specific service specified, deploy all enabled services"
            @platform_services = enabled_services
            @infra_services = enabled_application_services
          # Launch all infra services and jobs. Useful for new environments to make sure infra is up and running before deploy any services
          elsif @platform_services.empty? && @infra_services.empty? && options.only_infra
            STDOUT.puts "Deploying infra services only"
            @infra_services = enabled_application_services
          # app service(s) specified - launch app and ensure required infra services are up and running
          elsif !@platform_services.empty? && @infra_services.empty?
            @infra_services = enabled_application_services
          # infra service(s) specified - force update
          elsif @platform_services.empty? && !@infra_services.empty?
            @force_infra_deploy = true
          end
          generate_config if stale_config
          if options.force or not system_cmd("kubectl get ns #{namespace}", kube_env)
            STDOUT.puts 'Forcing namespace create' if options.force
            deploy_namespace
          else
            STDOUT.puts 'Namespace exists. skipping create. Use -f to force'
          end
          return if options.skip
          update_helm_repo
          deploy_services unless options.skip_infra
          deploy_infra_migration_jobs unless options.skip_infra
          deploy_platform_environment
          deploy_platform
          show_endpoint
        end

        def deploy_namespace
          # create namespace
          system_cmd("kubectl create ns #{namespace}", kube_env)
          errors.add(:kubectl_create_namespace, stderr) if exit_code.positive?
          system_cmd("kubectl label namespace #{namespace} istio-injection=enabled --overwrite", kube_env)
          errors.add(:kubectl_label_namespace, stderr) if exit_code.positive? and stderr.index('AlreadyExists').nil?

          # deploy helm into namespace
          kubectl("apply -f #{application.deploy_path}/services/kubernetes/tiller-rbac")
          errors.add(:deploy_tiller, stderr) if exit_code.positive?
          system_cmd('helm init --upgrade --wait --service-account tiller', kube_env)
          errors.add(:initialize_helm, stderr) if exit_code.positive?
        end

        def deploy_services
          env_file = "#{services_root}/services.env"
          sync_secret(env_file) if File.exists?(env_file)
          @infra_services.each do |service|
            if service.to_s.eql?('kafka-connect')
              deploy_gcp_bigquery_secret unless application.components.services.components[:'kafka-connect']&.config&.gcp_service_account_key.nil?
            end
            if service.to_s.eql?('ingress')
              next true unless options.n || get_vs(name: :ingress).empty? || options.force
            else
              next if pod(name: service) unless @force_infra_deploy
            end
            env_file = "#{services_root}/#{service}.env"
            sync_secret(env_file) if File.exist?(env_file)
            service_file = "#{service}.yml"
            Dir.chdir(services_root) do
              base_cmd = options.build ? 'run' : 'deploy'
              force = @force_infra_deploy ? '--force=true' : ''
              skaffold("#{base_cmd} #{force} -f #{service_file}")
              errors.add("skaffold_#{base_cmd}", stderr) if exit_code.positive?
            end
          end
        end

        def deploy_infra_migration_jobs
          enabled_application_services.each do |service|
            if File.directory?("#{services_root}/jobs/#{service}")
              Dir.glob("#{services_root}/jobs/#{service}/*.yml") do |job_file|
                job_name = YAML.load_file(job_file)['metadata']['name']
                kubectl("delete job #{job_name}") if kubectl("get job #{job_name}")
                kube_cmd = "apply -f #{job_file} --force"
                kubectl(kube_cmd)
              end
            end
          end
        end

        def deploy_gcp_bigquery_secret
          if kubectl("get secret gcp-jsonkey")
            return unless options.force
            kubectl("delete secret gcp-jsonkey")
          end
          secret = application.components.services.components[:'kafka-connect']&.config&.gcp_service_account_key
          kube_cmd = "create secret generic gcp-jsonkey --from-literal=application_default_credentials.json='#{secret}'"
          kubectl(kube_cmd)
        end

        def deploy_platform_environment
          return if kubectl("get secret #{Stack.registry_secret_name}") unless options.force
          kube_cmd = "create secret docker-registry #{Stack.registry_secret_name} " \
            "--docker-server=#{Stack.config.platform.config.docker_server} " \
            "--docker-username=#{Stack.config.platform.config.docker_username} " \
            "--docker-password=#{Stack.config.platform.config.docker_password} " \
            "--docker-email=#{Stack.config.platform.config.docker_email}"
          kubectl(kube_cmd)
        end

        def deploy_platform
          update_platform_env unless options.skip_infra
          @platform_services.each do |service|
            #next unless platform.components.keys.include?(service.to_sym)
            env_file = "#{platform_root}/#{service}.env"
            sync_secret(env_file) if File.exist?(env_file)
            service_file = "#{platform_root}/#{service}.yml"
            Dir.chdir(platform_root) do
              if options.build
                skaffold("build -f #{File.basename(service_file)}")
                errors.add("skaffold_build", stderr) if exit_code.positive?
              end
              # TODO: next unless check and gem_version_check
              profiles = [options.profile] if options.profile
              profiles ||= platform.components[service].dig(:config, :profiles) || [:none]
              replica_count = (options.replicas || 1).to_s
              profiles.each do |profile|
                profile_cmd = " -p #{profile}" unless profile.eql?(:none)
                skaffold("deploy -f #{File.basename(service_file)}#{profile_cmd}",
                         { 'REPLICA_COUNT' => replica_count })
                errors.add("skaffold_deploy", stderr) if exit_code.positive?
              end
            end
          end
        end

        def update_platform_env
          env_file = "#{platform_root}/platform.env"
          sync_secret(env_file) if File.exist?(env_file)
        end

        def update_helm_repo
          system_cmd("helm repo add ros https://rails-on-services.github.io/helm-charts")
          system_cmd("helm repo update")
        end

        def ps
          generate_config if stale_config
          kubectl('get pods', true)
        end

        def console(service)
          exec(service, 'rails console')
        end

        def exec(service, command)
          generate_config if stale_config
          kubectl("exec -it #{service_pod(service)} -c #{service} #{command}", true)
        end

        def service_pod(service); pod(name: service, component: :server) end

        def logs(service)
          generate_config if stale_config
          trap("SIGINT") { throw StandardError } if options.tail
          k8s_selector = {name: service, component: :server}.map{ |k, v| "app.kubernetes.io/#{k}=#{v}"}.join(',')
          kubectl("#{command('logs')} -l #{k8s_selector} -c #{clean_kubernetes_name(service)}", true)
        rescue StandardError
        end

        def running_services; @running_services ||= pods(component: :server).map{ |svc| svc.split('-').first }.uniq end

        # TODO: This isn't working quite as expected
        # NOTE: restart should not remove a service, just restart it
        # This is the same behavior as with compose (at least it should be)
        def restart(services)
          generate_config if stale_config
          update_platform_env
          services.each do |service|
            kubectl("rollout restart deploy #{clean_kubernetes_name(service)}")
          end
          # down(services)
          # up(services)
          # status
        end

        def stop(services)
          STDOUT.puts "WARN: Stop command (kubectl scale deploy --replicas=0) would have no effect as pods scale managed by HPA"
          # generate_config if stale_config
          # services.each do |service|
            # kubectl("scale deploy #{clean_kubernetes_name(service)} --replicas=0")
            # pods(name: service).each do |pod|
              # kubectl("delete pod #{pod}")
            # end
          # end
        end

        def get_credentials
          bootstrap_pod = pod(name: 'iam', component: 'bootstrap')
          kubectl_capture("logs #{bootstrap_pod}")
          if index_of_json = stdout.index('[{"type":')
            json = stdout[index_of_json..-1]
            FileUtils.mkdir_p("#{runtime_dir}/platform")
            File.write(creds_file, json)
          else
            STDOUT.puts "NOTICE: Credentials not found in bootstrap pod's file system"
          end
        end

        def copy_service_file(service, src, dest)
          pod = pod(name: service, component: 'server')
          kubectl("cp #{pod}:#{src} #{dest}")
        end

        def copy(service, src, dest = nil)
          dest ||= src
          pod = pod(name: service, component: 'server')
          kubectl("cp #{src} #{pod}:#{dest}")
        end

        def down(services)
          if services.empty?
            # TODO: Are you sure?
            cmd = "kubectl delete ns #{namespace}"
            system_cmd(cmd)
            remove_cache
          else
            base_cmd = 'delete'
            services.each do |service|
              next unless platform.components.keys.include?(service.to_sym)
              # kubectl("delete secret #{service}") if kubectl("get secret #{service}")
              service_file = "#{platform_root}/#{service}.yml"
              profiles = (options.profile.nil? or options.profile.eql?('all')) ? platform.components[service].config.profiles : [options.profile]
              # binding.pry
              Dir.chdir(platform_root) do
                profiles.each do |profile|
                  skaffold("#{base_cmd} -f #{File.basename(service_file)} -p #{profile}")
                end
              end
              remove_cache if service.eql?('iam')
            end
          end
        end

        def attach(service)
          kubectl("attach -it #{service_pod(service)} -c #{service}", true)
        end

        # Supporting methods (1)
        # NOTE: only goes with 'logs' for now
        def command(cmd); "#{cmd}#{options.tail ? ' -f' : ''}" end

        def pod(labels = {}); get_pods(labels, true) unless options.n end
        def pods(labels = {}); get_pods(labels) unless options.n end

        def get_pods(labels = {}, return_one = false)
          # cmd = "get pod -l app=#{service} -l app.kubernetes.io/instance=#{service} #{labels.map{ |k, v| "-l #{k}=#{v}" }.join(' ')} -o yaml"
          # cmd = "get pod #{labels.map{ |k, v| "-l app.kubernetes.io/#{k}=#{v}" }.join(' ')} -o yaml"
          cmd = "get pod -l #{labels.map{ |k, v| "app.kubernetes.io/#{k}=#{v}" }.join(',')} -o yaml"
          result = svpr(cmd)
          return result.first if return_one
          result
        end

        # TODO: DRY up with get_pods above
        def get_vs(labels = {}, return_one = false)
          cmd = "get virtualservice -l #{labels.map{ |k, v| "app.kubernetes.io/#{k}=#{v}" }.join(',')} -o yaml"
          result = svpr(cmd)
          return result.first if return_one
          result
        end

        def svpr(cmd)
          kubectl_capture(cmd)
          if exit_code.positive?
            STDOUT.puts(stderr)
            Kernel.exit(1)
          end
          # TODO: Does this effectively handle > 1 pod running
          YAML.safe_load(stdout)['items'].map { |i| i['metadata']['name'] } unless options.n
        end

        # Supporting methods (2)
        def kubectl(cmd, never_capture = false)
          raise StandardError.new("kubeconfig not found at #{kubeconfig}") unless File.exist?(kubeconfig)
          system_cmd("kubectl -n #{namespace} #{cmd}", kube_env, never_capture)
        end

        def kubectl_capture(cmd)
          raise StandardError.new("kubeconfig not found at #{kubeconfig}") unless File.exist?(kubeconfig)
          capture_cmd("kubectl -n #{namespace} #{cmd}")
        end

        def skaffold(cmd, envs = {})
          puts "run skaffold with environment: #{skaffold_env.merge(envs)}" if options.v
          system_cmd("skaffold -n #{namespace} #{cmd}", skaffold_env.merge(envs))
        end

        def skaffold_env
          @skaffold_env ||= {
            'SKAFFOLD_DEFAULT_REPO' => Stack.config.platform.config.image_registry,
            'IMAGE_TAG' => Stack.image_tag
          }.merge(kube_env)
        end

        def kube_env; @kube_env ||= { 'KUBECONFIG' => kubeconfig, 'TILLER_NAMESPACE' => namespace } end

        def kubeconfig; @kubeconfig ||= "#{Dir.home}/.kube/config" end

        def namespace; @namespace ||= "#{application.current_feature_set}-#{Stack.config.name}" end

        def switch!; end

        def sync_secret(file)
          name = File.basename(file).chomp('.env')
          return if local_secrets_content(file) == k8s_secrets_content(name)
          STDOUT.puts "NOTICE: Updating cluster with new contents for secret #{name}"
          kubectl("delete secret #{name}") # if kubectl("get secret #{name}")
          kubectl("create secret generic #{name} --from-env-file #{file}")
          errors.add(:create_secret, stderr) if exit_code.positive?
        end

        def local_secrets_content(file)
          File.read(file).split("\n").each_with_object({}) { |a, h| b = a.split('='); h[b[0]] = b[1] || '' }
        end

        def k8s_secrets_content(type = 'platform')
          require 'base64'
          kubectl_capture("get secret #{type} -o yaml")
          return {} if exit_code.positive? || options.n
          yml = YAML.load(stdout)
          yml['data'].each_with_object({}) { |a, h| h[a[0]] = Base64.decode64(a[1]) }
        end

        def check; File.file?(kubeconfig) end

        def platform_root; "#{Ros::Be::Application::Model.deploy_path}/platform" end
        def services_root; "#{Ros::Be::Application::Model.deploy_path}/services" end

        def config_files
          Dir["#{Ros::Be::Application::Model.deploy_path}/**/*"]
        end
      end
    end
  end
end
