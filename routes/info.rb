module V1
class PavApi < Sinatra::Base

get "/info" do
    respond_to do |wants|
    	wants.html { erb :info }
    end
end

end
end
