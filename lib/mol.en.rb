# Just import every rb file. Yolo
Dir["#{File.expand_path('../',  __FILE__)}/**/*.rb"].each do |filename|
    require filename
end