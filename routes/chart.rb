# chart of top tracks
get "/#{@version}/chart/track" do
  program = get_program(params[:program])
  limit = get_limit(params[:limit])
  to_from = make_to_from(params[:from], params[:to])
  channel = get_channel(params[:channel])
  @tracks = repository(:default).adapter.select("select *, cnt from (select tracks.id, tracks.title, tracks.trackmbid, tracks.tracknote, tracks.tracklink, tracks.show, tracks.talent, tracks.aust, tracks.duration, tracks.publisher,tracks.datecopyrighted, tracks.created_at, count(*) as cnt from tracks,plays where tracks.id = plays.track_id #{channel} #{to_from} #{program} group by tracks.id order by cnt DESC limit #{limit}) as tracks Left Outer Join album_tracks ON album_tracks.track_id = tracks.id Left Outer Join albums ON album_tracks.album_id = albums.id Inner Join artist_tracks ON artist_tracks.track_id = tracks.id Inner Join artists ON artists.id = artist_tracks.artist_id")
  hat = @tracks.collect {|o| {:count => o.cnt, :title => o.title, :track_id => o.id, :artistname => o.artistname,:artistmbid => o.artistmbid, :trackmbid => o.trackmbid, :albumname => o.albumname, :albummbid => o.albummbid, :albumimage => o.albumimage} }
  respond_to do |wants|
    wants.html { erb :track_chart }
    wants.xml { builder :track_chart } 
    wants.json { hat.to_json }
   end
end


# chart of top artist by name
get "/#{@version}/chart/artist" do
 program = get_program(params[:program])
 to_from = make_to_from(params[:from], params[:to])
 limit = get_limit(params[:limit])
 channel = get_channel(params[:channel])
 @artists = repository(:default).adapter.select("select artists.id, artists.artistname, artists.artistmbid,count(*) as cnt from (select artist_tracks.artist_id from plays, tracks, artist_tracks where tracks.id=plays.track_id AND tracks.id=artist_tracks.track_id #{channel} #{to_from} #{program}) as artist_tracks, artists where artist_tracks.artist_id=artists.id group by artists.id order by cnt desc limit #{limit}")
 
 #@artists = repository(:default).adapter.select("select sum(cnt) as count, har.artistname, har.id from (select artists.artistname, artists.id, artist_tracks.artist_id, count(*) as cnt from tracks, plays, artists, artist_tracks where tracks.id=plays.track_id AND tracks.id=artist_tracks.track_id AND artist_tracks.artist_id= artists.id #{to_from} group by tracks.id, plays.playedtime) as har group by har.artistname order by count desc limit #{limit}")
  hat = @artists.collect {|o| {:count => o.cnt, :artistname => o.artistname, :id => o.id, :artistmbid => o.artistmbid} }
 respond_to do |wants|
    wants.html { erb :artist_chart }
    wants.xml { builder :artist_chart }
    wants.json {hat.to_json}
  end
end

get "/#{@version}/chart/album" do
  program = get_program(params[:program])
  to_from = make_to_from(params[:from], params[:to])
  limit = get_limit(params[:limit])
  channel = get_channel(params[:channel])
  @albums = repository(:default).adapter.select("select artists.artistname, artists.artistmbid, albums.albumname, albums.albumimage, albums.id as album_id,  albums.albummbid, count(distinct plays.id) as cnt from tracks, artists, plays, albums, album_tracks, artist_tracks where tracks.id=plays.track_id AND albums.id=album_tracks.album_id AND album_tracks.track_id=tracks.id AND tracks.id=artist_tracks.track_id AND artists.id=artist_tracks.artist_id #{channel} #{to_from} #{program} group by albums.id order by cnt DESC limit #{limit}")
  hat = @albums.collect {|o| {:count => o.cnt, :artistname => o.artistname, :artistmbid => o.artistmbid, :albumname => o.albumname, :album_id => o.album_id, :albummbid => o.albummbid,:albumimage => o.albumimage} }
  
  respond_to do |wants|
      wants.html { erb :album_chart }
      wants.xml { builder :album_chart }
      wants.json {hat.to_json}
  end
end