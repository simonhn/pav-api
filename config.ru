require 'rubygems'
require 'bundler'
Bundler.require
require './pavapi'

#set :environment,  :production
disable :run
enable :logging, :dump_errors, :raise_errors, :show_exceptions

run Sinatra::Application