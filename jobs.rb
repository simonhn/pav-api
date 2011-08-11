
#datamapper stuff
require 'dm-core'
require 'dm-timestamps'
require 'dm-aggregates'
require 'dm-migrations'

#require
#Models - to be moved to individual files
class Artist
    include DataMapper::Resource
    property :id, Serial
    property :artistmbid, String, :length => 36
    property :artistname, String, :length => 512
    property :artistnote, Text
    property :artistlink, Text
    property :created_at, DateTime
    has n, :tracks, :through => Resource
    has n, :channels, :through => Resource
end

class Album
    include DataMapper::Resource
    property :id, Serial
    property :albummbid, String, :length => 36
    property :albumname, String, :length => 512
    property :albumimage, Text
    property :created_at, DateTime 
    has n, :tracks, :through => Resource
end

class Track
    include DataMapper::Resource
    property :id, Serial
    property :trackmbid, String, :length => 36
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
    property :program_id, String, :length => 512
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
    property :programxml, String, :length => 512
    has n, :plays
    has n, :artists, :through => Resource
end

#template systems
require 'yajl/json_gem'
require 'builder'

#for xml fetch and parse
require 'rest_client'
require 'crack'

#musicbrainz stuff
require 'rbrainz'
include MusicBrainz
require 'rchardet19'
require 'logger'

#time parsing
require 'chronic_duration'
require 'chronic'
pwd  = File.dirname(File.expand_path(__FILE__))

