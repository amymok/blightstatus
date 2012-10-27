namespace :reports do
  desc "Empty streets table"  
  task :address_status => :environment  do |t, args|
    header = "id,address_long,most_relevant_case,status\r"
    file = "tmp/address_audit_#{Time.now.strftime("%Y%m%d%H%M%S")}.csv"
    
    File.open(file, "w") do |csv|
      puts "file opened => #{file}"
      csv << header

      addresses = Address.where('latest_type is not null').find_each do |address|
        step = address.latest_type && address.latest_id ? Kernel.const_get(address.latest_type).find(address.latest_id) : nil 
        case_number = step ? step.case_number : nil
        linestring= "#{address.id},#{address.address_long},#{case_number},#{address.latest_type}"
        puts linestring
        csv << "#{linestring}\r"
      end 
    end
  end


  desc "Empty streets table"  
  task :foreclosure => :environment  do |t, args|
    header = "address_id,address_long,status,notes,sale_date,cdc_number\r"
    file = "tmp/foreclosures_audit_#{Time.now.strftime("%Y%m%d%H%M%S")}.csv"
    
    File.open(file, "w") do |csv|
      puts "file opened => #{file}"
      csv << header

      foreclosures = Foreclosure.find_each do |f|
        linestring= "#{f.address_id},#{f.address_long},#{f.status},#{f.notes},#{f.sale_date.strftime("%m-%d-%Y")},#{f.cdc_case_number}"
        puts linestring
        csv << "#{linestring}\r"
      end 
    end
  end
end