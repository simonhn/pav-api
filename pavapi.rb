#core stuff
require 'rubygems'
require 'sinatra'
require './models'
require './store_methods'

#template systems
require 'json' 
require 'rack/contrib/jsonp'
require 'builder'

#musicbrainz stuff
require 'rbrainz'
include MusicBrainz
require 'logger'  
require 'rchardet'

require 'chronic_duration'

require 'sinatra/respond_to'
Sinatra::Application.register Sinatra::RespondTo
@version = "v1"

# MySQL connection:
configure do
  #DataMapper::Logger.new('log/datamapper.log', :debug)
  #DataMapper::Model.raise_on_save_failure = true
  $LOG = Logger.new('log/pavstore.log', 'monthly')
  
  @config = YAML::load( File.open( 'config/settings.yml' ) )
  @connection = "#{@config['adapter']}://#{@config['username']}:#{@config['password']}@#{@config['host']}/#{@config['database']}";
  DataMapper::setup(:default, @connection)  
  DataMapper.auto_upgrade!
  #DataMapper::auto_migrate!
  set :default_content, :html
end

#Caching 1 minute - must adjust
#before do
    #response['Cache-Control'] = "public, max-age=60" unless development?
#end

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

# Front page
get '/' do
  erb :front
end

# show tracks from artist
get "/#{@version}/artist/:id/tracks" do
  if params[:type] == 'mbid' || params[:id].length == 36
    @artist = Artist.first(:artistmbid => params[:id])
  else
    @artist = Artist.get(params[:id])
  end
  @tracks = @artist.tracks
  
  respond_to do |wants|
    wants.html { erb :artist_tracks }
    wants.xml { builder :artist_tracks }
  end
end

#show all artists, defaults to 10, ordered by created date
get "/#{@version}/artists" do
  limit = params[:limit]
  limit ||= 10
  channel = params[:channel]
  if !channel.nil?
    @artists = Artist.all('tracks.plays.channel_id' => channel, :limit=>limit.to_i, :order => [:created_at.desc ])
  else
    @artists =  Artist.all(:limit => limit.to_i, :order => [:created_at.desc ])
  end
  respond_to do |wants|
    wants.json { @artists.to_json }
    wants.html { erb :artists }
    wants.xml { builder :artists }
  end
end

# show artist from id. if ?type=mbid is added, it will perform a mbid lookup
get "/#{@version}/artist/:id" do
  if params[:type] == 'mbid' || params[:id].length == 36
     @artist = Artist.first(:artistmbid => params[:id])
  else
     @artist = Artist.get(params[:id])
  end
  respond_to do |wants|
    wants.html { erb :artist }
    wants.xml { builder :artist }
    wants.json { @artist.to_json }
  end
end


# show plays from artist
get "/#{@version}/artist/:id/plays" do
  if params[:type] == 'mbid' || params[:id].length == 36
    @artist = Artist.first(:artistmbid => params[:id])
  else
    @artist = Artist.get(params[:id])
  end
  @plays = @artist.tracks.plays
  respond_to do |wants|
    wants.html { erb :artist_plays }
    wants.xml { builder :artist_plays }
  end
end

#add new track item (an item in the playout xml)
post "/#{@version}/track" do
   protected!  
   data = JSON.parse params[:payload].to_json
   if !data['item']['artist']['artistname'].nil? && Play.count(:playedtime => data['item']['playedtime'], :channel_id => data['channel'])==0
      store_hash(data['item'], data['channel'])
   end
end

#show tracks
get "/#{@version}/tracks" do
  limit = params[:limit]
  limit ||= 10
  channel = params[:channel]
  if !channel.nil?
    @tracks = Track.all(Track.plays.channel_id => channel, :limit=>limit.to_i, :order => [:created_at.desc])
  else
    @tracks = Track.all(:limit => limit.to_i, :order => [:created_at.desc ])
  end
 respond_to do |wants|
    wants.html { erb :tracks }
    wants.xml { builder :tracks }
    wants.json {@tracks.to_json}
  end
end