$LOG = Logger.new(pwd+'/log/queue.log', 'monthly')

  #setup MySQL connection:  
  @config = YAML::load( File.open(pwd +'/config/settings.yml' ) )
  @connection = "#{@config['adapter']}://#{@config['username']}:#{@config['password']}@#{@config['host']}/#{@config['database']}";
  DataMapper.setup(:default, @connection)  
  DataMapper.finalize
  #Method that stores each playitem to database. Index is the id of the channel to associate the play with
   def store_hash(item, index)
      @albums = nil

      mbid_hash = nil
      duration = ChronicDuration.parse(item["duration"].to_s)     

       #there can be multiple artist seperated by '+' so we split them
       artist_array = item['artist']['artistname'].split("+")
       artist_array.each{ |artist_item|
       begin
         #for each item, lookup in musicbrainz. Returns hash with mbids for track, album and artist if found
         mbid_hash = mbid_lookup(artist_item.strip, item['title'], item['album']['albumname'])
        rescue StandardError => e
           $LOG.info("Issue while processing #{artist_item.strip} - #{item['title']} - #{e.backtrace}")  
        end
       #ARTIST
       if !mbid_hash.nil? && !mbid_hash["artistmbid"].nil?
         @artist = Artist.first_or_create({:artistmbid => mbid_hash["artistmbid"]},{:artistmbid => mbid_hash["artistmbid"],:artistname => artist_item.strip, :artistnote => item['artist']['artistnote'], :artistlink => item['artist']['artistlink']})
       else
         @artist = Artist.first_or_create({:artistname => artist_item.strip},{:artistname => artist_item.strip, :artistnote => item['artist']['artistnote'], :artistlink => item['artist']['artistlink']})
       end

        #store artist_id / channel_id to a lookup table, for faster selects 
        @artist_channels = @artist.channels << Channel.get(index)
        @artist_channels.save

        #ALBUM
        #creating and saving album if not exists
        if !item['album']['albumname'].empty?
          if !mbid_hash.nil? && !mbid_hash["albummbid"].nil?
            #puts "album mbid found for: " + mbid_hash["albummbid"]
            @albums = Album.first_or_create({:albummbid => mbid_hash["albummbid"]},{:albummbid => mbid_hash["albummbid"], :albumname => item['album']['albumname'], :albumimage=>item['album']['albumimage']})
          else
            @albums = Album.first_or_create({:albumname => item['album']['albumname']},{:albumname => item['album']['albumname'], :albumimage=>item['album']['albumimage']})
          end
        end


         #Track
         #creating and saving track
         if mbid_hash && !mbid_hash["trackmbid"].nil?        
           @tracks = Track.first_or_create({:trackmbid => mbid_hash["trackmbid"]},{:trackmbid => mbid_hash["trackmbid"],:title => item['title'],:show => item['show'],:talent => item['talent'],:aust => item['aust'],:tracklink => item['tracklink'],:tracknote => item['tracknote'],:publisher => item['publisher'], :datecopyrighted => item['datecopyrighted'].to_i})
         else
           @tracks = Track.first_or_create({:title => item['title'],:duration => duration},{:title => item['title'],:show => item['show'],:talent => item['talent'],:aust => item['aust'],:tracklink => item['tracklink'],:tracknote => item['tracknote'],:duration => duration,:publisher => item['publisher'],:datecopyrighted => item['datecopyrighted'].to_i})
         end

         #add the track to album - if album exists
         if !@albums.nil?
           @album_tracks = @albums.tracks << @tracks
           @album_tracks.save
         end

         #add the track to the artist
         @artist_tracks = @artist.tracks << @tracks
         @artist_tracks.save

         #adding play: only add if playedtime does not exsist in the database already
         play_items = Play.count(:playedtime=>item['playedtime'], :channel_id=>index)
         if play_items < 1
           @play = Play.create(:track_id =>@tracks.id, :channel_id => index, :playedtime=>item['playedtime'], :program_id => item['program_id'])
              @plays = @tracks.plays << @play
              @plays.save
         end

     }
   end

  def mbid_lookup(artist, track, album)
    result_hash = {}

    #we can only hit mbrainz once a second so we take a nap
    sleep 1
    service = MusicBrainz::Webservice::Webservice.new(:user_agent => 'pavapi/1.0')
    q = MusicBrainz::Webservice::Query.new(service)
    #TRACK
    if !album.empty?
      t_filter = MusicBrainz::Webservice::TrackFilter.new(:artist=>artist, :title=>track, :release=>album, :limit => 5)
    else
      t_filter = MusicBrainz::Webservice::TrackFilter.new(:artist=>artist, :title=>track, :limit => 5)
    end
    t_results = q.get_tracks(t_filter)

    #No results from the 'advanced' query, so trying artist and album individualy
    if t_results.count == 0
      #ARTIST
      sleep 1
      t_filter = MusicBrainz::Webservice::ArtistFilter.new(:name=>artist)
      t_results = q.get_artists(t_filter)
      if t_results.count > 0
        x = t_results.first
        if x.score == 100 && is_ascii(String(x.entity.name)) && String(x.entity.name).casecmp(artist)==0
          #puts 'ARTIST score: ' + String(x.score) + '- artist: ' + String(x.entity.name) + ' - artist mbid '+ String(x.entity.id.uuid)
          result_hash["artistmbid"] = String(x.entity.id.uuid)
        end
      end

      #ALBUM
      if !album.empty?
        sleep 1
        
        t_filter = MusicBrainz::Webservice::ReleaseGroupFilter.new(:artist=>artist, :title=>album)
        t_results = q.get_release_groups(t_filter)
        #puts "album results count "+t_results.count.to_s
        if t_results.count>0  
          x = t_results.first
          #puts 'ALBUM score: ' + String(x.score) + '- artist: ' + String(x.entity.artist) + ' - artist mbid '+ String(x.entity.id.uuid) +' - release title '+ String(x.entity.title) + ' - orginal album title: '+album
          if x.score == 100 && is_ascii(String(x.entity.title)) #&& String(x.entity.title).casecmp(album)==0
            #puts 'abekat'+x.entity.id.uuid.inspect
            result_hash["albummbid"] = String(x.entity.id.uuid)
          end
        end
      end

    elsif t_results.count > 0
      t_results.each{ |x|
      #puts 'score: ' + String(x.score) + '- artist: ' + String(x.entity.artist) + ' - artist mbid '+ String(x.entity.artist.id.uuid) + ' - track mbid: ' + String(x.entity.id.uuid) + ' - track: ' + String(x.entity.title)  +' - album: ' + String(x.entity.releases[0]) +' - album mbid: '+ String(x.entity.releases[0].id.uuid)
        if  x.score == 100 && is_ascii(String(x.entity.artist))
          sleep 1
          t_include = MusicBrainz::Webservice::ReleaseIncludes.new(:release_groups=>true)
          release = q.get_release_by_id(x.entity.releases[0].id.uuid, t_include)
          result_hash["trackmbid"] = String(x.entity.id.uuid)
          result_hash["artistmbid"] = String(x.entity.artist.id.uuid)
          result_hash["albummbid"] = String(release.release_group.id.uuid)
        end
      }
   end
   return result_hash
  end

  def is_ascii(item)
   cd = CharDet.detect(item)
   encoding = cd['encoding']
   return encoding == 'ascii'
  end

job 'track.store' do |args|
  store_hash(args['item'], args['channel'].to_i)
  error do |e, job, args|
    $LOG.info("error e #{e}")
    $LOG.info("error job #{job.inspect}")
    $LOG.info("error args #{args.inspect}")
  end
end
