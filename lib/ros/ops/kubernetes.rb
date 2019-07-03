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
            service_names: platform.services.keys,
            secrets_files: core.services.dig(name, :environment) ? [:platform, name.to_sym] : %i(platform)
          }
        end

def relative_path
  @x_relative_path ||= "../#{super}"
end

        def fluentd_header
          "configMaps:\n  rails-audit-log.conf: |"
        end

        def provision
          return unless provision_check
          provision_namespace
          provision_helm
          provision_secrets
          provision_services
        end

        def provision_namespace
          system_cmd(kube_env, "kubectl create ns #{namespace}") unless system_cmd(kube_env, "kubectl get ns #{namespace}")
          system_cmd(kube_env, "kubectl label namespace #{namespace} istio-injection=enabled --overwrite")
        end

        def provision_helm
          kube_ctl("apply -f #{Ros.k8s_root}/tiller-rbac")
          system_cmd(kube_env, 'helm init --upgrade --wait --service-account tiller')
        end

        def provision_secrets
          Dir["#{core_root}/*.env"].each { |file| sync_secret(file) }
        end

        def provision_services
          Dir.chdir(core_root) { Dir['*.yml'].each { |file| skaffold("deploy -f #{file}") } }
        end

        def rollback; puts "TODO: rollback #{self.class.name}" end
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
          {
            name: name,
            context_path: "#{relative_path}#{platform.services.dig(name, :ros) ? '/ros' : ''}",
            dockerfile_path: "#{relative_path}/#{platform.services.dig(name, :ros) ? 'ros/' : ''}Dockerfile",
            image: platform.config.image,
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
        def provision
          # return unless provision_check and gem_version_check
          # provision_secrets
          provision_services
        end

        def provision_secrets
          Dir["#{platform_root}/*.env"].each { |file| sync_secret(file) }
          kube_cmd = "create secret generic #{registry_secret_name} " \
            "--from-file=.dockerconfigjson=#{Dir.home}/.docker/config.json --type=kubernetes.io/dockerconfigjson"
          kube_ctl(kube_cmd)
        end

        def registry_secret_name; "registry-#{platform.config.image.registry}" end

        def provision_services
          thing = ARGV[0] || '*'
          binding.pry
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
      end

      def sync_secret(file)
        name = File.basename(file).chomp('.env')
        # TODO: base64 decode values then do an md5 on the contents
        # yaml = kube_ctl("get secret #{name} -o yaml")
        kube_ctl("delete secret #{name}") if kube_ctl("get secret #{name}")
        kube_ctl("create secret generic #{name} --from-env-file #{file}")
      end

      def provision_check
        puts File.file?(kubeconfig) ? "Using kubeconfig file: #{kubeconfig}" : "Kubeconfig not found at #{kubeconfig}"
        File.file?(kubeconfig) 
      end

      def template_prefix; 'skaffold' end

      def deploy_path; "#{Ros.env}/#{namespace}" end

      def kube_ctl(cmd); system_cmd(kube_env, "kubectl -n #{namespace} #{cmd}") end

      def kube_env; @kube_env ||= { 'KUBECONFIG' => kubeconfig, 'TILLER_NAMESPACE' => namespace } end

      def skaffold(cmd); system_cmd(skaffold_env, "skaffold -n #{namespace} #{cmd}") end

      def skaffold_env
        @skaffold_env ||=
          { 'SKAFFOLD_DEFAULT_REPO' => platform.config.image.registry, 'IMAGE_TAG' => image_tag }.merge(kube_env)
      end

      def namespace
        @namespace ||=
          if infra.config.branch_deployments
            branch_name.eql?(infra.config.api_branch) ? infra.config.namespace : "#{branch_name}-#{infra.config.namespace}"
          else
            infra.config.namespace
          end
      end

      def kubeconfig
        @kubeconfig ||= File.expand_path(infra.config.kubeconfig || '~/.kube/config')
        # @kubeconfig ||= File.expand_path(provider.kubeconfig ||
        #   "#{Ros.tf_root}/#{infra.provider}/provision/kubernetes/kubeconfig_#{name}")
      end
    end
  end
end
