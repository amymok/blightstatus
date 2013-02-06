require "#{Rails.root}/lib/import_helpers.rb"
require "#{Rails.root}/lib/spreadsheet_helpers.rb"
require "#{Rails.root}/lib/address_helpers.rb"
require "#{Rails.root}/lib/abatement_helpers.rb"

include ImportHelpers
include SpreadsheetHelpers
include AddressHelpers
include AbatementHelpers


namespace :demolitions do
  desc "Downloading FEMA files from s3.amazon.com and load them into the db"  
  task :load_fema, [:file_name, :bucket_name] => :environment  do |t, args|
    args.with_defaults(:bucket_name => "neworleansdata", :file_name => "FEMA Validated_Demo_DataEntry_2012_January.xlsx")  
    p args

    ImportHelpers.connect_to_aws
    s3obj = AWS::S3::S3Object.find args.file_name, args.bucket_name
    downloaded_file_path = ImportHelpers.download_from_aws(s3obj)

    SpreadsheetHelpers.workbook_to_hash(downloaded_file_path).each do |row|
      unless SpreadsheetHelpers.row_is_empty? row
        if row['Status Update']  == '12.Demolished'
          if row['Number'].to_s.end_with?(".0")
            row['Number'] = row['Number'].to_i.to_s
          end
          Demolition.find_or_create_by_address_long_and_date_completed(:house_num => row['Number'], :street_name => row['Street'].upcase, :address_long => "#{row['Number']} #{row['Street']}".upcase, :date_started => row['Demo Start'], :date_completed => row['Demo Complete'], :program_name => "NORA")
        end
      end
    end
  end

  desc "Downloading NORA files from s3.amazon.com and load them into the db"  
  task :load_nora, [:file_name, :bucket_name] => :environment  do |t, args|
    args.with_defaults(:bucket_name => "neworleansdata", :file_name => "NORA Validated_Demo_DataEntry_2012.xlsx")  
    p args

    ImportHelpers.connect_to_aws
    s3obj = AWS::S3::S3Object.find args.file_name, args.bucket_name
    downloaded_file_path = ImportHelpers.download_from_aws(s3obj)

    SpreadsheetHelpers.workbook_to_hash(downloaded_file_path).each do |row|
      unless SpreadsheetHelpers.row_is_empty? row
        if row['Number'].to_s.end_with?(".0")
            row['Number'] = row['Number'].to_i.to_s
          end
        Demolition.create(:house_num => row['Number'], :street_name => row['Street'].upcase, :address_long =>  row['Address'].upcase, :date_started => row['Demo Start'], :date_completed => row['Demo Complete'], :program_name => "NORA")
      end
    end
  end

  desc "Downloading NOSD files from s3.amazon.com and load them into the db"  
  task :load_nosd, [:file_name, :bucket_name] => :environment  do |t, args|
    args.with_defaults(:bucket_name => "neworleansdata", :file_name => "NOSD  BlightStat Report  January 2012.xlsx")  
    p args

    ImportHelpers.connect_to_aws
    s3obj = AWS::S3::S3Object.find args.file_name, args.bucket_name
    downloaded_file_path = ImportHelpers.download_from_aws(s3obj)

    SpreadsheetHelpers.workbook_to_hash(downloaded_file_path).each do |row|
      unless SpreadsheetHelpers.row_is_empty? row
        if row['Number'].to_s.end_with?(".0")
          row['Number'] = row['Number'].to_i.to_s
        end
        #:date_completed => row['Demo Complete'], this throws error. need to format date.
        Demolition.create(:house_num => row['Number'], :street_name => row['Street'].upcase, :address_long =>  row['Address'].upcase, :date_started => row['Demo Start'],  :program_name => "NOSD")
      end
    end
  end



  desc "Downloading LAMA Permit Demolition files from s3.amazon.com and load them into the db"  
  task :load_lama_demolition_permits, [:file_name, :bucket_name] => :environment  do |t, args|
    args.with_defaults(:bucket_name => "neworleansdata", :file_name => "tung_demolitions_oct_2012.xls")

    ImportHelpers.connect_to_aws
    s3obj = AWS::S3::S3Object.find args.file_name, args.bucket_name
    downloaded_file_path = ImportHelpers.download_from_aws(s3obj)
    #downloaded_file_path = "/Users/amirbey/Projects/openblight/tmp/cache/tung_demolitions_oct_2012.xls"
    SpreadsheetHelpers.workbook_to_hash(downloaded_file_path).each do |row|
       unless SpreadsheetHelpers.row_is_empty? row
        demo_number = row['Number'].strip if row['Number']
        next if demo_number.nil? || demo_number.length == 0
        current_status = row['Current Status'].strip if row['Current Status']
        address_long = row['Address'].strip.upcase if row['Address']
        date = row['Current Status Date'] if row['Current Status Date']
        
        addr = {}#address_long: nil, house_num: nil, street_type: nil, street_name: nil}
          if address_long
            addr[:address_long] = address_long
            addr[:address_long] = addr[:address_long].chop if addr[:address_long].end_with?(".")
          
            addr[:house_num] = addr[:address_long].split(' ')[0]
            addr[:street_type] = AddressHelpers.get_street_type addr[:address_long] 
            addr[:street_name] = AddressHelpers.get_street_name addr[:address_long]
        end
         
         if (current_status =~ /Permit/ && (current_status =~ /Issued/ || current_status =~ /Finaled/))
            d = Demolition.find_or_create_by_demo_number(:demo_number => demo_number, :address_long => addr[:address_long], :date_started => date, :house_num => addr[:house_num], :street_type => addr[:street_type], :street_name => addr[:street_name])
            puts "Demo imported with date_started => #{d.inspect}" if d
         elsif  (current_status =~ /Certificate/ && current_status =~ /Completion/)
            d = Demolition.find_by_demo_number(demo_number)
            if d
              d.update_attribute(:date_completed, date_completed) if d.date_completed.nil?
              puts "Demo updated with date_completed => #{d.inspect}" if d
            else
               d = Demolition.create(:address_long => addr[:address_long], :date_completed => date, :house_num => addr[:house_num], :street_type => addr[:street_type], :street_name => addr[:street_name], :demo_number => demo_number)
               puts "Demo imported with date_completed => #{d.inspect}" if d
            end
         elsif (current_status =~ /Issued/ && current_status =~ /Error/)
            d = Demolition.where(:address_long => addr[:address_long])
            puts "Demo deleted => #{d.inspect}"
            d.destroy_all
         end
      end
    end
  end

  desc "Downloading Socrata files from s3.amazon.com and load them into the db"
  task :load_socrata, [:socrata_id] => :environment  do |t, args|

    socrata_id = args.socrata_id
    
    unless socrata_id
      puts "Error: A Socrata dataset id is required"
      return
    end
    properties = ImportHelpers.download_json_convert_to_hash("https://data.nola.gov/api/views/#{socrata_id}/rows.json?accessType=DOWNLOAD")
    
    begin
      basename = "#{socrata_id}_#{DateTime.now.to_s}"
      file = Tempfile.new(basename)
      file.write("#{properties.inspect}")
      ImportHelpers.upload_to_aws("#{basename}.json", file.path)
    ensure
      file.close
      file.unlink   # deletes the temp file
    end

    exceptions = []
    properties[:data].each do |row|
      begin
        address_long = row[12] ? row[12] : row[11]
        next if address_long.nil?
        date_started = row[14]
        date_completed = row[15]
        program_name = row[9]
        house_num = address_long.split(' ')[0]
        
        demos = Demolition.where(:address_long => address_long)#, :program_name => program, :date_started => date_started, :date_completed)
        if demos.any?
          demos.each do |demo|
            updated = false
            next if demo.program_name && demo.program_name.upcase != program_name.upcase
            
             
            if (demo.date_started && demo.date_started != date_started) || (demo.date_completed && demo.date_completed != date_completed)
              Demolition.create(:address_long => address_long, :program_name => program_name, :date_started => date_started, :date_completed => date_completed)  
              next
            else
              if demo.program_name.nil? && program_name
                demo.program_name = program_name
                updated = true
               end #demo.program_name && demo.program_name.upcase == program_name.upcase
           
              if demo.date_started.nil? && date_started
                demo.date_started = date_started# unless demo.date_started
                updated = true
              end

              if demo.date_completed.nil? && date_completed
                demo.date_completed = date_completed #unless demo.date_completed              
                updated = true
              end
            end
            demo.save! if updated
          end
        else
          Demolition.create(:address_long => address_long, :program_name => program_name, :date_started => date_started, :date_completed => date_completed)  
        end

      rescue
        #these exceptions are for properties that are missing most data, except for address, date demolished, and program (they are all NORA). What do we want to do with them?
        exceptions.push({ :exception => $!, :row => row })
      end
    end
    
    if exceptions.length
      puts "There are #{exceptions.length} import errors"
      exceptions.each do |e|
        puts " OBJECT ID: #{e[:row][0]}, ERROR: #{e[:exception]}"
      end
    end
  end

  desc "Correlate demolitions data with addresses"  
  task :match => :environment  do |t, args|
    # go through each foreclosure
    success = 0
    failure = 0
    case_matches = 0
    Demolition.where('address_id is null').each do |demolition|
      if Address.match_abatement(demolition)
        case_matches += 1 if Case.match_abatement(demolition)
        success +=1
      else
        puts "#{demolition.address_long} address not found in address table"
        failure += 1
      end
    end
    puts "There were #{success} successful address matches and #{failure} failed address matches and #{case_matches} cases matched"      
  end

  desc "Correlate demolitions data with addresses"  
  task :match_address => :environment  do |t, args|
    # go through each foreclosure
    success = 0
    failure = 0
    case_matches = 0
    Demolition.where('address_id is null').each do |demolition|
      if Address.match_abatement(demolition)
        success +=1
      else
        puts "#{demolition.address_long} address not found in address table"
        failure += 1
      end
    end
    puts "There were #{success} successful address matches and #{failure} failed address matches"      
  end

  desc "Correlate demolition data with cases"  
  task :match_case => :environment  do |t, args|
    # go through each demolition
    demolitions = Demolition.where("address_id is not null and case_number is null")
    demolitions.each do |demolition|
      Case.match_abatement(demolition)
    end
  end

  desc "Delete all demolitions from database"
  task :drop => :environment  do |t, args|
    Demolition.destroy_all
  end

  desc "Delete all demolitions from database"
  task :save_test => :environment  do |t, args|
    file = ImportHelpers.save_file_to_local("test1_#{DateTime.now.to_s}.txt", 'blahblahblah')
    puts file.inspect
  end
end
