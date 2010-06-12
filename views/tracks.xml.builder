xml.instruct! :xml, :version => '1.0'
xml.tracks do
@tracks.each do |track|
xml.track :id => track.id do
  xml.title     track.title
  xml.tracknote track.tracknote
  xml.tracklink track.tracklink
  xml.show      track.show
  xml.talent    track.talent
  xml.aust      track.aust
  xml.duration  track.duration
  xml.publisher track.publisher
  xml.datecopyrighted track.datecopyrighted
  xml.created_at track.created_at
end
end
end