class PavApi < Sinatra::Base

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

# edit track from id. if ?type=mbid is added, it will perform a mbid lookup
get "/#{@version}/track/:id/edit" do
  protected!
  if params[:type] == 'mbid' || params[:id].length == 36
     @track = Track.first(:trackmbid => params[:id])
  else
     @track = Track.get(params[:id])
  end
  respond_to do |wants|
    wants.html { erb :track_edit }
  end
end

post "/#{@version}/track/:id/edit" do
  protected!
  @track = Track.get(params[:id])  
  raise not_found unless @track
  
  @track.attributes = {
      :title            => params["title"],
      :trackmbid        => params["trackmbid"],
      :tracklink        => params["tracklink"],
      :tracknote        => params["tracknote"],
      :talent           => params["talent"],
      :aust             => params["aust"],
      :datecopyrighted  => params["datecopyrighted"],
      :show             => params["show"],
      :publisher        => params["publisher"],
      :created_at       => params["created_at"]
    }

  @track.save
  redirect "/v1/track/#{@track.id}"
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
end