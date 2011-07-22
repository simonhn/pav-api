xml.instruct! :xml, :version => '1.0'
xml.chart do
@albums.each do |album|
  xml.album :count => album.cnt, :artistname => album.artistname, :albumname => album.albumname, :albumid => album.album_id, :albumimage => album.albumimage, :albummbid => album.albummbid
end
end