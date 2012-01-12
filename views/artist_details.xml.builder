xml.instruct! :xml, :version => '1.0'
xml.artist do
@res.each do |result|
xml.album :id => result.id do
end
end
end