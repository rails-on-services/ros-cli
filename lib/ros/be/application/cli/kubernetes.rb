# frozen_string_literal: true

module Ros
  module Be
    module Application
      class Kubernetes
        include Ros::Be::Application::CliBase
        attr_accessor :services

        def initialize(options = {})
          @options = options
        end

        def cmd(services)
          binding.pry
        end

        # TODO: Add ability for fail fast
        def up(services)
          succ = []
          @services = services.empty? ? enabled_services : services
          generate_config if stale_config
          if options.force or not system_cmd(kube_env, "kubectl get ns #{namespace}")
            STDOUT.puts 'Forcing namespace create' if options.force
            succ << deploy_namespace
          else
            STDOUT.puts 'Namespace exists. skipping create. Use -f to force'
          end
          succ << deploy_services
          succ << deploy_platform_environment
          succ << deploy_platform
          show_endpoint
          succ.none? false
        end

        def deploy_namespace
          succ = []
          # create namespace
          succ << system_cmd(kube_env, "kubectl create ns #{namespace}")
          succ << system_cmd(kube_env, "kubectl label namespace #{namespace} istio-injection=enabled --overwrite")

          # deploy helm into namespace
          succ << kubectl("apply -f #{cluster.kubernetes_root}/tiller-rbac")
          succ << system_cmd(kube_env, 'helm init --upgrade --wait --service-account tiller')
          succ.none? false
        end

        def deploy_services
          env_file = "#{services_root}/services.env"
          sync_secret(env_file) if File.exist?(env_file)
          succ = application.services.components.keys.map do |service|
            if service.eql?(:ingress)
              next true unless get_vs(name: :ingress).empty?
            else
              next true if pod(name: service)
            end
            env_file = "#{services_root}/#{service}.env"
            sync_secret(env_file) if File.exist?(env_file)
            service_file = "#{service}.yml"
            Dir.chdir(services_root) do
              base_cmd = options.build ? 'run' : 'deploy'
              skaffold("#{base_cmd} -f #{service_file}")
            end
          end
          succ.none? false
        end

        def deploy_platform_environment
          return if kubectl("get secret #{Stack.registry_secret_name}") unless options.force
          kube_cmd = "create secret generic #{Stack.registry_secret_name} " \
            "--from-file=.dockerconfigjson=#{Dir.home}/.docker/config.json --type=kubernetes.io/dockerconfigjson"
          kubectl(kube_cmd)
        end

        def deploy_platform
          update_platform_env
          succ = services.map do |service|
            next true unless platform.components.keys.include?(service.to_sym)

            env_file = "#{platform_root}/#{service}.env"
            sync_secret(env_file) if File.exist?(env_file)
            service_file = "#{platform_root}/#{service}.yml"
            Dir.chdir(platform_root) do
              # skaffold cmds: build, deploy or run (build and deploy)
              base_cmd = options.build ? 'run' : 'deploy'
              # TODO: next unless check and gem_version_check
              profiles = platform.components[service].config.profiles
              profiles = [options.profile] if options.profile and not options.profile.eql?('all')
              replica_count = (options.replicas || 1).to_s
              build_count = 0
              serv_succ = profiles.map do |profile|
                run_cmd = build_count.eql?(0) ? base_cmd : 'deploy'
                skaffold("#{run_cmd} -f #{File.basename(service_file)} -p #{profile}",
                         { 'REPLICA_COUNT' => replica_count })
                succ = kubectl("scale deploy #{service} --replicas=#{replica_count}")
                build_count += 1
                succ
              end
              serv_succ.none? false
            end
          end
          succ.none? false
        end

        def update_platform_env
          env_file = "#{platform_root}/platform.env"
          sync_secret(env_file) if File.exist?(env_file)
        end

        def ps
          generate_config if stale_config
          kubectl('get pods')
        end

        def console(service)
          exec(service, 'rails console')
        end

        def exec(service, command)
          generate_config if stale_config
          kubectl("exec -it #{service_pod(service)} -c #{service} #{command}")
        end

        def service_pod(service); pod(name: service, component: :server) end

        def logs(service)
          generate_config if stale_config
          trap("SIGINT") { throw StandardError } if options.tail
          kubectl("#{command('logs')} #{service_pod(service)} -c #{service}")
        rescue StandardError
        end

        def running_services; @running_services ||= pods(component: :server).map{ |svc| svc.split('-').first }.uniq end

        # TODO: This isn't working quite as expected
        def restart(services)
          generate_config if stale_config
          update_platform_env
          services.each do |service|
            kubectl("rollout restart deploy #{service}")
          end
          # stop(services)
          # up(services)
          # status
        end

        def stop(services)
          generate_config if stale_config
          services.each do |service|
            kubectl("scale deploy #{service} --replicas=0")
            pods(name: service).each do |pod|
              kubectl("delete pod #{pod}")
            end
          end
        end

        def get_credentials
          bootstrap_pod = pod(name: 'iam', component: 'bootstrap')
          rs = kubectl_x("logs #{bootstrap_pod}")
          if index_of_json = rs.index('[{"type":')
            json = rs[index_of_json..-1]
            FileUtils.mkdir_p("#{runtime_dir}/platform")
            File.write(creds_file, json)
          else
            STDOUT.puts 'WARNING: Credentials not found in bootstrap file'
          end
        end

        def down(services)
          if services.empty?
            cmd = "kubectl delete ns #{namespace}"
            system(cmd)
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
            end
          end
        end

        # TODO: fully implement so when down is called that all runtime and docs are revmoed
        # TODO: Iam cached credentials should also be remvoed when IAM service is brought down
        def remove_cache
          FileUtils.rm_rf(runtime_dir)
        end

        # Supporting methods (1)
        # NOTE: only goes with 'logs' for now
        def command(cmd); "#{cmd}#{options.tail ? ' -f' : ''}" end

        def pod(labels = {}); get_pods(labels, true) end
        def pods(labels = {}); get_pods(labels) end

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
          result = kubectl_x(cmd)
          # TODO: Does this effectively handle > 1 pod running
          YAML.safe_load(result)['items'].map { |i| i['metadata']['name'] }
        end

        # Supporting methods (2)
        def kubectl(cmd)
          if not File.exist?(kubeconfig)
            STDOUT.puts "kubeconfig not found at #{kubeconfig}"
            return
          end
          STDOUT.puts "Using kubeconfig file: #{kubeconfig}" if options.v
          system_cmd(kube_env, "kubectl -n #{namespace} #{cmd}")
        end

        def kubectl_x(cmd)
          cmd = "kubectl -n #{namespace} #{cmd}"
          STDOUT.puts cmd if options.v
          %x(#{cmd})
        end

        def skaffold(cmd, env = {})
          res = system_cmd(skaffold_env.merge(env), "skaffold -n #{namespace} #{cmd}")
          puts "with environment: #{env}" if options.v
          res
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
        end

        def local_secrets_content(file)
          File.read(file).split("\n").each_with_object({}) { |a, h| b = a.split('='); h[b[0]] = b[1] || '' }
        end

        def k8s_secrets_content(type = 'platform')
          require 'base64'
          result = kubectl_x("get secret #{type} -o yaml")
          return {} if result.empty?
          yml = YAML.load(result)
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
