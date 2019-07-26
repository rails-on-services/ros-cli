# frozen_string_literal: true

module Ros
  module Ops
    module CliCommon

      # TODO: implement
      def gem_version_check
        require 'bundler'
        errors = services.each_with_object([]) do |service, errors|
          config = service.last
          next if config&.enabled.eql? false
          check = image_gems_version_check(service)
          errors.append({ image: service.first, mismatches: check }) if check.size.positive?
        end
        if errors.size.positive?
          if config.force
            STDOUT.puts 'Gem version mismatch. -f used to force'
          else
            STDOUT.puts 'Gem version mismatch. Bundle update or use -f to force (build will be slower)'
            STDOUT.puts "\n#{errors.join("\n")}"
            return
          end
        end
        true
      end

      def image_gems_version_check(service)
        image = service.first
        root_dir = service.last.dig(:ros) ? "#{Ros.root}/ros" : Ros.root
        service_dir = "#{root_dir}/services/#{image}"
        definition = nil
        Dir.chdir(service_dir) do
          definition = Bundler::Definition.build('Gemfile', 'Gemfile.lock', nil)
        end
        gems = definition.requested_specs.select{ |s| images.static_gems.keys.include?(s.name.to_sym) }
        gems.each_with_object([]) do |gemfile_gem, errors|
          gemfile_version = gemfile_gem.version
          image_version = Gem::Version.new(images.static_gems[gemfile_gem.name.to_sym])
          next if gemfile_version.eql?(image_version)
          errors << { image: image, name: gemfile_gem.name, image_version: image_version.to_s, gemfile_version: gemfile_version.to_s }
        end
      end
    end
  end
end
