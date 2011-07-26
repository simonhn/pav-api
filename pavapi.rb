#core stuff
require 'rubygems'
require 'sinatra'
require './models'
require './store_methods'

#Queueing with delayed job
#require 'delayed_job'
#require 'delayed_job_data_mapper'
#require './storetrackjob'
require 'stalker'

#template systems
require 'yajl/json_gem'
require 'rack/contrib/jsonp'
require 'builder'
use Rack::JSONP

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

# Enable New Relic    
#configure :production do
  #require 'newrelic_rpm'
#end

#throttling
#require 'rack/throttle'
#require 'memcached'
#require './throttler'

#for serving different content types
require 'sinatra/respond_to'
Sinatra::Application.register Sinatra::RespondTo

#versioning
@version = "v1"

configure do
  #use Throttler, :min => 300.0, :cache => Memcached.new, :key_prefix => :throttle
  #use Rack::Throttle::Throttler, :min => 1.0, :cache => Memcached.new, :key_prefix => :throttle
  
  #logging
  DataMapper::Logger.new('log/datamapper.log', :warn)
  DataMapper::Model.raise_on_save_failure = true
  $LOG = Logger.new('log/pavstore.log', 'monthly')
  
  # MySQL connection:
  @config = YAML::load( File.open( 'config/settings.yml' ) )
  @connection = "#{@config['adapter']}://#{@config['username']}:#{@config['password']}@#{@config['host']}/#{@config['database']}";
  DataMapper.setup(:default, @connection)  
  DataMapper.finalize
  
  #DataMapper.auto_upgrade!
  #DataMapper::auto_migrate!
  set :default_content, :html
end

#Caching 1 minute - must adjust
before '/*' do
  cache_control :public, :must_revalidate, :max_age => 60 unless development?
end

before '/demo/*' do
  cache_control :public, :must_revalidate, :max_age => 3600 unless development?
end

before '*/chart/*' do
  cache_control :public, :must_revalidate, :max_age => 3600 unless development?
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
        from_date = played_to - 7

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
    
    def get_channel(cha)
      if isNumeric(cha)
        channel = cha
      elsif cha.nil?
        channel = false
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
        return "plays.channel_id=#{channel} AND"
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
  limit = get_limit(params[:limit])
  channel = get_channel(params[:channel])
  if channel
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
      Stalker.enqueue('track.store', :item => data['item'],:channel => data['channel'])
      
      #Delayed::Job.enqueue StoreTrackJob.new(data['item'], data['channel'])    
      #store_hash(data['item'], data['channel'])
   end
   
   rescue StandardError => e 
      $LOG.info("Post method end: Issue while processing #{data['item']['artist']['artistname']} - #{data['channel']},  #{e.backtrace}")
   end
end

