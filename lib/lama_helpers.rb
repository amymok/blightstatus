module LAMAHelpers
  def import_incidents_to_database(incidents, client=nil)
    return if incidents.nil?
    incidents.each do |incident|
      import_incident_to_database(incident,client) if incident
    end
  end
  def import_incident_to_database(incident, client=nil)
    
    return if incident.nil?
    
    l = client || LAMA.new({ :login => ENV['LAMA_EMAIL'], :pass => ENV['LAMA_PASSWORD']})
    
    #incidents.each do |incident|
      begin
        case_number = incident.Number
        return if case_number.nil? || case_number.length == 0 # need to find a better way to deal with this ... revisit post LAMA data cleanup
        return unless incident.Type == 'Public Nuisance and Blight'
        location = incident.Location
        addresses = AddressHelpers.find_address(location)
        address = addresses.first if addresses
        division = get_incident_division_by_location(l,address.address_long,case_number) if address
        division = get_incident_division_by_location(l,location,case_number) if division.nil? || division.strip.length == 0
        division = incident.Division if division.nil? || division.strip.length == 0
        return unless division == 'CE'
        
        case_state = 'Open'
        case_state = 'Closed' if incident.IsClosed =~/true/
        filed = incident.DateFiled
        kase = Case.find_or_create_by_case_number(:case_number => case_number, :state => case_state, :filed => filed)
        
        puts "case => #{case_number}   status => #{incident.CurrentStatus}    date => #{incident.CurrentStatusDate}"
        orig_state = kase.state
        kase.state = case_state
        orig_outcome = kase.outcome
        incident_full = l.incident(case_number)
        
        #Go through all data points and pull out relevant things here
        #Inspections
        spawn_hash = {}
        inspections = incident_full.Inspections
        if inspections
          if inspections.class == Hashie::Mash
            inspections = inspections.Inspection
            if inspections.class == Array
              inspections.each do |inspection|
                i = parseInspection(case_number,inspection)          
                spawn_hash[i[:spawn_id]] = i if i
              end
            else
              i = parseInspection(case_number,inspections)     
              spawn_hash[i[:spawn_id]] = i if i
            end
          end
        end

        judgements = incident_full.Judgments
        if judgements
          if judgements.class == Hashie::Mash
            judgements = judgements.Judgment
            if judgements.class == Array
              judgements.each do |judgement|
                j = parseJudgement(kase,judgement)
                spawn_hash[j[:spawn_id]] = j if j
              end
            else
              j = parseJudgement(kase,judgements)
              spawn_hash[j[:spawn_id]] = j if j
            end
          end
        end
        
        #Actions
        actions = []
        if incident_full.Actions && incident_full.Actions.CodeAction
          actions = incident_full.Actions.CodeAction
          if actions
            if actions.class == Array
              actions.each do |action|
                a = parseAction(kase, action)
                spawn_hash[a[:spawn_id]] = a if a
              end
            else
              a = parseAction(kase, actions)
              spawn_hash[a[:spawn_id]] = a if a
            end     
          end      
        end

        puts "spawn_hash => #{spawn_hash.inspect}"
        #Events
        events = []
        if incident_full.Events && incident_full.Events.IncidEvent
          events = incident_full.Events.IncidEvent
        end
        if events
          if events.class == Array
            events.each do |event|
              parseEvent(kase,event,spawn_hash)          
            end
          else
            parseEvent(kase,events,spawn_hash)
          end
        end

        remainingSpawns(kase,spawn_hash)

        # Violations
        # TODO: add violations table and create front end for this 
        # Judgments - Closed
        case_status = incident_full.Description
        if (case_status =~ /Status:/ && case_status =~ /Status Date:/)
          case_status = case_status[((case_status =~ /Status:/) + "Status:".length) ... case_status =~ /Status Date:/].strip

          d = incident_full.Description
          d = d[d.index('Status Date:') .. -1].split(' ')
          d = d[2].split('/')
          d = DateTime.new(d[2].to_i,d[0].to_i,d[1].to_i)

          # parseStatus(kase,case_status,d)
        end
        
        validateSchedHearings(kase)

        if kase.address.nil?
          if address
            kase.address = address
          end
        end
        if !kase.accela_steps.nil? || kase.state != orig_state || kase.outcome != orig_outcome
          # invalidate_steps(kase)
          k = kase.save
        end
      rescue StandardError => ex
        puts "THERE WAS AN EXCEPTION OF TYPE #{ex.class}, which told us that #{ex.message}"
        puts "Backtrace => #{ex.backtrace}"
      end
    #end
  end

  def validateSchedHearings(kase)
    #is scheduled hearing valid?
        schedHearings = Hearing.where("case_number = '#{kase.case_number}' and is_complete = false")
        return if schedHearings.count == 0

        h = kase.last_hearing
        s = kase.last_status

        if kase.judgement || (h && h.is_complete )|| (h && s && h != s)
          schedHearings.destroy_all
          return
        end

        Hearing.where("case_number = '#{kase.case_number}' and is_complete = false and id <> #{h.id}").destroy_all if h && schedHearings.count > 0
        h.destroy if h && !h.is_complete && kase.judgement && h != kase.last_status
  end

  def parseEvent(kase,event,spawn_hash)
    case_number = kase.case_number
    date = DateTime.parse(event.DateEvent)
    if event.class == Hashie::Mash && event.IsComplete =~ /true/
      j_status = nil
      if ((event.Type =~ /Notice/ || event.Name =~ /Notice/) && (event.Type =~ /Hearing/ || event.Name =~ /Hearing/)) || (event.Type == 'Notice' || event.Name == 'Notice')
        if event.SpawnID && event.SpawnID != '-1' && spawn_hash[event.SpawnID]
          unless Notification.where("case_number = '#{kase.case_number}' and (notified >= '#{date.beginning_of_day.to_formatted_s(:db)}' and notified <= '#{date.end_of_day.to_formatted_s(:db)}')").exists?
            # Notification.create(:case_number => kase.case_number, :notified => spawn_hash[event.SpawnID][:date], :notification_type => spawn_hash[event.SpawnID][:notes], :spawn_id => event.SpawnID.to_i)
            Notification.create(:case_number => kase.case_number, :notified => event.DateEvent, :notification_type => spawn_hash[event.SpawnID][:notes], :spawn_id => event.SpawnID.to_i)
          end
          spawn_hash.delete(event.SpawnID)
        else
          Notification.create(:case_number => kase.case_number, :notified => event.DateEvent, :notification_type => event.Type) unless Notification.where("case_number = '#{kase.case_number}' and (notified >= '#{DateTime.parse(event.DateEvent).beginning_of_day.to_formatted_s(:db)}' and notified <= '#{DateTime.parse(event.DateEvent).end_of_day.to_formatted_s(:db)}')").exists?
        end
      elsif event.Type =~ /Administrative Hearing/ || event.Name =~ /Administrative Hearing/
        if event.SpawnID && event.SpawnID != -1 && spawn_hash[event.SpawnID]
          unless Hearing.where("case_number = '#{kase.case_number}' and (hearing_date >= '#{date.beginning_of_day.to_formatted_s(:db)}' and hearing_date <= '#{date.end_of_day.to_formatted_s(:db)}')").exists? 
            Hearing.create(:case_number => kase.case_number, :hearing_date => spawn_hash[event.SpawnID][:date], :hearing_status => event.Status, :hearing_type => event.Type, :is_complete => true, :spawn_id => event.SpawnID.to_i)#, :is_valid => true)
          end

          unless Judgement.where("case_number = '#{kase.case_number}' and (judgement_date >= '#{date.beginning_of_day.to_formatted_s(:db)}' and judgement_date <= '#{date.end_of_day.to_formatted_s(:db)}')").exists?
            j = Judgement.new(:case_number => kase.case_number, :notes => spawn_hash[event.SpawnID][:notes], :status => spawn_hash[event.SpawnID][:status], :judgement_date => spawn_hash[event.SpawnID][:date], :spawn_id => event.SpawnID.to_i)# unless spawn_hash[event.SpawnID][:status].strip =~ /Pending/
            j.save unless j.status =~ /Pending/ || j.notes =~ /reset/
          end
          spawn_hash.delete(event.SpawnID)
        else  
          unless Hearing.where("case_number = '#{kase.case_number}' and (hearing_date >= '#{DateTime.parse(event.DateEvent).beginning_of_day.to_formatted_s(:db)}' and hearing_date <= '#{DateTime.parse(event.DateEvent).end_of_day.to_formatted_s(:db)}')").exists?#, :spawn_id => event.SpawnID.to_i)#, :is_valid => true)
            Hearing.create(:case_number => kase.case_number, :hearing_date => event.DateEvent, :hearing_status => event.Status, :hearing_type => event.Type, :is_complete => true) 
          end
        end
      elsif ((event.Type =~ /Notice/ || event.Name =~ /Notice/) && (event.Type =~ /Reset/ || event.Name =~ /Reset/))
        if event.SpawnID && event.SpawnID != -1 && spawn_hash[event.SpawnID]
          unless Reset.where("case_number = '#{kase.case_number}' and (reset_date >= '#{date.beginning_of_day.to_formatted_s(:db)}' and reset_date <= '#{date.end_of_day.to_formatted_s(:db)}')").exists?
            Reset.create(:case_number => kase.case_number, :reset_date => spawn_hash[event.SpawnID][:date], :spawn_id => event.SpawnID.to_i)
          end
          spawn_hash.delete(event.SpawnID)
        else
          unless Reset.where("case_number = '#{kase.case_number}' and (reset_date >= '#{DateTime.parse(event.DateEvent).beginning_of_day.to_formatted_s(:db)}' and reset_date <= '#{DateTime.parse(event.DateEvent).end_of_day.to_formatted_s(:db)}')").exists?
            Reset.create(:case_number => kase.case_number, :reset_date => event.DateEvent) 
          end
        end
      elsif event.Type =~ /Input Hearing Results/
       if event.Items != nil and event.IncidEventItem != nil
         event.IncidEventItem.each do |item|
           if item.class == Hashie::Mash
             if (item.Title =~ /Reset Notice/ || item.Title =~ /Reset Hearing/) && item.IsComplete == "true"
                if event.SpawnID && event.SpawnID != '-1' && spawn_hash[event.SpawnID]                  
                  unless Reset.where("case_number = '#{kase.case_number}' and (reset_date >= '#{date.beginning_of_day.to_formatted_s(:db)}' and reset_date <= '#{date.end_of_day.to_formatted_s(:db)}')").exists?
                    Reset.create(:case_number => kase.case_number, :reset_date => spawn_hash[event.SpawnID][:date], :spawn_id => event.SpawnID.to_i)
                  end
                  spawn_hash.delete(event.SpawnID)
                else
                  unless Reset.where("case_number = '#{kase.case_number}' and (reset_date >= '#{DateTime.parse(event.DateEvent).beginning_of_day.to_formatted_s(:db)}' and reset_date <= '#{DateTime.parse(event.DateEvent).end_of_day.to_formatted_s(:db)}')").exists?
                    Reset.create(:case_number => kase.case_number, :reset_date => item.DateCompleted) 
                  end
                end
             end
           end
         end
       end
      elsif event.Type =~ /Inspection/ || event.Name =~ /Inspection/ || event.Type =~ /Reinspection/ || event.Name =~ /Reinspection/
        if event.SpawnID && event.SpawnID != '-1' && spawn_hash[event.SpawnID]
          unless Inspection.where("case_number = '#{kase.case_number}' and (inspection_date >= '#{date.beginning_of_day.to_formatted_s(:db)}' and inspection_date <= '#{date.end_of_day.to_formatted_s(:db)}')").exists?
            i = Inspection.create(:case_number => kase.case_number, :inspection_date => spawn_hash[event.SpawnID][:date], :notes => spawn_hash[event.SpawnID][:notes], :result => event.Status, :spawn_id => event.SpawnID.to_i)
            if spawn_hash[event.SpawnID][:findings]
              spawn_hash[event.SpawnID][:findings].each do |key,finding|
                i.inspection_findings.create(:label => finding[:label], :finding => finding[:finding])
              end
            end
          end
          spawn_hash.delete(event.SpawnID)
        else          
          unless Inspection.where("case_number = '#{kase.case_number}' and (inspection_date >= '#{date.beginning_of_day.to_formatted_s(:db)}' and inspection_date <= '#{date.end_of_day.to_formatted_s(:db)}')").exists?
            Inspection.create(:case_number => kase.case_number, :inspection_date => event.DateEvent, :notes => event.Status, :inspection_type => event.Type, :result => event.Status)
          end
        end
      elsif event.Type =~ /Complaint Received/ || event.Name =~ /Complaint Received/ || event.Type =~ /Intake/ || event.Name =~ /Intake/
        if event.SpawnID && event.SpawnID != '-1' && spawn_hash[event.SpawnID]
          unless Complaint.where("case_number = '#{kase.case_number}' and (date_received >= '#{date.beginning_of_day.to_formatted_s(:db)}' and date_received <= '#{date.end_of_day.to_formatted_s(:db)}')").exists?
            Complaint.create(:case_number => kase.case_number, :date_received => spawn_hash[event.SpawnID][:date], :status => spawn_hash[event.SpawnID][:notes], :spawn_id => event.SpawnID.to_i)
          end
          spawn_hash.delete(event.SpawnID)
        else
          unless Complaint.where("case_number = '#{kase.case_number}' and (date_received >= '#{date.beginning_of_day.to_formatted_s(:db)}' and date_received <= '#{date.end_of_day.to_formatted_s(:db)}')").exists?
            Complaint.create(:case_number => kase.case_number, :date_received => event.DateEvent, :status => event.Status)
          end
        end
      elsif event.Type =~ /Research Property Record/
        if event.SpawnID && event.SpawnID != '-1' && spawn_hash[event.SpawnID] 
          rpfDate = spawn_hash[event.SpawnID][:date]
          spawn_hash.delete(event.SpawnID)
        else 
          rpfDate = event.DateEvent
        end
        Case.find(kase.id).ordered_case_steps.each do |step|
          step.date <= DateTime.parse(rpfDate) ? (step.destroy unless step.class == Inspection) : break
        end
      elsif (event.Name =~ /Guilty/ || event.Status =~ /Guilty/ || event.Type =~ /Guilty/) && (event.Name =~ /Hearing/ || event.Status =~ /Hearing/ || event.Type =~ /Hearing/)#event.Name =~ /Hearing/
        if event.Name =~ /Guilty/
          notes = event.Name.strip
        elsif event.Type =~ /Guilty/
          notes = event.Type.strip
        else
          notes = event.Status.strip
        end
        
        if notes =~ /Not Guilty/
          j_status = 'Not Guilty'
        else
          j_status = 'Guilty'
        end
        kase.outcome = j_status
      elsif (event.Name =~ /Judgment/ && (event.Name =~ /Posting/ || event.Name =~ /Notice/ || event.Name =~ /Recordation/))
        spawn_hash.delete(event.SpawnID)
        j_status = ''
      elsif (event.Name =~ /Hearing/ && event.Name =~ /Dismiss/) || (event.Name =~ /Hearing/ && (event.Status =~ /Dismiss/ || event.Status =~ /dismiss/))
        if event.Name =~ /Dismiss/
          notes = event.Name.strip
        else
          notes = event.Status.strip
        end
        j_status = 'Closed'
        kase.outcome = 'Closed: Dismissed'
      elsif event.Name =~ /Dismiss/
        kase.outcome = 'Dismissed'
      elsif (event.Name =~ /Hearing/ && event.Name =~ /Compliance/) || (event.Name =~ /Hearing/ && event.Status =~ /Compliance/)
        if event.Name =~ /Compliance/
          notes = event.Name.strip
        else
          notes = event.Status.strip
        end
        j_status = 'Closed'
        kase.outcome = 'Closed: In Compliance'
      elsif event.Name =~ /Compliance/
        kase.outcome = "Closed: In Compliance"
      elsif (event.Name =~ /Hearing/ && event.Name =~ /Closed/) || (event.Name =~ /Hearing/ && event.Status =~ /Closed/)
        if event.Name =~ /Closed/
          notes = event.Name.strip
        else
          notes = event.Status.strip
        end
        j_status = 'Closed'
        kase.outcome = 'Closed'
      elsif event.Name =~ /Closed New Owner/
        kase.outcome = 'Closed: New Owner'
      elsif (event.Name =~ /Hearing/ && event.Name =~ /Judgment rescinded/) || (event.Name =~ /Hearing/ && event.Status =~ /Judgment rescinded/)
        if event.Name =~ /rescinded/
          notes = event.Name.strip
        else
          notes = event.Status.strip
        end
        j_status = 'Judgment Rescinded'
        kase.outcome = j_status
      elsif event.Name =~ /Closed/# || event.Name == 'Closed - Closed'
        kase.outcome = "Closed"
      elsif event.Name =~ /Judgment rescinded/
        kase.outcome = 'Judgment Rescinded'
      end
      
      if j_status
        if j_status.length > 0
          Judgement.where(:case_number => kase.case_number, :status => nil).destroy_all
          j = nil
          if event.SpawnID && event.SpawnID != '-1' && spawn_hash[event.SpawnID]
            unless Judgement.where("case_number = '#{kase.case_number}' and (judgement_date >= '#{date.beginning_of_day.to_formatted_s(:db)}' and judgement_date <= '#{date.end_of_day.to_formatted_s(:db)}')").exists?
              Judgement.create(:case_number => kase.case_number, :notes => spawn_hash[event.SpawnID][:notes], :status => spawn_hash[event.SpawnID][:status], :judgement_date => spawn_hash[event.SpawnID][:date], :spawn_id => event.SpawnID.to_i)
            end
            spawn_hash.delete(event.SpawnID)
          else
            puts "spawn id => #{event.SpawnID}"
            unless Judgement.where("case_number = '#{kase.case_number}' and (judgement_date >= '#{date.beginning_of_day.to_formatted_s(:db)}' and judgement_date <= '#{date.end_of_day.to_formatted_s(:db)}')").exists?
              Judgement.create(:case_number => kase.case_number, :notes => notes, :status => j_status, :judgement_date => event.DateEvent)
            end
          end
          unless Hearing.where("case_number = '#{kase.case_number}' and (hearing_date >= '#{date.beginning_of_day.to_formatted_s(:db)}' and hearing_date <= '#{date.end_of_day.to_formatted_s(:db)}')").exists?
            Hearing.create(:case_number => kase.case_number, :hearing_date => date, :hearing_status => j_status, :hearing_type => event.Type, :is_complete => true, :spawn_id => event.SpawnID.to_i) 
          end
          kase.outcome = j_status
        else
          kase.outcome = 'Judgment'
          if event.SpawnID && event.SpawnID != '-1' && spawn_hash[event.SpawnID]
            Judgement.find_or_create_by_case_number(:case_number => kase.case_number, :notes => spawn_hash[event.SpawnID][:notes], :judgement_date => spawn_hash[event.SpawnID][:date], :spawn_id => event.SpawnID.to_i)
          else
            Judgement.find_or_create_by_case_number(:case_number => kase.case_number, :notes => notes, :judgement_date => event.DateEvent)
          end
        end
      end
    elsif event.class == Hashie::Mash && (event.Type =~ /Administrative Hearing/ || event.Name =~ /Administrative Hearing/)  && event.IsComplete =~ /false/ && kase.state == 'Open'
      last_notification = kase.last_notification
      last_hearing = kase.last_hearing
      h = Hearing.new(:case_number => kase.case_number, :hearing_date => event.DateEvent, :hearing_status => event.Status, :hearing_type => event.Type, :is_complete => false)
      h.spawn_id = event.SpawnID.to_i if event.SpawnID != '-1'
      h.save if kase.judgement.nil? && last_notification && h.date > last_notification.date && (last_hearing.nil? || ((last_hearing && h.date > last_hearing.date) && (last_notification.date > last_hearing.date)))         
    end
  end
  def parseInspection(case_number,inspection)
    inspection_spawn = nil
    if inspection.class == Hashie::Mash && inspection.IsComplete =~ /true/
      inspection_spawn = {:spawn_id => inspection.ID, :date => inspection.InspectionDate, :notes => inspection.Comment, :step => Inspection.to_s, :spawn_type => Inspection.to_s, :findings => {}}
      finding = {}
      if inspection.Findings != nil && inspection.Findings.InspectionFinding != nil
        inspection.Findings.InspectionFinding.each do |finding|
          if finding.class == Hashie::Mash
            if finding.Finding && finding.Finding.length > 0
              inspection_spawn[:findings][finding.ID] = {:finding_id => finding.ID, :finding => finding.Finding, :label => finding.Label}#i.inspection_findings.create(:finding => finding.Finding, :label => finding.Label)
            end
          end
        end
      end
    end
    inspection_spawn
  end
  def parseAction(kase,action)
    action_spawn = nil
    if action.class == Hashie::Mash && action.IsComplete =~ /true/
      action_spawn = {:spawn_id => action.ID, :date => action.Date, :notes => action.Type, :spawn_type => "Action"}
      if (action.Type =~ /Notice/ && action.Type =~ /Hearing/) || action.Type == 'Notice'
        action_spawn[:step] = Notification.to_s
      elsif action.Type =~ /Notice/ && action.Type =~ /Reset/
        action_spawn[:step] = Reset.to_s
      elsif action.Type =~ /Judgment/ && (action.Type =~ /Posting/ || action.Type =~ /Recordation/ || action.Type =~ /Notice/)
        action_spawn[:step] = Judgement.to_s
      elsif action.Type =~ /Notice/ && action.Type =~ /Compliance/
        kase.outcome = 'Closed: In Compliance'
      elsif action.Type =~ /Complaint/
        action_spawn[:step] = Complaint.to_s
      elsif action.Type =~ /Research Property Record/
        action_spawn[:step] = 'Research Property Record'
      end
    end
    return nil if action_spawn && action_spawn[:step].nil?
    action_spawn
  end
  def parseStatus(kase,case_status,date)
    c_status = case_status.downcase
    if c_status =~ /compliance/ 
      kase.outcome = "Closed: In Compliance"
      #Judgement.where(:case_number => kase.case_number, :status => nil).destroy_all
      Judgement.find_or_create_by_case_number(:case_number => kase.case_number, :status => 'Closed', :judgement_date => date, :notes => case_status) unless kase.judgement
    elsif c_status =~  /dismiss/
      kase.outcome = 'Closed: Dismissed'
      #Judgement.where(:case_number => kase.case_number, :status => nil).destroy_all
      Judgement.find_or_create_by_case_number(:case_number => kase.case_number, :status => 'Closed', :judgement_date => date, :notes => case_status) unless kase.judgement
    elsif c_status =~ /closed/ 
      kase.outcome = 'Closed'
    elsif c_status =~ /guilty/
      if c_status =~ /not guilty/
        kase.outcome = 'Not Guilty'
      else
        kase.outcome = 'Guilty'
      end
        #Judgement.where(:case_number => kase.case_number, :status => nil).destroy_all
        Judgement.find_or_create_by_case_number(:case_number => kase.case_number, :status => kase.outcome, :judgement_date => date, :notes => case_status) unless kase.judgement
    elsif c_status =~ /judgment/ && (c_status =~ /posting/ || c_status =~ /notice/ || c_status =~ /recordation/)
      j = Judgement.find_or_create_by_case_number(:case_number => kase.case_number, :judgement_date => date, :notes => case_status) unless kase.save
      unless j.status
        kase.outcome = 'Judgment' if kase.outcome != 'Judgment'
      end
    elsif c_status =~ /judgment rescinded/
      kase.outcome = 'Judgment Rescinded' 
    elsif c_status =~ /omplaint/ || c_status =~ /eceived/
      Complaint.create(:case_number => kase.case_number, :status => 'Received', :date_received => date, :notes => case_status) unless kase.complaint
    end
  end

  def invalidate_steps(kase)
    latest = kase.most_recent_status
    
    j = Judgement.where(:case_number => kase.case_number, :status => nil).last
    if  j && latest && j != latest && (j.status.nil? || j.status.length == 0)
      kase.adjudication_steps.each do |s|
        s.destroy if s.date < j.date
      end
      j.destroy
    end

    j = kase.judgement
    if  j && latest && j != latest && !j.status.nil? && (j.status =~ /Rescinded/).nil?
      kase.adjudication_steps.each do |s|
        if s.date > j.date
          s.destroy
        end
      end
    end
    kase.save
  end
  def import_by_location(address,lama=nil)
    begin
      lama = LAMA.new({ :login => ENV['LAMA_EMAIL'], :pass => ENV['LAMA_PASSWORD']}) if lama.nil?
    
      incidents = incidents_by_location(address,lama)
                
      incidents.nil? ? incid_num = 0 :incid_num = incidents.length
      p "There are #{incid_num} incidents for #{address}"
      if incid_num >= 1000
        p "LAMA can only return 1000 incidents at once- please try a smaller date range"
        return
      end

      import_incidents_to_database(incidents, lama)
    rescue StandardError => ex
      puts "There was an error of type #{ex.class}, with a message of #{ex.message}"
      puts "Backtrace => #{ex.backtrace}"
    end
  end

  def incidents_by_location(location,lama)
    incidents = lama.incidents_by_location(location,lama)
    if incidents.class == Hashie::Mash
      incident = incidents
      incidents = []
      incidents << incident
    end
    incidents
  end
  def unsaved_incidents_by_location(location,lama)
    cases = []
    incidents = incidents_by_location(location,lama)
    return if incidents.nil?
    incidents.each do |incident|
      cases << incident unless Case.where(:case_number => incident.Number).exists?
    end
    cases
  end
  
  def import_unsaved_cases_by_location(address,lama=nil)
    begin
      lama = LAMA.new({ :login => ENV['LAMA_EMAIL'], :pass => ENV['LAMA_PASSWORD']}) if lama.nil?
    
      incidents = unsaved_incidents_by_location(address,lama)
                
      incidents.nil? ? incid_num = 0 :incid_num = incidents.length
      p "There are #{incid_num} incidents for #{address}"
      if incid_num >= 1000
        p "LAMA can only return 1000 incidents at once- please try a smaller date range"
        return
      end

      import_incidents_to_database(incidents, lama)
    rescue StandardError => ex
      puts "There was an error of type #{ex.class}, with a message of #{ex.message}"
      puts "Backtrace => #{ex.backtrace}"
    end
  end

  def get_incident_division_by_location(lama,location,case_number)
    begin
      incidents = incidents_by_location(location,lama)
      if incidents
        incidents.each do |incident|
            return incident.Division if incident.Number == case_number
        end
      end
    rescue StandardError => ex
      puts "There was an error of type #{ex.class}, with a message of #{ex.message}"
      puts "Backtrace => #{ex.backtrace}"
    end
    nil
  end

  def parseJudgement(kase,judgement)
    judgement_spawn = nil
    if judgement.class == Hashie::Mash
       
      j_status = judgement.Status.downcase if judgement.Status
      date = judgement.D_Court if judgement.D_Court
      id = judgement.ID if judgement.ID
      
      return judgement_spawn if j_status =~ /pending/
      j = nil
      
      if j_status =~ /reset/
        kase.outcome = "Reset"
        return {:spawn_id => judgement.ID, :status => j, :date => date, :notes => j_status, :spawn_type => Reset.to_s, :step => Reset.to_s}
      elsif j_status =~ /dismiss/
        j = 'Dismissed'
        kase.outcome = "Closed: Dismissed"
      elsif j_status =~ /closed/
        j = 'Closed'
        kase.outcome = "Closed"
      elsif j_status =~ /guilty/
        if j_status =~ /not guilty/
          j = 'Not Guilty'
        else
          j = 'Guilty'
        end
        kase.outcome = j        
      elsif j_status =~ /rescinded/
          j = 'Rescinded'
          kase.outcome = 'Judgment Rescinded' 
      end
      return nil if j.nil?
      j_status = judgement.Status unless judgement.Status.nil?  

      judgement_spawn = {:spawn_id => judgement.ID, :status => j, :date => date, :notes => j_status, :spawn_type => Judgement.to_s, :step => Judgement.to_s}

    end
    judgement_spawn
  end

  def remainingSpawns(kase,spawnHash)
    # puts "Remaining SpawnHash => #{spawnHash.inspect}"
    spawnHash.each do |spawn_id,spawn|
      # puts "spawn => #{spawn.inspect}"
      if spawn[:step] == Judgement.to_s
        unless Judgement.where("case_number = '#{kase.case_number}' and (judgement_date >= '#{DateTime.parse(spawn[:date]).beginning_of_day.to_formatted_s(:db)}' and judgement_date <= '#{DateTime.parse(spawn[:date]).end_of_day.to_formatted_s(:db)}')").exists?
          Hearing.create(:case_number => kase.case_number, :hearing_date => spawn[:date], :hearing_status => spawn[:status], :hearing_type => spawn[:notes], :is_complete => true) unless Hearing.where("case_number = '#{kase.case_number}' and (hearing_date >= '#{DateTime.parse(spawn[:date]).beginning_of_day.to_formatted_s(:db)}' and hearing_date <= '#{DateTime.parse(spawn[:date]).end_of_day.to_formatted_s(:db)}')").exists?
          Judgement.create(:case_number => kase.case_number, :notes => spawn[:notes], :judgement_date => spawn[:date], :status => spawn[:status])# unless Judgement.where("case_number = '#{kase.case_number}' and (judgement_date >= '#{DateTime.parse(spawn[:date]).beginning_of_day.to_formatted_s(:db)}' and judgement_date <= '#{DateTime.parse(spawn[:date]).end_of_day.to_formatted_s(:db)}')").exists?
        end
      elsif spawn[:step] == Inspection.to_s
        i = Inspection.create(:case_number => kase.case_number, :inspection_date => spawn[:date], :notes => spawn[:notes]) unless Inspection.where("case_number = '#{kase.case_number}' and (inspection_date >= '#{DateTime.parse(spawn[:date]).beginning_of_day.to_formatted_s(:db)}' and inspection_date <= '#{DateTime.parse(spawn[:date]).end_of_day.to_formatted_s(:db)}')").exists?
        if i && spawn[:findings]
          spawn[:findings].each do |key,finding|
            i.inspection_findings.create(:label => finding[:label], :finding => finding[:finding])
          end
        end
      elsif spawn[:step] == Notification.to_s
        Notification.create(:case_number => kase.case_number, :notified => spawn[:date], :notification_type => spawn[:notes]) unless Notification.where("case_number = '#{kase.case_number}' and (notified >= '#{DateTime.parse(spawn[:date]).beginning_of_day.to_formatted_s(:db)}' and notified <= '#{DateTime.parse(spawn[:date]).end_of_day.to_formatted_s(:db)}')").exists?
      elsif spawn[:step] == Complaint.to_s
        Complaint.create(:case_number => kase.case_number, :date_received => spawn[:date], :status => spawn[:notes]) unless Complaint.where("case_number = '#{kase.case_number}' and (date_received >= '#{DateTime.parse(spawn[:date]).beginning_of_day.to_formatted_s(:db)}' and date_received <= '#{DateTime.parse(spawn[:date]).end_of_day.to_formatted_s(:db)}')").exists?
      elsif spawn[:step] == Reset.to_s
        Reset.create(:case_number => kase.case_number, :reset_date => spawn[:date]) unless Reset.where("case_number = '#{kase.case_number}' and (reset_date >= '#{DateTime.parse(spawn[:date]).beginning_of_day.to_formatted_s(:db)}' and reset_date <= '#{DateTime.parse(spawn[:date]).end_of_day.to_formatted_s(:db)}')").exists?
      elsif spawn[:step] == 'Research Property Record'
        Case.find(kase.id).ordered_case_steps.each do |step|
          step.date <= DateTime.parse(spawn[:date]) ? (step.destroy unless step.class == Inspection) : break
        end
      end
    end
    spawnHash.clear
  end

  def reloadCase(case_number, client=nil)
    client = LAMA.new({:login => ENV['LAMA_EMAIL'], :pass => ENV['LAMA_PASSWORD']}) unless client
    reloaded = nil
    kase = Case.where(:case_number => case_number).first
    if kase
      puts "destroying => #{case_number}"
      kase.complaint.destroy if kase.complaint
      kase.inspections.each{|i| i.inspection_findings.destroy_all}
      kase.inspections.destroy_all
      kase.notifications.destroy_all
      kase.hearings.destroy_all
      kase.judgements.destroy_all
      kase.resets.destroy_all
      kase.maintenances.each{ |m| m.update_attribute(:case_number, nil)}
      kase.demolitions.each{ |d| d.update_attribute(:case_number, nil)}
      kase.foreclosure.update_attribute(:case_number, nil) if kase.foreclosure
      kase.destroy
    end
    load_case(case_number, client)
  end

  def load_case(case_number, client=nil)
    loaded = false
    begin
      client = LAMA.new({:login => ENV['LAMA_EMAIL'], :pass => ENV['LAMA_PASSWORD']}) unless client
      incident = client.incident(case_number)
      if incident && incident.Type == 'Public Nuisance and Blight' 
        import_incident_to_database(incident,client)
        loaded = Case.where(:case_number => case_number).any?
      end
    rescue StandardError => ex
      puts "There was an error of type #{ex.class}, with a message of #{ex.message}"
      puts "Backtrace => #{ex.backtrace}"
    end
    loaded
  end
end
