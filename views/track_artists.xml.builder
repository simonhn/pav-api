xml.instruct! :xml, :version => '1.0'
xml.track_artists do
xml.track do
  xml.title @track.title
  xml.id @track.id
end
xml.artists do
@artists.each do |artist|
xml.artist do
  xml.id artist.id
  xml.artistname artist.artistname
  xml.created_at artist.created_at
end
end
end
end