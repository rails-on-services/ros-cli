# frozen_string_literal: true
require 'ros/deployment'
require 'ros/ops/infra'
require 'ros/ops/core'
require 'ros/ops/platform'

module Ros
  module Ops
    module Kubernetes
      class Infra < Deployment
        include Ros::Ops::Kubernetes
        include Ros::Ops::Infra

        def tf_vars_aws
          {
            aws_region: provider.config.region,
            route53_zone_main_name: infra.config.dns.domain,
            route53_zone_this_name: infra.config.dns.subdomain,
            # name: infra.name
          }
        end
      end

      # provision a platform into the infrastructure, including:
      # env to secrets, support services (pg, redis, localstack, etc) and S3 bucket
      # TODO: add fluentd and grafana skaffolds
      # TODO: implement rollback of support services
      class Core < Deployment
        include Ros::Ops::Kubernetes
        include Ros::Ops::Core

        def initialize(options)
          super(options)
          infra.config.namespace ||= 'default'
          infra.config.branch_deployments ||= false
          infra.config.api_branch ||= 'master'
        end

        def template_vars(name, profile_name)
          {
            chart_path: "#{relative_path}/devops/helm/charts/#{name}",
            pull_policy: 'Always',
            api_hostname: api_hostname,
            sftp_hostname: sftp_hostname,
            storage_name: "storage#{base_hostname.gsub('.', '-')}",
            storage_region: provider.region,
            service_names: platform.services.keys,
            secrets_files: core.services.dig(name, :environment) ? [:core, name.to_sym] : %i(core)
            # secrets_files: File.exists?("#{core_root}/#{name}.env") ? [:core, name.to_sym] : %i(core)
          }
        end

def relative_path
  @x_relative_path ||= "../#{super}"
end

        def fluentd_header
          "configMaps:\n  rails-audit-log.conf: |"
        end

        def apply
          return unless apply_check
          thing = ARGV[1] || '*'
          apply_namespace unless thing.eql?('*')
          apply_helm unless thing.eql?('*')
          apply_secrets
          apply_services
        end

        def apply_namespace
          system_cmd(kube_env, "kubectl create ns #{namespace}") unless system_cmd(kube_env, "kubectl get ns #{namespace}")
          system_cmd(kube_env, "kubectl label namespace #{namespace} istio-injection=enabled --overwrite")
        end

        def apply_helm
          kube_ctl("apply -f #{Ros.k8s_root}/tiller-rbac")
          system_cmd(kube_env, 'helm init --upgrade --wait --service-account tiller')
        end

        def apply_secrets
          thing = ARGV[1] || '*'
          Dir["#{core_root}/#{thing}.env"].each { |file| sync_secret(file) }
        end

        def apply_services
          thing = ARGV[1] || '*'
          Dir.chdir(core_root) { Dir["#{thing}.yml"].each { |file| skaffold("deploy -f #{file}") } }
        end

        # def rollback; puts "TODO: rollback #{self.class.name}" end
        def rollback
          string = "kubectl delete ns #{namespace}"
          system(string)
        end
      end

      class Platform < Deployment
        include Ros::Ops::Platform
        include Ros::Ops::Kubernetes

        def initialize(options)
          super(options)
          infra.config.namespace ||= 'default'
          infra.config.branch_deployments ||= false
          infra.config.api_branch ||= 'master'
        end

        def template_vars(name, profile_name)
          image_type = platform.services.dig(name, :type) || 'rails'
          image = platform.config.images[image_type]
          {
            name: name,
            context_path: "#{relative_path}#{platform.services.dig(name, :ros) ? '/ros' : ''}",
            dockerfile_path: "#{relative_path}/#{platform.services.dig(name, :ros) ? 'ros/' : ''}Dockerfile",
            image: image,
            chart_path: "#{relative_path}/devops/helm/charts/service",
            api_hostname: api_hostname,
            is_ros_service: platform.services.dig(name, :ros),
            pull_policy: 'Always',
            pull_secret: registry_secret_name,
            secrets_files: platform.services.dig(name, :environment) ? [:platform, name.to_sym] : %i(platform)
          }
        end

