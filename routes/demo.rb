class PavApi < Sinatra::Base

get '/demo/?' do
  respond_to do |wants|
    wants.html{erb :demo}
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

get '/demo/program-chart' do
  redirect '/demo/program-chart/track'
end

get '/demo/program-chart/track' do
  @program = params[:program]
  @program ||= 'super_request'
  @span = params[:span]
  @span ||= 7
  respond_to do |wants|
    wants.html{erb :program_chart_track}
  end
end

get '/demo/program-chart/artist' do
  @program = params[:program]
  @program ||= 'super_request'
  @span = params[:span]
  @span ||= 7
  respond_to do |wants|
    wants.html{erb :program_chart_artist}
  end
end

get '/demo/program-chart/artist-expand' do
  @program = params[:program]
  @program ||= 'super_request'
  @span = params[:span]
  @span ||= 7
  respond_to do |wants|
    wants.html{erb :program_chart_artist_expand}
  end
end

get '/demo/program-chart/album' do
  @program = params[:program]
  @program ||= 'super_request'
  @span = params[:span]
  @span ||= 7
  respond_to do |wants|
    wants.html{erb :program_chart_album}
  end
end

get '/demo/jjj' do
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
end
