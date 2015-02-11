#!/usr/bin/env ruby
# vim: sts=2 et ai
require 'rubygems'
require 'gollum/app'
require 'omniauth'
require 'omniauth-github'
require 'omniauth-facebook'
require 'omniauth-google-oauth2'
require 'puma'
require 'asin'
require 'json'
require 'httpi'
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
      # Redirect to authentication page
      return [302, {'Location' => '/auth'}, []]
    end

    # Setting authentication information and redirect to previously intended location
    if request.path =~ /^\/auth\/[^\/]+\/callback/ and env['omniauth.auth']
      info = env['omniauth.auth'][:info]
      pp info

      # Creating the 'gollum.author' session object which indicates that the request is authenticated.
      session['gollum.author'] = {
        :name => info[:name],
        :email => info[:email],
        :avatar => info[:image]
      }

      return_to = session[:return_to]
      return_to = return_to.to_s.empty? ? '/' : return_to

      session.delete(:return_to)
      return [302, {'Location' => return_to}, []]
    end

    @app.call(env)
  end
end

use Rack::Session::Cookie, :secret => ENV['COOKIE_SECRET']

use OmniAuth::Builder do
  #provider :github, ENV['GITHUB_KEY'], ENV['GITHUB_SECRET'], scope: 'user:email'
  provider :facebook, ENV['FACEBOOK_KEY'], ENV['FACEBOOK_SECRET'], scope: 'email'
  provider :google_oauth2, ENV['GOOGLE_CLIENT_ID'], ENV['GOOGLE_CLIENT_SECRET'], scope: 'email'
end

use GitHubPullRequest
use OmniAuthSetGollumAuthor

class Gollum::Macro::YouTube < Gollum::Macro
  def render(*args)
    "<a href=\"https://www.youtube.com/watch?v=#{args[0]}\"><img src=\"http://i1.ytimg.com/vi/#{args[0]}/0.jpg\"/></a>"
  end
end

ASIN::Configuration.configure do |config|
  config.key           = ENV['AMAZON_KEY'] or throw 'Missing AMAZON_KEY'
  config.secret        = ENV['AMAZON_SECRET'] or throw 'Missing AMAZON_SECRET'
  config.associate_tag = ENV['AMAZON_TAG'] or throw 'Missing AMAZON_TAG'
  config.logger        = nil
end

HTTPI.adapter = :curb
HTTPI.log = false

class Gollum::Macro::Amazon < Gollum::Macro
  def lookup(asin)
    filename = ".cache/#{asin}.json"

    return JSON.parse(File.read(filename)) if File.exists?(filename)

    item = ASIN::Client.instance.lookup(asin)

    if item
      item = item[0].raw
      File.write(filename, item.to_json)
      return item
    end
  end

  def get_html(json)
    item = json

    return %{
      <div class="amazon-product">
        <div><a href="#{item['DetailPageURL']}"><img src="#{item['LargeImage']['URL']}"></a></div>
        <p>
          <a href="#{item['DetailPageURL']}">#{item['ItemAttributes']['Title']}</a>
          #{item['OfferSummary']['LowestNewPrice']['FormattedPrice']}
        </p>
      </div>
    }
  end

  def render(*args)
    get_html(lookup(args[0]))
  end
end

gollum_path = File.expand_path(ENV['WIKI_REPO']) # CHANGE THIS TO POINT TO YOUR OWN WIKI REPO

#Gollum::Hook.register(:post_commit, :hook_id) do |committer, sha1|
#  `cd #{gollum_path} && git push origin master`
#end

#class CustomApp < Sinatra::Base
#  register Mustache::Sinatra
#  include Precious::Helpers
#  use Precious::EditingAuth
#
#  get '/auth' do
#    mustache :auth, :layout => Precious::App.mustache[:templates] + "/layout"
#  end
#end
#
#use CustomApp

Precious::App.set(:gollum_path, gollum_path)
Precious::App.set(:server, :puma)
Precious::App.set(:default_markup, :markdown) # set your favorite markup language
Precious::App.set(:wiki_options, {
  :mathjax => false,
  :live_preview => false,
  :universal_toc => false,
  :allow_uploads => 'dir',
#  :per_page_uploads => true,
  :user_icons => 'gravatar',
  :css => true,
  :js => true,
  :h1_title => true,
})

run Precious::App
