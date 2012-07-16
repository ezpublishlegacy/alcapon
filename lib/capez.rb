load_paths.push File.expand_path('../', __FILE__)
load 'database.rb'

# This will simply do chmod g+w on all dir
# See task :setup
set :group_writable, true

after "deploy:setup", :roles => :web do
  # If :deploy_to is something like /var/www then deploy:setup created
  # directories with sudo and we need to fix it
  run "#{try_sudo} chown -R #{user} #{deploy_to}"
  run "#{try_sudo} chgrp -R #{webserver_group} #{deploy_to}"
  run "mkdir #{shared_path}/var"
end

after "deploy:update", :roles => :web do
  capez.autoloads.generate
  capez.cache.clear
  capez.var.fix_permissions
end

before "deploy", :roles => :web do
  capez.dev.local_check
  deploy.web.disable
end

after "deploy", :roles => :web do
  deploy.web.enable
end

namespace :deploy do

  desc <<-DESC
    Finalize the update by creating symlink var -> shared/var
  DESC
  task :finalize_update do
    capez.var.link
  end

  namespace :web do
    desc <<-DESC
      Puts a html file somewhere in the documentroot
      This file is displayed by a RewriteRule if it exists
    DESC
    task :disable do
    end

    desc <<-DESC
      Remove the html file so that the application is reachable
    DESC
    task :enable do
    end
  end
  # End of namespace :deploy:web

end

namespace :capez do

  namespace :cache do
    desc <<-DESC
      Clear caches the way it is configured in ezpublish.rb
    DESC
    # Caches are just cleared for the primary server
    # Multiple server platform are supposed to use a cluster configuration (eZDFS/eZDBFS)
    # and cache management is done via expiry.php which is managed by the cluster API
    task :clear, :roles => :web, :only => { :primary => true } do
      on_rollback do
        clear
      end
      cache_list.each { |cache_tag| capture "cd #{current_path} && php bin/php/ezcache.php --clear-tag=#{cache_tag}#{' --purge' if cache_purge}" }
    end
  end

  namespace :var do
    desc <<-DESC
      Link .../shared/var into ../releases/[latest_release]/var
    DESC
    task :link, :roles => :web do
      run "ln -s #{shared_path}/var #{latest_release}/var"
    end

    desc <<-DESC
      Set the right permissions in var/
    DESC
    task :fix_permissions do
      # We need to fix user and group permissions since eZ Publish wants to chmod 0666...
      #run "#{try_sudo} chown -h #{webserver_user}:#{webserver_group} #{current_path}/var"
      #run "#{try_sudo} chown -R #{webserver_user}:#{webserver_group} #{shared_path}/var/"
      #run "#{try_sudo} chmod -R g+w #{shared_path}/var/"
    end

  end
  # End of namespace :capez:var

  # TODO : cache management must be aware of cluster setup  namespace :autoloads do
  namespace :autoloads do
    desc <<-DESC
      Generates autoloads (extensions and kernel overrides)
    DESC
    task :generate do
      on_rollback do
        generate
      end
      autoload_list.each { |autoload| capture "cd #{current_path} && php bin/php/ezpgenerateautoloads.php --#{autoload}" }
    end
  end
  # End of namespace :capez:autoloads

  # Should be transformed in a simple function (not aimed to be called as a Cap task...)
  namespace :dev do
    desc <<-DESC
      Checks if there are local changes or not (only with Git)
      Considers that your main git repo is at the top of your eZ Publish install
      If it is the case, ask the user to continue or not
    DESC
    task :local_check do
      if "#{scm}" != "git" then
        abort "Feature only available with git"
      end

      # TODO should be configurable
      ezroot_path = "#{File.dirname(__FILE__)}/../.."

      git_status = git_status_result( ezroot_path )

      ask_to_abort = false
      puts "Checking your local git..."
      if git_status['has_local_changes']
        ask_to_abort = true
        puts "You have local changes"
      end
      if git_status['has_new_files']
        ask_to_abort = true
        puts "You have new files"
      end

      if ask_to_abort
        user_abort = Capistrano::CLI.ui.ask "Abort ? y/n (n)"
        abort "Deployment aborted to commit/add local changes" unless user_abort == "n" or user_abort == ""
      end

      if git_status['tracked_branch_status'] == 'ahead'
        puts "You have #{git_status['tracked_branch_commits']} commits that need to be pushed"
        push_before = Capistrano::CLI.ui.ask "Push them before deployment ? y/n (y)"
        if push_before == "" or push_before == "y"
          system "cd #{ezroot_path} && git push"
        end
      end
    end
  end

  def git_status_result(path)
    result = Hash.new
    result['has_local_changes'] = false
    result['has_new_files'] = false
    result['tracked_branch'] = nil
    result['tracked_branch_status'] = nil
    result['tracked_branch_commits'] = 0
    cmd_result = `cd #{path} && git status 2> /dev/null`
    result['raw_result'] = cmd_result
    cmd_result_array = cmd_result.split( /\n/ );
    cmd_result_array.each { |value|
      case value
        when /# Changes not staged for commit:/
          result['has_local_changes'] = true
        when /# Untracked files:/
          result['has_new_files'] = true
        when /# On branch (.*)$/
          result['branch'] = $1
        when /# Your branch is (.*) of '(.*)' by (.*) commits?/
          result['tracked_branch_status'] = $1
          result['tracked_branch'] = $2
          result['tracked_branch_commits'] = $3
      end
      }
      return result
  end

end