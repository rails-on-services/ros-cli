# frozen_string_literal: true
require 'ros/generators/stack'

module Ros
  module Ops
    module Kubernetes
      module Base
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

def system_cmd(env, cmd)
  options = Config::Options.new
  puts cmd if options.v
  system(env, cmd) unless options.n
end
      end

      class Services
        include Base
        def invoke
          return unless check
          thing = ARGV[1] || '*'
          # deploy_namespace if thing.eql?('*')
          # deploy_helm if thing.eql?('*')
          # deploy_secrets
          deploy_services
        end

        def deploy_namespace
          system_cmd(kube_env, "kubectl create ns #{namespace}") unless system_cmd(kube_env, "kubectl get ns #{namespace}")
          system_cmd(kube_env, "kubectl label namespace #{namespace} istio-injection=enabled --overwrite")
        end

        def deploy_helm
          kube_ctl("apply -f #{Ros.k8s_root}/tiller-rbac")
          system_cmd(kube_env, 'helm init --upgrade --wait --service-account tiller')
        end

        def deploy_secrets
          thing = ARGV[1] || '*'
          Dir["#{core_root}/#{thing}.env"].each { |file| sync_secret(file) }
        end

require 'ros/generators/be/application'
def core_root; "#{Ros::Generators::Be::Application.deploy_path}/#{Ros::Generators::Stack.current_feature_set}/services" end

        def deploy_services
          thing = ARGV[1] || '*'
          Dir.chdir(core_root) { Dir["#{thing}.yml"].each { |file| skaffold("deploy -f #{file}") } }
        end

        # def rollback; puts "TODO: rollback #{self.class.name}" end
        def rollback
          string = "kubectl delete ns #{namespace}"
          system(string)
        end
      end

      class Platform
        include Base
        # provisions platform services
        # TODO: process service env files, crete sns path on platform’s S3 bucket, etc
        def deploy
          # return unless check and gem_version_check
          deploy_secrets
          deploy_services
        end

        def deploy_secrets
          thing = ARGV[1] || '*'
          Dir["#{platform_root}/#{thing}.env"].each { |file| sync_secret(file) }
          kube_cmd = "create secret generic #{Ros::Generators::Stack.registry_secret_name} " \
            "--from-file=.dockerconfigjson=#{Dir.home}/.docker/config.json --type=kubernetes.io/dockerconfigjson"
          kube_ctl(kube_cmd) if thing.eql?('*')
        end

require 'ros/generators/be/application'
def platform_root; "#{Ros::Generators::Be::Application.deploy_path}/#{Ros::Generators::Stack.current_feature_set}/platform" end

        # def registry_secret_name; "registry-#{platform.config.image_registry}" end

        def deploy_services
          thing = ARGV[1] || '*'
          # binding.pry
          Dir.chdir(platform_root) do
            Dir["#{thing}.yml"].each do |file|
              # skaffold("build -f #{file}")
              # TODO: Can get the profiles by loading the YAML and iterating over the list of profiles
              # since the profiles in the file were generated from the configuration already
              service = file.gsub('.yml', '')
              # run does build and deploy 
              Settings.components.be.components.application.components.platform.components[service].profiles.each { |profile| skaffold("run -f #{file} -p #{profile}") }
              # platform.services[service].profiles.each { |profile| skaffold("deploy -f #{file} -p #{profile}") }
            end
          end
        end

        # TODO Destroy a service using skaffold and remove secrets
        # def rollback; puts "rollback #{self.class.name}" end
      end

      class Cli
        include Base
        def initialize(opitons = {})
        end

        def ps; kube_ctl('get pods') end

        def console(service)
          kube_ctl("exec -it #{pod(service)} -c #{service} rails console")
        end

        def exec(service, command)
          kube_ctl("exec -it #{pod(service)} -c #{service} #{command}")
        end

        def logs(service)
          trap("SIGINT") { throw StandardError } if options.tail
          kube_ctl("#{command('logs')} #{pod(service)} -c #{service}")
        rescue StandardError
        end

        def command(cmd); "#{cmd}#{options.tail ? ' -f' : ''}" end

        # Compose specific commands
        def pod(service)
          result = kube_ctl_x("get pod -l app=#{service} -l app.kubernetes.io/instance=#{service}")
          result.split("\n").each do |res|
            pod, count, status, restarts, age = res.split
            break pod if status.eql?('Running')
          end
        end
      end
    end
  end
end
