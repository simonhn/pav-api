#datamapper stuff
require 'dm-core'
require 'dm-serializer'
require 'dm-timestamps'
require 'dm-aggregates'
require 'dm-migrations'

#Models - to be moved to individual files
class Artist
    include DataMapper::Resource
    property :id, Serial
    property :artistmbid, String, :length => 512
    property :artistname, String, :length => 512
    property :artistnote, Text
    property :artistlink, Text
    property :created_at, DateTime
    has n, :tracks, :through => Resource
end

class Album
    include DataMapper::Resource
    property :id, Serial
    property :albummbid, String, :length => 512
    property :albumname, String, :length => 512
    property :albumimage, Text
    property :created_at, DateTime 
    has n, :tracks, :through => Resource
end

class Track
    include DataMapper::Resource
    property :id, Serial
    property :trackmbid, String, :length => 512
    property :title, String, :length => 512
    property :tracknote, Text
    property :tracklink, Text
    property :show, Text
    property :talent, Text
    property :aust, String, :length => 512
    property :duration, Integer
    property :publisher, Text
    property :datecopyrighted, Integer
    property :created_at, DateTime
    has n, :artists, :through => Resource
    has n, :albums, :through => Resource
    has n, :plays
    def date
        created_at.strftime "%R on %B %d, %Y"
    end
    def playcount
      Play.count(:track_id => self.id);
    end
end

class Play
    include DataMapper::Resource
    property :id, Serial
    property :playedtime, DateTime
    belongs_to :track
    belongs_to :channel
    def date
        #converting from utc to aussie time
        #playedtime.new_offset(Rational(+20,24)).strftime "%R on %B %d, %Y"
        playedtime.strftime "%Y-%m-%d %H:%M:%S"
    end
end

class Channel
    include DataMapper::Resource
    property :id, Serial
    property :channelname, String, :length => 512
    property :channelxml, String, :length => 512
    property :logo, String, :length => 512
    property :channellink, String, :length => 512
    has n, :plays
end
