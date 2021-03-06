module V1
class PavApi < Sinatra::Base

#PLAY
get "/plays" do
  #DATE_FORMAT(playedtime, '%d %m %Y %H %i %S')
  artist_query = get_artist_query(params[:artist_query])
  track_query = get_track_query(params[:track_query])
  album_query = get_album_query(params[:album_query])
  query_all = get_all_query(params[:q])
  order_by = get_order_by(params[:order_by])
  order = get_order(params[:order])
  limit = get_limit(params[:limit])
  to_from = make_to_from(params[:from], params[:to])
  channel = get_channel(params[:channel]);
  program = get_program(params[:program])
  puts order_by
  if artist_query or album_query or query_all or params[:order_by]=='artist'
    @plays = repository(:default).adapter.select("select * from tracks Left Outer Join album_tracks ON album_tracks.track_id = tracks.id Left Outer Join albums ON album_tracks.album_id = albums.id Inner Join artist_tracks ON artist_tracks.track_id = tracks.id Inner Join artists ON artists.id = artist_tracks.artist_id Inner Join plays ON tracks.id = plays.track_id WHERE plays.id #{channel} #{to_from} #{artist_query} #{album_query} #{track_query} #{query_all} #{program} order by #{order_by} #{order} limit #{limit}")
  else
    @plays = repository(:default).adapter.select("select * from (select plays.playedtime, plays.program_id, plays.channel_id, tracks.id, tracks.title, tracks.trackmbid, tracks.tracknote, tracks.tracklink, tracks.show, tracks.talent, tracks.aust, tracks.duration, tracks.publisher,tracks.datecopyrighted, tracks.created_at from tracks,plays where tracks.id = plays.track_id #{channel} #{to_from} #{track_query} #{program} order by #{order_by} #{order} limit #{limit}) as tracks Left Outer Join album_tracks ON album_tracks.track_id = tracks.id Left Outer Join albums ON album_tracks.album_id = albums.id Inner Join artist_tracks ON artist_tracks.track_id = tracks.id Inner Join artists ON artists.id = artist_tracks.artist_id")
  end

  hat = @plays.collect {|o| {:title => o.title, :track_id => o.track_id, :trackmbid => o.trackmbid, :artistname => o.artistname, :artist_id => o.artist_id, :artistmbid => o.artistmbid, :playedtime => o.playedtime, :albumname => o.albumname, :albumimage => o.albumimage, :album_id => o.album_id, :albummbid => o.albummbid, :program_id => o.program_id, :channel_id => o.channel_id} }
  
  respond_to do |wants|
    wants.html { erb :plays }
    wants.xml { builder :plays }
    wants.json { hat.to_json }
  end
end

get "/play/:id" do
@play = Play.get(params[:id])
  respond_to do |wants|
    wants.json { @play.to_json }
  end
end
end
end