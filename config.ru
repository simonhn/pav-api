require 'rubygems'
#gem 'sinatra', '=0.9.6'
require 'sinatra'
#require 'rack/cache'
require 'pavapi'

#use Rack::Cache,
#  :verbose     => true,
#  :metastore   => 'file:/var/cache/rack/meta',
#  :entitystore => 'file:/var/cache/rack/body'

use Rack::JSONP

set :environment,  :development
disable :run
enable :logging, :dump_errors, :raise_errors, :show_exceptions

# so cucumber can find the view templates
configure do
  set :views, "#{File.dirname(__FILE__)}/views"
end

run Sinatra::Application