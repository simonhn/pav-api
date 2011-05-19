#core stuff
require 'rubygems'
require 'sinatra'
require './models'
require './store_methods'

#template systems
require 'yajl/json_gem'

require 'rack/contrib/jsonp'
require 'builder'

#musicbrainz stuff
require 'rbrainz'
include MusicBrainz
require 'rchardet'
require 'logger'

require 'chronic_duration'

require 'newrelic_rpm'


require 'sinatra/respond_to'
Sinatra::Application.register Sinatra::RespondTo
@version = "v1"

# MySQL connection:
configure do
  DataMapper::Logger.new('log/datamapper.log', :warn)
  DataMapper::Model.raise_on_save_failure = true
  $LOG = Logger.new('log/pavstore.log', 'monthly')
  
  @config = YAML::load( File.open( 'config/settings.yml' ) )
  @connection = "#{@config['adapter']}://#{@config['username']}:#{@config['password']}@#{@config['host']}/#{@config['database']}";
  DataMapper.setup(:default, @connection)  
  DataMapper.finalize
  
  #DataMapper.auto_upgrade!
  #DataMapper::auto_migrate!
  set :default_content, :html
end

#Caching 1 minute - must adjust
#before do
    #response['Cache-Control'] = "public, max-age=60" unless development?
#end

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
    wants.html { erb :artists }
    wants.xml { builder :artists }
    wants.json { @artists.to_json }
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
    wants.json { @tracks.to_json }   
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
    wants.json { @plays.to_json }
  end
end

#add new track item (an item in the playout xml)
post "/#{@version}/track" do
   protected!
   begin
   
   data = JSON.parse params[:payload].to_json
   if !data['item']['artist']['artistname'].nil? && Play.count(:playedtime => data['item']['playedtime'], :channel_id => data['channel'])==0
      store_hash(data['item'], data['channel'])
   end
   
   rescue StandardError => e 
      $LOG.info("Post method end: Issue while processing #{data['item']['artist']['artistname']} - #{data['channel']},  #{e.backtrace}")
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

# show tracks for an album
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

#PLAY
get "/#{@version}/plays" do
  #DATE_FORMAT(playedtime, '%d %m %Y %H %i %S')
  limit = params[:limit]
  limit ||= 10
  to_from = make_to_from(params[:from], params[:to])
  channel = params[:channel]
  if !channel.nil?
     @plays = repository(:default).adapter.select("select * from tracks, plays, artists, artist_tracks, albums, album_tracks  where plays.channel_id=#{channel} AND tracks.id=plays.track_id AND artists.id=artist_tracks.artist_id AND artist_tracks.track_id=tracks.id AND albums.id = album_tracks.album_id AND tracks.id = album_tracks.track_id #{to_from} group by tracks.id, plays.playedtime order by plays.playedtime DESC limit #{limit}")
  else
    @plays = repository(:default).adapter.select("select * from tracks, plays, artists, artist_tracks, albums, album_tracks  where tracks.id=plays.track_id AND artists.id=artist_tracks.artist_id AND artist_tracks.track_id=tracks.id AND albums.id = album_tracks.album_id AND tracks.id = album_tracks.track_id #{to_from} group by tracks.id, plays.playedtime order by plays.playedtime DESC limit #{limit}")
  end
  hat = @plays.collect {|o| {:title => o.title, :artistname => o.artistname, :playedtime => o.playedtime, :albumname => o.albumname, :albumimage => o.albumimage} }
  
  respond_to do |wants|
    wants.html { erb :plays }
    wants.xml { builder :plays }
    wants.json { hat.to_json }
  end
end

get "/#{@version}/play/:id" do
@play = Play.get(params[:id])
  respond_to do |wants|
    wants.json { @play.to_json }
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



# chart of top tracks
get "/#{@version}/chart/track" do
  limit = params[:limit]
  limit ||= 10
  to_from = make_to_from(params[:from], params[:to])
  channel = params[:channel]
  #SELECT tracks.title, artists.artistname, count(*) as cnt FROM `tracks` INNER JOIN `plays` ON `tracks`.`id` = `plays`.`track_id` INNER JOIN artist_tracks ON tracks.id=artist_tracks.track_id INNER JOIN artists ON artists.id=artist_tracks.artist_id WHERE `plays`.`channel_id` = 1 group by tracks.id   order by cnt DESC limit 10;
  
  if !channel.nil?
     @tracks = repository(:default).adapter.select("select *, count(distinct plays.id) as cnt from tracks, plays, artists, artist_tracks where plays.channel_id=#{channel} AND tracks.id=plays.track_id AND artists.id=artist_tracks.artist_id AND artist_tracks.track_id=tracks.id #{to_from} group by tracks.id order by cnt DESC limit #{limit}")
  else
    @tracks = repository(:default).adapter.select("select *, count(distinct plays.id) as cnt from tracks, plays, artists, artist_tracks where tracks.id=plays.track_id AND artists.id=artist_tracks.artist_id AND artist_tracks.track_id=tracks.id #{to_from} group by tracks.id order by cnt DESC limit #{limit}")
  end
  hat = @tracks.collect {|o| {:count => o.cnt, :title => o.title, :artistname => o.artistname,:artistmbid => o.artistmbid, :trackmbid => o.trackmbid} }
  respond_to do |wants|
    wants.html { erb :track_chart }
    wants.xml { builder :track_chart } 
    wants.json { hat.to_json }
   end
