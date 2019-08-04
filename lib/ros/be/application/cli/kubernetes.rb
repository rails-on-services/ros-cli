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

        # def up(services)
        #   x_services
        # end

        def up(services)
          @services = services.empty? ? enabled_services : services
          generate_config if stale_config
          if options.force or not system_cmd(kube_env, "kubectl get ns #{namespace}")
            STDOUT.puts 'Forcing namespace create' if options.force
            deploy_namespace
            deploy_services
          else
            STDOUT.puts 'Namespace exists. skipping create. Use -f to force'
          end
          deploy_platform_environment
          deploy_platform
          show_endpoint
        end

        def deploy_namespace
          # create namespace
          system_cmd(kube_env, "kubectl create ns #{namespace}")
          system_cmd(kube_env, "kubectl label namespace #{namespace} istio-injection=enabled --overwrite")

          # deploy helm into namespace
          kubectl("apply -f #{cluster.kubernetes_root}/tiller-rbac")
          system_cmd(kube_env, 'helm init --upgrade --wait --service-account tiller')
        end

        def deploy_services
          env_file = "#{services_root}/services.env"
          sync_secret(env_file) if File.exists?(env_file)
          services.each do |service|
            next unless application.services.components.keys.include?(service.to_sym)
            env_file = "#{services_root}/#{service}.env"
            sync_secret(env_file) if File.exists?(env_file)
            service_file = "#{services_root}/#{service}.yml"
            Dir.chdir(services_root) { skaffold("deploy -f #{service_file}") }
          end
        end

        def deploy_platform_environment
          kube_cmd = "create secret generic #{Stack.registry_secret_name} " \
            "--from-file=.dockerconfigjson=#{Dir.home}/.docker/config.json --type=kubernetes.io/dockerconfigjson"
          kubectl(kube_cmd)
        end

        def deploy_platform
          env_file = "#{platform_root}/platform.env"
          sync_secret(env_file) if File.exists?(env_file)
          services.each do |service|
            next unless platform.components.keys.include?(service.to_sym)
            env_file = "#{platform_root}/#{service}.env"
            sync_secret(env_file) if File.exists?(env_file)
            service_file = "#{platform_root}/#{service}.yml"
            Dir.chdir(platform_root) do
              # skaffold cmds: build, deploy or run (build and deploy)
              base_cmd = options.build ? 'run' : 'deploy'
              # next unless check and gem_version_check
              profiles = options.profile.eql?('all') ? platform.components[service].config.profiles : [options.profile]
              replica_count = (options.replicas || 1).to_s
              profiles.each do |profile|
                skaffold("#{base_cmd} -f #{File.basename(service_file)} -p #{profile}",
                         { 'REPLICA_COUNT' => replica_count })
                kubectl("scale deploy #{service} --replicas=#{replica_count}")
              end
            end
          end
        end

        def ps
          generate_config if stale_config
          kubectl('get pods')
        end

        def console(service)
          generate_config if stale_config
          kubectl("exec -it #{pod(service)} -c #{service} rails console")
        end

        def exec(service, command)
          generate_config if stale_config
          kubectl("exec -it #{pod(service)} -c #{service} #{command}")
        end

        def logs(service)
          generate_config if stale_config
          trap("SIGINT") { throw StandardError } if options.tail
          kubectl("#{command('logs')} #{pod(service)} -c #{service}")
        rescue StandardError
        end

        def running_services; @running_services ||= service_pods.map{ |svc| svc.split('-').first }.uniq end

        # TODO: This isn't working quite as expected
        def restart(services)
          generate_config if stale_config
          stop(services)
          up(services)
          # status
        end

        def stop(services)
          generate_config if stale_config
          services.each do |service|
            kubectl("scale deploy #{service} --replicas=0")
            service_pods(service).each do |pod|
              kubectl("delete pod #{pod}")
            end
          end
        end

        def get_credentials
          FileUtils.mkdir_p("#{runtime_dir}/platform")
          # source_creds_file = "/home/rails/services/app/tmp/#{application.current_feature_set}/credentials.json"
          # kubectl("cp #{pod('iam', { 'app.kubernetes.io/component' => 'bootstrap' })}:#{source_creds_file} #{creds_file}")
          # TODO: the following command isn't working
          # bootstrap_pod = pod('iam', { 'app.kubernetes.io/component' => 'bootstrap' })
          bootstrap_pod = 'iam-bootstrap-wn54f'
          rs = kubectl_x("logs #{bootstrap_pod}")
          index_of_json = rs.index('[{"type":')
          json = rs[index_of_json..-1]
          File.write(creds_file, json)
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

        def pod(service, labels = {})
          # cmd = "get pod -l app=#{service} -l app.kubernetes.io/instance=#{service} #{labels.map{ |k, v| "-l #{k}=#{v}" }.join(' ')}"
          cmd = "get pod #{labels.map{ |k, v| "-l #{k}=#{v}" }.join(' ')}"
          result = kubectl_x(cmd)
          # result = kubectl_x("get pod -l app=#{service} -l app.kubernetes.io/instance=#{service}")
          result.split("\n").each do |res|
            pod, count, status, restarts, age = res.split
            break pod if status.eql?('Running')
          end
        end

        def service_pods(service = nil, application_component = nil) # (status: nil, application_component: nil)
          status ||= 'running'
          # TODO: these filters are more or less identical with instance so refactor to cli_base
          filters = []
          filters.append("-l stack.name=#{Settings.config.name}")
          filters.append("-l application.component=#{application_component}") if application_component
          filters.append("-l platform.feature_set=#{application.current_feature_set}")
          filters.append("-l app.kubernetes.io/instance=#{service}") if service
          cmd = "get pods #{filters.join(' ')} -o yaml"
          svpr(cmd)
        end

        def svpr(cmd)
          result = kubectl_x(cmd)
          # puts cmd
          # puts result
          # binding.pry
          # TODO: Does this effectively handle > 1 pod running
          YAML.load(result)['items'].map{ |i| i['metadata']['name'] }
        end

        # Supporting methods (2)
        def kubectl(cmd)
          if not File.exists?(kubeconfig)
            STDOUT.puts "kubeconfig not found at #{kubeconfig}"
            return
          end
          STDOUT.puts "Using kubeconfig file: #{kubeconfig}" if options.v
          system_cmd(kube_env, "kubectl -n #{namespace} #{cmd}")
        end

        def kubectl_x(cmd)
          STDOUT.puts cmd if options.v
          %x(kubectl -n #{namespace} #{cmd})
        end

        def skaffold(cmd, env = {})
          system_cmd(skaffold_env.merge(env), "skaffold -n #{namespace} #{cmd}")
          puts "with environment: #{env}" if options.v
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
          # TODO: base64 decode values then do an md5 on the contents
          # yaml = kubectl("get secret #{name} -o yaml")
          kubectl("delete secret #{name}") if kubectl("get secret #{name}")
          kubectl("create secret generic #{name} --from-env-file #{file}")
        end

        def check; File.file?(kubeconfig) end

        def platform_root; "#{Ros::Be::Application::Model.deploy_path}/platform" end
        def services_root; "#{Ros::Be::Application::Model.deploy_path}/services" end

        def config_files
          Dir["#{Ros::Be::Application::Model.deploy_path}/**"]
        end
      end
    end
  end
end