def relative_path
  @x_relative_path ||= "../#{super}"
end

        # provisions platform services
        # TODO: process service env files, crete sns path on platform’s S3 bucket, etc
        def apply 
          # return unless apply_check and gem_version_check
          apply_secrets
          apply_services
        end

        def apply_secrets
          thing = ARGV[1] || '*'
          Dir["#{platform_root}/#{thing}.env"].each { |file| sync_secret(file) }
          kube_cmd = "create secret generic #{registry_secret_name} " \
            "--from-file=.dockerconfigjson=#{Dir.home}/.docker/config.json --type=kubernetes.io/dockerconfigjson"
          kube_ctl(kube_cmd) if thing.eql?('*')
        end

        def registry_secret_name; "registry-#{platform.config.image_registry}" end

        def apply_services
          thing = ARGV[1] || '*'
          # binding.pry
          Dir.chdir(platform_root) do
            Dir["#{thing}.yml"].each do |file|
              # skaffold("build -f #{file}")
              # TODO: Can get the profiles by loading the YAML and iterating over the list of profiles
              # since the profiles in the file were generated from the configuration already
              service = file.gsub('.yml', '')
              # run does build and deploy 
              platform.services[service].profiles.each { |profile| skaffold("run -f #{file} -p #{profile}") }
              # platform.services[service].profiles.each { |profile| skaffold("deploy -f #{file} -p #{profile}") }
            end
          end
        end

        # TODO Destroy a service using skaffold and remove secrets
        def rollback; puts "rollback #{self.class.name}" end

        # Common commands for compose/kubectl
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

      def sync_secret(file)
        name = File.basename(file).chomp('.env')
        # TODO: base64 decode values then do an md5 on the contents
        # yaml = kube_ctl("get secret #{name} -o yaml")
        kube_ctl("delete secret #{name}") if kube_ctl("get secret #{name}")
        kube_ctl("create secret generic #{name} --from-env-file #{file}")
      end

      def apply_check
        puts File.file?(kubeconfig) ? "Using kubeconfig file: #{kubeconfig}" : "Kubeconfig not found at #{kubeconfig}"
        File.file?(kubeconfig) 
      end

      def template_prefix; 'skaffold' end

      def deploy_path; "#{Ros.env}/#{current_feature_set}" end

      def kube_ctl(cmd); system_cmd(kube_env, "kubectl -n #{namespace} #{cmd}") end
      def kube_ctl_x(cmd); %x(kubectl -n #{namespace} #{cmd}) end

      def kube_env; @kube_env ||= { 'KUBECONFIG' => kubeconfig, 'TILLER_NAMESPACE' => namespace } end

      def skaffold(cmd); system_cmd(skaffold_env, "skaffold -n #{namespace} #{cmd}") end

      def skaffold_env
        @skaffold_env ||=
          { 'SKAFFOLD_DEFAULT_REPO' => platform.config.image_registry, 'IMAGE_TAG' => image_tag }.merge(kube_env)
      end

      def namespace
        @namespace ||= "#{current_feature_set}-#{core.config.name}"
          # if infra.config.branch_deployments
          #   branch_name.eql?(infra.config.api_branch) ? infra.config.namespace : "#{branch_name}-#{infra.config.namespace}"
          # else
          #   infra.config.namespace
          # end
      end

      def switch!; end

      def kubeconfig
        @kubeconfig ||= File.expand_path(infra.config.kubeconfig || '~/.kube/config')
        # @kubeconfig ||= File.expand_path(provider.kubeconfig ||
        #   "#{Ros.tf_root}/#{infra.provider}/provision/kubernetes/kubeconfig_#{name}")
      end
    end
  end
end