end


# chart of top artist by name
get "/#{@version}/chart/artist" do
 to_from = make_to_from(params[:from], params[:to])
 limit = params[:limit]
 limit ||= 10
 channel = params[:channel]
 if !channel.nil?
   @artists = repository(:default).adapter.select("select artists.artistname, artists.id, artist_tracks.artist_id, artists.artistmbid, count(*) as cnt from tracks, plays, artists, artist_tracks where plays.channel_id=#{channel} AND  tracks.id=plays.track_id AND tracks.id=artist_tracks.track_id AND artist_tracks.artist_id=artists.id #{to_from} group by artists.id order by cnt desc limit #{limit}")
 else
   @artists = repository(:default).adapter.select("select artists.artistname, artists.id, artist_tracks.artist_id, artists.artistmbid, count(*) as cnt from tracks, plays, artists, artist_tracks where tracks.id=plays.track_id AND tracks.id=artist_tracks.track_id AND artist_tracks.artist_id=artists.id #{to_from} group by artists.id order by cnt desc limit #{limit}")
 end
 #@artists = repository(:default).adapter.select("select sum(cnt) as count, har.artistname, har.id from (select artists.artistname, artists.id, artist_tracks.artist_id, count(*) as cnt from tracks, plays, artists, artist_tracks where tracks.id=plays.track_id AND tracks.id=artist_tracks.track_id AND artist_tracks.artist_id= artists.id #{to_from} group by tracks.id, plays.playedtime) as har group by har.artistname order by count desc limit #{limit}")
  hat = @artists.collect {|o| {:count => o.cnt, :artistname => o.artistname, :id => o.id, :artistmbid => o.artistmbid} }
 respond_to do |wants|
    wants.html { erb :artist_chart }
    wants.xml { builder :artist_chart }
    wants.json {hat.to_json}
  end
end

