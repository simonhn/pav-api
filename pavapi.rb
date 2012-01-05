#core stuff
require 'rubygems'

gem 'sinatra', '=1.2.6'
require 'sinatra/base'
require_relative 'models'
require_relative 'store_methods'

#Queueing with delayed job
#require 'delayed_job'
#require 'delayed_job_data_mapper'
#require './storetrackjob'
require 'stalker'

#template systems
require 'yajl/json_gem'
require 'rack/contrib/jsonp'
require 'builder'
#use Rack::JSONP

#for xml fetch and parse
require 'rest_client'
require 'crack'

#musicbrainz stuff
require 'rbrainz'
include MusicBrainz
require 'rchardet19'
require 'logger'

#time parsing
require 'chronic_duration'
require 'chronic'

#throttling
#require 'rack/throttle'
#require 'memcached'
#require './throttler'

#for serving different content types
gem 'sinatra-respond_to', '=0.7.0'
require 'sinatra/respond_to'
require 'bigdecimal'

class PavApi < Sinatra::Base
  
  configure do
    set :environment, :development
    set :app_file, File.join(File.dirname(__FILE__), 'pavapi.rb')
    #versioning
    @version = "v1"
    use Rack::JSONP
    register Sinatra::RespondTo
    
    #use Throttler, :min => 300.0, :cache => Memcached.new, :key_prefix => :throttle
    #use Rack::Throttle::Throttler, :min => 1.0, :cache => Memcached.new, :key_prefix => :throttle
  
    # MySQL connection:
    @config = YAML::load( File.open( 'config/settings.yml' ) )
    @connection = "#{@config['adapter']}://#{@config['username']}:#{@config['password']}@#{@config['host']}/#{@config['database']}";
    DataMapper.setup(:default, @connection)  
    DataMapper.finalize
  
    #DataMapper.auto_upgrade!
    #DataMapper::auto_migrate!
    set :default_content, :html
    
  end
  
  configure :production do
    set :show_exceptions, false
    set :haml, { :ugly=>true, :format => :html5 }
    set :clean_trace, true
    #logging
    DataMapper::Logger.new('log/datamapper.log', :warn )  
    require 'newrelic_rpm'  
  end

  configure :development do
    set :show_exceptions, true
    set :haml, { :ugly=>false, :format => :html5 }
    enable :logging
    DataMapper::Logger.new('log/datamapper.log', :debug )
    $LOG = Logger.new('log/pavstore.log', 'monthly')    
  end

  #Caching
  before '/*' do
    cache_control :public, :must_revalidate, :max_age => 60 
  end

  before '/demo/*' do
    cache_control :public, :must_revalidate, :max_age => 3600
  end

  before '*/chart/*' do
    cache_control :public, :must_revalidate, :max_age => 3600
  end


  # Error 404 Page Not Found
  not_found do
    json_status 404, "Not found"
  end

  error do
    json_status 500, env['sinatra.error'].message
  end

  helpers do
  
    def protected!
        unless authorized?
          response['WWW-Authenticate'] = %(Basic realm="Auth needed for post requests")
          throw(:halt, [401, "Not authorized\n"])
        end
      end

      def authorized?
        @auth ||=  Rack::Auth::Basic::Request.new(request.env)
        @config = YAML::load( File.open( 'config/settings.yml' ) )
         @user = @config['authuser']
         @pass = @config['authpass']
        @auth.provided? && @auth.basic? && @auth.credentials && @auth.credentials == [@user.to_s, @pass.to_s]
      end
    
      def json_status(code, reason)
            status code
            {
              :status => code,
              :reason => reason
            }.to_json
      end
    
      def make_to_from(played_from, played_to)
        #both to and from parameters provided
        played_from = Chronic.parse(played_from)
        played_to = Chronic.parse(played_to)
      
        if (!played_from.nil? && !played_to.nil?)
         return "AND playedtime < '#{played_to.strftime("%Y-%m-%d %H:%M:%S")}' AND playedtime > '#{played_from.strftime("%Y-%m-%d %H:%M:%S")}'"
        end
        #no parameters, sets from a week ago
        if (played_from.nil? && played_to.nil?)
          now_date = DateTime.now - 7
          return "AND playedtime > '#{now_date.strftime("%Y-%m-%d %H:%M:%S")}'"
        end
        #only to parameter, setting from a week before that
        if (played_from.nil? && !played_to.nil?)
          #one week = 60*60*24*7
          from_date = played_to - 604800
          return "AND playedtime < '#{played_to.strftime("%Y-%m-%d %H:%M:%S")}' AND playedtime > '#{from_date.strftime("%Y-%m-%d %H:%M:%S")}'"
        end
        #only from parameter
        if (!played_from.nil? && played_to.nil?)
         return "AND playedtime > '#{played_from.strftime("%Y-%m-%d %H:%M:%S")}'"
        end
      end  
    
      def isNumeric(s)
          Float(s) != nil rescue false
      end
    
      def get_limit(lim)
        #if no limit is set, we default to 10
        #a max at 5000 on limit to protect the server
        if isNumeric(lim)
          if lim.to_i < 5000
            return lim
          else
            return 5000
          end
        else
          return 10
        end
      end
      
      def get_artist_query(q)
        if (!q.nil?)
          return "AND artists.artistname LIKE '%#{q}%' "
        end
      end
    
      def get_track_query(q)
        if (!q.nil?)
          return "AND tracks.title LIKE '%#{q}%' "
        end
      end
    
      def get_album_query(q)
        if (!q.nil?)
          return "AND albums.albumname LIKE '%#{q}%' "
        end
      end
      def get_all_query(q)
        if (!q.nil?)
          return "AND (albums.albumname LIKE '%#{q}%' OR albums.albumname LIKE '%#{q}%' OR artists.artistname LIKE '%#{q}%') "
        end
      end
      def get_order_by(order)
        if (order=='artist')
          return "artists.artistname ASC, plays.playedtime DESC"
        elsif (order=='track')
          return "tracks.title ASC, plays.playedtime DESC"
        else 
          return "plays.playedtime DESC"
        end
      end
    
      def get_channel(channel)
        if(!channel.nil?)
          return "AND plays.channel_id=#{channel}"
        end
      end
    
      def get_program(program)
        if(!program.nil?)
          return "AND plays.program_id='#{program}'"
        end
      end
    
      def merge_tracks(old_id, new_id)
         old_track = Track.get(old_id)
         new_track = Track.get(new_id)

         if(old_track&&new_track)

           #album
           #move tracks from old album to new album
           link = AlbumTrack.all(:track_id => old_track.id)
           link.each{ |link_item|
             @album_load = Album.get(link_item.album_id)
             @moved = @album_load.tracks << new_track
             @moved.save
           }
            #delete old album_track relations
           link.destroy!

           #artist
           #move tracks from old artist to new artist
           link = ArtistTrack.all(:track_id => old_track.id)
           link.each{ |link_item|
             @artist_load = Artist.get(link_item.artist_id)
             @moved = @artist_load.tracks << new_track
             @moved.save
           }  
           #delete old artist_track relations
           link.destroy!

           #plays
           plays = Play.all(:track_id => old_track.id)
           plays.each{ |link_item|
             link_item.update(:track_id => new_id)
           }  

           #delete old track
           old_track.destroy!
         end
      end
  end

  #ROUTES

  # Front page
  get '/' do
    erb :front
  end

  require_relative 'routes/admin'

  require_relative 'routes/artist'

  require_relative 'routes/track'

  require_relative 'routes/album'

  require_relative 'routes/channel'

  require_relative 'routes/play'

  require_relative 'routes/chart'

  require_relative 'routes/demo'


  # search artist by name
  get "/#{@version}/search/:q" do
    limit = get_limit(params[:limit])
    @artists = Artist.all(:artistname.like =>'%'+params[:q]+'%', :limit => limit.to_i)
    respond_to do |wants|
      wants.html { erb :artists }
      wants.xml { builder :artists }
      wants.json { @artists.to_json }
    end
  end
end