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

# edit track from id. if ?type=mbid is added, it will perform a mbid lookup
get "/#{@version}/album/:id/edit" do
  protected!
  if params[:type] == 'mbid' || params[:id].length == 36
     @album = Album.first(:albummbid => params[:id])
  else
     @album = Album.get(params[:id])
  end
  respond_to do |wants|
    wants.html { erb :album_edit }
  end
end

post "/#{@version}/album/:id/edit" do
  protected!
  @album = Album.get(params[:id])  
  raise not_found unless @album
  
  @album.attributes = {
      :albumname  => params["albumname"],
      :albummbid  => params["albummbid"],
      :albumimage => params["albumimage"],
      :created_at => params["created_at"]
    }
  
  @album.save
  redirect "/v1/album/#{@album.id}"
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
