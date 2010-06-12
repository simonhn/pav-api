xml.instruct! :xml, :version => '1.0'
xml.album :id => @album.id do
  xml.albumname @album.albumname
  xml.albumimage @album.albumimage
  xml.created_at @album.created_at
end
