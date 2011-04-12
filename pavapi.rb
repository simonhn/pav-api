#core stuff
require 'rubygems'
require 'sinatra'
require './models'

#template systems
require 'json' 
require 'rack/contrib/jsonp'
require 'builder'

require 'sinatra/respond_to'
Sinatra::Application.register Sinatra::RespondTo
@version = "1"

# MySQL connection:
configure do
  DataMapper::Logger.new('log/datamapper.log', :debug)
  @config = YAML::load( File.open( 'config/settings.yml' ) )
  @connection = "#{@config['adapter']}://#{@config['username']}:#{@config['password']}@#{@config['host']}/#{@config['database']}";
  DataMapper::setup(:default, @connection)  
  DataMapper.auto_upgrade!
  #DataMapper::auto_migrate!
  set :default_content, :html
end

#Caching 1 minute - must adjust
before do
    response['Cache-Control'] = "public, max-age=60" unless development?
end

#Error handling
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
      @config = YAML::load( File.open( 'conf/settings.yml' ) )
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
      if (!played_from.nil? && !played_to.nil?)
       return "AND playedtime < '#{played_to}' AND playedtime > '#{played_from}'"
      end
      #no parameter, sets from a week ago
      if (played_from.nil? && played_to.nil?)
        now_date = DateTime.now - 7
        return "AND playedtime > '#{now_date.strftime("%Y-%m-%d %H:%M:%S")}'"
      end
      #only to parameter, setting from a week before that
      if (played_from.nil? && !played_to.nil?)
        from_date = DateTime.parse(played_to) - 7
        return "AND playedtime < '#{played_to}' AND playedtime > '#{from_date.strftime("%Y-%m-%d %H:%M:%S")}'"
      end
      #only from parameter
      if (!played_from.nil? && played_to.nil?)
       return "AND playedtime > '#{played_from}'"
      end
    end
end

#ROUTES


post "/#{@version}/api" do
   data = JSON.parse params[:data].to_s
   data
end

post "/#{@version}/artist" do
   data = JSON.parse params[:data].to_s
   data.inspect
end

post "/#{@version}/track" do
   protected!
   data = JSON.parse params[:data].to_s
   puts data
end

post "/#{@version}/play" do
   data = JSON.parse params[:data].to_s
   puts data.inspect
end

#GET
# Front page
get '/' do
  erb :front
end

#show all artists
get "/#{@version}/artists" do
  @artists =  Artist.all(:limit => 10, :order => [:created_at.desc ])
  respond_to do |wants|
    wants.json { @artists.to_json }
    wants.html { erb :artists }
    wants.xml { builder :artists }
  end
end

#show all artists
get "/#{@version}/artists/:limit" do
  @artists =  Artist.all(:limit => params[:limit].to_i, :order => [:created_at.desc ])
  respond_to do |wants|
    wants.html { erb :artists }
    wants.xml { builder :artists }
    wants.json { @artists.to_json }
  end
end

# show artist from id
get "/#{@version}/artist/:id" do
  @artist = Artist.get(params[:id])
  respond_to do |wants|
    wants.html { erb :artist }
    wants.xml { builder :artist }
    wants.json { @artist.to_json }
  end
end

# show tracks from artist
get "/#{@version}/artist/:id/tracks" do
  @artist = Artist.get(params[:id])
  @tracks = Artist.get(params[:id]).tracks
  respond_to do |wants|
    wants.html { erb :artist_tracks }
    wants.xml { builder :artist_tracks }
  end
end

# show tracks from artist
get "/#{@version}/artist/:id/plays" do
  @artist = Artist.get(params[:id])
  @plays = Artist.get(params[:id]).tracks.plays
  respond_to do |wants|
    wants.html { erb :artist_plays }
    wants.xml { builder :artist_plays }
  end
end

#show all albums
get "/#{@version}/albums" do
  @albums =  Album.all(:limit => 10, :order => [:created_at.desc ])
    respond_to do |wants|
      wants.html { erb :albums }
      wants.xml { builder :albums }
      wants.json { @albums.to_json }
    end
end

#show all albums with limit
get "/#{@version}/albums/:limit" do
  @albums =  Album.all(:limit => params[:limit].to_i, :order => [:created_at.desc ])
  respond_to do |wants|
    wants.html { erb :albums }
    wants.xml { builder :albums }
    wants.json { @albums.to_json }
  end
end

# show album from id
get "/#{@version}/album/:id" do
  @album = Album.get(params[:id])
  respond_to do |wants|
    wants.html { erb :album }
    wants.xml { builder :album }
    wants.json {@album.to_json}
  end
end

# show tracks for an album - json version not perfect
get "/#{@version}/album/:id/tracks" do
  @album = Album.get(params[:id])
  @tracks = Album.get(params[:id]).tracks
  respond_to do |wants|
    wants.html { erb :album_tracks }
    wants.xml { builder :album_tracks }
    wants.json {@tracks.to_json }
  end
end

#show tracks
get "/#{@version}/tracks" do
 @tracks = Track.all(:limit => 10, :order => [:created_at.desc ])
 respond_to do |wants|
    wants.html { erb :tracks }
    wants.xml { builder :tracks }
    wants.json {@tracks.to_json}
  end
end

