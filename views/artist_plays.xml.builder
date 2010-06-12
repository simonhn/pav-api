xml.instruct! :xml, :version => '1.0'
xml.artist_plays do
xml.artist do
  xml.artistname @artist.artistname
  xml.id @artist.id
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