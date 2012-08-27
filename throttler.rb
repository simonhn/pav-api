require 'rack/throttle'

class ApiDefender < Rack::Throttle::Hourly
  def initialize(app, options = {})
    super
  end
  def allowed?(request)
    if request.ip.to_s =='203.2.218.145'
      true
    else
      super(request)
    end
  end
end