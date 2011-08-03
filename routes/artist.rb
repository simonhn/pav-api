#show all artists, defaults to 10, ordered by created date
get "/#{@version}/artists" do
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

# edit artist from id. if ?type=mbid is added, it will perform a mbid lookup
get "/#{@version}/artist/:id/edit" do
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

post "/#{@version}/artist/:id/edit" do
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
  redirect "/v1/artist/#{@artist.id}"
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