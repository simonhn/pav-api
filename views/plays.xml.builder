xml.instruct! :xml, :version => '1.0'
xml.plays do
  @plays.each do |track|
    xml.track do
      xml.trackid track.track_id
      xml.trackmbid track.trackmbid
      xml.tracktitle track.title
      xml.artistname track.artistname
      xml.artistid track.artist_id
      xml.artistmbid track.artistmbid
      xml.albumid track.album_id
      xml.albummbid track.albummbid
      xml.albumname track.albumname
      xml.albumimage track.albumimage
      xml.channelid track.channel_id
      xml.programid track.program_id
      xml.playedtime track.playedtime
    end
  end
end