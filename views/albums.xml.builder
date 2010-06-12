xml.instruct! :xml, :version => '1.0'
xml.albums do
@albums.each do |album|
xml.album :id => album.id do
  xml.artistname album.albumname
  xml.created_at album.created_at
end
end
end
