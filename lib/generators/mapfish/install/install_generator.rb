require 'rails/generators'
module Mapfish
  module Generators
    class InstallGenerator < Rails::Generators::Base
      class_option "default-site-name", :type => :string, :required => true
      class_option "no-migrate", :type => :boolean

      source_root File.expand_path("../templates", __FILE__)

      def add_geodatabase_config
        path = "#{Rails.root}/config/geodatabase.yml"
        if File.exists?(path)
          puts "Skipping config/geodatabase.yml creation, as file already exists!"
        else
          puts "Adding sample geodatabase config (config/geodatabase.yml)..."
          template "geodatabase.yml", path
        end
      end

      def install_migrations
        puts "Copying over migrations..."
        Dir.chdir(Rails.root) do
          `rake mapfish:install:migrations`
        end
      end

      def run_migrations
        unless options["no-migrate"]
          puts "Running rake db:migrate"
          `rake db:migrate`
        end
      end

      def seed_database
        unless options["no-migrate"]
          puts "Creating admin user and default site"
          ENV['DEFAULT_SITE'] = options["default-site-name"]
          ENV['ADMIN_PWD'] = SecureRandom.hex(4)
          begin
            MapfishAppserver::Engine.load_seed
            puts "Generated user for administraton"
            puts "User: 'admin' - Password: '#{ENV['ADMIN_PWD']}'"
          rescue
            puts "Couldn't load seed data - already done?"
          end
        end
      end

      def add_mapfish_initializer
        path = "#{Rails.root}/config/initializers/mapfish.rb"
        if File.exists?(path)
          puts "Skipping config/initializers/mapfish.rb creation, as file already exists!"
        else
          puts "Adding mapfish initializer (config/initializers/mapfish.rb)..."
          template "initializer.rb", path
        end
      end

      def rm_application_controller
        remove_file "#{Rails.root}/app/controllers/application_controller.rb"
      end

      def add_environment_config
        env_config = %Q{
#Parts for building a Mapserver URL
# Example: http://localhost/cgi-bin/mapserv.fcgi?map=#{Rails.root}/mapconfig/#{options["default-site-name"]}/naturalearth.map)
MAPSERV_SERVER = 'http://localhost' #nil for current application server
MAPSERV_URL = '/cgi-bin/mapserv.fcgi'
MAPSERV_CGI_URL = '/cgi-bin/mapserv'
MAPPATH = '#{Rails.root}/mapconfig'

#Internal URL of print servlet (nil: print-standalone)
PRINT_URL = nil #'http://localhost:8080/print-servlet-1.1/pdf/print.pdf'
}
        %w[development test production].each do |env|
          append_to_file("config/environments/#{env}.rb", env_config)
        end
      end

      def add_print_config_template
        template "print.yml", "config/print.yml"
      end

      def setup_mapconfig
        empty_directory "mapconfig/#{options["default-site-name"]}"
      end

      def copy_map_templates
        puts "Copying templates for map import..."
        directory "../../../../../lib/tasks/templates", "lib/tasks/templates", :verbose => false
      end

      def setup_sencha
        puts "Setup sencha apps workspace..."
        directory "sencha", "public/apps/.sencha", :verbose => false
      end

      def copy_js_libs
        puts "Copying over Javascript libraries..."
        directory "../../../../../vendor/assets/javascripts", "public/lib", :verbose => false
      end
    end
  end
end
