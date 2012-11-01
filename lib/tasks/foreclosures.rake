require "#{Rails.root}/lib/import_helpers.rb"
require "#{Rails.root}/lib/spreadsheet_helpers.rb"
require "#{Rails.root}/lib/address_helpers.rb"
require "#{Rails.root}/lib/abatement_helpers.rb"
require "#{Rails.root}/lib/foreclosure_helpers.rb"
require 'rubyXL'

include ImportHelpers
include SpreadsheetHelpers
include AddressHelpers
include AbatementHelpers
include ForeclosureHelpers


namespace :foreclosures do
  desc "Downloading CDC case numbers from s3.amazon.com"  
  task :load_writfile, [:file_name, :bucket_name] => :environment  do |t, args|
    
    args.with_defaults(:bucket_name => "neworleansdata", :file_name => "WRITS - WORKING COPY - Oct.3.2012.xlsx")#"Writs Filed - Code Enforcement.xlsx")  
    p args

    #connect to amazon
    ImportHelpers.connect_to_aws
    s3obj = AWS::S3::S3Object.find args.file_name, args.bucket_name
    downloaded_file_path = ImportHelpers.download_from_aws(s3obj)


    workbook = RubyXL::Parser.parse(downloaded_file_path)
    sheet = workbook.worksheets[1].extract_data
    cdc_col = 4
    addr_col = 2

    client = Savon.client ENV['SHERIFF_WSDL']

    sheet.each do |row|
      if row[cdc_col]
        cdc_number = row[cdc_col]
        address_long = row[addr_col]
        puts "writs file row => " << row.to_s
        ForeclosureHelpers.load_foreclosure(cdc_number,client) if cdc_number && cdc_number != "CDC ID"
      end
    end
    puts "foreclosures:loaded_sheriff"
  end

  desc "Downloading CDC case numbers from s3.amazon.com"  
  task :load_cdcNumbers, [:cdc_numbers] => :environment  do |t, args|
    
    p args
    client = Savon.client ENV['SHERIFF_WSDL']
    cdc_Numbers = args[:cdc_numbers].split('|')
    cdc_Numbers.each do |cdc_number|# sheet.each do |row|
      ForeclosureHelpers.load_foreclosure(cdc_number,client)#, client)          
    end
    puts "foreclosures:load_cdcNumbers"
  end


  desc "Correlate foreclosure data with addresses"  
  task :match => :environment  do |t, args|
    # go through each foreclosure
    success = 0
    failure = 0
    case_matches = 0
    Foreclosure.where('address_id is null').find_each do |foreclosure|
      if Address.match_abatement(foreclosure)
        case_matches +=1 if Case.match_abatement(foreclosure)
        success +=1
      else
        puts "#{foreclosure.address_long} address not found in address table"
        failure += 1
      end
    end
    puts "There were #{success} successful address matches and #{failure} failed address matches and #{case_matches} cases matched"      
  end

  # desc "Correlate foreclosure data with cases"  
  # task :match_case => :environment  do |t, args|
  #   # go through each demolition
  #   foreclosures = Foreclosure.where("address_id is not null and case_number is null")
  #   foreclosures.each do |foreclosure|
  #     Case.match_abatement(foreclosure)
  #   end
  # end

  # desc "Delete all foreclosures from database"
  # task :drop => :environment  do |t, args|
  #   Foreclosure.destroy_all
  # end
end