#show tracks
get "/#{@version}/tracks" do
  limit = get_limit(params[:limit])
  channel = params[:channel]
  if channel
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
  limit = get_limit(params[:limit])
  channel = params[:channel]
  if channel
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
  artist_query = get_artist_query(params[:artist_query])
  track_query = get_track_query(params[:track_query])
  album_query = get_album_query(params[:album_query])
  query_all = get_all_query(params[:q])
  order_by = get_order_by(params[:order_by])
  limit = get_limit(params[:limit])
  to_from = make_to_from(params[:from], params[:to])
  channel = params[:channel]
  if channel
     #@plays = repository(:default).adapter.select("select * from tracks, plays, artists, artist_tracks, albums, album_tracks  where plays.channel_id=#{channel} AND tracks.id=plays.track_id AND artists.id=artist_tracks.artist_id AND artist_tracks.track_id=tracks.id AND albums.id = album_tracks.album_id AND tracks.id = album_tracks.track_id #{to_from} group by tracks.id, plays.playedtime order by plays.playedtime DESC limit #{limit}")
     @plays = repository(:default).adapter.select("select * from tracks Left Outer Join album_tracks ON album_tracks.track_id = tracks.id Left Outer Join albums ON album_tracks.album_id = albums.id Inner Join artist_tracks ON artist_tracks.track_id = tracks.id Inner Join artists ON artists.id = artist_tracks.artist_id Inner Join plays ON tracks.id = plays.track_id WHERE `plays`.`channel_id` = #{channel} #{to_from} #{artist_query} #{album_query} #{track_query} #{query_all} group by tracks.id, plays.playedtime order by #{order_by} limit #{limit}")
  else
    #@plays = repository(:default).adapter.select("select * from tracks, plays, artists, artist_tracks, albums, album_tracks  where tracks.id=plays.track_id AND artists.id=artist_tracks.artist_id AND artist_tracks.track_id=tracks.id AND albums.id = album_tracks.album_id AND tracks.id = album_tracks.track_id #{to_from} group by tracks.id, plays.playedtime order by plays.playedtime DESC limit #{limit}")
    @plays = repository(:default).adapter.select("select * from tracks Left Outer Join album_tracks ON album_tracks.track_id = tracks.id Left Outer Join albums ON album_tracks.album_id = albums.id Inner Join artist_tracks ON artist_tracks.track_id = tracks.id Inner Join artists ON artists.id = artist_tracks.artist_id Inner Join plays ON tracks.id = plays.track_id WHERE tracks.id #{to_from} #{artist_query} #{album_query} #{track_query} #{query_all} group by tracks.id, plays.playedtime order by #{order_by} limit #{limit}")
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
  limit = get_limit(params[:limit])
  to_from = make_to_from(params[:from], params[:to])
  channel = get_channel(params[:channel])
  #SELECT tracks.title, artists.artistname, count(*) as cnt FROM `tracks` INNER JOIN `plays` ON `tracks`.`id` = `plays`.`track_id` INNER JOIN artist_tracks ON tracks.id=artist_tracks.track_id INNER JOIN artists ON artists.id=artist_tracks.artist_id WHERE `plays`.`channel_id` = 1 group by tracks.id   order by cnt DESC limit 10;
  @tracks = repository(:default).adapter.select("select *, count(distinct plays.id) as cnt from tracks, plays, artists, artist_tracks where #{channel} tracks.id=plays.track_id AND artists.id=artist_tracks.artist_id AND artist_tracks.track_id=tracks.id #{to_from} group by tracks.id order by cnt DESC limit #{limit}")
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
 limit = get_limit(params[:limit])
 channel = get_channel(params[:channel])
 @artists = repository(:default).adapter.select("select artists.artistname, artists.id, artist_tracks.artist_id, artists.artistmbid, count(*) as cnt from tracks, plays, artists, artist_tracks where #{channel} tracks.id=plays.track_id AND tracks.id=artist_tracks.track_id AND artist_tracks.artist_id=artists.id #{to_from} group by artists.id order by cnt desc limit #{limit}")
 
 #@artists = repository(:default).adapter.select("select sum(cnt) as count, har.artistname, har.id from (select artists.artistname, artists.id, artist_tracks.artist_id, count(*) as cnt from tracks, plays, artists, artist_tracks where tracks.id=plays.track_id AND tracks.id=artist_tracks.track_id AND artist_tracks.artist_id= artists.id #{to_from} group by tracks.id, plays.playedtime) as har group by har.artistname order by count desc limit #{limit}")
  hat = @artists.collect {|o| {:count => o.cnt, :artistname => o.artistname, :id => o.id, :artistmbid => o.artistmbid} }
 respond_to do |wants|
    wants.html { erb :artist_chart }
    wants.xml { builder :artist_chart }
    wants.json {hat.to_json}
  end
end

get "/#{@version}/chart/album" do
  to_from = make_to_from(params[:from], params[:to])
  limit = get_limit(params[:limit])
  channel = get_channel(params[:channel])
  @albums = repository(:default).adapter.select("select artists.artistname, artists.artistmbid, albums.albumname, albums.albumimage, albums.id as album_id,  albums.albummbid, count(distinct plays.id) as cnt from tracks, artists, plays, albums, album_tracks, artist_tracks where #{channel} tracks.id=plays.track_id AND albums.id=album_tracks.album_id AND album_tracks.track_id=tracks.id AND tracks.id=artist_tracks.track_id AND artists.id=artist_tracks.artist_id #{to_from} group by albums.id order by cnt DESC limit #{limit}")
  hat = @albums.collect {|o| {:count => o.cnt, :artistname => o.artistname, :artistmbid => o.artistmbid, :albumname => o.albumname, :album_id => o.album_id, :albummbid => o.albummbid,:albumimage => o.albumimage} }
  
  respond_to do |wants|
      wants.html { erb :album_chart }
      wants.xml { builder :album_chart }
      wants.json {hat.to_json}
  end
