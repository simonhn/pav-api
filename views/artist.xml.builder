xml.instruct! :xml, :version => '1.0'
xml.artist :id => @artist.id do
  xml.artistname @artist.artistname
  xml.artistnote @artist.artistnote
  xml.artistlink @artist.artistlink
  xml.created_at @artist.created_at
end