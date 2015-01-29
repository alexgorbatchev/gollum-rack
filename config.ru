#!/usr/bin/env ruby
# vim: sts=2 et ai
require 'rubygems'
require 'gollum/app'
require 'omniauth'
require 'omniauth-github'
require 'omniauth-facebook'
require 'omniauth-google-oauth2'
require 'puma'
require 'pp'

class GitHubPullRequest
  def initialize(app)
    @app = app
  end

  def call(env)
    request = Rack::Request.new(env)

    if request.path =~ /^\/pull/
      status = system({'GIT_DIR' => "#{ENV['WIKI_REPO']}/.git"}, 'git pull')
      if status
        return [200, {}, ['ok']]
      else
        return [401, {}, ['not-ok']]
      end
    end
    
    if request.path =~ /^\/push/
      status = system({'GIT_DIR' => "#{ENV['WIKI_REPO']}/.git"}, 'git push')
      if status
        return [200, {}, ['ok']]
      else
        return [401, {}, ['not-ok']]
      end
    end
    @app.call(env)
  end
end

class OmniAuthSetGollumAuthor
  def initialize(app)
    @app = app
  end

  def call(env)
    request = Rack::Request.new(env)
    session = env['rack.session']

    # Check whether we are authorized, if not redirect.
    if request.path =~ /^\/(edit|create|revert|delete)\// and not session['gollum.author']
      session[:return_to] = request.url
      # Redirect to authentication
      return [302, {'Location' => '/auth/github'}, []]
    end

    # Setting authentication information and redirect to previously intended location
    if request.path =~ /^\/auth\/[^\/]+\/callback/ and env['omniauth.auth']
      # puts env['omniauth.auth'].to_s
      # Creating the 'gollum.author' session object which indicates that the request is authenticated.
      session['gollum.author'] = {
        :name => env['omniauth.auth'][:info][:name],
        :email => env['omniauth.auth'][:info][:email]
      }
      return_to = session[:return_to] or '/'
      session.delete(:return_to)
      return [302, {'Location' => return_to}, []]
    end
    @app.call(env)
  end
end

use Rack::Session::Cookie, :secret => "somethingverysecret1234"

use OmniAuth::Builder do
  provider :github, ENV['GITHUB_KEY'], ENV['GITHUB_SECRET'], scope: 'user:email'
#  provider :facebook, ENV['FACEBOOK_KEY'], ENV['FACEBOOK_SECRET'], scope: 'email'
  provider :google_oauth2, ENV['GOOGLE_CLIENT_ID'], ENV['GOOGLE_CLIENT_SECRET'], scope: 'email'
end

use GitHubPullRequest
use OmniAuthSetGollumAuthor

gollum_path = File.expand_path(ENV['WIKI_REPO']) # CHANGE THIS TO POINT TO YOUR OWN WIKI REPO
puts gollum_path

#Gollum::Hook.register(:post_commit, :hook_id) do |committer, sha1|
#  committer.wiki.repo.git.pull
#  committer.wiki.repo.git.push
#end

Precious::App.set(:gollum_path, gollum_path)
Precious::App.set(:server, :puma)
Precious::App.set(:default_markup, :markdown) # set your favorite markup language
Precious::App.set(:wiki_options, {
  :mathjax => false,
  :live_preview => true,
  :universal_toc => false,
  :allow_uploads => 'page',
  :user_icons => 'gravatar',
  :css => true,
  :h1_title => true,
  :css => true,
})

run Precious::App
