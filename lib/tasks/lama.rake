require 'open-uri'
require 'json'
require "#{Rails.root}/lib/lama_helpers.rb"
include LAMAHelpers

namespace :lama do
  desc "Import updates from LAMA"
  task :load_by_date, [:start_date, :end_date] => :environment do |t, args|
    date = Time.now
    args.with_defaults(:start_date => date - 2.weeks, :end_date => date)
    start = args.start_date
    finish = args.end_date

    if finish == date
      if ENV['start_date']
        start = ENV['start_date']
      end
      if ENV['end_date']
        finish = ENV['end_date']
      end
    end

    l = LAMA.new({ :login => ENV['LAMA_EMAIL'], :pass => ENV['LAMA_PASSWORD']})
    
    puts "Searching for incidents from #{start} to #{finish}"
    incidents = l.incidents_by_date(args.start_date, args.end_date)

    incid_num = incidents.length
    puts "There are #{incid_num} incidents"
    if incid_num >= 1000
      p "LAMA can only return 1000 incidents at once- please try a smaller date range"
      return
    end

    LAMAHelpers.import_incidents_to_database(incidents, l)
  end

  desc "Import day's LAMA events"
  task :load_latest => :environment do |t, args|
    date = Time.now
    event_dates = [] 
    event_dates << Inspection.last.date << Hearing.last.date << Notification.last.date << Judgement.last.date
    end_date = event_dates.sort{|a,b| a <=> b}.last 

    Hearing.clear_incomplete
    puts "load lama start:#{end_date.strftime("%-m/%-d/%y")} - end#{date.strftime("%-m/%-d/%y")}"
    Rake::Task["lama:load_by_date"].invoke(end_date, date)
  end

  desc "Send notifications for new events"
  task :send_notifications => :environment do |t, args|
    Account.all.each(&:send_digest)
  end

  desc "Import LAMA data from our Accela endpoint until current time"
  task :load_historical => :environment do |t, args|
    start_date = Time.now #Date.new(2012, 5, 30)#Time.now
    end_date = Date.new(2012, 1, 1)

    l = LAMA.new({ :login => ENV['LAMA_EMAIL'], :pass => ENV['LAMA_PASSWORD']})

    while start_date > end_date
      call_end_date = start_date - 1.week
      incidents = l.incidents_by_date(call_end_date, start_date)
      if incidents
        p "There are #{incidents.length} incidents"
        LAMAHelpers.import_incidents_to_database(incidents, l)
      end
      start_date = call_end_date
    end
  end

  desc "Import updates from LAMA by parameter pipe (|) delimited string of cases"
  task :load_by_case, [:case_numbers] => :environment do |t, args|
    l = LAMA.new({ :login => ENV['LAMA_EMAIL'], :pass => ENV['LAMA_PASSWORD']})
    
    case_numbers = args[:case_numbers].split('|')

    case_numbers.each do |case_number|
      case_number = case_number.strip
      incident = l.incident(case_number)
      LAMAHelpers.import_incident_to_database(incident, l) if incident
      puts "#{case_number}"
    end
  end


  desc "Compare cases in our system to cases from Accela spreadsheets"
  task :compare_to_accela, [:filename] => :environment do |t, args|
    args.with_defaults(:filename => "#{Rails.root}/tmp/db_accela_compare_#{DateTime.now.strftime("%Y%m%d%H%M%s")}.csv")
    puts "fileneme => #{args[:filename]}"

    File.open(args[:filename], "w+") do |f|
      page = 1
      url = "https://blightstatus-dev.herokuapp.com/cases.json?page=#{page}"
      result = JSON.parse(open(url).read)
      while result.count > 0
        result.each do |c|
          unless Case.exists?(:case_number => c["case_number"])
            puts c["case_number"]
            f.write(c["case_number"] << "\r")
          end
        end
        page += 1
        url = "https://blightstatus-dev.herokuapp.com/cases.json?page=#{page}"
        result = JSON.parse(open(url).read)
      end
    end
  end

  desc "Refresh case.state for all cases"
  task :update_case_state => :environment do |t, args|
    
    l = LAMA.new({ :login => ENV['LAMA_EMAIL'], :pass => ENV['LAMA_PASSWORD']})
    Case.all.each do |kase|
      puts kase.case_number
      incident = l.incident(kase.case_number)
      if incident && incident.IsClosed
        incident.IsClosed =~ /true/ ? state = 'Closed' : state = 'Open'
        kase.update_attribute(:state, state)
      end
    end
  end

  desc "Import updates from LAMA by parameter pipe (|) delimited string of cases"
  task :load_by_location, [:addresses] => :environment do |t, args|
    l = LAMA.new({ :login => ENV['LAMA_EMAIL'], :pass => ENV['LAMA_PASSWORD']})
    addresses = args[:addresses].split('|')

    addresses.each do |address|
      LAMAHelpers.import_by_location(address.strip,l)
    end
  end

  desc "Import cases for addresses with no cases"
  task :load_addresses_with_no_cases, [:streets] => :environment do |t, args|
    l = LAMA.new({ :login => ENV['LAMA_EMAIL'], :pass => ENV['LAMA_PASSWORD']})
    if args[:streets]
      streets = args[:streets].split('|')
    else
      streets = Address.uniq.pluck(:street_name)
    end
    puts "#{streets}"
    streets.each do |street|
      addresses = Address.includes([:cases]).where("cases.id IS NULL and addresses.street_name = '#{street}'")
      addresses.each do |address|
        puts "Load cases for => #{address.address_long}"
        LAMAHelpers.import_by_location(address.address_long,l)
      end
    end
  end

  desc "Import unsaved cases for all addresses"
  task :load_addresses_with_unsaved_cases, [:streets] => :environment do |t, args|
    l = LAMA.new({ :login => ENV['LAMA_EMAIL'], :pass => ENV['LAMA_PASSWORD']})
    if args[:streets]
      streets = args[:streets].split('|')
    else
      streets = Address.uniq.pluck(:street_name)
    end
    puts "#{streets}"
    streets.each do |street|
      addresses = Address.select(:address_long).where(:street_name => street)
      addresses.each do |address|
        puts "Load cases for => #{address.address_long}"
        LAMAHelpers.import_unsaved_cases_by_location(address.address_long,l)
      end
    end
  end

  desc "Import unsaved cases for all addresses"
  task :load_cases_by_street, [:streets] => :environment do |t, args|
    l = LAMA.new({ :login => ENV['LAMA_EMAIL'], :pass => ENV['LAMA_PASSWORD']})
    if args[:streets]
      streets = args[:streets].split('|')
    else
      streets = Address.uniq.pluck(:street_name)
    end
    puts "#{streets}"
    streets.each do |street|
      addresses = Address.select(:address_long).where(:street_name => street)
      addresses.each do |address|
        puts "Load cases for => #{address.address_long}"
        LAMAHelpers.import_by_location(address.address_long,l)
      end
    end
  end

  desc "reload cases imported without spawn"
  task :reload_cases_before_date, [:before_date] => :environment do |t, args|
    if args[:before_date].nil?
      puts "this task requires a date parameter (ie: YYYY-MM-dd)"
      return
    end
    date = args[:before_date]
    now = Time.now
    file = "log/case_spawn_reload_#{now.strftime("%Y%m%d%H%M%S")}.csv"
    l = LAMA.new({:login => ENV['LAMA_EMAIL'], :pass => ENV['LAMA_PASSWORD']})
    File.open(file, "w") do |log|
      puts "file opened => #{file}"
      Case.where("created_at < '#{date}'").find_each do |kase|
        if LAMAHelpers.reloadCase(kase.case_number,l).nil?
          msg = "FAILURE : #{kase.case_number} NOT reimported with spawns !!!!!!" 
          puts msg
          log << "#{msg}\r"
          return
        end
      end 
    end
  end  

  desc "reload cases imported without spawn"
  task :reload_cases, [:case_number] => :environment do |t, args|
    if args[:case_number].nil?
      puts "this task requires | delimited list of cases"
      return
    end
    case_numbers = args[:case_number]
    l = LAMA.new({:login => ENV['LAMA_EMAIL'], :pass => ENV['LAMA_PASSWORD']})
    case_numbers.split('|').each do |case_number|
      if LAMAHelpers.reloadCase(case_number,l).nil?
        puts "FAILURE : #{case_number} NOT reimported with spawns !!!!!!" 
        break
      end
    end
  end

  desc "reload cases imported without spawn"
  task :reload_pipeline_non_existent_cases_file, [:file] => :environment do |t, args|
    if args[:file].nil?
      puts "this task requires an input file"
      return
    end
    file = args[:file]
    l = LAMA.new({:login => ENV['LAMA_EMAIL'], :pass => ENV['LAMA_PASSWORD']})
    outfile = "tmp/cache/rake/pipeline_reload_#{DateTime.now.strftime("%Y%m%d%H%M%S")}.csv"
    File.open(outfile, "w") do |log|
      IO.readlines(file).each do |line|
        case_number =  line.strip
        next if Case.where(:case_number => case_number).exists?
        puts "loading #{case_number}"
        log << "#{case_number}|"
        puts "#{case_number} => processed"
      end
    end
  end

  desc "reload cases without steps"
  task :reload_cases_without_steps => :environment do |t, args|
    l = LAMA.new({:login => ENV['LAMA_EMAIL'], :pass => ENV['LAMA_PASSWORD']})
    where = "hearings.id IS NULL AND judgements.id IS NULL AND inspections.id IS NULL AND notifications.id IS NULL AND filed IS NULL AND state = 'Open'"
    Case.includes([:inspections,:notifications, :hearings, :judgements]).where(where).find_each do |kase|
      if LAMAHelpers.reloadCase(kase.case_number,l).nil?
        puts "FAILURE : #{case_number} failed to re-import !!!!!!" 
        break
      end
    end
  end

  desc "save case filed date for all cases with no steps and no filed date"
  task :update_filed_case_without_steps => :environment do |t, args|    
    l = LAMA.new({ :login => ENV['LAMA_EMAIL'], :pass => ENV['LAMA_PASSWORD']})
    where = "hearings.id IS NULL AND judgements.id IS NULL AND inspections.id IS NULL AND notifications.id IS NULL AND filed IS NULL AND state = 'Open'"
    Case.includes([:inspections,:notifications, :hearings, :judgements]).where(where).find_each do |kase|
      puts kase.case_number
      incident = l.incident(kase.case_number)
      if incident && incident.DateFiled
        kase.update_attribute(:filed, incident.DateFiled)
      end
    end
  end

  desc "save case filed date for all cases"
  task :update_filed_case => :environment do |t, args|    
    l = LAMA.new({ :login => ENV['LAMA_EMAIL'], :pass => ENV['LAMA_PASSWORD']})
    Case.where(:filed => nil).find_each do |kase|
      puts kase.case_number
      incident = l.incident(kase.case_number)
      if incident && incident.DateFiled
        kase.update_attribute(:filed, incident.DateFiled)
      end
    end
  end

  desc "generate case_list"
  task :reload_cases_where_steps_after_judgement => :environment do |t, args|
    l = LAMA.new({:login => ENV['LAMA_EMAIL'], :pass => ENV['LAMA_PASSWORD']})
    puts "#{Case.includes([:inspections, :notifications, :hearings, :judgements]).where('judgements.judgement_date < hearings.hearing_date OR judgements.judgement_date <  inspections.inspection_date OR notifications.notified > judgements.judgement_date').count}"
    Case.includes([:inspections, :notifications, :hearings, :judgements]).where('judgements.judgement_date < hearings.hearing_date OR judgements.judgement_date <  inspections.inspection_date OR notifications.notified > judgements.judgement_date').find_each do |kase|
      if LAMAHelpers.reloadCase(kase.case_number,l).nil?
        puts "FAILURE : #{case_number} failed to re-import !!!!!!" 
        break
      end
    end
  end    

  desc "reload cases imported without spawn"
  task :load_open_cases => :environment do |t, args|
    l = LAMA.new({:login => ENV['LAMA_EMAIL'], :pass => ENV['LAMA_PASSWORD']})
    total = Case.where(:state => 'Open').count
    puts "#{total.to_s} Open Cases as of #{DateTime.now}"
    i = 1
    Case.where(:state => 'Open').find_each do |kase|
      puts "#{i.to_s} of #{total.to_s}: #{kase.case_number} loading attempted at #{DateTime.now}"
      LAMAHelpers.load_case(kase.case_number,l)
      puts "#{i.to_s} of #{total.to_s}: #{kase.case_number} loaded"
      i+=1
    end 
  end

  desc "reload cases imported without spawn"
  task :load_open_cases_like, [:case_number_like] => :environment do |t, args|
    where = "state = 'Open' and case_number like '#{args.case_number_like}'"
    l = LAMA.new({:login => ENV['LAMA_EMAIL'], :pass => ENV['LAMA_PASSWORD']})
    total = Case.where(where).count
    puts "#{total.to_s} Open Cases as of #{DateTime.now}"
    i = 1
    Case.where(where).order('filed asc').find_each do |kase|
      puts "#{i.to_s} of #{total.to_s}: #{kase.case_number} loading attempted at #{DateTime.now}"
      LAMAHelpers.load_case(kase.case_number,l)
      puts "#{i.to_s} of #{total.to_s}: #{kase.case_number} loaded"
      i+=1
    end 
  end

