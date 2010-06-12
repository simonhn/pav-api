xml.instruct! :xml, :version => '1.0'
xml.chart do
@artists.each do |artist|
  xml.artist :count => artist.count.to_i, :artistname => artist.artistname, :id => artist.id
end
end
