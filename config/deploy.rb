set :application, "revs-lib"
set :repo_url, "https://github.com/sul-dlss/revs"
set :user, "lyberadmin"
set :home_directory, "/home/lyberadmin" # will eventually be "/opt/app"

set :deploy_to, "#{fetch(:home_directory)}/#{fetch(:application)}"
set :rvm_ruby_version, '2.2.2'

set :stages, %W(staging development production)

set :whenever_identifier, ->{ "#{fetch(:application)}_#{fetch(:stage)}" }

# Default value for :linked_files is []
set :linked_files, %w{config/database.yml config/blacklight.yml config/secrets.yml}

# Default value for linked_dirs is []
set :linked_dirs, %w{log tmp/pids tmp/cache tmp/sockets vendor/bundle public/uploads}

last_tag = `git describe --abbrev=0 --tags`.strip
default_tag='master'
set :tag, ask("Tag to deploy (make sure to push the tag first): [default: #{default_tag}, last tag: #{last_tag}] ", default_tag)

set :branch, fetch(:tag)

namespace :jetty do
  task :start do
    on roles(:app) do
      execute "cd #{deploy_to}/current && bundle exec rake jetty:start RAILS_ENV=#{fetch(:rails_env)}"
    end
  end
  task :stop do
    on roles(:app) do
      execute "if [ -d #{deploy_to}/current ]; then cd #{deploy_to}/current && bundle exec rake jetty:stop RAILS_ENV=#{fetch(:rails_env)}; fi"
    end
  end
  task :remove do
    on roles(:app) do
      execute "rm -fr #{release_path}/jetty"
    end
  end
  task :symlink do
    on roles(:app) do
      execute "rm -fr #{release_path}/jetty"
      execute "ln -s #{shared_path}/jetty #{release_path}/jetty"
    end
  end
end

namespace :fixtures do
  task :ingest do
    on roles(:app) do
      execute "cd #{deploy_to}/current && bundle exec rake revs:index_fixtures RAILS_ENV=#{fetch(:rails_env)}"
    end
  end
  task :refresh do
    on roles(:app) do
      execute "cd #{deploy_to}/current && bundle exec rake revs:refresh_fixtures RAILS_ENV=#{fetch(:rails_env)}"
    end
  end
end

namespace :db do
  task :loadfixtures do
    on roles(:app) do
      execute "cd #{deploy_to}/current && bundle exec rake db:fixtures:load RAILS_ENV=#{fetch(:rails_env)}"
    end
  end
  task :loadseeds do
    on roles(:app) do
      execute "cd #{deploy_to}/current && bundle exec rake db:seed RAILS_ENV=#{fetch(:rails_env)}"
    end
  end
  task :symlink_sqlite do
    on roles(:app) do
      execute "ln -s #{shared_path}/#{fetch(:rails_env)}.sqlite3 #{release_path}/db/#{fetch(:rails_env)}.sqlite3"
    end
  end
end

namespace :deploy do
  task :symlink_editstore do
    on roles(:app) do
      execute "ln -s #{fetch(:home_directory)}/editstore-updater/current/public #{release_path}/public/editstore"
    end
  end
  task :symlink_robotstxt do
    shared_robots="#{shared_path}/robots.txt"
    if remote_file_exists?(shared_robots)
      on roles(:app) do
        execute "rm -fr #{release_path}/public/robots.txt && ln -s #{shared_robots} #{release_path}/public/robots.txt"
      end
    end
  end
  task :dev_options_set do
    on roles(:app) do
      execute "cd #{deploy_to}/current && bundle exec rake revs:dev_options_set RAILS_ENV=#{fetch(:rails_env)}"
    end
  end
  task :start do ; end
  task :stop do ; end
  desc 'Restart application'
  task :restart do
    on roles(:app), in: :sequence, wait: 5 do
      # Your restart mechanism here, for example:
      execute :touch, release_path.join('tmp/restart.txt')
    end
  end
  after :publishing, :restart

end

before 'deploy:compile_assets', 'squash:write_revision'
before "deploy:finishing", "deploy:dev_options_set"
after  "deploy:finishing", "deploy:symlink_editstore"
after  "deploy:finishing", "deploy:symlink_robotstxt"


def remote_file_exists?(path)

  on roles(:all) do
    if test("[ -f #{path}]")
      true
    else
      false
    end
  end

end
