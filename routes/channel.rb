class PavApi < Sinatra::Base

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
end