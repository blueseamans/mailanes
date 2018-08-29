# Copyright (c) 2018 Yegor Bugayenko
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the 'Software'), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

STDOUT.sync = true

require 'time'
require 'haml'
require 'sinatra'
require 'sinatra/cookies'
require 'raven'
require 'glogin'
require 'glogin/codec'

require_relative 'version'
require_relative 'objects/owner'

if ENV['RACK_ENV'] != 'test'
  require 'rack/ssl'
  use Rack::SSL
end

configure do
  Haml::Options.defaults[:format] = :xhtml
  config = {
    'github' => {
      'client_id' => '?',
      'client_secret' => '?',
      'encryption_secret' => ''
    },
    's3' => {
      'key' => '?',
      'secret' => '?',
      'bucket' => '?'
    },
    'pgsql' => {
      'host' => 'localhost',
      'port' => 0,
      'user' => 'test',
      'dbname' => 'test',
      'password' => 'test'
    },
    'pass_encryption_secret' => '?',
    'sentry' => ''
  }
  config = YAML.safe_load(File.open(File.join(File.dirname(__FILE__), 'config.yml'))) unless ENV['RACK_ENV'] == 'test'
  if ENV['RACK_ENV'] != 'test'
    Raven.configure do |c|
      c.dsn = config['sentry']
      c.release = VERSION
    end
  end
  set :dump_errors, true
  set :show_exceptions, true
  set :config, config
  set :logging, true
  set :server_settings, timeout: 25
  set :glogin, GLogin::Auth.new(
    config['github']['client_id'],
    config['github']['client_secret'],
    'https://www.mailanes.com/github-callback'
  )
  set :pgsql, Pgsql.new(
    host: config['pgsql']['host'],
    port: config['pgsql']['port'].to_i,
    dbname: config['pgsql']['dbname'],
    user: config['pgsql']['user'],
    password: config['pgsql']['password']
  )
end

before '/*' do
  @locals = {
    ver: VERSION,
    login_link: settings.glogin.login_uri,
    request_ip: request.ip
  }
  cookies[:glogin] = params[:glogin] if params[:glogin]
  if cookies[:glogin]
    begin
      @locals[:user] = GLogin::Cookie::Closed.new(
        cookies[:glogin],
        settings.config['github']['encryption_secret'],
        context
      ).to_user
    rescue OpenSSL::Cipher::CipherError => _
      cookies.delete(:glogin)
    end
  end
end

get '/github-callback' do
  cookies[:glogin] = GLogin::Cookie::Open.new(
    settings.glogin.user(params[:code]),
    settings.config['github']['encryption_secret'],
    context
  ).to_s
  redirect to('/')
end

get '/logout' do
  cookies.delete(:glogin)
  cookies.delete(:passcode)
  redirect to('/')
end

get '/hello' do
  haml :hello, layout: :layout, locals: merged(
    title: '/'
  )
end

get '/' do
  haml :index, layout: :layout, locals: merged(
    title: '/'
  )
end

get '/lists' do
  haml :lists, layout: :layout, locals: merged(
    title: '/lists',
    lists: owner.lists
  )
end

post '/add-list' do
  owner.lists.add(params[:title])
  redirect '/lists'
end

get '/list' do
  list = owner.lists.list(params[:id].to_i)
  haml :list, layout: :layout, locals: merged(
    title: "##{list.id}",
    list: list
  )
end

post '/add-recipient' do
  list = owner.lists.list(params[:id].to_i)
  list.recipients.add(params[:email], "@#{current_user}")
  redirect "/list?id=#{list.id}"
end

get '/lanes' do
  haml :lanes, layout: :layout, locals: merged(
    title: '/lanes',
    lanes: owner.lanes
  )
end

post '/add-lane' do
  owner.lanes.add(params[:title])
  redirect '/lanes'
end

get '/lane' do
  lane = owner.lanes.lane(params[:id].to_i)
  haml :lane, layout: :layout, locals: merged(
    title: "##{lane.id}",
    lane: lane
  )
end

post '/add-letter' do
  lane = owner.lanes.lane(params[:id].to_i)
  lane.letters.add(params[:title])
  redirect "/lane?id=#{lane.id}"
end

get '/letter' do
  letter = owner.lanes.letter(params[:id].to_i)
  haml :letter, layout: :layout, locals: merged(
    title: "##{letter.id}",
    letter: letter
  )
end

post '/save-letter' do
  letter = owner.lanes.letter(params[:id].to_i)
  letter.save_liquid(params[:liquid])
  letter.save_yaml(params[:yaml])
  redirect "/letter?id=#{letter.id}"
end

get '/toggle-letter' do
  letter = owner.lanes.letter(params[:id].to_i)
  letter.toggle
  redirect "/letter?id=#{letter.id}"
end

get '/campaigns' do
  haml :campaigns, layout: :layout, locals: merged(
    title: '/campaigns',
    campaigns: owner.campaigns,
    lists: owner.lists,
    lanes: owner.lanes
  )
end

post '/add-campaign' do
  list = owner.lists.list(params[:list].to_i)
  lane = owner.lanes.lane(params[:lane].to_i)
  owner.campaigns.add(list, lane, params[:title])
  redirect '/campaigns'
end

get '/campaign' do
  campaign = owner.campaigns.campaign(params[:id].to_i)
  haml :campaign, layout: :layout, locals: merged(
    title: "##{campaign.id}",
    campaign: campaign
  )
end

post '/save-campaign' do
  campaign = owner.campaigns.campaign(params[:id].to_i)
  campaign.save_yaml(params[:yaml])
  redirect "/campaign?id=#{campaign.id}"
end

get '/toggle-campaign' do
  campaign = owner.campaigns.campaign(params[:id].to_i)
  campaign.toggle
  redirect "/campaign?id=#{campaign.id}"
end

get '/robots.txt' do
  content_type 'text/plain'
  "User-agent: *\nDisallow: /"
end

get '/version' do
  content_type 'text/plain'
  VERSION
end

not_found do
  status 404
  content_type 'text/html', charset: 'utf-8'
  haml :not_found, layout: :layout, locals: merged(
    title: request.url
  )
end

error do
  status 503
  e = env['sinatra.error']
  Raven.capture_exception(e)
  haml(
    :error,
    layout: :layout,
    locals: merged(
      title: 'error',
      error: "#{e.message}\n\t#{e.backtrace.join("\n\t")}"
    )
  )
end

private

def context
  "#{request.ip} #{request.user_agent} #{VERSION} #{Time.now.strftime('%Y/%m/%d')}"
end

def merged(hash)
  out = @locals.merge(hash)
  out[:local_assigns] = out
  out
end

def current_user
  redirect '/hello' unless @locals[:user]
  @locals[:user][:login]
end

def owner
  Owner.new(login: current_user, pgsql: settings.pgsql)
end
