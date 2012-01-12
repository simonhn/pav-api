module V1
class PavApi < Sinatra::Base

#show all artists, defaults to 10, ordered by created date
get "/artists" do
  limit = get_limit(params[:limit])
  channel = params[:channel]
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
get "/artist/:id" do
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

get "/artist/:id/details" do
  result = Hash.new
  
  #if no channel parameter provided, we assume all channels
  channel = get_channel(params[:channel])
  if params[:type] == 'mbid' || params[:id].length == 36
     @artist = Artist.first(:artistmbid => params[:id])
  else
     @artist = Artist.get(params[:id])
  end
  
  artist_result = Hash.new
  artist_result['artist_id'] = @artist.id
  artist_result['artistname'] = @artist.artistname
  result["artist"] = artist_result
    
  @play_count = repository(:default).adapter.select("SELECT plays.playedtime, tracks.title FROM `artists` INNER JOIN `artist_tracks` ON `artists`.`id` = `artist_tracks`.`artist_id` INNER JOIN `tracks` ON `artist_tracks`.`track_id` = `tracks`.`id` INNER JOIN `plays` ON `tracks`.`id` = `plays`.`track_id` WHERE `artists`.`id` = #{@artist.id} #{channel} order by playedtime")
  
  if !@play_count.empty?
    @tracks = repository(:default).adapter.select("SELECT count(plays.id) as play_count, tracks.title, tracks.id FROM `artists` INNER JOIN `artist_tracks` ON `artists`.`id` = `artist_tracks`.`artist_id` INNER JOIN `tracks` ON `artist_tracks`.`track_id` = `tracks`.`id` INNER JOIN `plays` ON `tracks`.`id` = `plays`.`track_id` WHERE `artists`.`id` = #{@artist.id} #{channel} group by tracks.id order by playedtime")
    result["tracks"] = @tracks.collect {|o| {:count => o.play_count, :title => o.title, :track_id => o.id} }
    
    @albums = @artist.tracks.albums
    result["albums"]  = @albums.collect {|o| {:album_id => o.id, :albumname => o.albumname, :albumimage => o.albumimage} }  
    
    result["play_count"] = @play_count.size
    
    programs = repository(:default).adapter.select("select count(plays.id) as play_count, program_id from plays, tracks, artist_tracks, artists where artists.id=#{@artist.id} AND artists.id = artist_tracks.artist_id AND artist_tracks.track_id=tracks.id and tracks.id=plays.track_id AND plays.program_id !='' group by program_id")
    result["programs"] = programs.collect {|o| {:play_count => o.play_count, :program_id => o.program_id} }
    
    first_play = @play_count.first
    #puts 'first played on '+Time.parse(first_play.playedtime.to_s).to_s
    result["first_play"] = Time.parse(first_play.playedtime.to_s).to_s

    last_play = @play_count.last
    #puts 'last played on '+Time.parse(last_play.playedtime.to_s).to_s
    result["last_play"] = Time.parse(last_play.playedtime.to_s).to_s
    
    average_duration = @artist.tracks.avg(:duration)
    #puts 'average track duration '+average_duration.inspect
    result["avg_duration"] = average_duration

    australian = @artist.tracks.first.aust
    #puts 'australian? '+australian.inspect
    result["australian"] = australian

    @artist_chart = repository(:default).adapter.select("select artists.artistname, artists.id, artist_tracks.artist_id, artists.artistmbid, count(*) as cnt from tracks, plays, artists, artist_tracks where tracks.id=plays.track_id AND tracks.id=artist_tracks.track_id AND artist_tracks.artist_id=artists.id #{channel} group by artists.id order by cnt desc")
    index_number = @artist_chart.index{|x|x[:id]==@artist.id}
    real_index = 1+index_number.to_i
    #puts 'Position on all time chart '+real_index.to_s
    result["chart_pos"] = real_index
    
    #@play_count_range, divides last - first into 10 time slots
    if @play_count.size > 1 #only makes sense if more than one play
      @time_range = (Time.parse(last_play.playedtime.to_s) - Time.parse(first_play.playedtime.to_s))
      @slice = @time_range / 10
      hat = Time.parse(first_play.playedtime.to_s)
      i = 0
      result_array = []

      while i < 10 do
         from = hat
         hat = hat + @slice
         to = hat
         to_from = "AND playedtime <= '#{to.strftime("%Y-%m-%d %H:%M:%S")}' AND playedtime >= '#{from.strftime("%Y-%m-%d %H:%M:%S")}'"
         @play_counter = repository(:default).adapter.select("SELECT plays.playedtime, tracks.title FROM `artists` INNER JOIN `artist_tracks` ON `artists`.`id` = `artist_tracks`.`artist_id` INNER JOIN `tracks` ON `artist_tracks`.`track_id` = `tracks`.`id` INNER JOIN `plays` ON `tracks`.`id` = `plays`.`track_id` WHERE `artists`.`id` = #{@artist.id} #{channel} #{to_from} order by playedtime")
         item = Hash.new
         item["from"] = from.to_s
         item["to"] = to.to_s
         item["count"] = @play_counter.size.to_s
         result_array[i] = item
         i += 1
      end
      #puts 'time sliced play count '+result_array.inspect
      result["time_sliced"] = result_array
      
      #average play counts per week from first played to now
      #@play_count.size
      @new_time_range = (Time.now - Time.parse(first_play.playedtime.to_s))
      avg = @play_count.size/(@new_time_range/(60*60*24*7))
      #puts 'avg plays per week '+ avg.to_s
      result["avg_play_week"] = avg
    else
      #when only 1 play:
      result["time_sliced"] = []
      result["avg_play_week"] = 0    
    end

    #played on other channels?
    channel_result = Hash.new
    channels = Channel.all
    channels.each do |channel|
      q = repository(:default).adapter.select("SELECT count(*) FROM `artists` INNER JOIN `artist_tracks` ON `artists`.`id` = `artist_tracks`.`artist_id` INNER JOIN `tracks` ON `artist_tracks`.`track_id` = `tracks`.`id` INNER JOIN `plays` ON `tracks`.`id` = `plays`.`track_id` WHERE `artists`.`id` = #{@artist.id} AND plays.channel_id=#{channel.id}")
      if q.first.to_i>0
        channel_result[channel.channelname] = q.first
        #puts 'played on ' + channel.channelname+' '+q.first.to_s+' times'
      end
    end
    result["channels"] = channel_result
    @res = result
  end
  respond_to do |wants|
    wants.json { result.to_json }
  end
