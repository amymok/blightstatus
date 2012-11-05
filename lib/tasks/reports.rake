require "#{Rails.root}/lib/lama_helpers.rb"
include LAMAHelpers
namespace :reports do
  desc "Empty streets table"  
  task :address_status => :environment  do |t, args|
    header = "id,address_long,most_relevant_case,status\r"
    file = "tmp/address_audit_#{Time.now.strftime("%Y%m%d%H%M%S")}.csv"
    
    File.open(file, "w") do |csv|
      puts "file opened => #{file}"
      csv << header

      addresses = Address.where('latest_type is not null').find_each do |address|
        step = address.most_recent_status
        case_number = step.case_number
        # if case_number.nil?
        #   LAMAHelpers.import_by_location(address.address_long)
        #   step = address.most_recent_status
        #   case_number = step.case_number
        # end
        linestring= "#{address.id},#{address.address_long},#{case_number},#{step.class.to_s}"
        puts linestring
        csv << "#{linestring}\r"
      end 
    end
  end


  desc "Empty streets table"  
  task :foreclosure => :environment  do |t, args|
    header = "address_id,address_long,status,notes,sale_date,cdc_number\r"
    file = "tmp/cache/rake/foreclosures_audit_#{Time.now.strftime("%Y%m%d%H%M%S")}.csv"
    
    File.open(file, "w") do |csv|
      puts "file opened => #{file}"
      csv << header

      foreclosures = Foreclosure.find_each do |f|
        linestring= "#{f.address_id},#{f.address_long},#{f.status},#{f.notes},#{f.sale_date.strftime("%m-%d-%Y")}" if f.sale_date#{f.cdc_case_number}"
        puts linestring
        csv << "#{linestring}\r"
      end 
    end
  end
end