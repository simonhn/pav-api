xml.instruct! :xml, :version => '1.0'
xml.track_albums do
xml.track do
  xml.title @track.title
  xml.id @track.id
end
xml.albums do
@albums.each do |album|
xml.album do
  xml.id album.id
  xml.albumname album.albumname
  xml.albumimage album.albumimage
  xml.created_at album.created_at
end
end
end
end