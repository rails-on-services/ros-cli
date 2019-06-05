# frozen_string_literal: true

module Ros
  class Exec
    def execute(task, services)
      services = Ros.service_names_enabled if services.empty?
      exec_type = Ros.env.eql?('console') ? :console : Settings.meta.components.provider.split('/').last
      services.each do |service|
        next unless config = Settings.services[service]
        next if config&.enabled.eql? false
        prefix = config.ros ? 'app:' : ''
        send(exec_type, service, "#{prefix}#{task}")
      end
    end

    def instance(service, task)
      run_string = %x(docker-compose ps #{service} | grep #{service}).length.positive? ? 'exec' : 'run --rm'
      full_string = "docker-compose #{run_string} #{service} rails #{task}"
      # STDOUT.puts "Running #{full_string}" if options.verbose
      system(full_string)
    end

    def console(service, task)
      Dir.chdir(values.root.to_s) { system("rails #{task}") }
    end

    def kubernetes(service, task)
      STDOUT.puts "Implement #{task} for kubernetes in ros/exec.rb"
    end
  end
end