#show tracks with limit
get "/#{@version}/tracks/:limit" do
  @tracks = Track.all(:limit => params[:limit].to_i, :order => [:created_at.desc ])
  respond_to do |wants|
    wants.html { erb :tracks }
    wants.xml { builder :tracks }
    wants.json {@tracks.to_json}
  end
end

# show track
get "/#{@version}/track/:id" do
  @track = Track.get(params[:id])
  respond_to do |wants|
    wants.html { erb :track }
    wants.xml { builder :track }
    wants.json {@track.to_json}
  end
end

#show artists for a track
get "/#{@version}/track/:id/artists" do
  @track = Track.get(params[:id])
  @artists = Track.get(params[:id]).artists
  respond_to do |wants|
    wants.html { erb :track_artists }
    wants.xml { builder :track_artists }
    wants.json {@artists.to_json}
  end
end

#show albums for a track
get "/#{@version}/track/:id/albums" do
  @track = Track.get(params[:id])
  @albums = Track.get(params[:id]).albums
  respond_to do |wants|
    wants.html { erb :track_albums }
    wants.xml { builder :track_albums }
    wants.json {@albums.to_json}
  end
end

# show plays for a track
get "/#{@version}/track/:id/plays" do
  @track = Track.get(params[:id])
  @plays = Track.get(params[:id]).plays
  respond_to do |wants|
    wants.html { erb :track_plays }
    wants.xml { builder :track_plays }
    wants.json {@plays.to_json}
  end
end

# show all channels
get "/#{@version}/channels" do
    @channels = Channel.all
    respond_to do |wants|
      wants.xml { @channels.to_xml }
      wants.json { @channels.to_json }  
    end
end

# show channel from id
get "/#{@version}/channel/:id" do
    @channel = Channel.get(params[:id])
    respond_to do |wants|
      wants.xml { @channel.to_xml }
      wants.json { @channel.to_json }  
    end
end

# show tracks for specific channel
get "/#{@version}/channel/:id/plays" do
  @channel_plays = Channel.get(params[:id]).plays
  @channel_tracks = Channel.get(params[:id]).plays(:limit =>10,:order => [:playedtime.desc ]).tracks
  respond_to do |wants|
    wants.xml { @channel_tracks.to_xml }
    wants.json { @channel_tracks.to_json }
  end
end

# chart of top tracks by name
get "/#{@version}/chart/track" do
  #date in this format: 2010-05-11 01:06:14
  to_from = make_to_from(params[:played_from], params[:played_to])
  @tracks = repository(:default).adapter.select("select artists.artistname, tracks.id, tracks.title, count(*) as cnt from tracks, plays, artists, artist_tracks where tracks.id=plays.track_id AND artists.id=artist_tracks.artist_id AND artist_tracks.track_id=tracks.id #{to_from} group by tracks.id order by cnt DESC limit 10")
  respond_to do |wants|
     wants.xml { builder :track_chart }
   end
end

# chart of top tracks by name
get "/#{@version}/chart/track/channel/:id" do
  #date in this format: 2010-05-11 01:06:14
  to_from = make_to_from(params[:f], params[:t])
  limit = params[:l]
  limit ||= 10
  
  @tracks = repository(:default).adapter.select("select artists.artistname, tracks.id, tracks.title, count(*) as cnt from tracks, plays, artists, artist_tracks where plays.channel_id=#{params[:id]} AND tracks.id=plays.track_id AND artists.id=artist_tracks.artist_id AND artist_tracks.track_id=tracks.id #{to_from} group by tracks.id order by cnt DESC limit #{limit}")
    respond_to do |wants|
     wants.xml { builder :track_chart }
   end
end


# chart of top artist by name
get "/#{@version}/chart/artist" do
 to_from = make_to_from(params[:played_from], params[:played_to])
 @artists = repository(:default).adapter.select("select sum(cnt) as count, har.artistname, har.id from (select artists.artistname, artists.id, artist_tracks.artist_id, count(*) as cnt from tracks, plays, artists, artist_tracks where tracks.id=plays.track_id AND tracks.id=artist_tracks.track_id AND artist_tracks.artist_id= artists.id #{to_from} group by tracks.id) as har group by har.artistname order by count desc limit 10")
 respond_to do |wants|
    wants.xml { builder :artist_chart }
  end
end

get "/#{@version}/chart/album" do
  to_from = make_to_from(params[:played_from], params[:played_to])
  @albums = repository(:default).adapter.select("select albums.albumname, albums.id as album_id, tracks.id as track_id, count(*) as cnt from tracks, plays, albums, album_tracks where tracks.id=plays.track_id AND albums.id=album_tracks.album_id AND album_tracks.track_id=tracks.id #{to_from} group by albums.id order by cnt DESC limit 10")
  respond_to do |wants|
      wants.xml { builder :album_chart }
  end
end

# search artist by name
get "/#{@version}/search/:q" do
  @artists = Artist.all(:artistname.like =>'%'+params[:q]+'%')
  respond_to do |wants|
    wants.html { erb :artists }
    wants.xml { builder :artists }
    wants.json { @artists.to_json }
  end
end

#Sinatra version info
get "/#{@version}/about" do
  "I'm running version " + Sinatra::VERSION 
end

#Count all artists
get "/#{@version}/stats" do
  @artistcount = Artist.count
  @trackcount = Track.count
  @playcount = Play.count
  @albumcount = Album.count 
  respond_to do |wants|
    wants.html { erb :stats }
  end

end