end

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

get "/#{@version}/admin/merge-artists" do
  protected!
  respond_to do |wants|
    wants.html { erb :merge_artists }
  end
end

post "/#{@version}/admin/merge-artists" do
   protected!
   old_artist = Artist.get(params[:id_old])
   new_artist = Artist.get(params[:id_new])
   
   if(old_artist&&new_artist)
     #move tracks from old artist to new artist
     link = ArtistTrack.all(:artist_id => old_artist.id)
     link.each{ |link_item|
       @track_load = Track.get(link_item.track_id)
       @moved = new_artist.tracks << @track_load
       @moved.save
     }
  
     #delete old artist_track relations
     link.destroy!
   
     #delete old artist
     old_artist.destroy!
   end
end


get '/demo/album-charts' do
  from_date = DateTime.now - 7
  @from_date_string = from_date.strftime("%b %e")
  
  to_date = DateTime.now
  @to_date_string = to_date.strftime("%b %e")
  
  respond_to do |wants|
    wants.html{erb :album_chart_all}
  end
end

get '/jjj' do
  cache_control :public, :max_age => 600
  artistmbid = {}
  har ='a'
  hur = 'b'
   @artists = repository(:default).adapter.select("select artists.artistname, artists.id, artist_tracks.artist_id, artists.artistmbid, count(*) as cnt from tracks, plays, artists, artist_tracks where plays.channel_id=4 AND  tracks.id=plays.track_id AND tracks.id=artist_tracks.track_id AND artist_tracks.artist_id=artists.id group by artists.id order by cnt desc limit 10")
   #hat = @artists.collect {|o| {:count => o.cnt, :artistname => o.artistname, :id => o.id, :artistmbid => o.artistmbid} }
all = Hash.new
   @artists.each{ |o| 
     begin
       if o.artistmbid
         #puts o.artistname
         begin
            result = RestClient.get 'http://www.abc.net.au/triplej/media/artists/'+o.artistmbid+'/all-media.xml'

         if(result.code==200)
           all[o.artistname] = Hash.new
           all[o.artistname].store("media",Hash.new())
           all[o.artistname].store("info",Hash.new())
           all[o.artistname].fetch("info").store("mbid",o.artistmbid)
           all[o.artistname].fetch("info").store("count",o.cnt)
           xml = Crack::XML.parse(result)
           if(xml["rss"]["channel"]["item"].kind_of?(Array))
             xml["rss"]["channel"]["item"].each_with_index{|ha,i|
               if !ha["title"].empty? && !ha["media:thumbnail"].first.nil?           
                 har = ha["title"]
                 da = ha["media:thumbnail"]
                 if da.kind_of?(Array)
                   hur = da.first["url"]
                   all[o.artistname].fetch("media").store(ha["title"],hur)              
                 else
                   hur = da["url"]
                   all[o.artistname].fetch("media").store(ha["title"],hur)      
                 end
                 if ha["media:content"].kind_of?(Array)
                   all[o.artistname].fetch("media").store(ha["media:content"].first["medium"],ha["media:content"].first["url"]) 
                 else
                   all[o.artistname].fetch("media").store(ha["media:content"]["medium"],ha["media:content"]["url"]) 
                   
                 end
               end
             }
           else
             if(!xml["rss"]["channel"]["item"]["title"].nil? && !xml["rss"]["channel"]["item"]["media:thumbnail"]["url"].nil?)
               har = xml["rss"]["channel"]["item"]["title"]
               hur = xml["rss"]["channel"]["item"]["media:thumbnail"]["url"]
            end
           end
           #john = @artists.map {|o| {:count => o.cnt, :artistname => o.artistname, :id => o.id, :artistmbid => o.artistmbid, :media=> {:title => har.to_s, :thumb=>hur.to_s}} }
           #puts john.inspect
         end
         rescue => e
         end
       end
    end
    }
    @hat = all
    respond_to do |wants|
      wants.html { erb :jjj }  
      wants.json { all.to_json }  
    end
end