# show track
get "/#{@version}/track/:id" do
  if params[:type] == 'mbid' || params[:id].length == 36
    @track = Track.first(:trackmbid => params[:id])
  else
    @track = Track.get(params[:id])
  end
  respond_to do |wants|
    wants.html { erb :track }
    wants.xml { builder :track }
    wants.json {@track.to_json}
  end
end

#show artists for a track
get "/#{@version}/track/:id/artists" do
  if params[:type] == 'mbid' || params[:id].length == 36
    @track = Track.first(:trackmbid => params[:id])
  else
    @track = Track.get(params[:id])
  end
  @artists = @track.artists
  
  respond_to do |wants|
    wants.html { erb :track_artists }
    wants.xml { builder :track_artists }
    wants.json {@artists.to_json}
  end
end

#show albums for a track
get "/#{@version}/track/:id/albums" do
  if params[:type] == 'mbid' || params[:id].length == 36
    @track = Track.first(:trackmbid => params[:id])
  else
    @track = Track.get(params[:id])
  end
  
  @albums = @track.albums
  respond_to do |wants|
    wants.html { erb :track_albums }
    wants.xml { builder :track_albums }
    wants.json {@albums.to_json}
  end
end

# show plays for a track
get "/#{@version}/track/:id/plays" do
  if params[:type] == 'mbid' || params[:id].length == 36
    @track = Track.first(:trackmbid => params[:id])
  else
    @track = Track.get(params[:id])
  end
  @plays = @track.plays
  respond_to do |wants|
    wants.html { erb :track_plays }
    wants.xml { builder :track_plays }
    wants.json {@plays.to_json}
  end
end

#show all albums
get "/#{@version}/albums" do
  limit = params[:limit]
  limit ||= 10
  channel = params[:channel]
  if !channel.nil?
    @albums = Album.all('tracks.plays.channel_id' => channel, :limit=>limit.to_i, :order => [:created_at.desc ])
  else
    @albums =  Album.all(:limit => limit.to_i, :order => [:created_at.desc ])
  end
    respond_to do |wants|
      wants.html { erb :albums }
      wants.xml { builder :albums }
      wants.json { @albums.to_json }
    end
end

# show album from id
get "/#{@version}/album/:id" do 
  if params[:type] == 'mbid' || params[:id].length == 36
    @album = Album.first(:albummbid => params[:id])
  else
    @album = Album.get(params[:id])
  end
  respond_to do |wants|
    wants.html { erb :album }
    wants.xml { builder :album }
    wants.json {@album.to_json}
  end
end

# show tracks for an album - json version not perfect
get "/#{@version}/album/:id/tracks" do
  if params[:type] == 'mbid' || params[:id].length == 36
    @album = Album.first(:albummbid => params[:id])
  else
    @album = Album.get(params[:id])
  end
  @tracks = @album.tracks
  respond_to do |wants|
    wants.html { erb :album_tracks }
    wants.xml { builder :album_tracks }
    wants.json {@tracks.to_json }
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

#create new channel
post "/#{@version}/channel" do
   protected!
   data = JSON.parse params[:payload].to_json
   channel = Channel.first_or_create({ :channelname => data['channelname'] }, { :channelname => data['channelname'],:channelxml => data['channelxml'], :logo => data['logo'], :channellink => data['channellink'] })
end

#update a channel
put "/#{@version}/channel/:id" do
   protected!
   channel = Channel.get(params[:id])
   data = JSON.parse params[:payload].to_json
   channel = channel.update(:channelname => data['channelname'],:channelxml => data['channelxml'], :logo => data['logo'], :channellink => data['channellink'])
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
  @channel_tracks = Channel.get(params[:id]).plays(:limit =>10,:order => [:playedtime.desc ])
  respond_to do |wants|
    wants.xml { @channel_tracks.to_xml }
    wants.json { @channel_tracks.to_json }
  end
end

