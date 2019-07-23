# frozen_string_literal: true

module Ros
  module Ops
    module Kubernetes
      class Cli
        include Ros::Ops::CliCommon

        def init
          Ros::Generators::Be::Cluster.send("init_#{Settings.components.be.config.provider}", self)
        end

        def up(services)
          return unless check
          generate_config if stale_config
          if options.force or not system_cmd(kube_env, "kubectl get ns #{namespace}")
            STDOUT.puts 'Forcing namespace create' if options.force
            deploy_application_namespace
            deploy_application_services
          else
            STDOUT.puts 'Namespace exists. skipping create. Use -f to force'
          end
          services = enabled_services if services.empty?
          show_endpoint
          # binding.pry
          thing = ARGV[1] || '*'
          # binding.pry
        end

        def deploy_application_namespace
          # create namespace
          system_cmd(kube_env, "kubectl create ns #{namespace}")
          system_cmd(kube_env, "kubectl label namespace #{namespace} istio-injection=enabled --overwrite")

          # deploy helm into namespace
          kube_ctl("apply -f #{Ros.k8s_root}/tiller-rbac")
          system_cmd(kube_env, 'helm init --upgrade --wait --service-account tiller')
        end

        def deploy_application_services
          thing = ARGV[1] || '*'
          Dir["#{services_root}/#{thing}.env"].each { |file| sync_secret(file) }
          Dir.chdir(services_root) { Dir["#{thing}.yml"].each { |file| skaffold("deploy -f #{file}") } }
        end

        def deploy_platform_services
          # return unless check and gem_version_check
          # deploy secrets
          thing = ARGV[1] || '*'
          Dir["#{platform_root}/#{thing}.env"].each { |file| sync_secret(file) }
          kube_cmd = "create secret generic #{Ros::Generators::Stack.registry_secret_name} " \
            "--from-file=.dockerconfigjson=#{Dir.home}/.docker/config.json --type=kubernetes.io/dockerconfigjson"
          kube_ctl(kube_cmd) if thing.eql?('*')

          # deploy services
          Dir.chdir(platform_root) do
            Dir["#{thing}.yml"].each do |file|
              # skaffold("build -f #{file}")
              # TODO: Can get the profiles by loading the YAML and iterating over the list of profiles
              # since the profiles in the file were generated from the configuration already
              service = file.gsub('.yml', '')
              # run does build and deploy 
              components[service].profiles.each { |profile| skaffold("run -f #{file} -p #{profile}") }
              # platform.services[service].profiles.each { |profile| skaffold("deploy -f #{file} -p #{profile}") }
            end
          end
        end

        def components; Settings.components.be.components.application.components.platform.components end

        def ps
          generate_config if stale_config
          kube_ctl('get pods')
        end

        def console(service)
          generate_config if stale_config
          kube_ctl("exec -it #{pod(service)} -c #{service} rails console")
        end

        def exec(service, command)
          generate_config if stale_config
          kube_ctl("exec -it #{pod(service)} -c #{service} #{command}")
        end

        def logs(service)
          generate_config if stale_config
          trap("SIGINT") { throw StandardError } if options.tail
          kube_ctl("#{command('logs')} #{pod(service)} -c #{service}")
        rescue StandardError
        end

        def restart(services)
          generate_config if stale_config
        end

        def stop(services)
          generate_config if stale_config
        end

        def down
          string = "kubectl delete ns #{namespace}"
          system(string)
        end

        # Supporting methods (1)
        # NOTE: only goes with 'logs' for now
        def command(cmd); "#{cmd}#{options.tail ? ' -f' : ''}" end

        def pod(service)
          result = kube_ctl_x("get pod -l app=#{service} -l app.kubernetes.io/instance=#{service}")
          result.split("\n").each do |res|
            pod, count, status, restarts, age = res.split
            break pod if status.eql?('Running')
          end
        end

        # Supporting methods (2)
        def kube_ctl(cmd); system_cmd(kube_env, "kubectl -n #{namespace} #{cmd}") end
        def kube_ctl_x(cmd); %x(kubectl -n #{namespace} #{cmd}) end

        def skaffold(cmd); system_cmd(skaffold_env, "skaffold -n #{namespace} #{cmd}") end

        def skaffold_env
          @skaffold_env ||=
            { 'SKAFFOLD_DEFAULT_REPO' => Settings.platform.config.image_registry, 'IMAGE_TAG' => Ros::Generators::Stack.image_tag }.merge(kube_env)
        end

        def kube_env; @kube_env ||= { 'KUBECONFIG' => kubeconfig, 'TILLER_NAMESPACE' => namespace } end

        def kubeconfig; @kubeconfig ||= File.expand_path(Settings.infra.config.kubeconfig || '~/.kube/config') end

        def namespace; @namespace ||= "#{Ros::Generators::Stack.current_feature_set}-#{Settings.config.name}" end

        def switch!; end

        def sync_secret(file)
          name = File.basename(file).chomp('.env')
          # TODO: base64 decode values then do an md5 on the contents
          # yaml = kube_ctl("get secret #{name} -o yaml")
          kube_ctl("delete secret #{name}") if kube_ctl("get secret #{name}")
          kube_ctl("create secret generic #{name} --from-env-file #{file}")
        end

        def check
          puts File.file?(kubeconfig) ? "Using kubeconfig file: #{kubeconfig}" : "Kubeconfig not found at #{kubeconfig}"
          File.file?(kubeconfig)
        end

        def platform_root; "#{Ros::Generators::Be::Application.deploy_path}/platform" end
        def services_root; "#{Ros::Generators::Be::Application.deploy_path}/services" end
      end
    end
  end
end
