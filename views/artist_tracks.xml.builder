builder do |xml|
xml.instruct! :xml, :version => '1.0'
xml.artist_tracks do
xml.artist do
  xml.artistname @artist.artistname
  xml.id @artist.id
end
xml.tracks do
@tracks.each do |track|
xml.track do
  xml.id track.id
  xml.title track.title
  xml.tracknote track.tracknote
  xml.tracklink track.tracklink
  xml.show track.show
  xml.talent track.talent
  xml.duration track.duration
  xml.publisher track.publisher
  xml.datecopyrighted track.datecopyrighted
  xml.created_at track.created_at
end
end
end
end
end