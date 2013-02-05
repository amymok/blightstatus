class Demolition < ActiveRecord::Base
  belongs_to :address
  belongs_to :case, :foreign_key => :case_number, :primary_key => :case_number
  # validates_presence_of :demo_number
  # validates_uniqueness_of :demo_number
  # validates_uniqueness_of :address_long, :scope => :date_completed
  validates_uniqueness_of :address_long, :scope => [:program_name, :address_long, :date_started]
  validates_uniqueness_of :address_long, :scope => [:program_name, :address_long, :date_completed]

  after_save do
    if self.case
      self.case.update_status(self)
    else
      if self.address
        self.address.update_most_recent_status(self)
      end
    end
  end

  after_destroy do
    if self.case
      self.case.update_last_status
    else
      if self.address
        self.address.latest_status
      end
    end
  end

  def date
    self.date_completed || self.date_started || DateTime.new(0)
  end

  def self.matched_count
  	Demolition.count(:conditions =>'address_id is not null')
  end

  def self.unmatched_count
  	Demolition.count(:conditions => 'address_id is null')
  end

  def self.pct_matched
  	Demolition.count(:conditions => "address_id is not null").to_f / Demolition.count.to_f * 100
  end

end
