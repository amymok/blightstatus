require "#{Rails.root}/lib/address_helpers.rb"
require "#{Rails.root}/lib/import_helpers.rb"
require 'open-uri'
require 'rest_client'


namespace :addresses do
  desc "Load data.nola.gov addresses into database"
  task :update, [:remote_shapefile] => :environment  do |t, args|
    args.with_defaults(:address_file_name => "NOLA_Addresses_20121214.zip", :districts_file_name => "NOLA_Addresses_20121214.zip")  

    #download zip file
    # remote_shapefile = "https://data.nola.gov/api/file_data/Gn9aLqlGx_9jR-DzakSNiXu3Y5iO1YvL5O8XPgIj6no?filename=NOLA_Addresses_20121214.zip"

    address_list = get_geojson_from_shapefile_zip(remote_shapefile)


    p "File contains #{p address_list['features'].count} records"


    new_addresses_count = addresses_count = 0


    address_list['features'].each do |n|
      record = n['properties']
      # p record.inspect
      addr = nil
      if addr = Address.where("address_id = ?", record["ADDRESS_ID"]).first
        result = addr.update_attributes(:point => n['geometry'], :official => true, :address_id => record["ADDRESS_ID"], :street_full_name => record["ADDRESS_LA"].sub(/^\d+\s/, ''), :address_long => record["ADDRESS_LA"], :geopin => record["GEOPIN"], :house_num => record["HOUSE_NUMB"], :parcel_id => record["PARCEL_ID"], :status => record["STATUS"], :street_id => record["STREET_ID"], :street_name => record["STREET"], :street_type => record["TYPE"], :x => record["X"], :y => record["Y"] )
        p "updating address id #{record["ADDRESS_ID"]} #{result.inspect}"
        addresses_count = addresses_count + 1;
      else
        p "creating new address id #{record["ADDRESS_ID"]}"
        addr = Address.create(:point => n['geometry'], :official => true, :address_id => record["ADDRESS_ID"], :street_full_name => record["ADDRESS_LA"].sub(/^\d+\s/, ''), :address_long => record["ADDRESS_LA"], :geopin => record["GEOPIN"], :house_num => record["HOUSE_NUMB"], :parcel_id => record["PARCEL_ID"], :status => record["STATUS"], :street_id => record["STREET_ID"], :street_name => record["STREET"], :street_type => record["TYPE"], :x => record["X"], :y => record["Y"] )
        new_addresses_count = new_addresses + 1;
      end
      addr.save
    end

    p "Total addresses updated #{addresses_count}"
    p "Total new addresses #{new_addresses_count}"

  end

  desc "Empty address table"  
  task :drop => :environment  do |t, args|
    Address.destroy_all
  end

  desc "Set assessor_url for all addresses"
  task :set_assessor_urls => :environment do |t, args|
    Address.find_in_batches do |group|
      group.each do |a|
        begin
         a.set_assessor_link 
        rescue Exception => e
         p "Assessor link could not be set for #{a.address_long}"
         p e.to_s
        end
      end
    end
  end

  desc "call get neighborhood"
  task :get_neighborhood => :environment do
    #addresses = Address.all
    a = Address.find(1)#addresses.each do |a|
      #example: http://maps.googleapis.com/maps/api/geocode/json?latlng=40.714224,-73.961452&sensor=true
      #http://maps.googleapis.com/maps/api/geocode/xml?address=298+Fairmount+Ave,+Oakland,+CA&sensor=true
      puts "lat: #{a.y} and long: #{a.x}"
      AddressHelpers.get_neighborhood(a.y,a.x)

    #end
  end

  desc "Empty streets table"  
  task :load_cases_for_addresses_with_only_abatements => :environment  do |t, args|
    addresses = Address.includes(:cases).where("latest_type in ('#{Foreclosure.to_s}','#{Maintenance.to_s}','#{Demolition.to_s}') and cases.id is null").find_each do |address|
      step = address.most_recent_status
      LAMAHelpers.import_by_location(address.address_long) if step && step.case_number.nil? 
    end
  end

  desc "generate address_list"
  task :address_list, [:where] => :environment do |t, args|
    if args[:where].nil?
      puts "this task requires a clause"
      return
    end
    where = args[:where]
    file = "tmp/cache/rake/address_list_#{where.gsub(/ /,'_')}_#{Time.now.strftime("%Y%m%d%H%M%S")}.csv"
    l = LAMA.new({:login => ENV['LAMA_EMAIL'], :pass => ENV['LAMA_PASSWORD']})
    File.open(file, "w") do |log|
      puts "file opened => #{file}"
      Address.select(:id).where(where).find_each do |address|
        puts address.id
        log << address.id << '|'
      end
    end
  end    
end