end
# edit artist from id. if ?type=mbid is added, it will perform a mbid lookup
get "/artist/:id/edit" do
  protected!
  if params[:type] == 'mbid' || params[:id].length == 36
     @artist = Artist.first(:artistmbid => params[:id])
  else
     @artist = Artist.get(params[:id])
  end
  respond_to do |wants|
    wants.html { erb :artist_edit }
  end
end

post "/artist/:id/edit" do
  protected!
  @artist = Artist.get(params[:id])
  raise not_found unless @artist
  
  @artist.attributes = {
    :artistname => params["artistname"],
    :artistmbid => params["artistmbid"],
    :artistlink => params["artistlink"],
    :artistnote => params["artistnote"]
  }    
  @artist.save
  redirect "/#{options.version}/artist/#{@artist.id}"
end


# show tracks from artist
get "/artist/:id/tracks" do
  if params[:type] == 'mbid' || params[:id].length == 36
    @artist = Artist.first(:artistmbid => params[:id])
  else
    @artist = Artist.get(params[:id])
  end
  @tracks = @artist.tracks
  @tracks_json = repository(:default).adapter.select("SELECT count(plays.id) as play_count, tracks.title FROM `artists` INNER JOIN `artist_tracks` ON `artists`.`id` = `artist_tracks`.`artist_id` INNER JOIN `tracks` ON `artist_tracks`.`track_id` = `tracks`.`id` INNER JOIN `plays` ON `tracks`.`id` = `plays`.`track_id` WHERE `artists`.`id` = #{@artist.id} group by tracks.id order by playedtime")
    
  respond_to do |wants|
    wants.html { erb :artist_tracks }
    wants.xml { builder :artist_tracks }
    wants.json { @tracks_json.to_json }   
  end
end

# show albums from artist
get "/artist/:id/albums" do
  if params[:type] == 'mbid' || params[:id].length == 36
    @artist = Artist.first(:artistmbid => params[:id])
  else
    @artist = Artist.get(params[:id])
  end
  @albums = @artist.tracks.albums
  
  respond_to do |wants|
    wants.html { erb :artist_albums }
    wants.xml { builder :artist_albums }
    wants.json { @albums.to_json }
  end
end

# show plays from artist
get "/artist/:id/plays" do
  if params[:type] == 'mbid' || params[:id].length == 36
    @artist = Artist.first(:artistmbid => params[:id])
  else
    @artist = Artist.get(params[:id])
  end
  channel = params[:channel]
  limit = get_limit(params[:limit])
    if channel

     @plays = repository(:default).adapter.select("select * from tracks Left Outer Join album_tracks ON album_tracks.track_id = tracks.id Left Outer Join albums ON album_tracks.album_id = albums.id Inner Join artist_tracks ON artist_tracks.track_id = tracks.id Inner Join artists ON artists.id = artist_tracks.artist_id Inner Join plays ON tracks.id = plays.track_id WHERE `plays`.`channel_id` = #{channel} AND artists.id=#{@artist.id} group by tracks.id, plays.playedtime order by plays.playedtime limit #{limit}")
  else
    @plays = repository(:default).adapter.select("select * from tracks Left Outer Join album_tracks ON album_tracks.track_id = tracks.id Left Outer Join albums ON album_tracks.album_id = albums.id Inner Join artist_tracks ON artist_tracks.track_id = tracks.id Inner Join artists ON artists.id = artist_tracks.artist_id Inner Join plays ON tracks.id = plays.track_id WHERE tracks.id AND artists.id=#{@artist.id} group by tracks.id, plays.playedtime order by plays.playedtime limit #{limit}")
  end
  hat = @plays.collect {|o| {:title => o.title, :track_id => o.track_id, :trackmbid => o.trackmbid, :artistname => o.artistname, :artist_id => o.artist_id, :artistmbid => o.artistmbid, :playedtime => o.playedtime, :albumname => o.albumname, :albumimage => o.albumimage, :album_id => o.album_id, :albummbid => o.albummbid, :program_id => o.program_id, :channel_id => o.channel_id} }
  respond_to do |wants|
    wants.html { erb :artist_plays }
    wants.xml { builder :artist_plays }
    wants.json { hat.to_json }
  end
end
end
end