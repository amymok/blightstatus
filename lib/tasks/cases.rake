require "#{Rails.root}/lib/import_helpers.rb"
require "#{Rails.root}/lib/spreadsheet_helpers.rb"
require "#{Rails.root}/lib/address_helpers.rb"

include ImportHelpers
include SpreadsheetHelpers
include AddressHelpers


namespace :cases do
  desc "Correlate case data with addresses"  
  task :match_geopin => :environment  do |t, args|
    # go through each foreclosure
    success = 0
    failure = 0

    Case.where('address_id is null').each do |row|
      # compare each address in demo list to our address table
      #address = Address.where("address_long LIKE ?", "%#{row.address_long}%")
      address = AddressHelpers.find_address_by_geopin(row.geopin)

      unless (address.empty?)
        Case.find(row.id).update_attributes(:address_id => address.first.id)      
        success += 1
      else
        puts "#{row.geopin} geopin not found in address table"
        failure += 1
      end
    end
    puts "There were #{success} successful matches and #{failure} failed matches"      
  end

  desc "Delete all cases from database"
  task :drop => :environment  do |t, args|
    Case.destroy_all
  end

  desc "generate case_list"
  task :case_list, [:where] => :environment do |t, args|
    if args[:where].nil?
      puts "this task requires a clause"
      return
    end
    where = args[:where]
    file = "tmp/cache/rake/case_list_#{where.gsub(/ /,'_').gsub('\'','').gsub('%','')}_#{Time.now.strftime("%Y%m%d%H%M%S")}.csv"
    l = LAMA.new({:login => ENV['LAMA_EMAIL'], :pass => ENV['LAMA_PASSWORD']})
    File.open(file, "w") do |log|
      puts "file opened => #{file}"
      Case.select(:case_number).where(where).find_each do |kase|
        log << "#{kase.case_number}\n"
      end
    end
  end    
end
