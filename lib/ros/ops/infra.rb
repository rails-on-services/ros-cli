# frozen_string_literal: true

module Ros
  module Ops
    module Infra
      # Write the TF files
      def configure
        puts "Provision platform config '#{namespace}' of type #{infra.config.type} in #{Ros.env} environment"
        puts "Work dir: #{workdir}"
        Dir.chdir(workdir) do
          File.open('state.tf.json', 'w') { |f| f.puts(JSON.pretty_generate(tf_state)) }
          File.open('terraform.tfvars', 'w') { |f| f.puts(JSON.pretty_generate(tf_vars)) }
        end
      end

      def workdir; "#{Ros.tf_root}/#{infra.config.provider}/provision/#{infra.config.type}" end

      def tf_vars; send("tf_vars_#{infra.config.provider}") end

      def tf_vars_gcp; raise NotImplementedError end
      def tf_vars_azure; raise NotImplementedError end

      def tf_state
        {
          terraform: {
            backend: {
              "#{devops.provisioning.terraform.state.type}": devops.provisioning.terraform.state.to_h.select { |k, v| k.to_s != 'type' } || {}
            }
          }
        }
      end

      # Standup infra via Terraform: k8s, minikube or instance
      def provision
        Dir.chdir(workdir) do
          system('terraform init')
          system('terraform apply')
        end
        after_provision
      end

      def after_provision; end

      # Destroy the infrastructure
      def rollback
        Dir.chdir(workdir) do
          system('terraform destroy')
        end
      end
    end
  end
end
