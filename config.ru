require File.join(File.dirname(__FILE__), 'pavapi.rb')
use Rack::JSONP
map "/v1" do
	run V1::PavApi
end

#run PavApi