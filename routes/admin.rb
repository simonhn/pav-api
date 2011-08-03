#admin dashboard
get "/admin" do
  protected!
  respond_to do |wants|
    wants.html { erb :admin }
  end
end

#Count all artists
get "/admin/stats" do
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

get "/admin/duplicate/artist" do
  protected!
  @list = repository(:default).adapter.select("SELECT distinct d2.id, d2.artistname, d2.artistmbid FROM artists d1 JOIN artists d2 ON d2.artistname = d1.artistname AND d2.id <> d1.id order by artistname, id")
  respond_to do |wants|
    wants.html { erb :duplicate_artists }
  end
end

post "/admin/merge/artist" do
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

get "/admin/duplicate/album" do
  protected!
  @list = repository(:default).adapter.select("SELECT distinct d2.id, d2.albumname, d2.albummbid FROM albums d1 JOIN albums d2 ON d2.albumname = d1.albumname AND d2.id <> d1.id order by albumname, id")
  respond_to do |wants|
    wants.html { erb :duplicate_albums }
  end
end

post "/admin/merge/album" do
   protected!
   
   old_album = Album.get(params[:id_old])
   old_album_tracks = old_album.tracks

   new_album = Album.get(params[:id_new])
   new_album_tracks = new_album.tracks
   
   if(old_album&&new_album)
     
     #if there are similar track on the two albums, 
     # move the 'old' tracks to the 'new' tracks before moving album links
     old_album_tracks.each{ |old_track|
       new_track = new_album_tracks.find {|e| e.title==old_track.title&&e.id!=old_track.id }
       if(new_track)
         merge_tracks(old_track.id, new_track.id) 
       end
     } 
   
     #move tracks from old album to new album
      link = AlbumTrack.all(:album_id => old_album.id)
      link.each{ |link_item|
        @track_load = Track.get(link_item.track_id)
        @moved = new_album.tracks << @track_load
        @moved.save
      }
 
      #delete old album_track relations
      link.destroy!
  
      #delete old album
      old_album.destroy!
   end
   
end

get "/admin/duplicate/track" do
  protected!
  @list = repository(:default).adapter.select("SELECT distinct d2.id, d2.title, d2.trackmbid FROM tracks d1 JOIN tracks d2 ON d2.title = d1.title AND d2.id <> d1.id order by title, id")
  respond_to do |wants|
    wants.html { erb :duplicate_tracks }
  end
end

post "/admin/merge/track" do
   protected!
   
   merge_tracks(params[:id_old], params[:id_new]) 
end