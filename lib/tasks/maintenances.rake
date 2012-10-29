require "#{Rails.root}/lib/import_helpers.rb"
require "#{Rails.root}/lib/spreadsheet_helpers.rb"
require "#{Rails.root}/lib/address_helpers.rb"
require "#{Rails.root}/lib/abatement_helpers.rb"

include ImportHelpers
include SpreadsheetHelpers
include AddressHelpers
include AbatementHelpers


namespace :maintenances do
  desc "Downloading files from s3.amazon.com"  
  task :load, [:file_name, :bucket_name] => :environment  do |t, args|
    args.with_defaults(:bucket_name => "neworleansdata", :file_name => "INAP Validated Address Data entry sheet 2012.xlsx")  
    p args

    #connect to amazon
    ImportHelpers.connect_to_aws
    s3obj = AWS::S3::S3Object.find args.file_name, args.bucket_name
    downloaded_file_path = ImportHelpers.download_from_aws(s3obj)

    if downloaded_file_path.match(/\.xls$/)
      SpreadsheetHelpers.workbook_to_hash(downloaded_file_path).each do |row|
        unless SpreadsheetHelpers.row_is_empty? row
          Maintenance.create(:house_num => row['Number'], :street_name => row['Street'].upcase, :street_type => AddressHelpers.get_street_type(row['Accessory']),  :address_long =>  AddressHelpers.abbreviate_street_types(row['Address']), :date_recorded => row['Date Recorded'], :date_completed => row['Date Cut'], :program_name => row['Program'])
        end
      end
    else
      workbook = RubyXL::Parser.parse(downloaded_file_path)
      if workbook[1][0][0].value == "Number"
        Maintenance.import_from_workbook(workbook, workbook[1])
      else
        Maintenance.import_from_workbook(workbook, workbook[2])
      end
    end
  end

  desc "Downloading archival file from s3.amazon.com"
  task :load_2011 => :environment do |t, args|
    args.with_defaults(:bucket_name => "neworleansdata", :file_name => "INAP_2011_ytd.xlsm")
    p args

    #connect to amazon
    ImportHelpers.connect_to_aws
    s3obj = AWS::S3::S3Object.find args.file_name, args.bucket_name
    downloaded_file_path = ImportHelpers.download_from_aws(s3obj)

    workbook = RubyXL::Parser.parse(downloaded_file_path)
    workbook[1].each do |row|
      date = workbook.num_to_date(row[4].value.to_i)
      Maintenance.create(:address_long => row[1].value, :date_completed => date, :status => row[3].value, :program_name => "INAP")
    end
  end

  desc "Correlate maintenance data with addresses"  
  task :match => :environment  do |t, args|
    # go through each maintenance
    success = 0
    failure = 0
    case_matches = 0
    Maintenance.where('address_id is null').each do |maintenance|
      if Address.match_abatement(maintenance)
        case_matches +=1 if Case.match_abatement(maintenance)
        success +=1
      else
        puts "#{maintenance.address_long} address not found in address table"
        failure += 1
      end
    end
    puts "There were #{success} successful address matches and #{failure} failed address matches and #{case_matches} cases matched"      
  end

  desc "Correlate maintenance data with cases"  
  task :match_case => :environment  do |t, args|
    # go through each demolition
    maintenances = Maintenance.where("address_id is not null and case_number is null")
    maintenances.each do |maintenance|
      Case.match_abatement(maintenance)
    end
  end

  desc "Delete all maintenances from database"
  task :drop => :environment  do |t, args|
    Maintenance.destroy_all
  end
end
