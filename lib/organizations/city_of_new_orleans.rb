namespace :new_orleans do
	desc "Rake task to call other rake tasks with proper options"
	task :initialize do
    address_shapefile_url = 'https://data.nola.gov/api/file_data/Gn9aLqlGx_9jR-DzakSNiXu3Y5iO1YvL5O8XPgIj6no?filename=NOLA_Addresses_20121214.zip'
		Rake::Task["addresses:load address_shapefile_url=#{address_shapefile_url}"].invoke
	end


  task :update do
    Rake::Task["addresses:update"].invoke
  end

end
