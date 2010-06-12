xml.instruct! :xml, :version => '1.0'
xml.chart do
@albums.each do |album|
  xml.album :count => album.cnt.to_i, :albumname => album.albumname, :albumid => album.album_id, :trackid => album.track_id
end
end