get "/#{@version}/chart/album" do
  to_from = make_to_from(params[:played_from], params[:played_to])
  limit = params[:limit]
  limit ||= 10
  channel = params[:channel]
  if !channel.nil?
    @albums = repository(:default).adapter.select("select albums.albumname, albums.albumimage, albums.id as album_id, tracks.id as track_id, albums.albummbid, count(*) as cnt from tracks, plays, albums, album_tracks where plays.channel_id=#{channel} AND tracks.id=plays.track_id AND albums.id=album_tracks.album_id AND album_tracks.track_id=tracks.id #{to_from} group by albums.id order by cnt DESC limit #{limit}")
  else
    @albums = repository(:default).adapter.select("select albums.albumname, albums.albumimage, albums.id as album_id, tracks.id as track_id, albums.albummbid, count(*) as cnt from tracks, plays, albums, album_tracks where tracks.id=plays.track_id AND albums.id=album_tracks.album_id AND album_tracks.track_id=tracks.id #{to_from} group by albums.id order by cnt DESC limit #{limit}")
  end
  hat = @albums.collect {|o| {:count => o.cnt, :albumname => o.albumname, :album_id => o.album_id, :albummbid => o.albummbid,:albumimage => o.albumimage} }
  
  respond_to do |wants|
      wants.xml { builder :album_chart }
      wants.json {hat.to_json}
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
  @artistmbid = (Artist.count(:artistmbid).to_f/@artistcount.to_f)*100
  
  @trackcount = Track.count
  @trackmbid = (Track.count(:trackmbid).to_f/@trackcount.to_f)*100
  
  @playcount = Play.count
  
  @albumcount = Album.count
  @albummbid = (Album.count(:albummbid).to_f/@albumcount.to_f)*100
  
  @dig_track = repository(:default).adapter.select("SELECT COUNT(distinct tracks.id) FROM `tracks` INNER JOIN `plays` ON `tracks`.`id` = `plays`.`track_id` WHERE `plays`.`channel_id` = 1")
  @dig_artist = repository(:default).adapter.select("SELECT COUNT(distinct artists.id) FROM `artists` INNER JOIN `artist_tracks` ON `artists`.`id` = `artist_tracks`.`artist_id` INNER JOIN `tracks` ON `artist_tracks`.`track_id` = `tracks`.`id` INNER JOIN `plays` ON `tracks`.`id` = `plays`.`track_id` WHERE `plays`.`channel_id` = 1")
  @dig_album = repository(:default).adapter.select("SELECT COUNT(distinct albums.id) FROM `albums` INNER JOIN `album_tracks` ON `albums`.`id` = `album_tracks`.`album_id` INNER JOIN `tracks` ON `album_tracks`.`track_id` = `tracks`.`id` INNER JOIN `plays` ON `tracks`.`id` = `plays`.`track_id` WHERE `plays`.`channel_id` = 1")
  @dig_play = Play.all('channel_id'=>1).count
  
  
  @jazz_track = repository(:default).adapter.select("SELECT COUNT(distinct tracks.id) FROM `tracks` INNER JOIN `plays` ON `tracks`.`id` = `plays`.`track_id` WHERE `plays`.`channel_id` = 2")
  @jazz_artist = repository(:default).adapter.select("SELECT COUNT(distinct artists.id) FROM `artists` INNER JOIN `artist_tracks` ON `artists`.`id` = `artist_tracks`.`artist_id` INNER JOIN `tracks` ON `artist_tracks`.`track_id` = `tracks`.`id` INNER JOIN `plays` ON `tracks`.`id` = `plays`.`track_id` WHERE `plays`.`channel_id` = 2")
  @jazz_album = repository(:default).adapter.select("SELECT COUNT(distinct albums.id) FROM `albums` INNER JOIN `album_tracks` ON `albums`.`id` = `album_tracks`.`album_id` INNER JOIN `tracks` ON `album_tracks`.`track_id` = `tracks`.`id` INNER JOIN `plays` ON `tracks`.`id` = `plays`.`track_id` WHERE `plays`.`channel_id` = 2")
  @jazz_play = Play.all('channel_id'=>2).count
  
  
  @country_track = repository(:default).adapter.select("SELECT COUNT(distinct tracks.id) FROM `tracks` INNER JOIN `plays` ON `tracks`.`id` = `plays`.`track_id` WHERE `plays`.`channel_id` = 3")
  @country_artist = repository(:default).adapter.select("SELECT COUNT(distinct artists.id) FROM `artists` INNER JOIN `artist_tracks` ON `artists`.`id` = `artist_tracks`.`artist_id` INNER JOIN `tracks` ON `artist_tracks`.`track_id` = `tracks`.`id` INNER JOIN `plays` ON `tracks`.`id` = `plays`.`track_id` WHERE `plays`.`channel_id` = 3")
  @country_album = repository(:default).adapter.select("SELECT COUNT(distinct albums.id) FROM `albums` INNER JOIN `album_tracks` ON `albums`.`id` = `album_tracks`.`album_id` INNER JOIN `tracks` ON `album_tracks`.`track_id` = `tracks`.`id` INNER JOIN `plays` ON `tracks`.`id` = `plays`.`track_id` WHERE `plays`.`channel_id` = 3")
  @country_play = Play.all('channel_id'=>3).count
  
  
  @jjj_track = repository(:default).adapter.select("SELECT COUNT(distinct tracks.id) FROM `tracks` INNER JOIN `plays` ON `tracks`.`id` = `plays`.`track_id` WHERE `plays`.`channel_id` = 4")
  @jjj_artist = repository(:default).adapter.select("SELECT COUNT(distinct artists.id) FROM `artists` INNER JOIN `artist_tracks` ON `artists`.`id` = `artist_tracks`.`artist_id` INNER JOIN `tracks` ON `artist_tracks`.`track_id` = `tracks`.`id` INNER JOIN `plays` ON `tracks`.`id` = `plays`.`track_id` WHERE `plays`.`channel_id` = 4")
  @jjj_album = repository(:default).adapter.select("SELECT COUNT(distinct albums.id) FROM `albums` INNER JOIN `album_tracks` ON `albums`.`id` = `album_tracks`.`album_id` INNER JOIN `tracks` ON `album_tracks`.`track_id` = `tracks`.`id` INNER JOIN `plays` ON `tracks`.`id` = `plays`.`track_id` WHERE `plays`.`channel_id` = 4")
  @jjj_play = Play.all('channel_id'=>4).count
   
  respond_to do |wants|
    wants.html { erb :stats }
  end

end