desc "reload cases imported without spawn"
  task :load_open_cases_thread, [:batch_size] => :environment do |t, args|
    args.with_defaults(:batch_size => 24*60)
    batch_size = args.batch_size.to_i
    l = LAMA.new({:login => ENV['LAMA_EMAIL'], :pass => ENV['LAMA_PASSWORD']})
    
    open_cases_count = Case.where(:state => 'Open').count
    num_threads = (open_cases_count.to_f / batch_size.to_f).ceil

    puts "#{open_cases_count.to_s} Open Cases as of #{DateTime.now}"

    threads = []
    
    for i in 0..num_threads-1
     puts "Thread => #{i}"

     threads << Thread.new do

        Thread.current[:index] = i
        puts "start => #{Thread.current[:index]*batch_size}     batch_size => #{batch_size}"
        k=1
       Case.where(:state => 'Open').order("case_number").find_in_batches(start: (Thread.current[:index] * batch_size), batch_size: batch_size) do |group|
          group.each do |kase|
            puts "Thread => #{Thread.current[:index]}     #{k} of #{batch_size}      case_number => #{kase.case_number}"
            LAMAHelpers.load_case(kase.case_number,l)
            k+=1
          end
       end
     end
     sleep(60)
    end
    threads.each(&:join)
  end
end