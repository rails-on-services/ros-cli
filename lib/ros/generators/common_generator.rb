# frozen_string_literal: true

require 'thor/group'

module Ros
  module Generators
    module CommonGenerator
      def source_paths; [user_path, internal_path] end
      def user_path; Ros.root.join("#{a_path.gsub("#{Ros.gem_root}/lib/ros", 'lib')}/templates") end
      def internal_path; "#{a_path}/templates" end

      def install_templates
        FileUtils.mkdir_p(user_path)
        FileUtils.cp_r("#{internal_path}/.", user_path)
      end
    end
  end
end
