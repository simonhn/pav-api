xml.instruct! :xml, :version => '1.0'
xml.track_plays do
xml.track do
  xml.title @track.title
  xml.id @track.id
end
xml.plays do
@plays.each do |play|
xml.play do
  xml.id play.id
  xml.channel_id play.channel_id
  xml.playedtime play.date
end
end
end
end