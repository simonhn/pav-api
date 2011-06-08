#MAX_REQUESTS_PER_HOUR = 10
ABC_IP = '174.143.182.132'
module Rack; 
  module Throttle
    class Throttler < Rack::Throttle::Interval
      def initialize(app, options = {})
        super
      end
      def allowed?(request)
        if request.ip.to_s == ABC_IP
          true
        else
          super(request)
        end
      end     
    end
  end
end