# chart of top tracks by name
get "/#{@version}/chart/track" do
  limit = params[:limit]
  limit ||= 10
  #date in this format: 2010-05-11 01:06:14
  to_from = make_to_from(params[:from], params[:to])
  @tracks = repository(:default).adapter.select("select artists.artistname, tracks.id, tracks.title, count(*) as cnt from tracks, plays, artists, artist_tracks where tracks.id=plays.track_id AND artists.id=artist_tracks.artist_id AND artist_tracks.track_id=tracks.id #{to_from} group by tracks.id order by cnt DESC limit #{limit}")
  respond_to do |wants|
     wants.xml { builder :track_chart }
   end
end

# chart of top tracks by name
get "/#{@version}/chart/track/channel/:id" do
  #date in this format: 2010-05-11 01:06:14
  to_from = make_to_from(params[:from], params[:to])
  limit = params[:limit]
  limit ||= 10
  
  @tracks = repository(:default).adapter.select("select artists.artistname, tracks.id, tracks.title, count(*) as cnt from tracks, plays, artists, artist_tracks where plays.channel_id=#{params[:id]} AND tracks.id=plays.track_id AND artists.id=artist_tracks.artist_id AND artist_tracks.track_id=tracks.id #{to_from} group by tracks.id order by cnt DESC limit #{limit}")
    respond_to do |wants|
     wants.xml { builder :track_chart }
   end
end


# chart of top artist by name
get "/#{@version}/chart/artist" do
 to_from = make_to_from(params[:from], params[:to])
 limit = params[:limit]
 limit ||= 10
 @artists = repository(:default).adapter.select("select sum(cnt) as count, har.artistname, har.id from (select artists.artistname, artists.id, artist_tracks.artist_id, count(*) as cnt from tracks, plays, artists, artist_tracks where tracks.id=plays.track_id AND tracks.id=artist_tracks.track_id AND artist_tracks.artist_id= artists.id #{to_from} group by tracks.id) as har group by har.artistname order by count desc limit #{limit}")
 respond_to do |wants|
    wants.xml { builder :artist_chart }
  end
end

get "/#{@version}/chart/album" do
  to_from = make_to_from(params[:played_from], params[:played_to])
  limit = params[:limit]
  limit ||= 10
  @albums = repository(:default).adapter.select("select albums.albumname, albums.id as album_id, tracks.id as track_id, count(*) as cnt from tracks, plays, albums, album_tracks where tracks.id=plays.track_id AND albums.id=album_tracks.album_id AND album_tracks.track_id=tracks.id #{to_from} group by albums.id order by cnt DESC limit #{limit}")
  respond_to do |wants|
      wants.xml { builder :album_chart }
  end
end

# search artist by name
get "/#{@version}/search/:q" do
  limit = params[:limit]
  limit ||= 10
  @artists = Artist.all(:artistname.like =>'%'+params[:q]+'%', :limit => limit.to_i)
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
  @artistmbid = (Artist.count(:artistmbid).to_f/Artist.count.to_f)*100
  
  @trackcount = Track.count
  @trackmbid = (Track.count(:trackmbid).to_f/Track.count.to_f)*100
  
  @playcount = Play.count
  
  @albumcount = Album.count
  @albummbid = (Album.count(:albummbid).to_f/Album.count.to_f)*100
  
  @dig_track = Channel.get(1).plays.tracks.count
  @dig_artist = Channel.get(1).plays.tracks.artists.count
  @dig_album = Channel.get(1).plays.tracks.albums.count
  @dig_play = Channel.get(1).plays.count
  
  
  @jazz_track = Channel.get(2).plays.tracks.count
  @jazz_artist = Channel.get(2).plays.tracks.artists.count
  @jazz_album = Channel.get(2).plays.tracks.albums.count
  @jazz_play = Channel.get(1).plays.count
  
  
  @country_track = Channel.get(3).plays.tracks.count
  @country_artist = Channel.get(3).plays.tracks.artists.count
  @country_album = Channel.get(3).plays.tracks.albums.count
  @country_play = Channel.get(3).plays.count
  
  
  @jjj_track = Channel.get(4).plays.tracks.count
  @jjj_artist = Channel.get(4).plays.tracks.artists.count
  @jjj_album = Channel.get(4).plays.tracks.albums.count
   @jjj_play = Channel.get(4).plays.count
   
  respond_to do |wants|
    wants.html { erb :stats }
  end

end