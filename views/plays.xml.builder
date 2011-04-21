xml.instruct! :xml, :version => '1.0'
xml.plays do
  @plays.each do |track|
    xml.track do
      xml.trackid track.id
      xml.tracktitle track.title
      xml.artistname track.artistname
      xml.albumname track.albumname
      xml.albumimage track.albumimage
      xml.channelid track.channel_id
      xml.playedtime track.playedtime
    end
  end
end